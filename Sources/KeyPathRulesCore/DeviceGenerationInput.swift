import Foundation

/// Persisted selection state for a single device.
package struct DeviceSelection: Codable, Equatable, Sendable {
    package let hash: String
    package let productKey: String
    package var isEnabled: Bool
    package var lastSeen: Date

    package init(hash: String, productKey: String, isEnabled: Bool, lastSeen: Date) {
        self.hash = hash
        self.productKey = productKey
        self.isEnabled = isEnabled
        self.lastSeen = lastSeen
    }

    /// Cleaned-up product name for display, matching `ConnectedDevice.displayName`.
    package var displayName: String {
        DeviceDisplayNameFormatter.format(productKey)
    }
}

/// A point-in-time device view used while generating a candidate configuration.
/// It prevents a retained transaction from reading a cache that has already
/// moved to a different selection.
package struct DeviceGenerationInput: Sendable {
    package let selections: [DeviceSelection]
    package let connectedDevices: [ConnectedDevice]

    package init(selections: [DeviceSelection], connectedDevices: [ConnectedDevice]) {
        self.selections = selections
        self.connectedDevices = connectedDevices
    }
}
