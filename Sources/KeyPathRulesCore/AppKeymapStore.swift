import Foundation
import KeyPathCore

// MARK: - Notifications

package extension Notification.Name {
    /// Posted when app keymaps are added, updated, or removed
    static let appKeymapsDidChange = Notification.Name("appKeymapsDidChange")
}

/// Persists app-specific keymaps to disk.
///
/// File location: `~/.config/keypath/AppKeymaps.json`
///
/// See ADR-027 for the full architecture.
package actor AppKeymapStore {
    package static let shared = AppKeymapStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let fileManager: FileManager

    /// In-memory cache of keymaps
    private var cachedKeymaps: [AppKeymap]?

    package init(fileURL: URL? = nil, fileManager: FileManager = Foundation.FileManager()) {
        self.fileManager = fileManager
        let defaultDirectory = URL(
            fileURLWithPath: WizardSystemPaths.userConfigDirectory, isDirectory: true
        )
        self.fileURL = fileURL ?? defaultDirectory.appendingPathComponent("AppKeymaps.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    package var persistenceURL: URL {
        fileURL
    }

    /// Transaction reads must not use a stale cache or replace malformed data.
    package func loadForMutation() throws -> [AppKeymap] {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        }
        return try decoder.decode([AppKeymap].self, from: data)
    }

    package func encodedKeymaps(_ keymaps: [AppKeymap]) throws -> Data {
        try encoder.encode(keymaps)
    }

    package func publishCommittedKeymaps(_ keymaps: [AppKeymap]) {
        cachedKeymaps = keymaps
        postChangeNotification()
    }

    // MARK: - CRUD Operations

    /// Load all app keymaps from disk
    package func loadKeymaps() -> [AppKeymap] {
        if let cached = cachedKeymaps {
            return cached
        }

        AppLogger.shared.log("📂 [AppKeymapStore] loadKeymaps from: \(fileURL.path)")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            AppLogger.shared.log("📂 [AppKeymapStore] File does not exist, returning []")
            cachedKeymaps = []
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            AppLogger.shared.log("📂 [AppKeymapStore] Read \(data.count) bytes from file")
            let keymaps = try decoder.decode([AppKeymap].self, from: data)
            AppLogger.shared.log("📂 [AppKeymapStore] Decoded \(keymaps.count) app keymaps")
            for keymap in keymaps {
                AppLogger.shared.log(
                    "📂 [AppKeymapStore]   - \(keymap.mapping.displayName) (\(keymap.mapping.bundleIdentifier)): \(keymap.overrides.count) overrides"
                )
            }
            cachedKeymaps = keymaps
            return keymaps
        } catch {
            AppLogger.shared.log("⚠️ [AppKeymapStore] Failed to load keymaps: \(error)")
            cachedKeymaps = []
            return []
        }
    }

    /// Save all app keymaps to disk
    package func saveKeymaps(_ keymaps: [AppKeymap]) throws {
        AppLogger.shared.log("💾 [AppKeymapStore] saveKeymaps: \(keymaps.count) keymaps to \(fileURL.path)")

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(keymaps)
        try data.write(to: fileURL, options: .atomic)
        cachedKeymaps = keymaps

        AppLogger.shared.log("💾 [AppKeymapStore] Saved \(data.count) bytes")
    }

    /// Add or update an app keymap
    package func upsertKeymap(_ keymap: AppKeymap) throws {
        var keymaps = loadKeymaps()
        Self.upsert(keymap, in: &keymaps)
        try saveKeymaps(keymaps)
        postChangeNotification()
    }

    package nonisolated static func upsert(_ keymap: AppKeymap, in keymaps: inout [AppKeymap]) {
        if let index = keymaps.firstIndex(where: { $0.mapping.bundleIdentifier == keymap.mapping.bundleIdentifier }) {
            keymaps[index] = keymap
            AppLogger.shared.log("📝 [AppKeymapStore] Updated keymap for \(keymap.mapping.displayName)")
        } else {
            // Check for virtual key name collision
            let existingNames = Set(keymaps.map(\.mapping.virtualKeyName))
            var finalKeymap = keymap
            if existingNames.contains(keymap.mapping.virtualKeyName) {
                let uniqueName = AppKeyMapping.generateUniqueVirtualKeyName(
                    displayName: keymap.mapping.displayName,
                    bundleIdentifier: keymap.mapping.bundleIdentifier
                )
                finalKeymap = AppKeymap(
                    id: keymap.id,
                    mapping: AppKeyMapping(
                        id: keymap.mapping.id,
                        bundleIdentifier: keymap.mapping.bundleIdentifier,
                        displayName: keymap.mapping.displayName,
                        virtualKeyName: uniqueName,
                        createdAt: keymap.mapping.createdAt,
                        modifiedAt: Date(),
                        isEnabled: keymap.mapping.isEnabled
                    ),
                    overrides: keymap.overrides
                )
                AppLogger.shared.log(
                    "⚠️ [AppKeymapStore] VK name collision, using unique name: \(uniqueName)"
                )
            }
            keymaps.append(finalKeymap)
            AppLogger.shared.log("➕ [AppKeymapStore] Added keymap for \(finalKeymap.mapping.displayName)")
        }
    }

    /// Remove an app keymap by bundle identifier
    package func removeKeymap(bundleIdentifier: String) throws {
        var keymaps = loadKeymaps()
        let countBefore = keymaps.count
        keymaps.removeAll { $0.mapping.bundleIdentifier == bundleIdentifier }

        if keymaps.count < countBefore {
            try saveKeymaps(keymaps)
            AppLogger.shared.log("🗑️ [AppKeymapStore] Removed keymap for \(bundleIdentifier)")
            postChangeNotification()
        }
    }

    /// Post notification on main thread that keymaps have changed
    private func postChangeNotification() {
        Task { @MainActor in
            NotificationObserverManager.defaultCenter.post(
                name: Notification.Name.appKeymapsDidChange,
                object: nil as AnyObject?
            )
        }
    }

    /// Get keymap for a specific bundle identifier
    package func getKeymap(bundleIdentifier: String) -> AppKeymap? {
        loadKeymaps().first { $0.mapping.bundleIdentifier == bundleIdentifier }
    }

    /// Get all enabled keymaps
    package func getEnabledKeymaps() -> [AppKeymap] {
        loadKeymaps().filter(\.mapping.isEnabled)
    }

    /// Get mapping from bundle ID to virtual key name for enabled apps
    package func getBundleToVKMapping() -> [String: String] {
        var result: [String: String] = [:]
        for keymap in getEnabledKeymaps() {
            result[keymap.mapping.bundleIdentifier] = keymap.mapping.virtualKeyName
        }
        return result
    }

    /// Get all apps that have a mapping for a specific input key
    package func getAppsWithMapping(forInputKey inputKey: String) -> [AppKeymap] {
        let lowercased = inputKey.lowercased()
        return loadKeymaps().filter { keymap in
            keymap.overrides.contains { $0.inputKey.lowercased() == lowercased }
        }
    }

    /// Invalidate the cache (call after external modifications)
    package func invalidateCache() {
        cachedKeymaps = nil
    }
}

// MARK: - Test Support

#if DEBUG
    package extension AppKeymapStore {
        nonisolated static func testStore(at url: URL) -> AppKeymapStore {
            AppKeymapStore(fileURL: url)
        }
    }
#endif
