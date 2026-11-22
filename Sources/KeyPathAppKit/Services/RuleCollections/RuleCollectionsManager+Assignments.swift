import Foundation
import KeyPathRulesCore

/// Versioned clipboard data contains output behavior only. A paste never adopts
/// the source rule's ID, input, layer, or pack ownership.
struct KeyAssignment: Codable, Equatable, Sendable {
    private(set) var version = 1
    let action: KeyAction
    let shiftedOutput: String?
    let behavior: MappingBehavior?

    init?(rule: CustomRule) {
        guard rule.isEnabled, rule.packSource == nil, rule.deviceOverrides?.isEmpty != false else { return nil }
        if case let .rawKanata(expression) = rule.action {
            let typedAction = KanataBehaviorRenderer.parseActionString(expression)
            guard typedAction.kanataOutput == expression else { return nil }
            action = typedAction
        } else {
            action = rule.action
        }
        shiftedOutput = rule.shiftedOutput
        behavior = rule.behavior
        guard isSupported else { return nil }
    }

    var isSupported: Bool {
        guard version == 1, Self.isPortable(action),
              shiftedOutput.map(Self.isKeyToken) ?? true else { return false }
        switch behavior {
        case nil, .tapOrTapDance(.tap):
            return true
        case let .dualRole(behavior):
            return Self.isPortable(behavior.tapAction) && Self.isPortable(behavior.holdAction)
                && behavior.customTapKeys.allSatisfy(Self.isKeyToken)
        case let .tapOrTapDance(.tapDance(behavior)):
            return behavior.steps.allSatisfy { Self.isPortable($0.action) }
        case let .macro(macro):
            return macro.isValid && (macro.source == .text || macro.outputs.allSatisfy(Self.isKeyToken))
        case .chord:
            return false
        }
    }

    private static func isPortable(_ action: KeyAction) -> Bool {
        switch action {
        case let .keystroke(key): isKeyToken(key)
        case .hyper, .meh: true
        case let .activateLayer(name): isKeyToken(name)
        case let .launchApp(name, bundleID):
            isQuotedValueSafe(bundleID.flatMap { $0.isEmpty ? nil : $0 } ?? name)
        case let .openURL(value):
            URL(string: value).map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil } ?? false
        case let .openFolder(path, _): isQuotedValueSafe(path)
        case let .systemAction(id): isQuotedValueSafe(id)
        case let .windowAction(position): isQuotedValueSafe(position)
        case .notify: true
        case .runScript, .fakeKey, .rawKanata: false
        }
    }

    private static func isQuotedValueSafe(_ value: String) -> Bool {
        !value.isEmpty && value.rangeOfCharacter(from: CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "\"\\"))) == nil
    }

    private static func isKeyToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    func applied(to rule: CustomRule) -> CustomRule {
        var result = rule
        result.action = action
        result.shiftedOutput = shiftedOutput
        result.behavior = behavior
        return result
    }
}

extension RuleCollectionsManager {
    enum AssignmentEdit: Sendable {
        case swap(String, String)
        case paste(KeyAssignment, String)
    }

    static func assignmentRule(input: String, layer: RuleCollectionLayer, in rules: [CustomRule]) -> CustomRule? {
        let matches = rules.filter { $0.targetLayer.kanataName == layer.kanataName && $0.input.caseInsensitiveCompare(input) == .orderedSame }
        guard matches.count == 1, let rule = matches.first, KeyAssignment(rule: rule) != nil else { return nil }
        return rule
    }

    func editAssignments(_ edit: AssignmentEdit, layer: RuleCollectionLayer) async -> RemapSaveOutcome {
        await withRuleMutation(failure: RemapSaveOutcome.failed) { [self] permit in
            guard let before = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return .failed }
            let candidates: [CustomRule]
            switch edit {
            case let .swap(first, second):
                guard first.caseInsensitiveCompare(second) != .orderedSame,
                      let source = Self.assignmentRule(input: first, layer: layer, in: customRules),
                      let destination = Self.assignmentRule(input: second, layer: layer, in: customRules),
                      let sourceAssignment = KeyAssignment(rule: source),
                      let destinationAssignment = KeyAssignment(rule: destination)
                else { return .failed }
                candidates = [destinationAssignment.applied(to: source), sourceAssignment.applied(to: destination)]
            case let .paste(assignment, input):
                guard assignment.isSupported else { return .failed }
                let existing = Self.assignmentRule(input: input, layer: layer, in: customRules)
                guard existing != nil || !customRules.contains(where: {
                    $0.targetLayer.kanataName == layer.kanataName && $0.input.caseInsensitiveCompare(input) == .orderedSame
                }) else { return .failed }
                candidates = [assignment.applied(to: existing ?? CustomRule(input: input, action: assignment.action, targetLayer: layer))]
            }

            guard !candidates.contains(where: { reviewAdmission(forProposed: $0).refusal != nil }) else { return .failed }
            for rule in candidates {
                if let index = customRules.firstIndex(where: { $0.id == rule.id }) {
                    customRules[index] = rule
                } else {
                    customRules.append(rule)
                }
            }
            guard !candidates.contains(where: { conflictInfo(for: $0) != nil }) else {
                customRules = before.customRules
                return .failed
            }
            refreshLayerIndicatorState()
            let result = await commitRuleMutationResult(
                snapshot: before, resolvesMappingConflicts: false, mutationPermit: permit
            )
            return await remapSaveOutcome(before: before, result: result)
        }
    }
}

