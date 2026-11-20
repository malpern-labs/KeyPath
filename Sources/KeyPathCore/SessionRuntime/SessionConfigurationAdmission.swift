import Foundation

package struct SessionConfigurationAdmission: Sendable {
    package let result: KanataHostBridgeValidationResult
    package let managedCaps: Bool
    /// The intermediate the profile was admitted with. It differs from the
    /// saved one when the profile or `occupied` took the saved key.
    package let intermediateUsage: UInt32
    /// The profile needs managed Caps but no keyboard is usable (none
    /// chosen, the chosen one disconnected, or setup is off). It runs
    /// with Caps Lock passing through unchanged; its other rules work.
    package let capsPaused: Bool

    package init(result: KanataHostBridgeValidationResult, managedCaps: Bool,
                 intermediateUsage: UInt32, capsPaused: Bool = false)
    {
        self.result = result
        self.managedCaps = managedCaps
        self.intermediateUsage = intermediateUsage
        self.capsPaused = capsPaused
    }

    /// Parse the profile and choose its Caps reservation. The caller owns the
    /// current keyboard selection. The parser tries ordinary admission first.
    package static func evaluate(configPath: String, runtimeHost: KanataRuntimeHost,
                                 preferred: UInt32, occupied: Set<UInt32>, rechoose: Bool,
                                 canManageCaps: () -> Bool) -> Self
    {
        let usages = SessionKeyMap.sessionOutputUsages
        let legacy = KanataHostBridge.validateSessionConfig(runtimeHost: runtimeHost, configPath: configPath, supportedUsages: usages)
        if case .valid = legacy { return Self(result: legacy, managedCaps: false, intermediateUsage: preferred) }
        // Parse eligibility before consent so stale setup cannot disguise an
        // unrelated syntax or unsupported-action error. This acquires no mapping.
        var checked: [UInt32: KanataHostBridgeValidationResult] = [:]
        func managed(_ usage: UInt32) -> KanataHostBridgeValidationResult {
            if let result = checked[usage] { return result }
            let result = KanataHostBridge.validateSessionConfig(runtimeHost: runtimeHost, configPath: configPath,
                                                                supportedUsages: usages, managedCaps: true,
                                                                reservedUsage: usage)
            checked[usage] = result
            return result
        }
        var chosen = preferred
        let preferredValid = if case .valid = managed(preferred) { true } else { false }
        // Only a profile with physical Caps can be managed; skip re-parsing
        // every candidate for one that failed for another reason.
        let mentionsCaps = !preferredValid
            && ((try? String(contentsOfFile: configPath, encoding: .utf8))?.lowercased().contains("caps") ?? true)
        if rechoose, mentionsCaps || occupied.contains(preferred) {
            // A rule that uses the saved key, or another app that took it,
            // moves the reservation instead of refusing the profile.
            if let next = SessionCapsIntermediate.choose(preferred: preferred, occupied: occupied, acceptsProfile: {
                if case .valid = managed($0) { true } else { false }
            }) {
                chosen = next
            } else if preferredValid {
                return Self(
                    result: .invalid(reason: String(localized: "every key KeyPath can reserve for Caps Lock (F13\u{2013}F20) is already in use by your rules, another app, or a keyboard shortcut")),
                    managedCaps: false,
                    intermediateUsage: preferred
                )
            }
        }
        if canManageCaps() {
            guard case .valid = managed(chosen) else { return Self(result: legacy, managedCaps: false, intermediateUsage: preferred) }
            return Self(result: .valid, managedCaps: true, intermediateUsage: chosen)
        }
        // No usable keyboard. Physical Caps Lock is never mapped, so no key is
        // reserved; the profile only has to parse under some candidate.
        let parses = if case .valid = managed(chosen) { true } else {
            SessionCapsIntermediate.choose(preferred: preferred, occupied: [], acceptsProfile: {
                if case .valid = managed($0) { true } else { false }
            }) != nil
        }
        guard parses else { return Self(result: legacy, managedCaps: false, intermediateUsage: preferred) }
        return Self(result: .valid, managedCaps: false, intermediateUsage: preferred, capsPaused: true)
    }
}
