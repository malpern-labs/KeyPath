import AppKit
import Foundation
import KeyPathRulesCore

// MARK: - App Launch Info

/// Info about a selected app for launch action
public struct AppLaunchInfo: Equatable {
    public let name: String
    public let bundleIdentifier: String?
    public let icon: NSImage

    public init(name: String, bundleIdentifier: String?, icon: NSImage) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.icon = icon
    }

    /// The kanata output string for this app launch
    public var kanataOutput: String {
        // Use bundle identifier if available, otherwise app name
        let appId = bundleIdentifier ?? name
        return "(push-msg \"launch:\(appId)\")"
    }
}

@MainActor
extension AppLaunchInfo {
    static func knownApps(in appKeymapStore: AppKeymapStore) async -> [AppLaunchInfo] {
        // Get apps from app-specific keymaps
        let keymaps = await appKeymapStore.loadKeymaps()
        var apps: [AppLaunchInfo] = []
        var seenAppKeys: Set<String> = []

        for keymap in keymaps {
            let bundleId = keymap.mapping.bundleIdentifier
            let name = keymap.mapping.displayName

            // Get icon
            let icon: NSImage
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)
            } else {
                icon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: name) ?? NSImage()
            }

            let appKey = bundleId.isEmpty ? name : bundleId
            if seenAppKeys.insert(appKey).inserted {
                apps.append(AppLaunchInfo(name: name, bundleIdentifier: bundleId.isEmpty ? nil : bundleId, icon: icon))
            }
        }

        // Add running apps
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular || $0.activationPolicy == .accessory }
        for app in runningApps {
            guard let url = app.bundleURL else { continue }
            guard isUserFacingAppURL(url) else { continue }
            let appInfo = appLaunchInfo(for: url)
            let appKey = appInfo.bundleIdentifier ?? appInfo.name
            if seenAppKeys.insert(appKey).inserted {
                apps.append(appInfo)
            }
        }
        return apps.sorted { $0.name < $1.name }
    }

    private static func appLaunchInfo(for url: URL) -> AppLaunchInfo {
        let displayName = url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        let bundleId = Bundle(url: url)?.bundleIdentifier
        return AppLaunchInfo(name: displayName, bundleIdentifier: bundleId, icon: icon)
    }

    private static func isUserFacingAppURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/Applications/") ||
            path.hasPrefix("/System/Applications/") ||
            path.hasPrefix(Foundation.FileManager().homeDirectoryForCurrentUser.appendingPathComponent("Applications").path)
    }
}

// MARK: - Device Condition Info

/// Info about a selected keyboard device for precondition (rule only applies on this device)
public struct DeviceConditionInfo: Equatable, Identifiable {
    public let deviceHash: String
    public let displayName: String
    public let sfSymbolName: String
    public var id: String {
        deviceHash
    }

    public init(deviceHash: String, displayName: String, sfSymbolName: String) {
        self.deviceHash = deviceHash
        self.displayName = displayName
        self.sfSymbolName = sfSymbolName
    }
}

// MARK: - App Condition Info

/// Info about a selected app for precondition (rule only applies when this app is frontmost)
public struct AppConditionInfo: Equatable, Identifiable {
    public let bundleIdentifier: String
    public let displayName: String
    public let icon: NSImage

    public var id: String {
        bundleIdentifier
    }

    public init(bundleIdentifier: String, displayName: String, icon: NSImage) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.icon = icon
    }
}
