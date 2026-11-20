import Foundation
import KeyPathCore
import KeyPathRulesCore

public struct RulesFacade: Sendable {
    private let store: CustomRulesStore
    private let operation: CLIConfigurationOperation?
    /// Loads the rule collections the generated config will be built from.
    ///
    /// Only the CLI-operation path supplies this. A custom rule can collide with a
    /// key an *enabled collection* already claims (its mappings, or its momentary
    /// layer activator), and `ConfigurationService.generateConfiguration` refuses to
    /// generate at all in that case. Without this loader `addRule` only sees other
    /// custom rules, so it happily persists a rule that every later `apply` will
    /// reject — the rule is reported as created, never takes effect, and poisons
    /// the store until it is removed by hand.
    private let collectionLoader: (@Sendable () async -> [RuleCollection])?

    public init() {
        store = .shared
        operation = nil
        collectionLoader = nil
    }

    init(operation: CLIConfigurationOperation) {
        let directory = URL(fileURLWithPath: operation.directory)
        store = CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))
        self.operation = operation
        let collectionStore = RuleCollectionStore(
            fileURL: directory.appendingPathComponent("RuleCollections.json")
        )
        collectionLoader = { await collectionStore.loadCollections() }
    }

    init(store: CustomRulesStore) {
        self.store = store
        operation = nil
        collectionLoader = nil
    }

    init(store: CustomRulesStore, collectionLoader: @escaping @Sendable () async -> [RuleCollection]) {
        self.store = store
        operation = nil
        self.collectionLoader = collectionLoader
    }

    /// Conflicts that `rules` introduce against the enabled collections, relative to
    /// `baselineRules`. Pre-existing conflicts between collections are subtracted so a
    /// store that is already in a bad state does not block an unrelated rule.
    private func collectionConflicts(
        adding rules: [CustomRule], baseline baselineRules: [CustomRule]
    ) async -> [KeyPathError.MappingConflictInfo] {
        guard let collectionLoader else { return [] }
        let collections = await collectionLoader()
        // Custom rules first, exactly as generateConfiguration orders them.
        let after = AdmissionEngine.mappingConflicts(in: rules.asRuleCollections() + collections)
        guard !after.isEmpty else { return [] }
        let before = Set(
            AdmissionEngine.mappingConflicts(in: baselineRules.asRuleCollections() + collections).map(\.description)
        )
        return after.filter { !before.contains($0.description) }
    }

    private func withMutation<Result: Sendable>(
        _ body: @Sendable () async throws -> Result
    ) async throws -> Result {
        if let operation {
            return try await operation.service.operationGate.withOperation(using: operation.permit) { _ in
                try await body()
            }
        }
        let directory = await store.persistenceURL.deletingLastPathComponent()
        let gate = ConfigurationOperationGate(configurationDirectory: directory)
        return try await gate.withOperation { _ in try await body() }
    }

    public func loadCustomRules() async -> [CLICustomRule] {
        let rules = await store.loadRules()
        return rules.map { CLICustomRule(input: $0.input, output: $0.action.outputString, behavior: $0.behavior.map(Self.describeBehavior)) }
    }

    static func describeBehavior(_ behavior: MappingBehavior) -> String {
        switch behavior {
        case let .dualRole(d):
            "tap-hold: tap=\(d.tapActionString), hold=\(d.holdActionString), timeout=\(d.tapTimeout)ms"
        case .tapOrTapDance(.tap):
            "tap"
        case let .tapOrTapDance(.tapDance(td)):
            "tap-dance: \(td.steps.map(\.actionString).joined(separator: ", "))"
        case let .macro(m):
            "macro: \(m.text ?? m.outputs.joined(separator: " "))"
        case let .chord(c):
            "chord: \(c.keys.joined(separator: "+")) → \(c.outputString)"
        }
    }

    @discardableResult
    public func addSimpleRemap(input: String, output: String) async throws -> Bool {
        try await withMutation {
            var rules = await store.loadRules()
            let hadExisting = rules.contains { $0.input == input }
            rules.removeAll { $0.input == input }
            let rule = CustomRule(input: input, action: .keystroke(key: output))
            rules.append(rule)
            try await store.saveRules(rules)
            return hadExisting
        }
    }

    @discardableResult
    public func addTapHoldRemap(input: String, tap: String, hold: String, timeout: Int = 200) async throws -> Bool {
        try await withMutation {
            var rules = await store.loadRules()
            let hadExisting = rules.contains { $0.input == input }
            rules.removeAll { $0.input == input }
            let rule = CustomRule(
                input: input,
                action: .keystroke(key: tap),
                behavior: .dualRole(DualRoleBehavior(
                    tapAction: .keystroke(key: tap),
                    holdAction: .keystroke(key: hold),
                    tapTimeout: timeout
                ))
            )
            rules.append(rule)
            try await store.saveRules(rules)
            return hadExisting
        }
    }

    public func addRule(
        input: String,
        action: KeyAction,
        behavior: MappingBehavior? = nil,
        shiftedOutput: String? = nil,
        title: String? = nil,
        notes: String? = nil,
        targetLayer: String? = nil,
        deviceOverrides: [DeviceKeyOverride]? = nil,
        onConflict: CLIConflictStrategy = .fail
    ) async throws -> RuleAddResult {
        try await withMutation {
            var rules = await store.loadRules()
            let baseline = rules
            let existingIndex = rules.firstIndex(where: { $0.input == input })

            if let existingIndex {
                switch onConflict {
                case .fail:
                    throw CLIConflictError(input: input)
                case .skip:
                    return .skipped
                case .replace:
                    rules.removeAll { $0.input == input }
                case .merge:
                    let existing = rules[existingIndex]
                    let merged = try Self.mergeRules(existing: existing, newAction: action, newBehavior: behavior)
                    rules[existingIndex] = merged
                    let conflicts = await collectionConflicts(adding: rules, baseline: baseline)
                    if !conflicts.isEmpty {
                        throw CLICollectionConflictError(
                            input: input, conflicts: conflicts, ruleName: merged.displayTitle
                        )
                    }
                    try await store.saveRules(rules)
                    return .merged(CLIRuleDetail(from: merged))
                }
            }

            let layer: RuleCollectionLayer = if let targetLayer {
                Self.parseLayer(targetLayer)
            } else {
                .base
            }

            let rule = CustomRule(
                title: title ?? "",
                input: input,
                action: action,
                shiftedOutput: shiftedOutput,
                notes: notes,
                behavior: behavior,
                targetLayer: layer,
                deviceOverrides: deviceOverrides
            )
            rules.append(rule)

            // A key an enabled collection already claims cannot be taken by a custom
            // rule: config generation refuses the whole file rather than silently
            // picking a winner. Refuse here, before anything is written, so the CLI
            // never reports a rule as created that can never be applied.
            let conflicts = await collectionConflicts(adding: rules, baseline: baseline)
            if !conflicts.isEmpty {
                if onConflict == .skip {
                    return .skipped
                }
                throw CLICollectionConflictError(
                    input: input, conflicts: conflicts, ruleName: rule.displayTitle
                )
            }

            try await store.saveRules(rules)

            let detail = CLIRuleDetail(from: rule)
            return existingIndex != nil ? .replaced(detail) : .created(detail)
        }
    }

    public func listRules(enabledOnly: Bool = false) async -> [CLIRuleDetail] {
        await store.listRules(enabledOnly: enabledOnly)
    }

    public func showRule(input: String) async -> CLIRuleDetail? {
        await store.showRule(input: input)
    }

    public func removeRemap(input: String) async throws -> Bool {
        try await withMutation {
            var rules = await store.loadRules()
            let before = rules.count
            rules.removeAll { $0.input == input }
            if rules.count == before {
                return false
            }
            try await store.saveRules(rules)
            return true
        }
    }

    public func enableRule(input: String) async throws -> String? {
        try await withMutation {
            var rules = await store.loadRules()
            guard let index = rules.firstIndex(where: { $0.input.caseInsensitiveCompare(input) == .orderedSame }) else {
                return nil
            }
            rules[index].isEnabled = true
            try await store.saveRules(rules)
            return rules[index].displayTitle
        }
    }

    public func disableRule(input: String) async throws -> String? {
        try await withMutation {
            var rules = await store.loadRules()
            guard let index = rules.firstIndex(where: { $0.input.caseInsensitiveCompare(input) == .orderedSame }) else {
                return nil
            }
            rules[index].isEnabled = false
            try await store.saveRules(rules)
            return rules[index].displayTitle
        }
    }

    static func parseLayer(_ name: String) -> RuleCollectionLayer {
        switch name.lowercased() {
        case "base": .base
        case "nav", "navigation": .navigation
        default: .custom(name)
        }
    }

    static func mergeRules(existing: CustomRule, newAction: KeyAction, newBehavior: MappingBehavior?) throws -> CustomRule {
        let existingIsSimple = existing.behavior == nil
        let newIsSimple = newBehavior == nil

        if existingIsSimple, newIsSimple {
            throw CLIMergeError(
                input: existing.input,
                reason: "both rules are simple remaps with different outputs — ambiguous"
            )
        }

        var merged = existing

        if existingIsSimple, case let .dualRole(newDual) = newBehavior {
            merged.behavior = .dualRole(DualRoleBehavior(
                tapAction: existing.action,
                holdAction: newDual.holdAction,
                tapTimeout: newDual.tapTimeout,
                holdTimeout: newDual.holdTimeout,
                activateHoldOnOtherKey: newDual.activateHoldOnOtherKey
            ))
            merged.action = existing.action
            return merged
        }

        if case var .dualRole(existingDual) = existing.behavior, newIsSimple {
            existingDual.tapAction = newAction
            merged.behavior = .dualRole(existingDual)
            merged.action = newAction
            return merged
        }

        if case let .dualRole(existingDual) = existing.behavior,
           case let .dualRole(newDual) = newBehavior
        {
            merged.behavior = .dualRole(DualRoleBehavior(
                tapAction: newDual.tapAction,
                holdAction: newDual.holdAction,
                tapTimeout: newDual.tapTimeout,
                holdTimeout: existingDual.holdTimeout,
                activateHoldOnOtherKey: newDual.activateHoldOnOtherKey
            ))
            merged.action = newDual.tapAction
            return merged
        }

        throw CLIMergeError(
            input: existing.input,
            reason: "incompatible behavior types cannot be merged"
        )
    }
}

