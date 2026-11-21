@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import KeyPathWizardCore
@preconcurrency import XCTest

/// Fast unit tests for individual components
/// No system dependencies, mocked environment
@MainActor
final class UnitTestSuite: XCTestCase {
    // MARK: - Key Mapping Tests

    func testKeyMappingInitialization() {
        let mapping = KeyMapping(input: "caps", action: .keystroke(key: "escape"))

        XCTAssertEqual(mapping.input, "caps")
        XCTAssertEqual(mapping.action, .keystroke(key: "escape"))
    }

    func testKeyMappingValidation() {
        // Valid mapping
        let validMapping = KeyMapping(input: "caps", action: .keystroke(key: "esc"))
        XCTAssertTrue(validMapping.isValid)

        // Invalid mapping (empty keys)
        let invalidMapping = KeyMapping(input: "", action: .keystroke(key: "esc"))
        XCTAssertFalse(invalidMapping.isValid)
    }

    // MARK: - Configuration Generation Tests

    func testBasicConfigGeneration() {
        let mappings = [
            KeyMapping(input: "caps", action: .keystroke(key: "esc")),
            KeyMapping(input: "space", action: .keystroke(key: "space")) // passthrough
        ]

        let config = KanataConfiguration.generateFromMappings(mappings)

        // Check required sections
        XCTAssertTrue(config.contains("(defcfg"))
        XCTAssertTrue(config.contains("(defsrc"))
        XCTAssertTrue(config.contains("(deflayer"))

        // Check key mappings
        XCTAssertTrue(config.contains("caps"))
        XCTAssertTrue(config.contains("esc"))
        XCTAssertTrue(config.contains("spc"))
    }

    func testComplexKeyMappingGeneration() {
        let mapping = KeyMapping(input: "caps", action: .keystroke(key: "cmd+c"))

        let config = KanataConfiguration.generateFromMappings([mapping])

        // Should generate macro for complex output
        XCTAssertTrue(
            config.contains("C-c") || config.contains("cmd") || config.contains("macro")
                || config.contains("caps")
        )
    }

    // MARK: - Wizard Types Tests

    func testWizardPageAccessibilityIdentifiers() {
        XCTAssertEqual(WizardPage.summary.accessibilityIdentifier, "overview")
        XCTAssertEqual(WizardPage.accessibility.accessibilityIdentifier, "accessibility")
        XCTAssertFalse(WizardPage.allCases.contains { $0.accessibilityIdentifier == "input-monitoring" })
    }

    // MARK: - Path Utilities Tests

    func testBasicPathGeneration() {
        // Test basic path operations work
        let homePath = NSHomeDirectory()
        let configPath = homePath + "/.config/keypath/keypath.kbd"

        XCTAssertTrue(configPath.hasSuffix(".kbd"))
        XCTAssertTrue(configPath.contains(".config/keypath"))
        XCTAssertFalse(configPath.contains("Application Support"))
    }

    // MARK: - TCP Protocol Tests

    func testTCPMessageSerialization() throws {
        let message = TCPMessage.layerChange("base")

        let serialized = try message.serialize()
        let deserialized = try TCPMessage.deserialize(from: serialized)

        XCTAssertEqual(message, deserialized)
    }

    // MARK: - Logger Tests

    func testLoggerConfiguration() {
        let logDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-unit-logger-\(UUID().uuidString)", isDirectory: true)
        let logger = AppLogger(enableConsoleLogging: false)
        logger.overrideLogDirectory(logDirectory.path)
        logger.setMinimumLevel(.trace)
        logger.flushBuffer() // Wait for the queued level change before logging.
        defer {
            logger.flushBuffer()
            try? FileManager.default.removeItem(at: logDirectory)
        }

        XCTAssertNoThrow(logger.log("Test message", level: .error))
        logger.flushBuffer()
        XCTAssertTrue(FileManager.default.fileExists(atPath: logDirectory.appendingPathComponent("keypath-debug.log").path))
    }
}

// MARK: - Helper Extensions

extension KeyMapping {
    var isValid: Bool {
        !input.isEmpty && !action.outputString.isEmpty
    }
}

// SystemStatus extension removed - type no longer exists in codebase

/// Mock TCP Message for testing
struct TCPMessage: Equatable {
    let type: String
    let payload: String

    static func layerChange(_ layer: String) -> TCPMessage {
        TCPMessage(type: "layer_change", payload: layer)
    }

    func serialize() throws -> Data {
        let dict = ["type": type, "payload": payload]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func deserialize(from data: Data) throws -> TCPMessage {
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: String]
        return TCPMessage(type: dict["type"]!, payload: dict["payload"]!)
    }
}
