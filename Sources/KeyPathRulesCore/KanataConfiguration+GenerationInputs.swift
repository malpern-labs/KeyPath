import Foundation
import KeyPathCore

package extension KanataGenerationInputs {
    init(
        leaderKeyPreference: LeaderKeyPreference? = nil,
        navActivationMode: ContextHUDTriggerMode = .tapToToggle,
        navHoldDelayMs: Int = 200,
        deviceGenerationInput: DeviceGenerationInput = DeviceGenerationInput(selections: [], connectedDevices: []),
        chordGroups: [ChordGroupConfig] = [],
        sequences: [KanataDefseqParser.ParsedSequence] = [],
        appSpecificKeys: Set<String> = [],
        physicalLayout: PhysicalLayout = .macBookUS
    ) {
        self.init(
            leaderKeyPreference: leaderKeyPreference,
            navActivationMode: navActivationMode,
            navHoldDelayMs: navHoldDelayMs,
            deviceGenerationInput: deviceGenerationInput,
            chordGroups: chordGroups,
            sequences: sequences,
            appSpecificKeys: appSpecificKeys,
            navigationKeyCodes: physicalLayout.keys.map(\.keyCode).filter { $0 != PhysicalKey.unmappedKeyCode }
        )
    }

    static let empty = KanataGenerationInputs()
}

extension KanataConfiguration {
    /// Generate configuration content from key mappings (adds default system collections when absent).
    public static func generateFromMappings(_ mappings: [KeyMapping]) -> String {
        let collections = [RuleCollection].collection(named: "Custom Mappings", mappings: mappings)
        return generateFromCollections(collections, inputs: .empty)
    }

    /// Compatibility convenience for callers that do not own all point-in-time inputs yet.
    /// It deliberately supplies deterministic empty values instead of consulting live state.
    package static func generateFromCollections(
        _ collections: [RuleCollection],
        leaderKeyPreference: LeaderKeyPreference? = nil,
        navActivationMode: ContextHUDTriggerMode = .tapToToggle,
        navHoldDelayMs: Int = 200,
        deviceGenerationInput: DeviceGenerationInput? = nil,
        chordGroups: [ChordGroupConfig] = [],
        sequences: [KanataDefseqParser.ParsedSequence] = [],
        appSpecificKeys: Set<String> = []
    ) -> String {
        generateFromCollections(
            collections,
            inputs: KanataGenerationInputs(
                leaderKeyPreference: leaderKeyPreference,
                navActivationMode: navActivationMode,
                navHoldDelayMs: navHoldDelayMs,
                deviceGenerationInput: deviceGenerationInput ?? DeviceGenerationInput(selections: [], connectedDevices: []),
                chordGroups: chordGroups,
                sequences: sequences,
                appSpecificKeys: appSpecificKeys
            )
        )
    }
}
