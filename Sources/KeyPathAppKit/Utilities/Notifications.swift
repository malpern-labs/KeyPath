import Foundation
import KeyPathRulesCore

extension Notification.Name {
    /// Startup coordination
    static let kp_startupRevalidate = Notification.Name("KeyPath.Startup.Revalidate")

    // App navigation
    static let showWizard = Notification.Name("ShowWizard")
    static let showEmergencyStop = Notification.Name("ShowEmergencyStop")
    static let showUninstall = Notification.Name("ShowUninstall")
    static let showSimpleMods = Notification.Name("ShowSimpleMods")
    static let showUserFeedback = Notification.Name("ShowUserFeedback")
    static let wizardOpened = Notification.Name("KeyPath.Wizard.Opened")
    static let wizardClosed = Notification.Name("KeyPath.Wizard.Closed")

    // Settings navigation
    static let openSettingsGeneral = Notification.Name("KeyPath.Settings.General")
    static let openSettingsStatus = Notification.Name("KeyPath.Settings.Status")
    static let openSettingsRules = Notification.Name("KeyPath.Settings.Rules")
    static let openSettingsSimulator = Notification.Name("KeyPath.Settings.Simulator")
    static let openSettingsSystemStatus = Notification.Name("KeyPath.Settings.SystemStatus")
    static let openSettingsLogs = Notification.Name("KeyPath.Settings.Logs")
    static let openSettingsAdvanced = Notification.Name("KeyPath.Settings.Advanced")

    // User notification actions
    static let openInstallationWizard = Notification.Name("KeyPath.Action.OpenWizard")
    static let retryStartService = Notification.Name("KeyPath.Action.RetryStart")
    static let openAccessibilitySettings = Notification.Name("KeyPath.Action.OpenAccessibility")
    static let openApp = Notification.Name("KeyPath.Action.OpenApp")
    static let resetToSafeConfig = Notification.Name("KeyPath.Action.ResetToSafeConfig")

    /// Rule collections
    static let ruleCollectionsChanged = Notification.Name("KeyPath.RuleCollections.Changed")

    /// Config validation
    static let configReloadFailed = Notification.Name("KeyPath.Config.ReloadFailed")
    static let configReloadRecovered = Notification.Name("KeyPath.Config.ReloadRecovered")

    /// Overlay app-scoped suppression list changed — observers should
    /// re-evaluate whether to hide/show the overlay for the current app.
    static let overlaySuppressedBundleIDsChanged = Notification.Name("KeyPath.Overlay.SuppressedBundleIDsChanged")

    /// Mapper drawer
    /// Posted when a key is clicked and should be selected in the mapper drawer
    /// userInfo: keyCode (UInt16), inputKey (String), outputKey (String), optional shiftedOutputKey (String), layer (String)
    static let mapperDrawerKeySelected = Notification.Name("KeyPath.Mapper.DrawerKeySelected")

    /// Diagnostics
    static let verboseLoggingChanged = Notification.Name("KeyPath.Diagnostics.VerboseLoggingChanged")

    /// Config-affecting preference changed (e.g., nav trigger mode) - triggers config regeneration
    static let configAffectingPreferenceChanged = Notification.Name("KeyPath.Preferences.ConfigAffectingChanged")

    /// Launcher: select and edit a specific key in LauncherCollectionView. userInfo["key"] = String
    static let launcherSelectKey = Notification.Name("KeyPath.Launcher.SelectKey")

    /// HID keyboard connected (posted by HIDDeviceMonitor). object = HIDKeyboardEvent
    static let hidKeyboardConnected = Notification.Name("KeyPath.HID.KeyboardConnected")
    /// HID keyboard disconnected (posted by HIDDeviceMonitor). object = HIDKeyboardEvent
    static let hidKeyboardDisconnected = Notification.Name("KeyPath.HID.KeyboardDisconnected")

    /// Command palette requests a specific overlay inspector section.
    /// userInfo["section"] = InspectorSection.rawValue (String)
    static let commandPaletteSelectInspectorSection = Notification.Name("KeyPath.CommandPalette.SelectInspectorSection")
}

enum SettingsNavigationUserInfo {
    static let ruleCollectionTarget = "ruleCollectionTarget"
}

struct SettingsNavigationRequest {
    let notification: Notification.Name
    let userInfo: [AnyHashable: Any]?
}

@MainActor
final class SettingsNavigationCoordinator {
    static let shared = SettingsNavigationCoordinator()

    private var pendingRequest: SettingsNavigationRequest?

    private init() {}

    func store(notification: Notification.Name, userInfo: [AnyHashable: Any]? = nil) {
        pendingRequest = SettingsNavigationRequest(notification: notification, userInfo: userInfo)
    }

    func consumePendingRequest() -> SettingsNavigationRequest? {
        defer { pendingRequest = nil }
        return pendingRequest
    }

    func clearIfMatches(_ notification: Notification.Name) {
        guard pendingRequest?.notification == notification else { return }
        pendingRequest = nil
    }
}

public extension Notification.Name {
    /// Posted when user should navigate to App Rules tab in drawer
    static let switchToAppRulesTab = Notification.Name("switchToAppRulesTab")
    /// Posted when Mapper should open the app condition picker (for "New Rule" from App Rules tab)
    static let openMapperAppConditionPicker = Notification.Name("openMapperAppConditionPicker")
    /// Posted when overlay should open with mapper tab selected (from Settings)
    static let openOverlayWithMapper = Notification.Name("openOverlayWithMapper")
    /// Posted when overlay view should switch to mapper tab
    static let switchToMapperTab = Notification.Name("switchToMapperTab")
    /// Posted when overlay should open with mapper tab and preset values for editing
    /// UserInfo: inputKey (String), outputKey (String), optional shiftedOutputKey (String), optionally appBundleId (String)
    static let openOverlayWithMapperPreset = Notification.Name("openOverlayWithMapperPreset")
    /// Posted to set the app condition on the mapper (for adding a rule to a specific app)
    /// UserInfo: bundleId (String), displayName (String)
    static let mapperSetAppCondition = Notification.Name("mapperSetAppCondition")
}