extension RuleCollectionsManager {
    struct HoldLayerRemap: Identifiable {
        let rule: CustomRule
        let previousRule: CustomRule?
        let conflict: RuleConflictInfo?
        let previousHold: KeyAction?
        let target: RuleCollectionLayer

        var id: UUID {
            rule.id
        }
    }

    func prepareHoldLayerRemap(
        input: String, source: RuleCollectionLayer, target: RuleCollectionLayer, fallbackTap: KeyAction
    ) -> HoldLayerRemap? {
        let hold = KeyAction.rawKanata("(layer-while-held \(target.kanataName))")
        guard target != .base, target != source, hold.heldLayerName == target.kanataName else { return nil }

        let previous = getCustomRule(forInput: input, layer: source)
        // Keep disabled assignments available to re-enable from Settings.
        guard previous?.isEnabled != false else { return nil }
        let original = previous?.asKeyMapping()
        var rule = previous ?? CustomRule(input: input, action: fallbackTap, targetLayer: source)
        guard rule.packSource == nil, rule.deviceOverrides?.isEmpty != false else { return nil }
        rule.isEnabled = true
        // A tap-hold claims its input even when its tap output is an identity.
        rule.behavior = .dualRole(DualRoleBehavior(tapAction: fallbackTap, holdAction: hold))
        let conflict = conflictInfo(for: rule)
        let conflictingMapping: KeyMapping?
        var conflictingActivator: MomentaryActivator?
        switch conflict?.source {
        case let .collection(collection):
            conflictingActivator = collection.momentaryActivator.flatMap {
                $0.sourceLayer == source && KanataKeyConverter.convertToKanataKey($0.input) == input ? $0 : nil
            }
            conflictingMapping = KanataConfiguration.effectiveMappings(for: collection).first {
                collection.targetLayer == source && KanataKeyConverter.convertToKanataKey($0.input) == input
            }
        case let .customRule(custom):
            conflictingMapping = custom.asKeyMapping()
        case .named:
            return nil
        case nil:
            conflictingMapping = nil
        }

        let mapping = original ?? conflictingMapping
        guard mapping?.shiftedOutput == nil, mapping?.deviceOverrides?.isEmpty != false else { return nil }
        let tap = conflictingActivator == nil ? (mapping?.action ?? fallbackTap) : .keystroke(key: input)
        var behavior = DualRoleBehavior(tapAction: tap, holdAction: hold)
        var previousHold = conflictingActivator.map { KeyAction.activateLayer(name: $0.targetLayer.kanataName) }
        if let existing = mapping?.behavior, conflictingActivator == nil {
            switch existing {
            case let .dualRole(dualRole):
                behavior = dualRole
                previousHold = dualRole.holdAction
                behavior.holdAction = hold
            case .tapOrTapDance(.tap):
                break
            default:
                return nil
            }
        }

        rule.action = behavior.tapAction
        rule.behavior = .dualRole(behavior)
        rule.shiftedOutput = nil
        return HoldLayerRemap(rule: rule, previousRule: previous, conflict: conflict, previousHold: previousHold, target: target)
    }

    func saveHoldLayerRemap(_ assignment: HoldLayerRemap) async -> RemapSaveOutcome {
        await withRuleMutation(failure: RemapSaveOutcome.failed) { [self] permit in
            let rule = assignment.rule
            guard let before = await recoverAndSnapshotRuleState(mutationPermit: permit),
                  getCustomRule(forInput: rule.input, layer: rule.targetLayer) == assignment.previousRule,
                  conflictInfo(for: rule) == assignment.conflict,
                  reviewAdmission(forProposed: rule).refusal == nil
            else { return .failed }

            if let replacement = assignment.conflict {
                await disableConflicting(replacement.source, regenerate: false)
            }
            guard await updateCustomRuleInMemory(rule, mutationPermit: permit) else {
                customRules = before.customRules
                ruleCollections = before.collections
                return .failed
            }
            refreshLayerIndicatorState()
            let result = await commitRuleMutationResult(
                snapshot: before, resolvesMappingConflicts: false, mutationPermit: permit
            )
            return await remapSaveOutcome(before: before, result: result)
        }
    }
}
