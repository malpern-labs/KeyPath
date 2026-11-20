import Darwin
import Foundation
import KeyPathCore

/// Copies or restores a snapshot under the configuration directory's existing operation gate.
package struct ConfigurationArchive: Sendable {
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

        // Copy-over first, prune extras second: a failure at any point leaves the
        // user with a superset of their config, never a gutted directory. The
        // previous wipe-then-copy ordering lost data when a transient
        // temp_validation_*.kbd file vanished mid-wipe and aborted the restore
        // before anything was copied back (#881).
        try overwriteDirectoryContents(from: resolvedSourceURL, to: restoreTargetURL, fileManager: fileManager)
        try pruneExtraneousItems(
            at: restoreTargetURL,
            keeping: Set(fileManager.contentsOfDirectory(atPath: resolvedSourceURL.path)),
            fileManager: fileManager
        )

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
            if isTransientValidationArtifact(item.lastPathComponent) { continue }
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

    /// Copy every backup item over the destination, replacing existing entries
    /// in place. Unlike wipe-then-copy, an interruption never leaves the
    /// destination with less data than it started with.
    private func overwriteDirectoryContents(from source: URL, to destination: URL, fileManager: FileManager) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            if isTransientValidationArtifact(item.lastPathComponent) { continue }
            let target = destination.appendingPathComponent(item.lastPathComponent)
            do {
                try fileManager.removeItem(at: target)
            } catch where isFileNotFound(error) {
                // Nothing to replace — fine.
            }
            try fileManager.copyItem(at: item, to: target)
        }
    }

    /// Remove destination items that aren't part of the backup. Tolerates
    /// files that vanish mid-iteration (their owner cleaned up — that's the
    /// goal state) and skips transient validation artifacts entirely.
    private func pruneExtraneousItems(at directory: URL, keeping names: Set<String>, fileManager: FileManager) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            let name = item.lastPathComponent
            if names.contains(name) || isTransientValidationArtifact(name) { continue }
            do {
                try fileManager.removeItem(at: item)
            } catch where isFileNotFound(error) {
                // Already gone — pruning succeeded by other means.
            }
        }
    }

    /// Validation candidates and their safe-save shadows are transient. Keep
    /// recognizing old names when restoring backups from earlier builds (#881).
    private func isTransientValidationArtifact(_ name: String) -> Bool {
        name.hasPrefix(".keypath-session-validation-") || name.hasPrefix("temp_validation_")
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
