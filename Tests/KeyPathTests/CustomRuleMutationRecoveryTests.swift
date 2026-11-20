import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
import Observation
@preconcurrency import XCTest

@MainActor
final class CustomRuleMutationRecoveryTests: KeyPathTestCase {
    private var directory: URL!
    private var manager: RuleCollectionsManager!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service)
        manager.ruleCollections = []
        manager.customRules = [CustomRule(input: "f20", action: .keystroke(key: "f19"), createdAt: Date(timeIntervalSince1970: 42))]
        manager.ruleCollections = await collections.loadCollectionsDetailed().collections
        try await service.saveRuleState(
            ruleCollections: manager.ruleCollections,
            customRules: manager.customRules,
            collectionStore: collections,
            customStore: rules
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        manager = nil
        directory = nil
        try await super.tearDown()
    }

    private func files() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: ["keypath.kbd", "RuleCollections.json", "CustomRules.json"].map {
            try ($0, Data(contentsOf: directory.appendingPathComponent($0)))
        })
    }

    private static func reload(_ disposition: ReloadDisposition) -> ReloadResult {
        ReloadResult(success: disposition == .applied, response: nil, errorMessage: "injected \(disposition)", protocol: nil, disposition: disposition)
    }

    private func assertRejectedMutationRestores(_ mutate: @MainActor () async -> Void) async throws {
        let before = try files()
        let snapshot = manager.snapshotRuleState()
        var reloads = 0
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        manager.onRulesChanged = {
            reloads += 1
            if reloads == 2 {
                do {
                    let restored = try self.files()
                    XCTAssertEqual(restored, before)
                } catch { XCTFail("Could not read restored files: \(error)") }
            }
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        await mutate()
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try files(), before)
        XCTAssertEqual(manager.ruleCollections, snapshot.collections)
        XCTAssertEqual(manager.customRules, snapshot.customRules)
        XCTAssertEqual(errors.count, 1)
    }

    func testRawEditorRecoveryRefreshesManagerBeforeItsNextMissingRuleExit() async throws {
        let originalRules = manager.customRules
        let before = try files()
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore,
                                                 customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.customRules = [] // Interrupted candidate still visible to this editor.
        var reloads = 0
        let result = await SaveCoordinator(configurationService: service).editConfiguration(transform: { _ in
            throw CancellationError()
        }) {
            reloads += 1
            return Self.reload(.applied)
        }
        XCTAssertFalse(result.success)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try files(), before)
        manager.onRulesChanged = { XCTFail("Recovery already applied through the raw editor"); return Self.reload(.applied) }
        await manager.toggleCustomRule(id: UUID(), isEnabled: false)
        XCTAssertEqual(manager.customRules, originalRules)
    }

    func testMapperSaveRefreshesRuleStateRecoveredByRawEditor() async throws {
        let original = manager.customRules[0]
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore,
                                                 customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.customRules = []
        let owner = SaveCoordinator(configurationService: service)
        _ = await owner.editConfiguration(transform: { _ in throw CancellationError() }) { Self.reload(.applied) }
        let saved = await owner.saveMapping(input: "f13", output: "f14", ruleCollectionsManager: manager) { Self.reload(.applied) }
        XCTAssertTrue(saved.success)
        XCTAssertTrue(manager.customRules.contains(original))
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertTrue(stored.contains(original))
        XCTAssertTrue(stored.contains { $0.input == "f13" })
    }

    func testMapperRecoversRuntimeBeforeInputValidationCanReject() async throws {
        let service = manager.configurationService
        let before = try files()
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore,
                                                 customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        var reloads = 0
        let result = await SaveCoordinator(configurationService: service).saveMapping(input: "", output: "f14", ruleCollectionsManager: manager) {
            reloads += 1
            XCTAssertEqual(try? self.files(), before)
            return Self.reload(.applied)
        }
        XCTAssertFalse(result.success)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try files(), before)
    }

    func testRemapRuleIdentityIsScopedToTheEditingLayer() {
        let base = manager.customRules[0]
        let next = manager.makeCustomRule(input: base.input, output: "f18", layer: .navigation)
        XCTAssertNotEqual(next.id, base.id)
        XCTAssertEqual(next.targetLayer, .navigation)
        manager.customRules.append(next)
        XCTAssertEqual(manager.getCustomRule(forInput: base.input, layer: .base)?.id, base.id)
        XCTAssertEqual(manager.makeCustomRule(input: base.input, output: "f17", layer: .navigation).id, next.id)
    }

    func testSwapAndUndoKeepBothSlotsAndTheirCompleteAssignments() async throws {
        manager.onRulesChanged = { Self.reload(.applied) }
        let first = try XCTUnwrap(manager.customRules.first)
        let second = CustomRule(
            input: "f13", action: .keystroke(key: "f14"),
            shiftedOutput: "f15",
            createdAt: Date(timeIntervalSince1970: 55),
            behavior: .dualRole(DualRoleBehavior(tapAction: .keystroke(key: "f14"), holdAction: .keystroke(key: "lctl"), tapTimeout: 180, holdTimeout: 240))
        )
        let added = await manager.saveCustomRule(second)
        XCTAssertTrue(added)
        let before = manager.customRules
        let result = await manager.editAssignments(.swap(first.input, second.input), layer: .base)
        let undo = try XCTUnwrap(result.undo)
        XCTAssertEqual(manager.customRules[0].id, first.id)
        XCTAssertEqual(manager.customRules[0].behavior, second.behavior)
        XCTAssertEqual(manager.customRules[0].shiftedOutput, second.shiftedOutput)
        XCTAssertEqual(manager.customRules[1].id, second.id)
        XCTAssertEqual(manager.customRules[1].action, first.action)
        let restored = await manager.undoRemap(undo)
        XCTAssertTrue(restored)
        XCTAssertEqual(manager.customRules, before)
    }

    func testPasteAssignmentUsesDestinationLayerAndCanBeUndone() async throws {
        manager.onRulesChanged = { Self.reload(.applied) }
        let source = try XCTUnwrap(manager.customRules.first)
        let assignment = try XCTUnwrap(KeyAssignment(rule: source))
        let data = try JSONEncoder().encode(assignment)
        let copied = try JSONDecoder().decode(KeyAssignment.self, from: data)
        let result = await manager.editAssignments(.paste(copied, "f13"), layer: .navigation)
        let undo = try XCTUnwrap(result.undo)
        XCTAssertEqual(manager.customRules.first, source)
        XCTAssertEqual(manager.customRules.last?.targetLayer, .navigation)
        XCTAssertEqual(manager.customRules.last?.action, source.action)
        XCTAssertNotEqual(manager.customRules.last?.id, source.id)
        let restored = await manager.undoRemap(undo)
        XCTAssertTrue(restored)
        XCTAssertEqual(manager.customRules, [source])
    }

    func testClipboardPreservesStructuredMacrosAndExistingLayerSwitches() throws {
        let macro = MacroBehavior(text: "Hello!", source: .text)
        let source = CustomRule(input: "f13", action: .keystroke(key: "f14"), behavior: .macro(macro))
        let destination = CustomRule(input: "f15", action: .keystroke(key: "f16"), targetLayer: .navigation)
        let encoded = try JSONEncoder().encode(XCTUnwrap(KeyAssignment(rule: source)))
        let copied = try JSONDecoder().decode(KeyAssignment.self, from: encoded)
        XCTAssertTrue(copied.isSupported)
        XCTAssertEqual(copied.applied(to: destination).behavior, .macro(macro))
        let layerSwitch = CustomRule(input: "f13", action: .rawKanata("(layer-switch nav)"))
        let assignment = try XCTUnwrap(KeyAssignment(rule: layerSwitch))
        XCTAssertEqual(assignment.applied(to: destination).action, .activateLayer(name: "nav"))
    }

    func testClipboardRejectsRawExpressionsAndUnknownVersions() throws {
        let raw = CustomRule(input: "f13", action: .rawKanata("(cmd example)"))
        XCTAssertNil(KeyAssignment(rule: raw))
        let unsafe = CustomRule(input: "f13", action: .openFolder(path: "a\"b", name: nil))
        XCTAssertNil(KeyAssignment(rule: unsafe))
        let source = try XCTUnwrap(manager.customRules.first)
        let data = try JSONEncoder().encode(XCTUnwrap(KeyAssignment(rule: source)))
        var serialized = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        serialized["version"] = 2
        let future = try JSONDecoder().decode(KeyAssignment.self, from: JSONSerialization.data(withJSONObject: serialized))
        XCTAssertFalse(future.isSupported)
    }

    func testRemapUndoRestoresConflictingRuleAndKeepsInterveningEdit() async throws {
        let original = manager.customRules[0]
        manager.onRulesChanged = { Self.reload(.applied) }
        let candidate = CustomRule(input: original.input, action: .keystroke(key: "f18"), createdAt: Date(timeIntervalSince1970: 43.5))
        let saved = await manager.saveRemap(candidate)
        let undo = try XCTUnwrap(saved.undo)
        XCTAssertEqual(manager.customRules.first { $0.id == original.id }?.isEnabled, false)

        let unrelated = CustomRule(input: "f13", action: .keystroke(key: "f14"), createdAt: Date(timeIntervalSince1970: 44))
        let added = await manager.saveCustomRule(unrelated)
        XCTAssertTrue(added)
        let undone = await manager.undoRemap(undo)
        XCTAssertTrue(undone)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(stored, [original, unrelated])
    }

    func testRemapUndoIncludesCollectionChangedDuringSave() async throws {
        manager.onRulesChanged = { Self.reload(.applied) }
        let group = RuleCollection(
            name: "Test collection", summary: "", category: .custom,
            mappings: [KeyMapping(input: "f15", action: .keystroke(key: "f16"))]
        )
        let added = await manager.addCollection(group)
        XCTAssertTrue(added)

        // Model a collection being disabled by conflict resolution after save starts.
        let manager = manager!
        manager.onBeforeSave = { [weak manager] in
            guard let manager, let index = manager.ruleCollections.firstIndex(where: { $0.id == group.id }) else { return }
            manager.ruleCollections[index].isEnabled = false
        }
        let saved = await manager.saveRemap(CustomRule(input: "f13", action: .keystroke(key: "f14")))
        manager.onBeforeSave = nil
        let undo = try XCTUnwrap(saved.undo)
        XCTAssertEqual(manager.ruleCollections.first { $0.id == group.id }?.isEnabled, false)

        let undone = await manager.undoRemap(undo)
        XCTAssertTrue(undone)
        let stored = try await manager.ruleCollectionStore.loadForMutation()
        XCTAssertEqual(stored.first { $0.id == group.id }, group)
    }

    func testRemapUndoPreservesNewerEditToTheSameRule() async throws {
        manager.onRulesChanged = { Self.reload(.applied) }
        var candidate = manager.makeCustomRule(input: "f20", output: "f18", layer: .base)
        let saved = await manager.saveRemap(candidate)
        let undo = try XCTUnwrap(saved.undo)

        candidate.action = .keystroke(key: "f17")
        let updated = await manager.saveCustomRule(candidate)
        XCTAssertTrue(updated)
        let undone = await manager.undoRemap(undo)
        XCTAssertFalse(undone)
        XCTAssertEqual(manager.customRules, [candidate])
    }

    func testRejectedRemapProducesNoUndo() async throws {
        try await assertRejectedMutationRestores {
            let result = await self.manager.saveRemap(CustomRule(input: "f13", action: .keystroke(key: "f14")))
            XCTAssertFalse(result.saved)
            XCTAssertNil(result.undo)
        }
    }

    func testRejectedSaveRestoresFilesAndReportsFailure() async throws {
        try await assertRejectedMutationRestores {
            let saved = await self.manager.saveCustomRule(CustomRule(input: "f13", action: .keystroke(key: "f14")))
            XCTAssertFalse(saved)
        }
    }

    func testRejectedToggleRestoresEnabledState() async throws {
        let runtime = RuntimeCoordinator(injectedConfigurationService: manager.configurationService,
                                         injectedRuleCollectionsManager: manager)
        let viewModel = KanataViewModel(manager: runtime)
        let rule = try XCTUnwrap(viewModel.customRules.first)
        try await assertRejectedMutationRestores {
            await viewModel.toggleCustomRule(rule.id, enabled: false)
        }
        XCTAssertEqual(viewModel.customRules, [rule])
        XCTAssertEqual(viewModel.toastType, .error)
        XCTAssertTrue(viewModel.toastMessage?.contains("injected rejected") == true)
    }

    func testCustomTogglePublishesOnlyAfterSavingAndReloading() async throws {
        let runtime = RuntimeCoordinator(injectedConfigurationService: manager.configurationService,
                                         injectedRuleCollectionsManager: manager)
        let viewModel = KanataViewModel(manager: runtime)
        let rule = try XCTUnwrap(viewModel.customRules.first)
        let changed = expectation(description: "View observes the saved custom rule")
        withObservationTracking {
            XCTAssertTrue(viewModel.customRules.first?.isEnabled == true)
        } onChange: {
            changed.fulfill()
        }

        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            XCTAssertEqual(viewModel.customRules, [rule])
            do {
                let stored = try await self.manager.customRulesStore.loadForMutation()
                XCTAssertEqual(stored.first { $0.id == rule.id }?.isEnabled, false)
            } catch {
                XCTFail("Could not read staged custom rules: \(error)")
            }
            return Self.reload(.applied)
        }

        await viewModel.toggleCustomRule(rule.id, enabled: false)

        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(viewModel.customRules.first?.isEnabled, false)
        XCTAssertEqual(viewModel.toastType, .info)
        XCTAssertNotNil(viewModel.toastMessage)
    }

    func testDeclinedCustomToggleKeepsRulesAndShowsNoToast() async throws {
        let existing = try XCTUnwrap(manager.customRules.first)
        var candidate = CustomRule(input: existing.input, action: .keystroke(key: "f18"))
        candidate.isEnabled = false
        let saved = await manager.saveCustomRule(candidate, skipReload: true)
        XCTAssertTrue(saved)
        let before = try files()
        let runtime = RuntimeCoordinator(injectedConfigurationService: manager.configurationService,
                                         injectedRuleCollectionsManager: manager)
        let viewModel = KanataViewModel(manager: runtime)
        var prompts = 0
        manager.onConflictResolution = { _ in prompts += 1; return .keepExisting }
        manager.onRulesChanged = { XCTFail("Declined toggle must not reload"); return Self.reload(.applied) }

        await viewModel.toggleCustomRule(candidate.id, enabled: true)

        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(try files(), before)
        XCTAssertEqual(viewModel.customRules.first { $0.id == candidate.id }?.isEnabled, false)
        XCTAssertNil(viewModel.toastMessage)
    }

    func testRejectedRemovalRestoresDeletedRule() async throws {
        try await assertRejectedMutationRestores {
            await self.manager.removeCustomRule(id: self.manager.customRules[0].id)
        }
    }

    func testRejectedClearRestoresAllRules() async throws {
        try await assertRejectedMutationRestores { await self.manager.clearAllCustomRules() }
    }

    func testPendingSaveCommitsWithoutRecoveryOrError() async throws {
        var reloads = 0
        manager.onError = { XCTFail("Pending save is not a failure: \($0)") }
        manager.onRulesChanged = { reloads += 1; return Self.reload(.pending) }
        let saved = await manager.saveCustomRule(CustomRule(input: "f13", action: .keystroke(key: "f14")))
        XCTAssertTrue(saved)
        XCTAssertEqual(reloads, 1)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(Set(stored.map(\.input)), ["f13", "f20"])
    }

    func testSkippedReloadCommitsWithoutInventingRuntimeWork() async throws {
        manager.onRulesChanged = { XCTFail("Reload was explicitly skipped"); return Self.reload(.applied) }
        let saved = await manager.saveCustomRule(CustomRule(input: "f13", action: .keystroke(key: "f14")), skipReload: true)
        XCTAssertTrue(saved)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(stored.count, 2)
    }

    func testExternalSourceEditIsNotOverwrittenByManagerRollback() async throws {
        var expected: [String: Data]?
        var reloads = 0
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        manager.onRulesChanged = {
            reloads += 1
            do {
                try Data("external edit".utf8).write(to: self.directory.appendingPathComponent("CustomRules.json"))
                expected = try self.files()
            } catch { XCTFail("Could not inject external edit: \(error)") }
            return Self.reload(.rejected)
        }
        await manager.removeCustomRule(id: manager.customRules[0].id)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try files(), expected)
        XCTAssertEqual(manager.customRules.count, 1)
        XCTAssertTrue(errors.first?.contains("Recovery needs attention") == true)
    }

    func testEditRecoversInterruptedSourcesBeforePreparingNextRule() async throws {
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore, customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.customRules = []
        let saved = await manager.saveCustomRule(CustomRule(input: "f13", action: .keystroke(key: "f14")))
        XCTAssertTrue(saved)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(Set(stored.map(\.input)), ["f13", "f20"])
    }

    func testRejectedMutationRefreshesNormallyCommittedPeerRevisionBeforeSnapshot() async throws {
        let peerCollections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let peerRules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let peerService = ConfigurationService(
            configDirectory: directory.path,
            ruleCollectionStore: peerCollections,
            customRulesStore: peerRules
        )
        let peerRule = CustomRule(input: "f18", action: .keystroke(key: "f17"))
        let baseline = manager.customRules
        try await peerService.saveRuleState(
            ruleCollections: [],
            customRules: baseline + [peerRule],
            collectionStore: peerCollections,
            customStore: peerRules
        )

        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        let candidate = CustomRule(input: "f13", action: .keystroke(key: "f14"))
        let rejected = await manager.saveCustomRule(candidate)
        XCTAssertFalse(rejected)

        XCTAssertEqual(Set(manager.customRules.map(\.input)), ["f18", "f20"])
        let afterRejectedSave = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(Set(afterRejectedSave.map(\.input)), ["f18", "f20"])

        let applied = await manager.saveCustomRule(candidate)
        XCTAssertTrue(applied)
        let afterRetry = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(Set(afterRetry.map(\.input)), ["f13", "f18", "f20"])
    }

    func testNestedMutationRetainsOuterStagedCandidateUnderSamePermit() async throws {
        let outerCandidate = CustomRule(input: "f13", action: .keystroke(key: "f14"))
        let nestedCandidate = CustomRule(input: "f18", action: .keystroke(key: "f17"))
        manager.onRulesChanged = { Self.reload(.applied) }

        try await manager.configurationService.operationGate.withOperation { @MainActor permit in
            let snapshot = await self.manager.recoverAndSnapshotRuleState(mutationPermit: permit)
            XCTAssertNotNil(snapshot)
            self.manager.customRules.append(outerCandidate)

            let nestedSave = await self.manager.saveCustomRule(nestedCandidate, mutationPermit: permit)
            XCTAssertTrue(nestedSave)
        }

        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(Set(stored.map(\.input)), ["f13", "f18", "f20"])
    }

    func testUnreadableRecoveredSourcesBlockRetriesUntilRepaired() async throws {
        let service = manager.configurationService
        let sourceURL = directory.appendingPathComponent("RuleCollections.json")
        let originalCollections = try Data(contentsOf: sourceURL)
        try Data("damaged source".utf8).write(to: sourceURL)
        // Construct an interrupted prior revision directly: normal staging now
        // correctly refuses corrupt sources before creating a recovery journal.
        let targets = [
            "config": directory.appendingPathComponent("keypath.kbd"),
            "collections": sourceURL,
            "customRules": directory.appendingPathComponent("CustomRules.json"),
            "deviceTargetingManifest": directory.appendingPathComponent("keypath-device-targeting.manifest")
        ]
        var candidate = try targets.mapValues { try Data(contentsOf: $0) }
        candidate["collections"] = originalCollections
        candidate["customRules"] = try await manager.customRulesStore.encodedRules([])
        try await service.operationGate.withOperation { @MainActor _ in
            _ = try RecoverableRuleWrite.stage(files: targets, contents: candidate, directory: self.directory, scope: .rules)
        }
        manager.customRules = []
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        let proposed = CustomRule(input: "f13", action: .keystroke(key: "f14"))
        let first = await manager.saveCustomRule(proposed)
        XCTAssertFalse(first)
        let recoveredFiles = try files()
        let retry = await manager.saveCustomRule(proposed)
        XCTAssertFalse(retry)
        XCTAssertEqual(try files(), recoveredFiles)
        XCTAssertEqual(errors.count, 2)
        try originalCollections.write(to: sourceURL)
        let repaired = await manager.saveCustomRule(proposed)
        XCTAssertTrue(repaired)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(Set(stored.map(\.input)), ["f13", "f20"])
    }

    func testPackPickerReadsRecoveredRuleBeforeEditing() async throws {
        manager.customRules[0].packSource = "test-pack"
        let service = manager.configurationService
        try await service.saveRuleState(ruleCollections: [], customRules: manager.customRules,
                                        collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore)
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore, customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.customRules = []
        let saved = await PackInstaller.testInstaller().updateTapHold(packID: "test-pack", input: "f20", tap: "esc", manager: manager)
        XCTAssertTrue(saved)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.action.outputString, "esc")
        XCTAssertEqual(stored.first?.packSource, "test-pack")
    }

    func testCancelledSaveRestoresFilesWithoutErrorFeedback() async throws {
        let before = try files()
        let rules = manager.customRules
        var operation: Task<Bool, Never>?
        var reloads = 0
        manager.onError = { XCTFail("Cancellation must remain silent: \($0)") }
        manager.onRulesChanged = {
            reloads += 1
            if reloads == 1 { operation?.cancel() }
            else { XCTAssertFalse(Task.isCancelled, "Recovery must not inherit cancellation") }
            return Self.reload(.applied)
        }
        operation = Task { @MainActor in
            await self.manager.saveCustomRule(CustomRule(input: "f13", action: .keystroke(key: "f14")))
        }
        let saved = await operation!.value
        XCTAssertFalse(saved)
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try files(), before)
        XCTAssertEqual(manager.customRules, rules)
    }

    func testInterruptedRecoveryReloadsBeforeMissingRuleExit() async throws {
        let before = try files()
        try await stageInterruptedEmptyRules()
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            do {
                let restored = try self.files()
                XCTAssertEqual(restored, before)
            } catch { XCTFail("Cannot read recovery: \(error)") }
            return Self.reload(.applied)
        }
        await manager.toggleCustomRule(id: UUID(), isEnabled: false)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try files(), before)
    }

    func testRejectedInterruptedRecoveryIsRetriedBeforeNextEdit() async throws {
        let before = try files()
        try await stageInterruptedEmptyRules()
        var reloads = 0
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        manager.onRulesChanged = {
            reloads += 1
            XCTAssertFalse(Task.isCancelled)
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        await manager.toggleCustomRule(id: UUID(), isEnabled: false)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(errors.count, 1)
        await manager.toggleCustomRule(id: UUID(), isEnabled: false)
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(try files(), before)
    }

    private func stageInterruptedEmptyRules() async throws {
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore, customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.customRules = []
    }

    func testLocalLayerRefreshDoesNotEmitRuntimeHeartbeat() {
        var heartbeats = 0
        let token = NotificationCenter.default.addObserver(for: KanataHeartbeat.self) { _ in
            heartbeats += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }
        manager.refreshLayerIndicatorState()
        XCTAssertEqual(heartbeats, 0)
        manager.updateActiveLayerName("base")
        XCTAssertEqual(heartbeats, 1, "Even an unchanged observed layer is real heartbeat evidence")
    }
}
