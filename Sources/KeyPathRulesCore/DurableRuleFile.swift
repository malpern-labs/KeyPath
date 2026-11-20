import Darwin
import Foundation

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
}
