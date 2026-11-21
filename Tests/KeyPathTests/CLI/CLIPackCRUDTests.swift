@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class CLIPackCRUDTests: XCTestCase {
    private var facade: PacksFacade!
    private var tempDir: URL!
    private var installedPacks: InstalledPackTracker!

    private let testPackSlug = "chord-groups"
    private let testPackID = "com.keypath.pack.chord-groups"
    private let testPackName = "Chord Groups"

    override func setUp() async throws {
        try await super.setUp()

        // Keep the pack records, rule stores, and generated configuration
        // together so concurrent tests cannot read or restore each other's state.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-pack-crud-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir

        let collectionStore = RuleCollectionStore(
            fileURL: dir.appendingPathComponent("RuleCollections.json")
        )
        let customStore = CustomRulesStore(
            fileURL: dir.appendingPathComponent("CustomRules.json")
        )
        installedPacks = InstalledPackTracker(fileURL: dir.appendingPathComponent("installed-packs.json"))
        facade = PacksFacade(installedPackTracker: installedPacks) {
            RuleCollectionsManager(
                ruleCollectionStore: collectionStore,
                customRulesStore: customStore,
                configurationService: ConfigurationService(configDirectory: dir.path)
            )
        }
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testInstallHydratesSourcesAfterThePreviousWriterCommits() async throws {
        try await ensureUninstalled(testPackID)
        let directory = try XCTUnwrap(tempDir)
        let facade = try XCTUnwrap(facade)
        let gate = ConfigurationOperationGate(configurationDirectory: directory)
        let store = CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))
        let entered = expectation(description: "previous writer admitted")
        let earlyInstall = expectation(description: "install waits")
        earlyInstall.isInverted = true
        let phase = AdmissionPhase()
        var resume: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            try await gate.withOperation { @MainActor _ in
                await withCheckedContinuation { continuation in
                    resume = continuation
                    entered.fulfill()
                }
                try await store.saveRules([CustomRule(input: "f13", action: .keystroke(key: "f14"))])
            }
        }
        await fulfillment(of: [entered], timeout: 5)
        let install = Task { @MainActor in
            let result = try await facade.installPack(nameOrId: testPackSlug)
            if phase.waiting { earlyInstall.fulfill() }
            return result
        }
        await fulfillment(of: [earlyInstall], timeout: 0.15)
        phase.waiting = false
        resume?.resume()
        try await first.value
        let result = try await install.value
        XCTAssertEqual(result.action, "installed")
        let rules = await store.loadRules()
        XCTAssertEqual(rules.first(where: { $0.input == "f13" })?.action.outputString, "f14",
                       "Pack install must preserve the source committed while it waited")
    }

    func testCallbackCannotReenterAnyPackCommand() async throws {
        let directory = try XCTUnwrap(tempDir)
        let facade = try XCTUnwrap(facade)
        let gate = ConfigurationOperationGate(configurationDirectory: directory)
        let operations: [@MainActor @Sendable () async throws -> CLIPackInstallResult] = [
            { try await facade.installPack(nameOrId: "chord-groups", dryRun: true) },
            { try await facade.uninstallPack(nameOrId: "chord-groups", dryRun: true) },
            { try await facade.configurePack(nameOrId: "home-row-mods", settingValues: ["holdTimeout": 200], dryRun: true) }
        ]
        try await gate.withOperation { @MainActor _ in
            for operation in operations {
                do {
                    _ = try await operation()
                    XCTFail("Pack commands must reject callback reentry before reading or staging state")
                } catch ConfigurationOperationGate.Failure.recursiveOperation {
                    // Expected before early exits as well as actual mutations.
                }
            }
        }
    }

    private final class AdmissionPhase {
        var waiting = true
    }

    private func ensureUninstalled(_ packID: String) async throws {
        if await installedPacks.isInstalled(packID: packID) {
            try await installedPacks.remove(packID: packID)
        }
    }

    // MARK: - listPacks

    func testListPacksReturnsAllStarterKitPacks() async {
        let packs = await facade.listPacks()
        XCTAssertEqual(packs.count, PackRegistry.starterKit.count)
    }

    func testListPacksShowsInstalledStatus() async throws {
        let record = InstalledPackRecord(packID: testPackID, version: "1.0.0")
        try await installedPacks.upsert(record)

        let packs = await facade.listPacks()
        let found = packs.first(where: { $0.id == testPackID })
        XCTAssertNotNil(found)
        XCTAssertTrue(found?.isInstalled == true)
    }

    // MARK: - showPack

    func testShowPackByExactName() async throws {
        let detail = try await facade.showPack(nameOrId: "Vim Navigation")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.id, "com.keypath.pack.vim-navigation")
    }

    func testShowPackBySlug() async throws {
        let detail = try await facade.showPack(nameOrId: "vim-navigation")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.id, "com.keypath.pack.vim-navigation")
    }

    func testShowPackByFullID() async throws {
        let detail = try await facade.showPack(nameOrId: "com.keypath.pack.vim-navigation")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.name, "Vim Navigation")
    }

    func testShowPackNotFoundReturnsNil() async throws {
        let detail = try await facade.showPack(nameOrId: "nonexistent-pack-zzz")
        XCTAssertNil(detail)
    }

    func testShowPackBySubstringUnique() async throws {
        let detail = try await facade.showPack(nameOrId: "Chord")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.id, "com.keypath.pack.chord-groups")
    }

    func testShowPackIncludesQuickSettings() async throws {
        let detail = try await facade.showPack(nameOrId: "home-row-mods")
        XCTAssertNotNil(detail)
        XCTAssertFalse(detail!.quickSettings.isEmpty)
        XCTAssertEqual(detail!.quickSettings.first?.id, "holdTimeout")
    }

    func testShowPackIncludesDependencies() async throws {
        let detail = try await facade.showPack(nameOrId: "delete-enhancement")
        XCTAssertNotNil(detail)
        XCTAssertFalse(detail!.dependencies.isEmpty)
    }

    // MARK: - Name Resolution Edge Cases

    func testResolvePackAmbiguousThrows() async throws {
        // "Navigation" matches both "Vim Navigation" and "Fast Navigation"
        do {
            _ = try await facade.showPack(nameOrId: "Navigation")
            XCTFail("Should throw AmbiguousPackMatch")
        } catch is AmbiguousPackMatch {
            // expected
        }
    }

    func testResolvePackCaseInsensitive() async throws {
        let detail = try await facade.showPack(nameOrId: "VIM NAVIGATION")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.id, "com.keypath.pack.vim-navigation")
    }

    // MARK: - installPack / uninstallPack

    func testInstallAndUninstallRoundTrip() async throws {
        try await ensureUninstalled(testPackID)

        let installResult = try await facade.installPack(nameOrId: testPackSlug)
        XCTAssertEqual(installResult.action, "installed")
        XCTAssertEqual(installResult.packName, testPackName)

        let isInstalled = await installedPacks.isInstalled(packID: testPackID)
        XCTAssertTrue(isInstalled)

        let uninstallResult = try await facade.uninstallPack(nameOrId: testPackSlug)
        XCTAssertEqual(uninstallResult.action, "uninstalled")

        let stillInstalled = await installedPacks.isInstalled(packID: testPackID)
        XCTAssertFalse(stillInstalled)
    }

    func testInstallAlreadyInstalledReturnsAlreadyInstalled() async throws {
        let record = InstalledPackRecord(packID: testPackID, version: "1.0.0")
        try await installedPacks.upsert(record)

        let result = try await facade.installPack(nameOrId: testPackSlug)
        XCTAssertEqual(result.action, "already-installed")
    }

    func testUninstallNotInstalledReturnsNotInstalled() async throws {
        try await ensureUninstalled(testPackID)

        let result = try await facade.uninstallPack(nameOrId: testPackSlug)
        XCTAssertEqual(result.action, "not-installed")
    }

    func testInstallDryRun() async throws {
        try await ensureUninstalled(testPackID)

        let result = try await facade.installPack(nameOrId: testPackSlug, dryRun: true)
        XCTAssertEqual(result.action, "would-install")

        let isInstalled = await installedPacks.isInstalled(packID: testPackID)
        XCTAssertFalse(isInstalled)
    }

    func testUninstallDryRun() async throws {
        let record = InstalledPackRecord(packID: testPackID, version: "1.0.0")
        try await installedPacks.upsert(record)

        let result = try await facade.uninstallPack(nameOrId: testPackSlug, dryRun: true)
        XCTAssertEqual(result.action, "would-uninstall")

        let stillInstalled = await installedPacks.isInstalled(packID: testPackID)
        XCTAssertTrue(stillInstalled)
    }

    func testInstallNotFoundThrows() async throws {
        do {
            _ = try await facade.installPack(nameOrId: "nonexistent-zzz")
            XCTFail("Should throw CLIPackNotFound")
        } catch is CLIPackNotFound {
            // expected
        }
    }

    func testInstallWithInvalidSettingKeyThrows() async throws {
        // Use a pack that's not installed and has no quick settings
        try await ensureUninstalled(testPackID)

        do {
            _ = try await facade.installPack(
                nameOrId: testPackSlug,
                settingValues: ["bogusKey": 999]
            )
            XCTFail("Should throw CLIPackSettingError")
        } catch is CLIPackSettingError {
            // expected
        }
    }

    func testInstallWithValidQuickSettings() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")

        let result = try await facade.installPack(
            nameOrId: "home-row-mods",
            settingValues: ["holdTimeout": 200]
        )
        XCTAssertEqual(result.action, "installed")
        XCTAssertEqual(result.quickSettingValues["holdTimeout"], 200)
    }

    func testInstallRequiresReviewBeforeDisablingAConflictingRule() async throws {
        let ruleStore = try CustomRulesStore(fileURL: XCTUnwrap(tempDir).appendingPathComponent("CustomRules.json"))
        let existingRule = CustomRule(title: "My Caps Lock rule", input: "caps", action: .keystroke(key: "tab"))
        try await ruleStore.saveRules([existingRule])

        do {
            _ = try await facade.installPack(nameOrId: "caps-lock-to-escape")
            XCTFail("CLI pack installation must not silently disable an existing custom rule")
        } catch let error as PackInstaller.InstallError {
            guard case .needsReview = error else { return XCTFail("Expected a review-required refusal, got \(error)") }
        }

        let persistedRules = await ruleStore.loadRules()
        XCTAssertEqual(persistedRules.first?.id, existingRule.id)
        XCTAssertTrue(persistedRules.first?.isEnabled == true)
        let isInstalled = await installedPacks.isInstalled(packID: "com.keypath.pack.caps-lock-to-escape")
        XCTAssertFalse(isInstalled)
    }

    func testInstallRejectsOutOfRangeQuickSetting() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")

        do {
            _ = try await facade.installPack(
                nameOrId: "home-row-mods",
                settingValues: ["holdTimeout": 999],
                dryRun: true
            )
            XCTFail("Should throw CLIPackSettingValueError")
        } catch let error as CLIPackSettingValueError {
            XCTAssertEqual(error.settingKey, "holdTimeout")
            XCTAssertTrue(error.description.contains("between 120 ms and 300 ms"))
        }
    }

    // MARK: - configurePack

    func testConfigurePackUpdatesSettings() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")
        _ = try await facade.installPack(nameOrId: "home-row-mods", settingValues: ["holdTimeout": 200])

        let result = try await facade.configurePack(
            nameOrId: "home-row-mods",
            settingValues: ["holdTimeout": 250]
        )
        XCTAssertEqual(result.action, "configured")
        XCTAssertEqual(result.quickSettingValues["holdTimeout"], 250)
    }

    func testConfigurePackDryRun() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")
        _ = try await facade.installPack(nameOrId: "home-row-mods", settingValues: ["holdTimeout": 200])

        let result = try await facade.configurePack(
            nameOrId: "home-row-mods",
            settingValues: ["holdTimeout": 300],
            dryRun: true
        )
        XCTAssertEqual(result.action, "would-configure")
        XCTAssertEqual(result.quickSettingValues["holdTimeout"], 300)

        // Verify actual value unchanged
        let current = await installedPacks.record(for: "com.keypath.pack.home-row-mods")
        XCTAssertEqual(current?.quickSettingValues["holdTimeout"], 200)
    }

    func testConfigurePackRejectsOutOfRangeQuickSetting() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")
        _ = try await facade.installPack(nameOrId: "home-row-mods", settingValues: ["holdTimeout": 200])

        do {
            _ = try await facade.configurePack(
                nameOrId: "home-row-mods",
                settingValues: ["holdTimeout": 999],
                dryRun: true
            )
            XCTFail("Should throw CLIPackSettingValueError")
        } catch let error as CLIPackSettingValueError {
            XCTAssertEqual(error.settingKey, "holdTimeout")
            XCTAssertTrue(error.description.contains("between 120 ms and 300 ms"))
        }
    }

    func testConfigurePackNotInstalledReturnsNotInstalled() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")

        let result = try await facade.configurePack(
            nameOrId: "home-row-mods",
            settingValues: ["holdTimeout": 250]
        )
        XCTAssertEqual(result.action, "not-installed")
    }

    func testConfigurePackInvalidSettingThrows() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")
        _ = try await facade.installPack(nameOrId: "home-row-mods", settingValues: ["holdTimeout": 200])

        do {
            _ = try await facade.configurePack(
                nameOrId: "home-row-mods",
                settingValues: ["bogus": 123]
            )
            XCTFail("Should throw CLIPackSettingError")
        } catch is CLIPackSettingError {
            // expected
        }
    }
}
