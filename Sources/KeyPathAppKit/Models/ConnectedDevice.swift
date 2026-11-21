import Foundation
import KeyPathRulesCore

extension ConnectedDevice {
    /// Cleaned-up product name for display in the UI.
    /// Falls back to the device hash when the product key is empty.
    var displayName: String {
        let formatted = DeviceDisplayNameFormatter.format(productKey)
        return formatted.isEmpty ? String(localized: "Device \(hash.suffix(8))") : formatted
    }
}
