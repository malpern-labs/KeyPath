import Foundation
import KeyPathCore

@MainActor
struct SessionCapsSelectionStore {
    static let shared = Self(defaults: .standard)

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func save(_ selection: SessionCapsSelection?) throws {
        if let selection {
            let data = try JSONEncoder().encode(selection)
            _ = try SessionCapsSelection.decode(data, currentBoot: SessionCapsRuntimeSupport.bootSessionUUID())
            defaults.set(data, forKey: SessionCapsRuntimeSupport.selectionKey)
        } else {
            defaults.removeObject(forKey: SessionCapsRuntimeSupport.selectionKey)
            defaults.removeObject(forKey: SessionCapsRuntimeSupport.selectionNameKey)
            setDisplaced(nil, name: nil)
        }
    }

    private static let displacedKey = "keypath.session.caps.displaced.v1"

    /// The choice whose keyboard disconnected, with its name. Kept so that
    /// keyboard, back at the same port in the same boot, gets its choice back
    /// even after automatic setup moved Caps rules to another keyboard.
    /// Cleared by any explicit choice, by turning setup off, and on re-bind.
    var displaced: (data: Data, name: String?)? {
        guard let record = defaults.dictionary(forKey: Self.displacedKey),
              let data = record["selection"] as? Data, data.count <= 4096 else { return nil }
        return (data, record["name"] as? String)
    }

    func setDisplaced(_ data: Data?, name: String?) {
        guard let data else {
            defaults.removeObject(forKey: Self.displacedKey)
            return
        }
        var record: [String: Any] = ["selection": data]
        if let name { record["name"] = name }
        defaults.set(record, forKey: Self.displacedKey)
    }

    /// Remember what the chosen keyboard is called, for messages after it
    /// disconnects. Display only; the selection alone identifies the device.
    /// An unknown name clears the old one rather than naming the wrong keyboard.
    func saveName(_ name: String?) {
        guard let name, !name.isEmpty, name.utf8.count <= 256 else {
            defaults.removeObject(forKey: SessionCapsRuntimeSupport.selectionNameKey)
            return
        }
        defaults.set(name, forKey: SessionCapsRuntimeSupport.selectionNameKey)
    }

    var savedName: String? {
        defaults.string(forKey: SessionCapsRuntimeSupport.selectionNameKey)
    }
}
