import Foundation

/// Hold-duration presets for triggering the Shortcut List/navigation layer.
public enum ContextHUDHoldDelayPreset: String, CaseIterable, Sendable {
    case short
    case medium
    case long
    case custom

    package var milliseconds: Int? {
        switch self {
        case .short: 150
        case .medium: 200
        case .long: 300
        case .custom: nil
        }
    }
}

/// The three shortcut-list values that affect generated Kanata configuration.
/// A mutation captures this immutable candidate before it writes any defaults.
package struct ShortcutListGenerationInput: Sendable, Equatable {
    package static let defaultTriggerMode = ContextHUDTriggerMode.holdToShow
    package static let defaultHoldDelayPreset = ContextHUDHoldDelayPreset.long
    package static let defaultCustomHoldDelayMs = 200

    package let triggerMode: ContextHUDTriggerMode
    package let holdDelayPreset: ContextHUDHoldDelayPreset
    package let customHoldDelayMs: Int

    package init(triggerMode: ContextHUDTriggerMode, holdDelayPreset: ContextHUDHoldDelayPreset, customHoldDelayMs: Int) {
        self.triggerMode = triggerMode
        self.holdDelayPreset = holdDelayPreset
        self.customHoldDelayMs = customHoldDelayMs
    }

    package init(persistedIn defaults: UserDefaults) {
        typealias Role = RecoverableRuleWrite.PreferenceRole
        let storedTrigger = defaults.string(forKey: Role.contextHUDTriggerMode.key)
        let storedPreset = defaults.string(forKey: Role.contextHUDHoldDelayPreset.key)
        triggerMode = storedTrigger.flatMap(ContextHUDTriggerMode.init(rawValue:)) ?? Self.defaultTriggerMode
        holdDelayPreset = storedPreset.flatMap(ContextHUDHoldDelayPreset.init(rawValue:)) ?? Self.defaultHoldDelayPreset
        customHoldDelayMs = defaults.object(forKey: Role.contextHUDHoldDelayCustomMs.key) as? Int
            ?? Self.defaultCustomHoldDelayMs
    }

    package var holdDelayMs: Int {
        holdDelayPreset.milliseconds ?? customHoldDelayMs
    }
}
