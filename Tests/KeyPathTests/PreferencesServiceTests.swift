@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

@MainActor
final class PreferencesServiceTests: XCTestCase {
    private var fixture: IsolatedPreferenceDefaults!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try IsolatedPreferenceDefaults()
    }

    override func tearDown() async throws {
        fixture = nil
        try await super.tearDown()
    }

    private func makePreferences() -> PreferencesService {
        PreferencesService(leaderDefaults: fixture.defaults, defaults: fixture.defaults)
    }

    func testCanonicalDefaultsFallsBackToTestDomainWhenSuiteIsUnavailable() {
        let defaults = RecoverableRuleWrite.PreferenceDefaults.canonical(using: nil)
        XCTAssertFalse(defaults === UserDefaults.standard)

        let key = "KeyPathTests.preference-defaults.\(UUID().uuidString)"
        defaults.set(true, forKey: key)
        defer { defaults.removeObject(forKey: key) }
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    // MARK: - Context HUD Hold Delay

    func testContextHUDHoldDelayMs_ShortPreset() {
        let prefs = makePreferences()
        prefs.contextHUDHoldDelayPreset = .short
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 150)
    }

    func testContextHUDHoldDelayMs_MediumPreset() {
        let prefs = makePreferences()
        prefs.contextHUDHoldDelayPreset = .medium
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 200)
    }

    func testContextHUDHoldDelayMs_LongPreset() {
        let prefs = makePreferences()
        prefs.contextHUDHoldDelayPreset = .long
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 300)
    }

    func testContextHUDHoldDelayMs_CustomPresetUsesCustomValue() {
        let prefs = makePreferences()
        prefs.contextHUDHoldDelayCustomMs = 175
        prefs.contextHUDHoldDelayPreset = .custom
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 175)
    }

    // MARK: - Enum Display Names

    func testKeyLabelStyle_AllCasesHaveDisplayNames() {
        for style in KeyLabelStyle.allCases {
            XCTAssertFalse(style.displayName.isEmpty, "\(style) missing displayName")
            XCTAssertFalse(style.description.isEmpty, "\(style) missing description")
        }
    }

    func testContextHUDDisplayMode_AllCasesHaveDisplayNames() {
        for mode in ContextHUDDisplayMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode) missing displayName")
        }
    }

    func testContextHUDTriggerMode_AllCasesHaveDisplayNames() {
        for mode in ContextHUDTriggerMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode) missing displayName")
            XCTAssertFalse(mode.description.isEmpty, "\(mode) missing description")
        }
    }

    func testContextHUDHoldDelayPreset_AllCasesHaveDisplayNames() {
        for preset in ContextHUDHoldDelayPreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty, "\(preset) missing displayName")
        }
    }

    func testContextHUDHoldDelayPreset_MillisecondsValues() {
        XCTAssertEqual(ContextHUDHoldDelayPreset.short.milliseconds, 150)
        XCTAssertEqual(ContextHUDHoldDelayPreset.medium.milliseconds, 200)
        XCTAssertEqual(ContextHUDHoldDelayPreset.long.milliseconds, 300)
        XCTAssertNil(ContextHUDHoldDelayPreset.custom.milliseconds)
    }

    func testKindaVimLeaderHUDMode_AllCasesHaveDisplayNames() {
        for mode in KindaVimLeaderHUDMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode) missing displayName")
            XCTAssertFalse(mode.description.isEmpty, "\(mode) missing description")
        }
    }

    // MARK: - KeyLabelStyle raw values

    func testKeyLabelStyle_RawValues() {
        XCTAssertEqual(KeyLabelStyle.symbols.rawValue, "symbols")
        XCTAssertEqual(KeyLabelStyle.text.rawValue, "text")
    }

    func testKeyLabelStyle_InitFromRawValue() {
        XCTAssertEqual(KeyLabelStyle(rawValue: "symbols"), .symbols)
        XCTAssertEqual(KeyLabelStyle(rawValue: "text"), .text)
        XCTAssertNil(KeyLabelStyle(rawValue: "unknown"))
    }
}
