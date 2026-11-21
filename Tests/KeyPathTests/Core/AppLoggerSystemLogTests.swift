@testable import KeyPathCore
import OSLog
import XCTest

/// AppLogger also writes to the unified log, so Console can filter KeyPath by
/// subsystem, category (source file) and level. The text itself is private.
final class AppLoggerSystemLogTests: XCTestCase {
    func testAWarningReachesTheUnifiedLogUnderItsSourceFile() throws {
        let start = Date().addingTimeInterval(-1)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-system-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = AppLogger(minimumLevel: .trace, enableConsoleLogging: false)
        logger.overrideLogDirectory(directory.path)
        logger.setMinimumLevel(.trace)
        logger.flushBuffer()

        logger.warn("system log wiring check \(UUID().uuidString)")
        logger.flushBuffer()

        let entry = try XCTUnwrap(
            try entries(since: start).first { $0.category == "AppLoggerSystemLogTests" },
            "AppLogger.warn did not reach the unified log"
        )
        XCTAssertEqual(entry.subsystem, Bundle.main.bundleIdentifier ?? "com.keypath.KeyPath")
        XCTAssertEqual(entry.level, .error, "os.Logger.warning is recorded at the error level")
    }

    func testTheMessageTextIsPrivate() throws {
        let token = "applogger-private-\(UUID().uuidString)"
        let category = "AppLoggerPrivacy-\(UUID().uuidString)"
        let start = Date().addingTimeInterval(-1)

        AppLogger.writeToSystemLog("held key codes \(token)", level: .error, category: category)

        let entry = try XCTUnwrap(try entries(since: start).first { $0.category == category })
        XCTAssertFalse(entry.composedMessage.contains(token), "message text must not be public in the unified log")
    }

    private func entries(since date: Date) throws -> [OSLogEntryLog] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        return try store.getEntries(at: store.position(date: date)).compactMap { $0 as? OSLogEntryLog }
    }
}
