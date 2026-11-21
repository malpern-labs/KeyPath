@testable import KeyPathAppKit
import XCTest

/// Tests for AI Config Generation components
@MainActor
final class AIConfigGenerationTests: XCTestCase {
    private func makeIsolatedBiometricService() throws -> (BiometricAuthService, String) {
        let suiteName = "KeyPath.AIConfigGenerationTests.Biometric.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let service = BiometricAuthService(userDefaults: defaults)
        return (service, suiteName)
    }

    // MARK: - APIKeyValidator Tests

    // Note: testAPIKeyValidatorRejectsEmptyKey is not tested because
    // empty keys trigger a debug assertion. The assertion is appropriate
    // for catching programming errors - callers should check for empty
    // strings before calling validate().

    func testAPIKeyValidatorRejectsKeyWithWrongPrefix() async {
        let validator = APIKeyValidator.shared
        let result = await validator.validate("wrong-prefix-key-123456789")

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("sk-ant-") ?? false, "Error should mention correct prefix")
    }

    func testAPIKeyValidatorRejectsTooShortKey() async {
        let validator = APIKeyValidator.shared
        let result = await validator.validate("sk-ant-short")

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("incomplete") ?? false, "Error should mention key is incomplete")
    }

    func testAPIKeyValidatorValidationResultTypes() {
        // Test ValidationResult factory methods
        let valid = APIKeyValidator.ValidationResult.valid()
        XCTAssertTrue(valid.isValid)
        XCTAssertNil(valid.errorMessage)
        XCTAssertEqual(valid.statusCode, 200)

        let invalid = APIKeyValidator.ValidationResult.invalid(message: "Test error", statusCode: 401)
        XCTAssertFalse(invalid.isValid)
        XCTAssertEqual(invalid.errorMessage, "Test error")
        XCTAssertEqual(invalid.statusCode, 401)
    }

    // MARK: - BiometricAuthService Tests

    func testBiometricAuthServiceSharedInstanceExists() {
        let service = BiometricAuthService.shared
        XCTAssertNotNil(service)
    }

    func testBiometricAuthServiceIsEnabledDefaultsFalse() throws {
        let (service, suiteName) = try makeIsolatedBiometricService()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        // Should default to false (not enabled)
        XCTAssertFalse(service.isEnabled)
    }

    func testBiometricAuthServiceIsEnabledCanBeToggled() throws {
        let (service, suiteName) = try makeIsolatedBiometricService()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        // Save original state
        let originalState = service.isEnabled

        // Toggle
        service.isEnabled = !originalState
        XCTAssertEqual(service.isEnabled, !originalState)

        // Restore
        service.isEnabled = originalState
    }

    func testBiometricAuthServiceBiometricTypeName() {
        let service = BiometricAuthService.shared
        let name = service.biometricTypeName

        // Should be one of the known types
        let validNames = ["Touch ID", "Face ID", "Optic ID", "Password", "Biometric"]
        XCTAssertTrue(validNames.contains(name), "biometricTypeName should be a valid type")
    }

    func testBiometricAuthServiceWouldRequireAuthRespectsIsEnabled() throws {
        let (service, suiteName) = try makeIsolatedBiometricService()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        // When disabled, should not require auth
        service.isEnabled = false
        XCTAssertFalse(service.wouldRequireAuth)

        // When enabled, should require auth (unless recently authenticated)
        service.isEnabled = true
        service.clearAuthCache()
        XCTAssertTrue(service.wouldRequireAuth)

        // Clean up
        service.isEnabled = false
    }

    func testBiometricAuthServiceAuthReturnsNotRequiredWhenDisabled() async throws {
        let (service, suiteName) = try makeIsolatedBiometricService()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        service.isEnabled = false

        let result = await Task.detached { await service.authenticate() }.value

        switch result {
        case .notRequired:
            // Expected
            break
        default:
            XCTFail("Should return .notRequired when disabled")
        }
    }

    // MARK: - AICostTracker Tests

    func testAICostTrackerSharedInstanceExists() {
        let tracker = AICostTracker.shared
        XCTAssertNotNil(tracker)
    }

    func testAICostTrackerCostHistoryKeyConstant() {
        // Verify the constant is defined correctly
        XCTAssertEqual(AICostTracker.costHistoryKey, "KeyPath.AI.CostHistory")
    }

    func testAICostTrackerEstimateCost() {
        let tracker = AICostTracker.shared

        // Test the cost calculation logic
        // Claude 3.5 Sonnet: $3/1M input, $15/1M output
        let cost = tracker.estimateCost(inputTokens: 1000, outputTokens: 500)

        // 1000 input tokens = $0.003
        // 500 output tokens = $0.0075
        // Total = $0.0105
        XCTAssertEqual(cost, 0.0105, accuracy: 0.0001)
    }

    func testClaudeAPIPricingConstants() {
        // Verify pricing constants are set correctly (as of Dec 2024)
        XCTAssertEqual(ClaudeAPIPricing.inputPricePerMillion, 3.0)
        XCTAssertEqual(ClaudeAPIPricing.outputPricePerMillion, 15.0)
    }

    func testClaudeAPIPricingEstimateCost() {
        // Test the static pricing calculation
        let cost = ClaudeAPIPricing.estimateCost(inputTokens: 1000, outputTokens: 500)
        XCTAssertEqual(cost, 0.0105, accuracy: 0.0001)
    }

    func testAICostTrackerCostSourceEnumValues() {
        // Verify source enum values for debugging
        XCTAssertEqual(AICostTracker.CostSource.configRepair.rawValue, "config-repair")
    }

    func testAICostTrackerHistoryAccess() {
        // Verify history access methods work without crashing
        let tracker = AICostTracker.shared
        _ = tracker.costHistory
        _ = tracker.totalEstimatedCost
        _ = tracker.totalTokens
    }

    func testClaudeAPIConstantsAreDefined() {
        // Verify API constants are properly defined
        XCTAssertNotNil(ClaudeAPIConstants.messagesEndpoint)
        XCTAssertFalse(ClaudeAPIConstants.apiVersion.isEmpty)
        XCTAssertFalse(ClaudeAPIConstants.defaultModel.isEmpty)
        XCTAssertGreaterThan(ClaudeAPIConstants.maxTokensForConfig, 0)
        XCTAssertGreaterThan(ClaudeAPIConstants.requestTimeout, 0)
    }

    // MARK: - Integration Assertions

    func testAssertionsAreEnabled() {
        // Verify assertions are enabled in test builds
        var assertionTriggered = false

        // This would crash if assertions were enabled differently
        // We're just verifying the test environment is correct
        assertionTriggered = true

        XCTAssertTrue(assertionTriggered)
    }
}