// MARK: - Rule Types

public struct CLICustomRule: Codable, Sendable {
    public let input: String
    public let output: String
    public let behavior: String?
}

public enum RuleAddResult: Codable, Sendable {
    case created(CLIRuleDetail)
    case replaced(CLIRuleDetail)
    case merged(CLIRuleDetail)
    case skipped

    private enum CodingKeys: String, CodingKey {
        case status
        case rule
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        switch status {
        case "created":
            self = try .created(container.decode(CLIRuleDetail.self, forKey: .rule))
        case "replaced":
            self = try .replaced(container.decode(CLIRuleDetail.self, forKey: .rule))
        case "merged":
            self = try .merged(container.decode(CLIRuleDetail.self, forKey: .rule))
        case "skipped":
            self = .skipped
        default:
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Unknown status: \(status)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .created(rule):
            try container.encode("created", forKey: .status)
            try container.encode(rule, forKey: .rule)
        case let .replaced(rule):
            try container.encode("replaced", forKey: .status)
            try container.encode(rule, forKey: .rule)
        case let .merged(rule):
            try container.encode("merged", forKey: .status)
            try container.encode(rule, forKey: .rule)
        case .skipped:
            try container.encode("skipped", forKey: .status)
        }
    }
}

public enum CLIConflictStrategy: String, Sendable {
    case fail
    case replace
    case skip
    case merge
}

