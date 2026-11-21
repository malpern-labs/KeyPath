import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

@MainActor
enum RuleCollectionsManagerTestFixture {
    static func makeManager(testCase: XCTestCase) throws -> RuleCollectionsManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rule-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let suiteName = "KeyPathTests.rule-manager.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        testCase.addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

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
}
