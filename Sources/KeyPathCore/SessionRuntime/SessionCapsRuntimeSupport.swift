import Darwin
import Foundation
import IOKit

/// Read-only configuration admission shared by the app and standalone tools.
package enum SessionCapsRuntimeSupport {
    package typealias Policy = SessionCapsMappingPolicy
    package enum Refusal: Error {
        case selection, bootIdentity, registryLookup, physicalKeysHeld, configIdentity, liveOwner
    }

    package static func experimentalDevice(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Policy.DeviceIdentity? {
        #if DEBUG
            guard let raw = environment["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE"] else { return nil }
            guard environment["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_RESERVE_F18"] == "1", raw.utf8.count <= 4096 else { throw Refusal.selection }
            let device = try JSONDecoder().decode(Policy.DeviceIdentity.self, from: Data(raw.utf8))
            try SessionCapsMappingPolicy.validateLocator(device)
            return device
        #else
            return nil
        #endif
    }

    package static let automaticSetupDisabledKey = "keypath.session.caps.automatic.disabled"
    package static let selectionKey = "keypath.session.caps.selection.v1"
    package static let selectionEnvironmentKey = "KEYPATH_SESSION_CAPS_SELECTION"
    /// What the app passes when it launched the worker without managed Caps.
    /// The worker then never falls back to the saved selection, which the
    /// app may have declined (for example when no intermediate was free).
    package static let noSelection = "none"
    private static let allPrefix = "all:"

    package static func allKeyboardLaunchValue(intermediateUsage: UInt32) -> String {
        "\(allPrefix)\(intermediateUsage)"
    }

    package static func allKeyboardIntermediate(environment: [String: String] = ProcessInfo.processInfo.environment) -> UInt32? {
        guard let value = environment[selectionEnvironmentKey], value.hasPrefix(allPrefix),
              let usage = UInt32(value.dropFirst(allPrefix.count)), SessionCapsIntermediate.isCandidate(usage) else { return nil }
        return usage
    }

    private static func selectionSource(_ environment: [String: String], _ selectionData: Data?) -> Data? {
        guard let passed = environment[selectionEnvironmentKey] else { return selectionData }
        return passed == noSelection ? nil : Data(passed.utf8)
    }

    package static func selectedDevice(environment: [String: String] = ProcessInfo.processInfo.environment,
                                       selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey),
                                       registryEntryExists: (UInt64) throws -> Bool = SessionCapsRuntimeSupport.registryEntryExists) throws -> Policy.DeviceIdentity?
    {
        try selected(environment: environment, selectionData: selectionData, registryEntryExists: registryEntryExists)?.device
    }

    package static func selected(environment: [String: String] = ProcessInfo.processInfo.environment,
                                 selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey),
                                 registryEntryExists: (UInt64) throws -> Bool = SessionCapsRuntimeSupport.registryEntryExists) throws -> SessionCapsSelection?
    {
        #if DEBUG
            if environment["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE"] != nil {
                return try experimentalDevice(environment: environment).map {
                    try SessionCapsSelection(device: $0, bootSessionUUID: bootSessionUUID())
                }
            }
        #endif
        guard let data = selectionSource(environment, selectionData) else { return nil }
        let selection = try SessionCapsSelection.decode(data, currentBoot: bootSessionUUID())
        // Boot-valid consent still belongs to one registry instance. Let the
        // existing automatic-setup policy rediscover after a disconnect instead
        // of passing a stale registry ID to the next worker.
        guard try registryEntryExists(selection.device.registryEntryID) else { throw Refusal.selection }
        return selection
    }

    /// The saved (or launch-supplied) intermediate, without verifying the
    /// keyboard is connected. Used only to order the choice.
    package static func preferredIntermediate(environment: [String: String] = ProcessInfo.processInfo.environment,
                                              selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey)) -> UInt32
    {
        if let all = allKeyboardIntermediate(environment: environment) { return all }
        #if DEBUG
            if environment["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE"] != nil { return SessionCapsIntermediate.defaultUsage }
        #endif
        let data = selectionSource(environment, selectionData)
        guard let data, let boot = try? bootSessionUUID(),
              let selection = try? SessionCapsSelection.decode(data, currentBoot: boot)
        else {
            return SessionCapsIntermediate.defaultUsage
        }
        return selection.intermediateUsage
    }

    package static func validate(configPath: String, runtimeHost: KanataRuntimeHost,
                                 environment: [String: String] = ProcessInfo.processInfo.environment,
                                 selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey),
                                 requireSelection: Bool = true,
                                 automaticSetupDisabled: Bool = UserDefaults.standard.bool(forKey: automaticSetupDisabledKey)) -> (result: KanataHostBridgeValidationResult, managedCaps: Bool)
    {
        let admission = admit(configPath: configPath, runtimeHost: runtimeHost, environment: environment,
                              selectionData: selectionData, requireSelection: requireSelection,
                              automaticSetupDisabled: automaticSetupDisabled)
        return (admission.result, admission.managedCaps)
    }

    /// `occupied` names keys something else already uses (see
    /// `occupiedIntermediates`). With `rechoose`, a saved intermediate the
    /// profile uses or that is occupied is replaced by the next free one; the
    /// worker passes false so it runs exactly the key its parent chose.
    package static func admit(configPath: String, runtimeHost: KanataRuntimeHost,
                              environment: [String: String] = ProcessInfo.processInfo.environment,
                              selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey),
                              requireSelection: Bool = true, occupied: Set<UInt32> = [], rechoose: Bool = true,
                              automaticSetupDisabled: Bool = UserDefaults.standard.bool(forKey: automaticSetupDisabledKey)) -> SessionConfigurationAdmission
    {
        let preferred = preferredIntermediate(environment: environment, selectionData: selectionData)
        return SessionConfigurationAdmission.evaluate(configPath: configPath, runtimeHost: runtimeHost,
                                                      preferred: preferred, occupied: occupied, rechoose: rechoose)
        {
            (!automaticSetupDisabled && (!requireSelection || allKeyboardIntermediate(environment: environment) != nil))
                || (try? selected(environment: environment, selectionData: selectionData)) != nil
        }
    }

    package static func bootSessionUUID() throws -> String {
        var bytes = [CChar](repeating: 0, count: 128)
        var length = bytes.count
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &length, nil, 0) == 0,
              length > 1, length <= bytes.count else { throw Refusal.bootIdentity }
        let value = String(decoding: bytes.prefix(length - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard UUID(uuidString: value) != nil else { throw Refusal.bootIdentity }
        return value
    }

    /// Query the exact ID without keyboard eligibility filters. The fast match
    /// finds registered services; before claiming absence, inspect the registry
    /// plane too because an unregistered service can still be present there.
    package static func registryEntryExists(_ registryEntryID: UInt64) throws -> Bool {
        guard registryEntryID != 0,
              let matching = IORegistryEntryIDMatching(registryEntryID) else { throw Refusal.registryLookup }
        var matches: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &matches) == KERN_SUCCESS else {
            throw Refusal.registryLookup
        }
        if matches != 0 {
            defer { IOObjectRelease(matches) }
            let service = IOIteratorNext(matches)
            if service != 0 {
                IOObjectRelease(service)
                return true
            }
            guard IOIteratorIsValid(matches) != 0 else { throw Refusal.registryLookup }
        }
        // A successful match may return a null iterator for no registered match.
        var entries: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
                                       IOOptionBits(kIORegistryIterateRecursively), &entries) == KERN_SUCCESS,
            entries != 0 else { throw Refusal.registryLookup }
        defer { IOObjectRelease(entries) }
        while true {
            let entry = IOIteratorNext(entries)
            guard entry != 0 else { break }
            var currentID: UInt64 = 0
            let result = IORegistryEntryGetRegistryEntryID(entry, &currentID)
            IOObjectRelease(entry)
            guard result == KERN_SUCCESS else { throw Refusal.registryLookup }
            if currentID == registryEntryID { return true }
        }
        guard IOIteratorIsValid(entries) != 0 else { throw Refusal.registryLookup }
        return false
    }
}
