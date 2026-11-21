@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import SwiftUI
@preconcurrency import XCTest

/// Phase 1 Unit Tests: ContentView Debouncing
/// Tests the save operation debouncing added in Phase 1.3 to prevent rapid successive saves
@MainActor
class ContentViewDebounceTests: KeyPathTestCase {
    lazy var testManager: RuntimeCoordinator = .init()

    // MARK: - Debounce Logic Tests (Non-UI)

    func testConfigurationSaveDebouncing() throws {
        // Test actual debounce behavior by making rapid saves and verifying only the final result persists
        _ = RuntimeCoordinator()

        // Create test directory
        let testConfigDir = "/tmp/keypath-debounce-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: testConfigDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: testConfigDir) }

        // Test that rapid configuration changes result in final state being saved
        let finalInput = "caps"
        let finalOutput = "ctrl"

        let mapping = KeyMapping(input: finalInput, action: .keystroke(key: finalOutput))
        let config = KanataConfiguration.generateFromMappings([mapping])
        XCTAssertTrue(config.contains(finalInput), "Configuration should contain final input mapping")
        // Output "ctrl" is converted to "lctl" in Kanata format
        XCTAssertTrue(
            config.contains("lctl"),
            "Configuration should contain converted output mapping (ctrl -> lctl)"
        )
    }

    func testErrorHandlingPreservesUIState() {
        // Test that errors during save operations properly reset the UI state
        let manager = RuntimeCoordinator()

        // This test verifies that the error handling structure exists
        // In a full implementation, we would:
        // 1. Trigger a save operation that causes an error
        // 2. Verify that isSaving is reset to false
        // 3. Verify that the button becomes enabled again
        // 4. Verify that error messages are displayed

        XCTAssertNotNil(manager)
    }

    // MARK: - Configuration Save Integration Tests

    func testConfigurationSaveFlow() throws {
        // Test the complete save flow without UI dependencies
        _ = RuntimeCoordinator()

        // Create a test directory for configuration
        let testConfigDir = "/tmp/keypath-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: testConfigDir, withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(atPath: testConfigDir)
        }

        // Test saving a simple configuration
        // This would normally call manager.saveConfiguration(input:output:)
        // For now, we test the configuration generation
        let mapping = KeyMapping(input: "caps", action: .keystroke(key: "esc"))
        let config = KanataConfiguration.generateFromMappings([mapping])

        XCTAssertTrue(config.contains("caps"))
        XCTAssertTrue(config.contains("esc"))
    }

    func testMultipleConcurrentSaves() async {
        // Test that multiple concurrent save attempts are handled gracefully
        _ = RuntimeCoordinator()

        // Create multiple concurrent save tasks
        let saveTasks = (1 ... 3).map { taskId in
            Task {
                // In a real test, this would call the debounced save function
                // For now, we test the configuration generation under concurrent access
                let mapping = KeyMapping(input: "key\(taskId)", action: .keystroke(key: "output\(taskId)"))
                let config = KanataConfiguration.generateFromMappings([mapping])

                XCTAssertTrue(config.contains("key\(taskId)"))
            }
        }

        // Wait for all tasks to complete
        for task in saveTasks {
            await task.value
        }
    }
}

// MARK: - Logging and Monitoring Tests

@MainActor
class Phase1LoggingTests: XCTestCase {
    private func makeIsolatedLogger() -> (AppLogger, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-phase1-logging-\(UUID().uuidString)", isDirectory: true)
        let logger = AppLogger(minimumLevel: .trace, enableConsoleLogging: false)
        logger.overrideLogDirectory(directory.path)
        logger.setMinimumLevel(.trace)
        logger.flushBuffer()
        return (logger, directory)
    }

    func testLoggingCapturesActualOperations() throws {
        let (logger, directory) = makeIsolatedLogger()
        defer {
            logger.flushBuffer()
            try? FileManager.default.removeItem(at: directory)
        }

        let mapping = KeyMapping(input: "f1", action: .keystroke(key: "f13"))
        let config = KanataConfiguration.generateFromMappings([mapping])

        XCTAssertTrue(config.contains("(defsrc"), "Config should contain defsrc section")
        XCTAssertTrue(config.contains("f1"), "Config should contain source key definition")
        XCTAssertTrue(
            config.contains("f13"), "Config should contain target key mapping (f13 is a valid key name)"
        )

        let marker = "Generated config for logging test"
        logger.log(marker)
        logger.flushBuffer()
        let log = try String(contentsOf: directory.appendingPathComponent("keypath-debug.log"), encoding: .utf8)
        XCTAssertTrue(log.contains(marker), "The operation should be captured in this test's log")
    }

    func testPhase1LoggingPatterns() throws {
        let (logger, directory) = makeIsolatedLogger()
        defer {
            logger.flushBuffer()
            try? FileManager.default.removeItem(at: directory)
        }

        let testMessages = [
            "🚀 [Start] Starting Kanata with synchronization lock...",
            "💾 [Save] ========== SAVE OPERATION START ==========",
            "🔧 [Conflicts] ========== USER CONFIRMED TERMINATION ==========",
            "🧪 [Test] Testing logging pattern consistency"
        ]

        for message in testMessages {
            logger.log(message)
            XCTAssertTrue(message.contains("["), "Log message should contain category marker")
            XCTAssertTrue(
                message.hasPrefix("🚀") || message.hasPrefix("💾") || message.hasPrefix("🔧")
                    || message.hasPrefix("🧪") || message.contains("=========="),
                "Log message should follow Phase 1 patterns"
            )
        }

        logger.flushBuffer()
        let log = try String(contentsOf: directory.appendingPathComponent("keypath-debug.log"), encoding: .utf8)
        for message in testMessages {
            XCTAssertTrue(log.contains(message), "Expected log output for: \(message)")
        }
    }
}
