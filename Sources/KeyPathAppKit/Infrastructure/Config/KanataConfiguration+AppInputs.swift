import Foundation
import KeyPathCore
import KeyPathRulesCore

extension KanataGenerationInputs {
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
    static func generateFromCollections(
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

    #if os(macOS)
        /// Parse the output of `kanata --list` and return device identifiers suitable for
        /// `macos-dev-names-exclude`. Kept as a pure function for unit testing.
        /// Used by legacy callers — new code should use `DeviceEnumerationService.parseAllDevices`.
        static func parseExcludedMacOSDeviceNames(fromKanataList output: String) -> [String] {
            let devices = DeviceEnumerationService.parseAllDevices(fromKanataList: output)
            var results = Set<String>()
            for device in devices where device.isVirtualHID {
                results.insert(device.hash)
                results.insert(device.productKey)
            }
            return results.sorted()
        }
    #endif
}
