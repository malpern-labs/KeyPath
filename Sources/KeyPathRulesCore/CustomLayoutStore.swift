import Foundation
import KeyPathCore

/// Storage model for custom imported keyboard layouts
package struct CustomLayoutStore: Codable {
    package var layouts: [StoredLayout]

    package static let userDefaultsKey = "customKeyboardLayouts"

    /// Load custom layouts from UserDefaults
    package static func load(from userDefaults: UserDefaults = .standard) -> CustomLayoutStore {
        guard let data = userDefaults.data(forKey: userDefaultsKey),
              let store = try? JSONDecoder().decode(CustomLayoutStore.self, from: data)
        else {
            return CustomLayoutStore(layouts: [])
        }
        return store
    }

    /// Save custom layouts to UserDefaults
    package func save(to userDefaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else {
            AppLogger.shared.error("🔧 [CustomLayoutStore] Failed to encode custom layouts")
            return
        }
        userDefaults.set(data, forKey: Self.userDefaultsKey)
    }
}

/// A single stored custom layout
package struct StoredLayout: Codable, Identifiable {
    package let id: String // UUID
    package let name: String // User-provided name
    package let sourceURL: String? // Original import URL
    package let layoutJSON: Data // Raw QMK JSON for re-parsing
    package let importDate: Date
    package let layoutVariant: String? // Selected layout variant (e.g., "ansi", "iso")
    package let defaultKeymap: [String]? // Cached keymap tokens for keymap-based parsing
    package let keyboardPath: String? // QMK keyboard path (e.g., "crkbd/rev1") for re-fetching keymap

    package init(id: String = UUID().uuidString,
                 name: String,
                 sourceURL: String? = nil,
                 layoutJSON: Data,
                 importDate: Date = Date(),
                 layoutVariant: String? = nil,
                 defaultKeymap: [String]? = nil,
                 keyboardPath: String? = nil)
    {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.layoutJSON = layoutJSON
        self.importDate = importDate
        self.layoutVariant = layoutVariant
        self.defaultKeymap = defaultKeymap
        self.keyboardPath = keyboardPath
    }
}
