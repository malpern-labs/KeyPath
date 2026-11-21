@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

@MainActor
final class RuleCollectionsManagerAPITests: XCTestCase {
    private func makeManager() throws -> RuleCollectionsManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rule-manager-api-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let defaultsSuite = "KeyPathTests.rule-manager-api.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        addTeardownBlock { defaults.removePersistentDomain(forName: defaultsSuite) }
        let collectionStore = RuleCollectionStore(fileURL: directory.appendingPathComponent("RuleCollections.json"))
        let customRulesStore = CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))

        return RuleCollectionsManager(
            ruleCollectionStore: collectionStore,
            customRulesStore: customRulesStore,
            configurationService: ConfigurationService.sessionTestService(
                configDirectory: directory.path,
                ruleCollectionStore: collectionStore,
                customRulesStore: customRulesStore
            ),
            keymapPreferences: defaults,
            preferencesService: PreferencesService(leaderDefaults: defaults, defaults: defaults),
            installedPackTracker: InstalledPackTracker(fileURL: directory.appendingPathComponent("installed-packs.json")),
            notificationCenter: NotificationCenter()
        )
    }

    // MARK: - enabledMappings

    func testEnabledMappings_IncludesEnabledCollections() throws {
        let manager = try makeManager()
        manager.ruleCollections = [
            RuleCollection(
                id: UUID(),
                name: "Enabled",
                summary: "",
                category: .custom,
                mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"), description: "")],
                isEnabled: true,
                icon: "star",
                tags: [],
                targetLayer: .base,
                configuration: .list
            )
        ]
        manager.customRules = []

        let mappings = manager.enabledMappings()
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].input, "a")
    }

    func testEnabledMappings_ExcludesDisabledCollections() throws {
        let manager = try makeManager()
        manager.ruleCollections = [
            RuleCollection(
                id: UUID(),
                name: "Disabled",
                summary: "",
                category: .custom,
                mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"), description: "")],
                isEnabled: false,
                icon: "star",
                tags: [],
                targetLayer: .base,
                configuration: .list
            )
        ]
        manager.customRules = []

        let mappings = manager.enabledMappings()
        XCTAssertTrue(mappings.isEmpty)
    }

    func testEnabledMappings_IncludesEnabledCustomRules() throws {
        let manager = try makeManager()
        manager.ruleCollections = []
        var rule = CustomRule(input: "x", action: .keystroke(key: "y"))
        rule.isEnabled = true
        manager.customRules = [rule]

        let mappings = manager.enabledMappings()
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].input, "x")
    }

    func testEnabledMappings_ExcludesDisabledCustomRules() throws {
        let manager = try makeManager()
        manager.ruleCollections = []
        var rule = CustomRule(input: "x", action: .keystroke(key: "y"))
        rule.isEnabled = false
        manager.customRules = [rule]

        let mappings = manager.enabledMappings()
        XCTAssertTrue(mappings.isEmpty)
    }

    func testEnabledMappings_CombinesCollectionsAndCustomRules() throws {
        let manager = try makeManager()
        manager.ruleCollections = [
            RuleCollection(
                id: UUID(),
                name: "Col",
                summary: "",
                category: .custom,
                mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"), description: "")],
                isEnabled: true,
                icon: "star",
                tags: [],
                targetLayer: .base,
                configuration: .list
            )
        ]
        var rule = CustomRule(input: "c", action: .keystroke(key: "d"))
        rule.isEnabled = true
        manager.customRules = [rule]

        let mappings = manager.enabledMappings()
        XCTAssertEqual(mappings.count, 2)
    }

    // MARK: - makeCustomRule

    func testMakeCustomRule_NewInput_CreatesNew() throws {
        let manager = try makeManager()
        manager.customRules = []

        let rule = manager.makeCustomRule(input: "caps", output: "esc")
        XCTAssertEqual(rule.input, "caps")
        XCTAssertEqual(rule.action, .keystroke(key: "esc"))
        XCTAssertTrue(rule.isEnabled)
    }

    func testMakeCustomRule_ExistingInput_PreservesID() throws {
        let manager = try makeManager()
        let existing = CustomRule(input: "caps", action: .keystroke(key: "tab"))
        manager.customRules = [existing]

        let rule = manager.makeCustomRule(input: "caps", output: "esc")
        XCTAssertEqual(rule.id, existing.id)
        XCTAssertEqual(rule.action, .keystroke(key: "esc"))
    }

    func testMakeCustomRule_CaseInsensitiveMatch() throws {
        let manager = try makeManager()
        let existing = CustomRule(input: "Caps", action: .keystroke(key: "tab"))
        manager.customRules = [existing]

        let rule = manager.makeCustomRule(input: "caps", output: "esc")
        XCTAssertEqual(rule.id, existing.id)
    }

    func testMakeCustomRule_RawKanataOutput() throws {
        let manager = try makeManager()
        manager.customRules = []

        let rule = manager.makeCustomRule(input: "a", output: "(multi lctl lsft)")
        XCTAssertEqual(rule.action, .rawKanata("(multi lctl lsft)"))
    }

    // MARK: - getCustomRule

    func testGetCustomRule_Found() throws {
        let manager = try makeManager()
        let existing = CustomRule(input: "caps", action: .keystroke(key: "esc"))
        manager.customRules = [existing]

        let found = manager.getCustomRule(forInput: "caps")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, existing.id)
    }

    func testGetCustomRule_CaseInsensitive() throws {
        let manager = try makeManager()
        let existing = CustomRule(input: "Caps", action: .keystroke(key: "esc"))
        manager.customRules = [existing]

        let found = manager.getCustomRule(forInput: "CAPS")
        XCTAssertNotNil(found)
    }

    func testGetCustomRule_NotFound() throws {
        let manager = try makeManager()
        manager.customRules = []

        let found = manager.getCustomRule(forInput: "nonexistent")
        XCTAssertNil(found)
    }

    // MARK: - normalizedActivator

    func testNormalizedActivator_WithActivator() throws {
        let manager = try makeManager()
        let collection = RuleCollection(
            id: UUID(),
            name: "Nav",
            summary: "",
            category: .custom,
            mappings: [],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation),
            configuration: .list
        )

        let result = manager.normalizedActivator(for: collection)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.layer, .navigation)
    }

    func testNormalizedActivator_WithoutActivator() throws {
        let manager = try makeManager()
        let collection = RuleCollection(
            id: UUID(),
            name: "Base",
            summary: "",
            category: .custom,
            mappings: [],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )

        let result = manager.normalizedActivator(for: collection)
        XCTAssertNil(result)
    }

    // MARK: - updateActiveLayerName

    func testUpdateActiveLayerName_SetsCurrentLayerName() throws {
        let manager = try makeManager()
        manager.updateActiveLayerName("nav")
        XCTAssertEqual(manager.currentLayerName, "Nav")
    }

    func testUpdateActiveLayerName_EmptyString_DefaultsToBase() throws {
        let manager = try makeManager()
        manager.updateActiveLayerName("nav")
        manager.updateActiveLayerName("")
        XCTAssertEqual(manager.currentLayerName, "Base")
    }

    func testUpdateActiveLayerName_CallsOnLayerChanged() throws {
        let manager = try makeManager()
        var changedTo: String?
        manager.onLayerChanged = { changedTo = $0 }

        manager.updateActiveLayerName("nav")
        XCTAssertEqual(changedTo, "Nav")
    }

    func testUpdateActiveLayerName_SameValue_DoesNotCallCallback() throws {
        let manager = try makeManager()
        manager.updateActiveLayerName("nav")

        var called = false
        manager.onLayerChanged = { _ in called = true }
        manager.updateActiveLayerName("nav")
        XCTAssertFalse(called)
    }
}
