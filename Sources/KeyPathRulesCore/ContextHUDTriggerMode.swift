/// How the overlay/HUD is triggered when the modifier (Hyper/Meh) is activated
public enum ContextHUDTriggerMode: String, CaseIterable, Sendable {
    /// Show while holding modifier, dismiss on release
    case holdToShow
    /// Tap modifier to toggle visibility on/off
    case tapToToggle
}
