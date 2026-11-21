import AppKit
import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

final class UtilitiesTests: XCTestCase {
    private var loggers: [AppLogger] = []
    private var logDirectories: [URL] = []

    override func tearDown() {
        loggers.forEach { $0.flushBuffer() }
        logDirectories.forEach { try? FileManager.default.removeItem(at: $0) }
        loggers.removeAll()
        logDirectories.removeAll()
        super.tearDown()
    }

    private func makeLogger() -> AppLogger {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-logger-\(UUID().uuidString)", isDirectory: true)
        let logger = AppLogger(enableConsoleLogging: false)
        logger.overrideLogDirectory(directory.path)
        loggers.append(logger)
        logDirectories.append(directory)
        return logger
    }

    // MARK: - Logger Tests

    func testLogLevelEnvironmentOverrideIsExplicitlyControlled() {
        let environment = ["KEYPATH_LOG_LEVEL": "0"]
        let releaseLevel = AppLogger.configuredMinimumLevel(
            environment: environment,
            minimumLevel: .info,
            allowsEnvironmentOverride: false
        )
        let debugLevel = AppLogger.configuredMinimumLevel(
            environment: environment,
            minimumLevel: nil,
            allowsEnvironmentOverride: true
        )

        XCTAssertEqual(releaseLevel, .info)
        XCTAssertEqual(debugLevel, .trace)
    }

    func testLoggerSingleton() {
        let logger1 = AppLogger.shared
        let logger2 = AppLogger.shared

        XCTAssertTrue(logger1 === logger2, "Logger should be a singleton")
    }

    func testLoggerBasicLogging() {
        let logger = makeLogger()

        // Test basic logging doesn't crash
        logger.log("Test message")
        logger.log("Test message with special chars: !@#$%^&*()")
        logger.log("Test message with unicode: 🚀 中文 العربية")

        XCTAssertTrue(true, "Basic logging should not crash")
    }

    func testLoggerLongMessages() {
        let logger = makeLogger()

        // Test very long message
        let longMessage = String(repeating: "A", count: 10000)
        logger.log(longMessage)

        // Test message with many lines
        let multilineMessage = Array(repeating: "Line of text", count: 100).joined(separator: "\n")
        logger.log(multilineMessage)

        XCTAssertTrue(true, "Long messages should be handled gracefully")
    }

    func testLoggerEmptyMessages() {
        let logger = makeLogger()

        // Test edge cases
        logger.log("")
        logger.log(" ")
        logger.log("\n")
        logger.log("\t")

        XCTAssertTrue(true, "Empty or whitespace messages should not crash")
    }

    func testLoggerFlushBuffer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-logger-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logger = AppLogger(enableConsoleLogging: false)
        logger.overrideLogDirectory(directory.path)
        logger.error("Pending log entry")
        logger.flushBuffer()

        let log = try String(contentsOf: directory.appendingPathComponent("keypath-debug.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("Pending log entry"))
    }

    func testLoggerClearAllLogs() {
        let logger = makeLogger()

        // Log some messages
        logger.log("Message before clear")
        logger.log("Another message")

        // Clear logs
        logger.clearAllLogs()

        // Log after clear
        logger.log("Message after clear")

        XCTAssertTrue(true, "Clear logs should complete without error")
    }

    func testLoggerLogSize() {
        let logger = makeLogger()

        // Test log size methods
        let currentSize = logger.getCurrentLogSize()
        let totalSize = logger.getTotalLogSize()

        XCTAssertGreaterThanOrEqual(currentSize, 0, "Current log size should be non-negative")
        XCTAssertGreaterThanOrEqual(totalSize, currentSize, "Total size should be >= current size")
    }

    func testLoggerDirectoryCreation() {
        // Test that logger initializes without crashing even if directory creation fails
        // This is handled in the logger's init method
        let logger = makeLogger()

        XCTAssertNotNil(logger, "Logger should initialize even with directory issues")
    }

    func testLoggerFileInformation() {
        let logger = makeLogger()

        // Test logging with file information
        logger.log("Test message with file info", file: #file, function: #function, line: #line)

        XCTAssertTrue(true, "Logging with file information should work")
    }

    func testLoggerConcurrentAccess() throws {
        // Flaky on the loaded self-hosted CI runner: 10 .background-QoS tasks
        // can starve past the 5s timeout under parallel-lane load. The test
        // asserts nothing real (XCTAssertTrue(true) — it only checks the logger
        // doesn't deadlock), so gating it on CI loses no coverage. Should be
        // rewritten as a deterministic concurrency check or removed. Tracked
        // in #922.
        if ProcessInfo.processInfo.environment["CI_ENVIRONMENT"] == "true" {
            throw XCTSkip("Skipped on CI — timing flake, no real assertion (#922)")
        }
        let logger = makeLogger()
        let expectation = expectation(description: "Concurrent logging")
        expectation.expectedFulfillmentCount = 10

        // Test concurrent logging from multiple queues
        for i in 0 ..< 10 {
            DispatchQueue.global(qos: .background).async {
                logger.log("Concurrent message \(i)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(true, "Concurrent logging should be thread-safe")
    }

    func testLoggerRotationBehavior() {
        let logger = makeLogger()

        // We can't easily test actual rotation without creating large files,
        // but we can test that the rotation methods exist and don't crash
        let sizeBefore = logger.getCurrentLogSize()

        // Log a bunch of messages to potentially trigger rotation checks
        for i in 0 ..< 100 {
            logger.log("Rotation test message \(i) with some additional content to increase size")
        }

        let sizeAfter = logger.getCurrentLogSize()
        XCTAssertGreaterThanOrEqual(
            sizeAfter, sizeBefore, "Log size should increase or stay same after logging"
        )
    }

    // MARK: - Error Handling Tests

    func testLoggerErrorHandling() throws {
        let logger = makeLogger()

        // Test logging during error conditions
        do {
            throw NSError(
                domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"]
            )
        } catch {
            logger.log("Caught error: \(error.localizedDescription)")
        }

        XCTAssertTrue(true, "Error logging should work correctly")
    }

    func testLoggerMemoryPressure() {
        let logger = makeLogger()

        // Test logger behavior under memory pressure
        // Log many large messages rapidly
        for i in 0 ..< 50 {
            let largeMessage = String(repeating: "Memory pressure test \(i) ", count: 100)
            logger.log(largeMessage)
        }

        // Force flush and clear to test cleanup
        logger.flushBuffer()

        XCTAssertTrue(true, "Logger should handle memory pressure gracefully")
    }

    func testLoggerPathHandling() {
        let logger = makeLogger()

        // Test that logger handles path issues gracefully
        // The logger should fallback to temp directory if project path fails

        // Log a message to ensure logger is working
        logger.log("Path handling test")

        // Get log sizes to verify logger is functional
        let currentSize = logger.getCurrentLogSize()
        XCTAssertGreaterThanOrEqual(
            currentSize, 0, "Logger should be functional regardless of path issues"
        )
    }

    // MARK: - Performance Tests

    func testLoggerPerformance() {
        let logger = makeLogger()

        measure {
            for i in 0 ..< 1000 {
                logger.log("Performance test message \(i)")
            }
        }
    }

    func testLoggerFlushPerformance() {
        let logger = makeLogger()

        // Fill up buffer
        for i in 0 ..< 50 {
            logger.log("Buffer fill message \(i)")
        }

        measure {
            logger.flushBuffer()
        }
    }
}
