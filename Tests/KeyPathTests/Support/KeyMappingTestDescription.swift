@testable import KeyPathAppKit
import KeyPathRulesCore

/// Human-readable mapping text for tests that assert pack descriptions.
extension KeyMapping {
    var description: String {
        "\(input) → \(action.outputString)"
    }
}
