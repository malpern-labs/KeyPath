import Foundation

/// Consent belongs to one keyboard in one boot. It names one event-service
/// instance; the only substitute is the same keyboard plugged back into the
/// same port in the same boot (`rebound`). It also names the intermediate key
/// reserved for the substitution. Version 1 had no
/// choice: `reservesF18: true` meant F18, and such records still decode.
package struct SessionCapsSelection: Codable, Sendable, Equatable {
    package let version: Int
    package let bootSessionUUID: String
    package let device: SessionCapsMappingPolicy.DeviceIdentity
    package let intermediateUsage: UInt32

    package init(device: SessionCapsMappingPolicy.DeviceIdentity, bootSessionUUID: String,
                 intermediateUsage: UInt32 = SessionCapsIntermediate.defaultUsage)
    {
        version = 2
        self.device = device
        self.bootSessionUUID = bootSessionUUID
        self.intermediateUsage = intermediateUsage
    }

    package func with(intermediateUsage: UInt32) -> Self {
        Self(device: device, bootSessionUUID: bootSessionUUID, intermediateUsage: intermediateUsage)
    }

    private enum CodingKeys: String, CodingKey {
        case version, bootSessionUUID, device, intermediateUsage, reservesF18
    }

    package init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // A version-1 record is upgraded in memory and re-saved as version 2.
        let stored = try values.decode(Int.self, forKey: .version)
        version = 2
        bootSessionUUID = try values.decode(String.self, forKey: .bootSessionUUID)
        device = try values.decode(SessionCapsMappingPolicy.DeviceIdentity.self, forKey: .device)
        switch stored {
        case 1:
            guard try values.decode(Bool.self, forKey: .reservesF18) else { throw SessionCapsRuntimeSupport.Refusal.selection }
            intermediateUsage = SessionCapsIntermediate.defaultUsage
        case 2:
            intermediateUsage = try values.decode(UInt32.self, forKey: .intermediateUsage)
        default:
            throw SessionCapsRuntimeSupport.Refusal.selection
        }
    }

    package func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(bootSessionUUID, forKey: .bootSessionUUID)
        try values.encode(device, forKey: .device)
        try values.encode(intermediateUsage, forKey: .intermediateUsage)
    }

    package func approvedDevice(currentBoot: String) throws -> SessionCapsMappingPolicy.DeviceIdentity {
        guard version == 2, SessionCapsIntermediate.isCandidate(intermediateUsage),
              let approvedBoot = UUID(uuidString: bootSessionUUID),
              approvedBoot == UUID(uuidString: currentBoot) else { throw SessionCapsRuntimeSupport.Refusal.selection }
        try SessionCapsMappingPolicy.validateLocator(device)
        return device
    }

    /// The chosen keyboard replugged at the same port in this boot: the one
    /// connected instance with the same VID, PID, LocationID and serial (or
    /// the same absence of one). nil across a reboot, at another port, when
    /// twins match, or while the original instance still exists.
    package func rebound(among devices: [SessionCapsMappingPolicy.DeviceIdentity], currentBoot: String) -> Self? {
        guard let chosen = try? approvedDevice(currentBoot: currentBoot),
              let location = chosen.locationID, location != 0 else { return nil }
        let matches = devices.filter {
            $0.vendorID == chosen.vendorID && $0.productID == chosen.productID && $0.locationID == location
                && $0.serialNumber == chosen.serialNumber && $0.appleBuiltIn == chosen.appleBuiltIn
        }
        guard matches.count == 1, let match = matches.first, match.registryEntryID != chosen.registryEntryID,
              (try? SessionCapsMappingPolicy.requireUnique(match, among: devices)) != nil else { return nil }
        return Self(device: match, bootSessionUUID: bootSessionUUID, intermediateUsage: intermediateUsage)
    }

    package func verifyConnected(devices: [SessionCapsMappingPolicy.DeviceIdentity], currentBoot: String) throws {
        do {
            try SessionCapsMappingPolicy.requireUnique(approvedDevice(currentBoot: currentBoot), among: devices)
        } catch {
            throw SessionCapsRuntimeSupport.Refusal.selection
        }
    }

    package static func decode(_ data: Data, currentBoot: String) throws -> Self {
        guard data.count <= 4096,
              let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(fields.keys) == Set(["version", "bootSessionUUID", "device", "reservesF18"])
              || Set(fields.keys) == Set(["version", "bootSessionUUID", "device", "intermediateUsage"]),
              let device = fields["device"] as? [String: Any],
              Set(device.keys).isSuperset(of: ["registryEntryID", "vendorID", "productID"]),
              Set(device.keys).isSubset(of: ["registryEntryID", "vendorID", "productID", "serialNumber", "locationID", "appleBuiltIn"])
        else {
            throw SessionCapsRuntimeSupport.Refusal.selection
        }
        let selection = try JSONDecoder().decode(Self.self, from: data)
        _ = try selection.approvedDevice(currentBoot: currentBoot)
        return selection
    }
}
