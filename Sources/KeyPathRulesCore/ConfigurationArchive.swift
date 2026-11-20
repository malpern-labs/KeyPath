import Darwin
import Foundation
import KeyPathCore

/// Copies or restores a snapshot under the configuration directory's existing operation gate.
package struct ConfigurationArchive: Sendable {
    private static let restoreStagingPrefix = ".keypath-restore-"
    private let configDirectory: String

    package init(configDirectory: String = KeyPathConstants.Config.directory) {
        self.configDirectory = configDirectory
    }

    // MARK: - Backup / Restore

    package func backupConfig(outputPath: String? = nil) async throws -> CLIConfigBackupResult {
        let gate = ConfigurationOperationGate(configurationDirectory: URL(fileURLWithPath: configDirectory, isDirectory: true))
        return try await gate.withOperation { _ in
            try copyConfigBackup(outputPath: outputPath)
        }
    }

    private func copyConfigBackup(outputPath: String?) throws -> CLIConfigBackupResult {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: configDirectory, isDirectory: true)
        let sourceCopyURL = try resolvedExistingDirectory(sourceURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: sourceCopyURL.path) else {
            throw Self.error("Config directory does not exist: \(sourceURL.path)")
        }

        let destinationURL = try outputPath.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        } ?? defaultBackupURL()

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw Self.error("Backup destination already exists: \(destinationURL.path)")
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try copyDirectoryContents(from: sourceCopyURL, to: destinationURL, fileManager: fileManager)

        return try CLIConfigBackupResult(
            sourcePath: sourceURL.path,
            backupPath: destinationURL.path,
            copiedItems: copiedItemNames(in: destinationURL)
        )
    }

    package func restoreConfig(from backupPath: String, reload: Bool) async throws -> CLIConfigRestoreResult {
        let gate = ConfigurationOperationGate(configurationDirectory: URL(fileURLWithPath: configDirectory, isDirectory: true))
        return try await gate.withOperation { _ in
            try await restoreConfigContents(from: backupPath, reload: reload)
        }
    }

    private func restoreConfigContents(from backupPath: String, reload: Bool) async throws -> CLIConfigRestoreResult {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: (backupPath as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Self.error("Backup directory does not exist: \(sourceURL.path)")
        }

        let resolvedSourceURL = try resolvedExistingDirectory(sourceURL, fileManager: fileManager)
        let destinationURL = URL(fileURLWithPath: configDirectory, isDirectory: true)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let restoreTargetURL: URL
        if fileManager.fileExists(atPath: destinationURL.path) {
            restoreTargetURL = try resolvedExistingDirectory(destinationURL, fileManager: fileManager)
        } else {
            restoreTargetURL = destinationURL
            try fileManager.createDirectory(at: restoreTargetURL, withIntermediateDirectories: true)
        }

        if sameResolvedPath(resolvedSourceURL, restoreTargetURL) {
            throw Self.error("Backup path resolves to the active config directory: \(sourceURL.path)")
        }

        try restoreDirectoryContents(from: resolvedSourceURL, to: restoreTargetURL, fileManager: fileManager)

        // Only the running app can talk to its worker. Reuse the normal CLI request.
        let reloadSuccess = await reload ? (try? RuntimeControl.requestEngine(.reload)) != nil : nil
        return try CLIConfigRestoreResult(
            sourcePath: sourceURL.path,
            restoredPath: destinationURL.path,
            restoredItems: copiedItemNames(in: restoreTargetURL),
            reloadRequested: reload,
            reloadSuccess: reloadSuccess
        )
    }

    private func defaultBackupURL() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "keypath-config-\(formatter.string(from: Date()))"
        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return supportDirectory
            .appendingPathComponent("KeyPath", isDirectory: true)
            .appendingPathComponent("QA Backups", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private func resolvedExistingDirectory(_ url: URL, fileManager: FileManager) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Self.error("Directory does not exist: \(url.path)")
        }
        return url.resolvingSymlinksInPath()
    }

    private func copyDirectoryContents(from source: URL, to destination: URL, fileManager: FileManager) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            if isTransientArchiveItem(item.lastPathComponent) { continue }
            do {
                try fileManager.copyItem(
                    at: item,
                    to: destination.appendingPathComponent(item.lastPathComponent)
                )
            } catch where isFileNotFound(error) {
                // Vanished between enumeration and copy — transient, skip.
            }
        }
    }

    /// Stage the backup before changing live entries (#881). Keep the old
    /// entries until all replacements and removals succeed or are undone.
    private func restoreDirectoryContents(from source: URL, to destination: URL, fileManager: FileManager) throws {
        let contents = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            .filter { !isTransientArchiveItem($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let names = Set(contents.map(\.lastPathComponent))
        let staging = destination.appendingPathComponent(Self.restoreStagingPrefix + UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var preserveStaging = false
        defer {
            if !preserveStaging { try? fileManager.removeItem(at: staging) }
        }

        for item in contents {
            try fileManager.copyItem(at: item, to: staging.appendingPathComponent(item.lastPathComponent))
        }

        var undo: [(source: String, target: String, flags: UInt32)] = []
        do {
            for item in contents {
                let name = item.lastPathComponent
                let stagedPath = staging.appendingPathComponent(name).path
                let targetPath = destination.appendingPathComponent(name).path
                // Exchange existing items. If absent, publish with an exclusive
                // rename so a concurrently created file is preserved.
                if renamex_np(stagedPath, targetPath, UInt32(RENAME_SWAP)) == 0 {
                    undo.append((stagedPath, targetPath, UInt32(RENAME_SWAP)))
                } else if errno == ENOENT {
                    try renameWithoutReplacing(from: stagedPath, to: targetPath)
                    undo.append((targetPath, stagedPath, UInt32(RENAME_EXCL)))
                } else {
                    throw Self.renameError(at: targetPath, code: errno)
                }
            }

            let liveItems = try fileManager.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
            for item in liveItems {
                let name = item.lastPathComponent
                if names.contains(name) || isTransientArchiveItem(name) { continue }
                let stagedPath = staging.appendingPathComponent(name).path
                do {
                    try renameWithoutReplacing(from: item.path, to: stagedPath)
                    undo.append((stagedPath, item.path, UInt32(RENAME_EXCL)))
                } catch where isFileNotFound(error) {
                    // Another operation already removed the extra entry.
                }
            }
        } catch {
            for change in undo.reversed() {
                if renamex_np(change.source, change.target, change.flags) != 0 {
                    preserveStaging = true
                }
            }
            if preserveStaging {
                throw Self.error("Restore failed: \(error.localizedDescription). Rollback was incomplete. Remaining files are at \(staging.path).")
            }
            throw error
        }
    }

    private func renameWithoutReplacing(from source: String, to target: String) throws {
        if renamex_np(source, target, UInt32(RENAME_EXCL)) != 0 {
            throw Self.renameError(at: target, code: errno)
        }
    }

    private static func renameError(at path: String, code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: path])
    }

    /// Exclude in-progress validation and abandoned restore staging. Keep
    /// recognizing old validation names in backups from earlier builds (#881).
    private func isTransientArchiveItem(_ name: String) -> Bool {
        name.hasPrefix(".keypath-session-validation-") || name.hasPrefix("temp_validation_") ||
            name.hasPrefix(Self.restoreStagingPrefix)
    }

    private func isFileNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError
        {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOENT) {
            return true
        }
        return false
    }

    private func sameResolvedPath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path ==
            rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func copiedItemNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "KeyPath.ConfigFacade", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

package struct CLIConfigBackupResult: Codable, Sendable {
    package let sourcePath: String
    package let backupPath: String
    package let copiedItems: [String]
}

package struct CLIConfigRestoreResult: Codable, Sendable {
    package let sourcePath: String
    package let restoredPath: String
    package let restoredItems: [String]
    package let reloadRequested: Bool
    package let reloadSuccess: Bool?
}
