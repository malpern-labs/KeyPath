import Foundation
import XCTest

/// Owns one private defaults domain; never clears a shared or app domain.
final class IsolatedPreferenceDefaults {
    let suiteName = "KeyPathTests.preferences.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
