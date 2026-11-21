@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class PreferencesServicePersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuite: String!
    private var notificationCenter: NotificationCenter!

    override func setUp() async throws {
        try await super.setUp()
        defaultsSuite = "keypath-preference-test-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        notificationCenter = NotificationCenter()
    }

    override func tearDown() async throws {
        if let defaultsSuite { defaults?.removePersistentDomain(forName: defaultsSuite) }
        defaults = nil
        defaultsSuite = nil
        notificationCenter = nil
        try await super.tearDown()
    }

    private func makePreferences() -> PreferencesService {
        PreferencesService(leaderDefaults: defaults, defaults: defaults, notificationCenter: notificationCenter)
    }

    private static let preferenceKeys = [
        "KeyPath.TCP.ServerPort",
        "KeyPath.Notifications.Enabled",
        "KeyPath.Recording.ApplyMappingsDuringRecording",
        "KeyPath.Recording.IsSequenceMode",
        "KeyPath.Diagnostics.VerboseKanataLogging",
        "KeyPath.Testing.AccessibilityTestMode",
        "KeyPath.LeaderKey.Preference",
        "KeyPath.ContextHUD.DisplayMode",
        "KeyPath.ContextHUD.TriggerMode",
        "KeyPath.ContextHUD.HoldDelayPreset",
        "KeyPath.ContextHUD.HoldDelayCustomMs",
        "KeyPath.KindaVim.LeaderHUDMode",
        "KeyPath.Neovim.ReferenceTopics",
        "KeyPath.Neovim.ReferenceTopicsVersion",
        "KeyPath.Display.KeyLabelStyle",
        "KeyPath.Overlay.UnmappedLayerKeyStyle",
        "KeyPath.Education.OverlayHiddenHintShowCount",
        "KeyPath.Overlay.SuppressedBundleIDs",
        "KeyPath.Overlay.Opacity",
        "KeyPath.Overlay.ShowsOnlyWhileLayerHeld",
        "KeyPath.Overlay.FadesWhenIdle",
    ]

    private func withPreservedDefaults<T>(
        keys: [String] = PreferencesServicePersistenceTests.preferenceKeys,
        _ body: () throws -> T
    ) rethrows -> T {
        let savedValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = savedValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        return try body()
    }

    // MARK: - Critical Preference Round Trips

    func testCriticalSettings_RoundTripThroughUserDefaults() {
        withPreservedDefaults {
            for key in Self.preferenceKeys {
                defaults.removeObject(forKey: key)
            }

            let leader = LeaderKeyPreference(
                key: "tab",
                targetLayer: .custom("window"),
                enabled: false
            )
            let writer = makePreferences()
            defaults.set(45678, forKey: "KeyPath.TCP.ServerPort")
            writer.notificationsEnabled = false
            writer.applyMappingsDuringRecording = false
            writer.isSequenceMode = false
            writer.verboseKanataLogging = false
            writer.accessibilityTestMode = true
            writer.keyLabelStyle = .text
            writer.unmappedLayerKeyStyle = .dimmed
            writer.leaderKeyPreference = leader
            writer.overlayHiddenHintShowCount = 3
            writer.overlaySuppressedBundleIDs = Set(["com.example.Editor", "com.example.Terminal"])
            writer.contextHUDDisplayMode = .both
            writer.contextHUDTriggerMode = .tapToToggle
            writer.contextHUDHoldDelayPreset = .custom
            writer.contextHUDHoldDelayCustomMs = 750
            writer.kindaVimLeaderHUDMode = .cheatSheetOnly
            writer.neovimReferenceTopics = Set([
                NeovimTerminalCategory.basicMotions.rawValue,
                NeovimTerminalCategory.search.rawValue,
            ])

            let loaded = makePreferences()

            XCTAssertEqual(defaults.integer(forKey: "KeyPath.TCP.ServerPort"), 45678)
            XCTAssertFalse(loaded.notificationsEnabled)
            XCTAssertFalse(loaded.applyMappingsDuringRecording)
            XCTAssertFalse(loaded.isSequenceMode)
            XCTAssertFalse(loaded.verboseKanataLogging)
            XCTAssertTrue(loaded.accessibilityTestMode)
            XCTAssertEqual(loaded.keyLabelStyle, .text)
            XCTAssertEqual(loaded.unmappedLayerKeyStyle, .dimmed)
            XCTAssertEqual(loaded.leaderKeyPreference, leader)
            XCTAssertEqual(loaded.overlayHiddenHintShowCount, 3)
            XCTAssertEqual(loaded.overlaySuppressedBundleIDs, Set(["com.example.Editor", "com.example.Terminal"]))
            XCTAssertEqual(loaded.contextHUDDisplayMode, .both)
            XCTAssertEqual(loaded.contextHUDTriggerMode, .tapToToggle)
            XCTAssertEqual(loaded.contextHUDHoldDelayPreset, .custom)
            XCTAssertEqual(loaded.contextHUDHoldDelayCustomMs, 750)
            XCTAssertEqual(loaded.contextHUDHoldDelayMs, 750)
            XCTAssertEqual(loaded.kindaVimLeaderHUDMode, .cheatSheetOnly)
            XCTAssertEqual(
                loaded.neovimReferenceTopics,
                Set([
                    NeovimTerminalCategory.basicMotions.rawValue,
                    NeovimTerminalCategory.search.rawValue,
                ])
            )
        }
    }

    func testLoadClampsInvalidPersistedRuntimeAndHUDValues() {
        withPreservedDefaults {
            defaults.set(80, forKey: "KeyPath.TCP.ServerPort")
            defaults.set(-25, forKey: "KeyPath.ContextHUD.HoldDelayCustomMs")

            let prefs = makePreferences()

            XCTAssertEqual(defaults.integer(forKey: "KeyPath.TCP.ServerPort"), 80)
            XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 100)
            XCTAssertEqual(defaults.integer(forKey: "KeyPath.ContextHUD.HoldDelayCustomMs"), 100)
        }
    }

    func testLoadFallsBackForInvalidStoredEnumsAndLeaderPreference() {
        withPreservedDefaults {
            defaults.set("emoji", forKey: "KeyPath.Display.KeyLabelStyle")
            defaults.set("invisible", forKey: "KeyPath.Overlay.UnmappedLayerKeyStyle")
            defaults.set("drawer", forKey: "KeyPath.ContextHUD.DisplayMode")
            defaults.set("doubleTap", forKey: "KeyPath.ContextHUD.TriggerMode")
            defaults.set("instant", forKey: "KeyPath.ContextHUD.HoldDelayPreset")
            defaults.set("coach", forKey: "KeyPath.KindaVim.LeaderHUDMode")
            defaults.set(Data("not-json".utf8), forKey: "KeyPath.LeaderKey.Preference")
            defaults.set(["search", "bogus-topic"], forKey: "KeyPath.Neovim.ReferenceTopics")
            defaults.set(2, forKey: "KeyPath.Neovim.ReferenceTopicsVersion")

            let prefs = makePreferences()

            XCTAssertEqual(prefs.keyLabelStyle, .symbols)
            XCTAssertEqual(prefs.unmappedLayerKeyStyle, .baseLayer)
            XCTAssertEqual(prefs.contextHUDDisplayMode, .none)
            XCTAssertEqual(prefs.contextHUDTriggerMode, .holdToShow)
            XCTAssertEqual(prefs.contextHUDHoldDelayPreset, .long)
            XCTAssertEqual(prefs.kindaVimLeaderHUDMode, .off)
            XCTAssertEqual(prefs.leaderKeyPreference, .default)
            XCTAssertEqual(prefs.neovimReferenceTopics, Set([NeovimTerminalCategory.search.rawValue]))
        }
    }

    func testShortcutListPreferenceChangesPersistWithoutLegacyNotification() {
        withPreservedDefaults {
            let prefs = makePreferences()
            let recorder = NotificationRecorder()
            let center = notificationCenter!
            let observedNames: [Notification.Name] = [
                .verboseLoggingChanged,
                .accessibilityTestModeChanged,
                .overlaySuppressedBundleIDsChanged,
                .configAffectingPreferenceChanged,
            ]
            let observers = observedNames.map { name in
                center.addObserver(forName: name, object: nil, queue: nil) { notification in
                    recorder.record(notification.name)
                }
            }
            defer {
                for observer in observers {
                    center.removeObserver(observer)
                }
            }

            prefs.verboseKanataLogging.toggle()
            prefs.accessibilityTestMode.toggle()
            prefs.overlaySuppressedBundleIDs = Set(["com.example.SuppressMe"])
            prefs.contextHUDTriggerMode = prefs.contextHUDTriggerMode == .holdToShow ? .tapToToggle : .holdToShow
            prefs.contextHUDHoldDelayPreset = .custom
            prefs.contextHUDHoldDelayCustomMs = 444

            let postedNames = recorder.names
            XCTAssertTrue(postedNames.contains(.verboseLoggingChanged))
            XCTAssertTrue(postedNames.contains(.accessibilityTestModeChanged))
            XCTAssertTrue(postedNames.contains(.overlaySuppressedBundleIDsChanged))
            // Generation now uses a staged, durable shortcut input instead of
            // an ambient notification-driven regeneration path.
            XCTAssertFalse(postedNames.contains(.configAffectingPreferenceChanged))
        }
    }

    func testRuntimePreferencesAffectKanataLaunchArguments() {
        withPreservedDefaults {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("PreferencesServiceConfigArgs-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let configService = ConfigurationService(configDirectory: tempDir.path)
            let prefs = makePreferences()
            let manager = ConfigurationManager(configurationService: configService, preferences: prefs)
            let originalVerboseLogging = prefs.verboseKanataLogging
            defer {
                prefs.verboseKanataLogging = originalVerboseLogging
            }

            defaults.set(45678, forKey: "KeyPath.TCP.ServerPort")
            prefs.verboseKanataLogging = true

            let verboseArgs = manager.buildKanataArguments(checkOnly: false)
            XCTAssertNil(verboseArgs.portArgumentValue, "KeyPath no longer gives kanata a TCP port (ADR-046)")
            XCTAssertTrue(verboseArgs.contains("--trace"))
            XCTAssertTrue(verboseArgs.contains("--log-layer-changes"))

            prefs.verboseKanataLogging = false
            let normalArgs = manager.buildKanataArguments(checkOnly: false)
            XCTAssertNil(normalArgs.portArgumentValue)
            XCTAssertFalse(normalArgs.contains("--trace"))
            XCTAssertTrue(normalArgs.contains("--log-layer-changes"))
        }
    }

    // MARK: - Value Clamping Tests

    func testOverlayOpacityAndIdleFadePersistAndClamp() {
        withPreservedDefaults {
            let writer = makePreferences()
            XCTAssertEqual(writer.overlayOpacity, 1.0)
            XCTAssertTrue(writer.overlayFadesWhenIdle)

            writer.overlayOpacity = 0.6
            writer.overlayFadesWhenIdle = false
            let loaded = makePreferences()
            XCTAssertEqual(loaded.overlayOpacity, 0.6, accuracy: 0.001)
            XCTAssertFalse(loaded.overlayFadesWhenIdle)

            // Never so faint the overlay is lost, never above fully opaque.
            loaded.overlayOpacity = 0.05
            XCTAssertEqual(loaded.overlayOpacity, 0.3, accuracy: 0.001)
            loaded.overlayOpacity = 3
            XCTAssertEqual(loaded.overlayOpacity, 1.0, accuracy: 0.001)
            defaults.set(Double.nan, forKey: "KeyPath.Overlay.Opacity")
            XCTAssertEqual(makePreferences().overlayOpacity, 1.0, accuracy: 0.001)
        }
    }

    func testHideDetailedKeyLegendsIsOffByDefaultAndPersists() {
        let prefs = makePreferences()
        XCTAssertFalse(prefs.overlayHidesActionLegends)

        prefs.overlayHidesActionLegends = true
        XCTAssertTrue(makePreferences().overlayHidesActionLegends)

        prefs.overlayHidesActionLegends = false
        XCTAssertFalse(makePreferences().overlayHidesActionLegends)
    }

    func testShowOnlyWhileLayerHeldIsOffByDefaultAndPersists() {
        withPreservedDefaults {
            let writer = makePreferences()
            XCTAssertFalse(writer.overlayShowsOnlyWhileLayerHeld)
            writer.overlayShowsOnlyWhileLayerHeld = true
            XCTAssertTrue(makePreferences().overlayShowsOnlyWhileLayerHeld)
        }
    }

    func testContextHUDHoldDelayCustomMs_ClampedToMinimum() {
        let prefs = makePreferences()
        prefs.contextHUDHoldDelayCustomMs = 50
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 100, "Custom delay clamped to min 100ms")
    }

    func testContextHUDHoldDelayCustomMs_ClampedToMaximum() {
        let prefs = makePreferences()
        prefs.contextHUDHoldDelayCustomMs = 3000
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 2000, "Custom delay clamped to max 2000ms")
    }

    func testContextHUDHoldDelayCustomMs_AcceptsValidValue() {
        let prefs = makePreferences()
        prefs.contextHUDHoldDelayCustomMs = 500
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 500)
    }

    func testContextHUDHoldDelayCustomMs_AcceptsBoundaries() {
        let prefs = makePreferences()
        prefs.contextHUDHoldDelayCustomMs = 100
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 100)
        prefs.contextHUDHoldDelayCustomMs = 2000
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 2000)
    }

    func testContextHUDHoldDelayCustomMs_ZeroClampedToMin() {
        let prefs = makePreferences()
        prefs.contextHUDHoldDelayCustomMs = 0
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 100)
    }

    func testContextHUDHoldDelayCustomMs_NegativeClampedToMin() {
        let prefs = makePreferences()
        prefs.contextHUDHoldDelayCustomMs = -100
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 100)
    }

    // MARK: - Engine Endpoint

    /// A port left in UserDefaults by an older build cannot redirect the
    /// engine clients: they reach the worker's socket only (ADR-046).
    func testStoredPortValuesCannotRedirectEngineClients() {
        withPreservedDefaults(keys: ["KeyPath.TCP.ServerPort"]) {
            for storedPort in [80, 37001, 45678, 54141] {
                defaults.set(storedPort, forKey: "KeyPath.TCP.ServerPort")
                _ = makePreferences()
                XCTAssertEqual(defaults.integer(forKey: "KeyPath.TCP.ServerPort"), storedPort)
            }
        }
        XCTAssertEqual(KanataTCPClient().endpoint, .session)
    }

    // MARK: - Retired Preference Cleanup

    func testRetiredCommandActionsPreferenceIsRemovedOnLoad() {
        let key = "KeyPath.Security.ConfigCommandActionsEnabled"
        let saved = defaults.object(forKey: key)
        defer {
            if let saved { defaults.set(saved, forKey: key) } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(true, forKey: key)

        _ = makePreferences()

        XCTAssertNil(defaults.object(forKey: key))
    }

    // MARK: - LeaderKeyPreference Codable Tests

    func testLeaderKeyPreference_DefaultValues() {
        let pref = LeaderKeyPreference.default
        XCTAssertEqual(pref.key, "space")
        XCTAssertEqual(pref.targetLayer, .navigation)
        XCTAssertFalse(pref.enabled, "Fresh profiles must not create an unrequested navigation layer")
    }

    func testLeaderKeyPreference_RoundTripCodable() throws {
        let original = LeaderKeyPreference(
            key: "tab",
            targetLayer: .custom("window"),
            enabled: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LeaderKeyPreference.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testLeaderKeyPreference_NavigationLayerRoundTrip() throws {
        let original = LeaderKeyPreference(
            key: "space",
            targetLayer: .navigation,
            enabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LeaderKeyPreference.self, from: data)
        XCTAssertEqual(decoded.targetLayer, .navigation)
    }

    func testLeaderKeyPreference_BaseLayerRoundTrip() throws {
        let original = LeaderKeyPreference(
            key: "caps",
            targetLayer: .base,
            enabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LeaderKeyPreference.self, from: data)
        XCTAssertEqual(decoded.targetLayer, .base)
    }

    func testLeaderKeyPreference_CustomLayerRoundTrip() throws {
        let original = LeaderKeyPreference(
            key: "ralt",
            targetLayer: .custom("symbols"),
            enabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LeaderKeyPreference.self, from: data)
        XCTAssertEqual(decoded.targetLayer, .custom("symbols"))
    }

    func testLeaderKeyPreference_InvalidJsonFallsBackToDefault() {
        let invalidData = "not json".data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(LeaderKeyPreference.self, from: invalidData)
        XCTAssertNil(decoded, "Invalid JSON should fail to decode")
    }

    func testLeaderKeyPreference_Equatable() {
        let a = LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true)
        let b = LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true)
        let c = LeaderKeyPreference(key: "tab", targetLayer: .navigation, enabled: true)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Overlay Suppressed Bundle IDs

    func testOverlaySuppressedBundleIDs_DefaultContainsFigma() {
        let prefs = makePreferences()
        XCTAssertTrue(prefs.overlaySuppressedBundleIDs.contains("com.figma.Desktop"))
        XCTAssertTrue(prefs.overlaySuppressedBundleIDs.contains("com.figma.agent"))
    }

    func testOverlaySuppressedBundleIDs_SetOperations() {
        let prefs = makePreferences()
        let originalIDs = prefs.overlaySuppressedBundleIDs

        prefs.overlaySuppressedBundleIDs.insert("com.test.app")
        XCTAssertTrue(prefs.overlaySuppressedBundleIDs.contains("com.test.app"))

        prefs.overlaySuppressedBundleIDs.remove("com.test.app")
        XCTAssertFalse(prefs.overlaySuppressedBundleIDs.contains("com.test.app"))

        prefs.overlaySuppressedBundleIDs = originalIDs
    }

    func testOverlaySuppressedBundleIDs_DeduplicatesOnStorage() {
        let prefs = makePreferences()
        let originalIDs = prefs.overlaySuppressedBundleIDs

        prefs.overlaySuppressedBundleIDs = Set(["com.a.app", "com.a.app", "com.b.app"])
        XCTAssertEqual(prefs.overlaySuppressedBundleIDs.count, 2)
        XCTAssertTrue(prefs.overlaySuppressedBundleIDs.contains("com.a.app"))
        XCTAssertTrue(prefs.overlaySuppressedBundleIDs.contains("com.b.app"))

        prefs.overlaySuppressedBundleIDs = originalIDs
    }

    // MARK: - Neovim Reference Topics

    func testNeovimReferenceTopics_DefaultsNotEmpty() {
        let prefs = makePreferences()
        XCTAssertFalse(prefs.neovimReferenceTopics.isEmpty)
    }

    func testNeovimReferenceTopics_ContainsValidCategories() {
        let prefs = makePreferences()
        let validCategories = Set(NeovimTerminalCategory.allCases.map(\.rawValue))
        for topic in prefs.neovimReferenceTopics {
            XCTAssertTrue(validCategories.contains(topic), "\(topic) is not a valid category")
        }
    }

    // MARK: - Enum Raw Value Round-Trip Tests

    func testContextHUDDisplayMode_RawValueRoundTrip() {
        for mode in ContextHUDDisplayMode.allCases {
            let raw = mode.rawValue
            let restored = ContextHUDDisplayMode(rawValue: raw)
            XCTAssertEqual(restored, mode, "Round-trip failed for \(mode)")
        }
    }

    func testContextHUDTriggerMode_RawValueRoundTrip() {
        for mode in ContextHUDTriggerMode.allCases {
            let raw = mode.rawValue
            let restored = ContextHUDTriggerMode(rawValue: raw)
            XCTAssertEqual(restored, mode, "Round-trip failed for \(mode)")
        }
    }

    func testContextHUDHoldDelayPreset_RawValueRoundTrip() {
        for preset in ContextHUDHoldDelayPreset.allCases {
            let raw = preset.rawValue
            let restored = ContextHUDHoldDelayPreset(rawValue: raw)
            XCTAssertEqual(restored, preset, "Round-trip failed for \(preset)")
        }
    }

    func testKindaVimLeaderHUDMode_RawValueRoundTrip() {
        for mode in KindaVimLeaderHUDMode.allCases {
            let raw = mode.rawValue
            let restored = KindaVimLeaderHUDMode(rawValue: raw)
            XCTAssertEqual(restored, mode, "Round-trip failed for \(mode)")
        }
    }

    // MARK: - Invalid Enum Raw Values

    func testContextHUDDisplayMode_InvalidRawValueReturnsNil() {
        XCTAssertNil(ContextHUDDisplayMode(rawValue: "invalid"))
    }

    func testContextHUDTriggerMode_InvalidRawValueReturnsNil() {
        XCTAssertNil(ContextHUDTriggerMode(rawValue: "invalid"))
    }

    func testContextHUDHoldDelayPreset_InvalidRawValueReturnsNil() {
        XCTAssertNil(ContextHUDHoldDelayPreset(rawValue: "invalid"))
    }

    func testKeyLabelStyle_InvalidRawValueReturnsNil() {
        XCTAssertNil(KeyLabelStyle(rawValue: "invalid"))
    }

    func testKindaVimLeaderHUDMode_InvalidRawValueReturnsNil() {
        XCTAssertNil(KindaVimLeaderHUDMode(rawValue: "invalid"))
    }

    // MARK: - Hold Delay Computed Property

    func testContextHUDHoldDelayMs_CustomUsesStoredValue() {
        let prefs = makePreferences()
        let original = prefs.contextHUDHoldDelayPreset
        let originalMs = prefs.contextHUDHoldDelayCustomMs

        prefs.contextHUDHoldDelayCustomMs = 450
        prefs.contextHUDHoldDelayPreset = .custom
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 450)

        prefs.contextHUDHoldDelayPreset = original
        prefs.contextHUDHoldDelayCustomMs = originalMs
    }

    func testContextHUDHoldDelayMs_PresetOverridesCustom() {
        let prefs = makePreferences()
        let original = prefs.contextHUDHoldDelayPreset

        prefs.contextHUDHoldDelayCustomMs = 999
        prefs.contextHUDHoldDelayPreset = .short
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 150, "Preset value should win over custom")

        prefs.contextHUDHoldDelayPreset = original
    }

    // MARK: - Default Values

    func testDefaultValues_AreReasonable() {
        let prefs = makePreferences()
        XCTAssertTrue(prefs.notificationsEnabled)
        XCTAssertTrue(prefs.isSequenceMode)
    }

    func testDefaultContextHUDHoldDelay_InRange() {
        let prefs = makePreferences()
        XCTAssertGreaterThanOrEqual(prefs.contextHUDHoldDelayCustomMs, 100)
        XCTAssertLessThanOrEqual(prefs.contextHUDHoldDelayCustomMs, 2000)
    }

    // MARK: - RuleCollectionLayer Codable Tests

    func testRuleCollectionLayer_BaseCodableRoundTrip() throws {
        let original = RuleCollectionLayer.base
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleCollectionLayer.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testRuleCollectionLayer_NavigationCodableRoundTrip() throws {
        let original = RuleCollectionLayer.navigation
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleCollectionLayer.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testRuleCollectionLayer_CustomCodableRoundTrip() throws {
        let original = RuleCollectionLayer.custom("window")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleCollectionLayer.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - NeovimTerminalCategory Tests

    func testNeovimTerminalCategory_AllCasesHaveTitles() {
        for category in NeovimTerminalCategory.allCases {
            XCTAssertFalse(category.title.isEmpty, "\(category) missing title")
        }
    }

    func testNeovimTerminalCategory_HasExpectedCases() {
        XCTAssertGreaterThanOrEqual(NeovimTerminalCategory.allCases.count, 9)
        XCTAssertNotNil(NeovimTerminalCategory(rawValue: "basicMotions"))
        XCTAssertNotNil(NeovimTerminalCategory(rawValue: "operators"))
        XCTAssertNotNil(NeovimTerminalCategory(rawValue: "search"))
    }

    func testNeovimTerminalCategory_InvalidRawValue() {
        XCTAssertNil(NeovimTerminalCategory(rawValue: "nonexistent"))
    }
}

private extension [String] {
    var portArgumentValue: String? {
        guard let index = firstIndex(of: "--port"), index + 1 < count else { return nil }
        return self[index + 1]
    }
}

private final class NotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedNames: [Notification.Name] = []

    var names: [Notification.Name] {
        lock.lock()
        defer { lock.unlock() }
        return recordedNames
    }

    func record(_ name: Notification.Name) {
        lock.lock()
        recordedNames.append(name)
        lock.unlock()
    }
}
