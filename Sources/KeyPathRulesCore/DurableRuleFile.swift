import Darwin
import Foundation
import KeyPathCore

/// Persist rule data and its directory entry before advancing a transaction.
package enum DurableRuleFile {
    package struct SystemFailure: LocalizedError {
        let operation: String
        let code: Int32

        package init(_ operation: String, _ code: Int32) {
            self.operation = operation
            self.code = code
        }

        package var errorDescription: String? {
            String(localized: "Rule-write \(operation) failed (errno \(String(code))).")
        }
    }

    package static func write(_ data: Data, _ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw SystemFailure("open", errno) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw SystemFailure("fsync", errno) }
        try syncDirectory(parent)
    }

    package static func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw SystemFailure("open directory", errno) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw SystemFailure("fsync directory", errno) }
    }

    /// The config folder holds the user's mappings, including any scripts and
    /// URLs they bind, so only the user can read it. An older KeyPath created it
    /// 0755; tighten that once, without touching files inside.
    package static func restrictToOwner(directory path: String) {
        // A linked folder (dotfiles) may point at something shared, such as the
        // whole dotfiles folder, so its owner decides its permissions.
        let fileManager = Foundation.FileManager()
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              let mode = attributes[.posixPermissions] as? Int,
              mode & 0o077 != 0
        else { return }
        do {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            AppLogger.shared.log("🔐 [ConfigService] Restricted \(path) to its owner")
        } catch {
            AppLogger.shared.log("⚠️ [ConfigService] Could not restrict \(path): \(error.localizedDescription)")
        }
    }
}
