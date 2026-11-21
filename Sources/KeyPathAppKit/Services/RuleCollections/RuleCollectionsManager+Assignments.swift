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