public struct CLIMergeError: Error, CustomStringConvertible {
    public let input: String
    public let reason: String
    public var description: String {
        "Cannot merge rules for '\(input)': \(reason)"
    }
}

public struct CLIConflictError: Error, CustomStringConvertible {
    public let input: String
    public var description: String {
        "Rule already exists for '\(input)'"
    }
}

/// The requested key is already claimed by an enabled rule collection (either one of
/// its mappings or its momentary layer activator). Config generation refuses to build
/// a file with two owners for one key, so the rule is rejected before it is persisted
/// rather than written and then rejected by every subsequent `apply`.
public struct CLICollectionConflictError: Error, CustomStringConvertible {
    public let input: String
    public let conflicts: [KeyPathError.MappingConflictInfo]
    /// Display name the rejected rule would have had as a collection. Custom rules
    /// appear in the conflict as a collection named after their display title, so it
    /// is filtered out of `collectionNames` — the user does not need to be told their
    /// own pending rule is one of the claimants.
    public let ruleName: String

    public init(input: String, conflicts: [KeyPathError.MappingConflictInfo], ruleName: String = "") {
        self.input = input
        self.conflicts = conflicts
        self.ruleName = ruleName
    }

    /// Names of the collections claiming the key, excluding the pending custom rule.
    public var collectionNames: [String] {
        var seen = Set<String>()
        return conflicts.flatMap(\.conflictingCollections)
            .filter { $0 != ruleName && seen.insert($0).inserted }
    }

    public var explanation: String {
        conflicts.map(\.userExplanation).joined(separator: "\n\n")
    }

    public var description: String {
        "Key '\(input)' is already used by \(collectionNames.joined(separator: ", "))"
    }
}
