import Foundation

package enum DeviceDisplayNameFormatter {
    package static func format(_ productKey: String) -> String {
        productKey
            .replacingOccurrences(of: " / Trackpad", with: "")
            .replacingOccurrences(of: "/ Trackpad", with: "")
            .replacingOccurrences(of: "/Trackpad", with: "")
            .replacingOccurrences(of: "Karabiner-DriverKit-VirtualHIDDevice-", with: "")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "/")))
    }
}

/// A physical keyboard device detected by Kanata's `--list` command.
package struct ConnectedDevice: Codable, Identifiable, Hashable, Sendable {
    /// Stable-ish identifier from kanata output, e.g. "0x1234ABCD"
    package let hash: String
    /// USB Vendor ID
    package let vendorID: Int
    /// USB Product ID
    package let productID: Int
    /// IOKit product name, e.g. "Apple Internal Keyboard / Trackpad"
    package let productKey: String
    /// True if the product key indicates a VirtualHID device
    package let isVirtualHID: Bool

    package init(hash: String, vendorID: Int, productID: Int, productKey: String, isVirtualHID: Bool) {
        self.hash = hash
        self.vendorID = vendorID
        self.productID = productID
        self.productKey = productKey
        self.isVirtualHID = isVirtualHID
    }

    package var id: String {
        hash
    }

    /// Formatted vendor:product hex string, e.g. "05ac:0342"
    package var vendorProductHex: String {
        String(format: "%04x:%04x", vendorID, productID)
    }

    /// True if this device appears to be a trackpad with no keyboard functionality.
    /// These are filtered out of the keyboard picker since they can't produce key events.
    package var isTrackpadOnly: Bool {
        let lower = productKey.lowercased()
        return lower.contains("trackpad") && !lower.contains("keyboard")
    }

    /// True if this device is a known mouse that exposes a composite HID keyboard
    /// endpoint (for programmable buttons/macros) but isn't an actual keyboard.
    package var isMouseOnly: Bool {
        let lower = productKey.lowercased()
        let mouseNames = ["x2a", "x2h", "x2v", "xlite", "x2 mini"]
        return lower.contains("mouse") || mouseNames.contains(where: { lower == $0 })
    }

    /// True if this device should be excluded from the keyboard picker.
    package var isNonKeyboard: Bool {
        isVirtualHID || isTrackpadOnly || isMouseOnly
    }

    /// SF Symbol name for this device type.
    /// Apple internal keyboards (vendor 0x05AC) use `laptopcomputer`;
    /// all external keyboards use `keyboard`.
    package var sfSymbolName: String {
        vendorID == 0x05AC ? "laptopcomputer" : "keyboard"
    }
}
