import Carbon
import CryptoKit
import Darwin
import Foundation
import KeyPathCore

/// Caps consent and recovery shared by the existing lifecycle and worker.
/// Session events cannot distinguish another keyboard's native press of the
/// intermediate key: the reservation is an eligibility declaration, never a
/// device-attribution claim.
extension SessionCapsRuntimeSupport {
    /// Worker failure meaning "the reloaded profile needs a restart": it
    /// uses the reserved key, or no longer runs as managed Caps.
    static let profileChangedReason = "managed-caps-profile-changed"

    /// One tick of the reconnect watcher for a kept (displaced) choice.
    enum ReconnectState: Equatable {
        /// Its keyboard is back at the same port: restart onto it.
        case back
        /// The choice belongs to an earlier boot: forget it and stop watching.
        case stale
        /// Not back yet, or nothing could be read this tick: look again.
        case waiting
    }

    /// Unreadable boot identity or inventory waits rather than giving up:
    /// one failed read must not end the watch, and never re-binds.
    static func reconnectState(displaced: Data, boot: String?,
                               devices: () throws -> [Policy.DeviceIdentity]) -> ReconnectState
    {
        guard let boot else { return .waiting }
        guard (try? SessionCapsSelection.decode(displaced, currentBoot: boot)) != nil else { return .stale }
        guard let devices = try? devices() else { return .waiting }
        return reboundSelection(selectionData: displaced, devices: devices, boot: boot) != nil ? .back : .waiting
    }

    /// Worker failure meaning the leased keyboard instance is gone. Its
    /// mapping went with it; the app restarts without managed Caps.
    static let keyboardDisconnectedReason = "managed-caps-keyboard-disconnected"
    static let ownershipLostReason = "managed-caps-ownership-lost"
    /// Display name of the chosen keyboard, kept so messages can name it
    /// after it disconnects. Never used to identify a device.
    static let selectionNameKey = "keypath.session.caps.selection.name.v1"
    /// Advanced compatibility mode. The normal rule scope is every keyboard.
    static let selectedKeyboardOnlyKey = "keypath.session.caps.selected.only"

    /// One-keyboard scope is opt-in only. A saved selection on its own does
    /// not imply it: a choice left over from before all-keyboards mode
    /// otherwise pinned that Mac to one keyboard, and because a selection
    /// expires at every restart, paused Caps Lock rules after each reboot.
    static func selectedKeyboardOnly(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: selectedKeyboardOnlyKey)
    }

    static let allIntermediateKey = "keypath.session.caps.all.intermediate"
    static let excludedKeyboardsKey = "keypath.session.caps.excluded.keyboards.v1"

    /// An exception follows the physical keyboard at its serial or port, not
    /// a boot-scoped IORegistry entry. The encoded tuple is unambiguous even
    /// when a vendor uses punctuation in its serial number.
    static func preferenceID(_ device: Policy.DeviceIdentity) -> String {
        let fields = [String(device.vendorID), String(device.productID),
                      device.serialNumber ?? "", String(device.locationID ?? 0),
                      device.appleBuiltIn == true ? "1" : "0"]
        return fields.map { "\($0.utf8.count):\($0)" }.joined()
    }

    static func excludedKeyboardIDs(defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.stringArray(forKey: excludedKeyboardsKey) ?? []).filter { $0.utf8.count <= 4096 })
    }

    /// Pool keys already used elsewhere: in any keyboard service's
    /// UserKeyMapping (either side) or by an enabled macOS keyboard shortcut.
    /// KeyPath's own Caps row on `own` is not counted. Synchronous; call off
    /// the main actor.
    static func occupiedIntermediates(own: Policy.DeviceIdentity? = nil,
                                      run: ([String]) throws -> String = SessionCapsHIDUtilTransport.runHIDUtil,
                                      shortcutKeyCodes: () -> Set<UInt16> = enabledShortcutKeyCodes,
                                      emitsKeyboardUsages: (UInt64) -> Bool? = SessionCapsHIDUtilTransport.serviceEmitsKeyboardUsages) throws -> Set<UInt32>
    {
        let rows = try SessionCapsHIDUtilTransport.parseAllMappings(run(["property", "--get", "UserKeyMapping"]))
        // Our lease covers the chosen keyboard's service group (see
        // `SessionCapsHIDUtilTransport.serviceGroup`), so its Caps row on any
        // member is ours; on any other service it is not. Without the device
        // list, fall back to the chosen service.
        var ownServices = Set<UInt64>()
        if let own {
            ownServices = (try? SessionCapsHIDUtilTransport.groupMembers(own, run: run, emitsKeyboardUsages: emitsKeyboardUsages))
                ?? [own.registryEntryID]
        }
        var usages: [UInt64] = []
        for (registry, mappings) in rows {
            for mapping in mappings {
                if ownServices.contains(registry), mapping.source == Policy.caps,
                   SessionCapsIntermediate.isCandidate(packed: mapping.destination) { continue }
                usages += [mapping.source, mapping.destination]
            }
        }
        return SessionCapsIntermediate.occupied(mappingUsages: usages, shortcutKeyCodes: shortcutKeyCodes())
    }

    /// Virtual keycodes of enabled entries in System Settings > Keyboard >
    /// Keyboard Shortcuts (`com.apple.symbolichotkeys`), any modifiers.
    static func enabledShortcutKeyCodes() -> Set<UInt16> {
        guard let hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                      "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        else { return [] }
        return parseShortcutKeyCodes(hotkeys)
    }

    static func parseShortcutKeyCodes(_ hotkeys: [String: Any]) -> Set<UInt16> {
        var codes = Set<UInt16>()
        for case let entry as [String: Any] in hotkeys.values {
            guard (entry["enabled"] as? NSNumber)?.boolValue == true,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [NSNumber], parameters.count >= 2,
                  let code = UInt16(exactly: parameters[1].intValue) else { continue }
            codes.insert(code)
        }
        return codes
    }

    /// Read any existing Caps Lock mapping on the keyboard. Call off the main actor.
    static func capsConflict(on device: Policy.DeviceIdentity,
                             backend: SessionCapsMappingLease.Backend = SessionCapsHIDUtilTransport.backend()) throws -> SessionCapsConflict?
    {
        // Another tool may have mapped Caps on only one covered interface of
        // the board. Other interfaces (consumer, raw HID) are not read.
        let members = try backend.members(device)
        var rows = try [backend.read(device).mappings]
        if members.count > 1 {
            let group = try backend.readGroup(device)
            rows += members.sorted().filter { $0 != device.registryEntryID }.compactMap { group[$0] }
        }
        for mappings in rows {
            if let conflict = SessionCapsConflict.identify(mappings) { return conflict }
        }
        return nil
    }

    /// The saved choice re-bound to its keyboard replugged at the same port
    /// (see `SessionCapsSelection.rebound`), or nil.
    static func reboundSelection(selectionData: Data?, devices: [Policy.DeviceIdentity], boot: String) -> SessionCapsSelection? {
        guard let selectionData, let stored = try? SessionCapsSelection.decode(selectionData, currentBoot: boot) else { return nil }
        return stored.rebound(among: devices, currentBoot: boot)
    }

    /// Only discovers a selection. Mapping writes remain owned by the worker lease.
    /// A withheld keyboard (one KeyPath cannot target) still counts: the user
    /// may type on it, so the lone eligible one is not picked on their behalf.
    static func automaticSelection(devices: [Policy.DeviceIdentity], withheld: Int, boot: String) throws -> SessionCapsSelection {
        guard devices.count == 1, withheld == 0 else { throw Refusal.selection }
        let selection = SessionCapsSelection(device: devices[0], bootSessionUUID: boot)
        _ = try selection.approvedDevice(currentBoot: boot)
        return selection
    }

    static func journalDirectory(configPath: String = KeyPathConstants.Config.mainConfigPath) -> URL {
        URL(fileURLWithPath: configPath).deletingLastPathComponent().appendingPathComponent(".session-caps-mapping", isDirectory: true)
    }

    /// All representable keys must be up in HID state, excluding Caps Lock’s
    /// persistent latch. It does not attribute a key to a device. Combined
    /// session state also keeps a posted press whose own release never came:
    /// on 2026-10-20 it reported Space held for hours while HID state and every
    /// keyboard had released it. Posted presses can still reach HID state, so a
    /// caller that waits on this must say which key it is waiting for.
    static func requirePhysicalAllUp(isDown: (CGKeyCode) -> Bool = hidKeyDown) throws {
        guard heldKeys(isDown: isDown).isEmpty else { throw Refusal.physicalKeysHeld }
    }

    static func heldKeys(isDown: (CGKeyCode) -> Bool = hidKeyDown) -> [CGKeyCode] {
        SessionKeyMap.keyCodeToUsage.keys.filter { $0 != 57 && isDown($0) }.sorted()
    }

    /// Posts a key-up at the HID level for each key, which clears HID state
    /// that kept a press whose release never arrived.
    static func postHIDRelease(_ keys: [CGKeyCode]) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for key in keys {
            CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    static func hidKeyDown(_ key: CGKeyCode) -> Bool {
        CGEventSource.keyState(.hidSystemState, key: key)
    }

    static func configSHA256(_ path: String) throws -> String {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Refusal.configIdentity }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var before = stat(), after = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size > 0, before.st_size <= 65536,
              let data = try file.read(upToCount: 65537), data.count == before.st_size,
              fstat(descriptor, &after) == 0, before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw Refusal.configIdentity }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func validatedConfigDigest(_ path: String, beforeValidation: String?) throws -> String {
        guard let beforeValidation, try configSHA256(path) == beforeValidation else { throw Refusal.configIdentity }
        return beforeValidation
    }

    static func verifyActive(directory: URL, owner: Policy.Owner,
                             backend: SessionCapsMappingLease.Backend = SessionCapsHIDUtilTransport.backend(),
                             bootSessionUUID boot: () throws -> String = bootSessionUUID) throws
    {
        let lease = SessionCapsMappingLease(directory: directory, backend: backend)
        guard let record = try lease.pendingRecord(), record.owner == owner else { throw SessionCapsMappingLease.Refusal.wrongOwner }
        // Other keyboards may be connected; the leased instance must be present
        // exactly once. The intermediate stays reserved: merged events carry no attribution.
        do { try Policy.requireUnique(record.device, among: backend.enumerate()) } catch { throw Refusal.selection }
        let snapshot = try backend.read(record.device)
        _ = try Policy.restore(record: record, current: snapshot.mappings, device: snapshot.device, bootSessionUUID: boot())
        // Every recorded companion interface must still carry exactly our
        // mapping. One that could not be read this tick is not a foreign
        // write: it is checked again next tick (the chosen interface was just
        // verified). A different mapping is foreign; restore decides the rest.
        if !record.companions.isEmpty {
            let group = try backend.readGroup(record.device)
            for companion in record.companions {
                guard let mappings = group[companion.registryEntryID] else { continue }
                guard mappings == record.applied(over: companion.original) else { throw Policy.Refusal.foreignMapping }
            }
        }
    }

    /// The worker's periodic lease check. Only a leased instance that no
    /// longer exists is a disconnect; one that is present but no longer
    /// verifies (a foreign write, a duplicate locator) is lost ownership.
    static func leaseCheckFailure(registryEntryID: UInt64, verify: () throws -> Void,
                                  registryEntryExists: (UInt64) throws -> Bool) -> String?
    {
        do { try verify(); return nil } catch {
            return (try? registryEntryExists(registryEntryID)) == false ? keyboardDisconnectedReason : ownershipLostReason
        }
    }

    /// Off-main caller constructs the transport here; only scalar ownership
    /// crosses actor boundaries. A PID reused by a live process refuses recovery.
    static func recoverPending(directory: URL, expectedOwner: Policy.Owner? = nil) throws {
        let boot = try bootSessionUUID()
        try recoverIndependent(
            legacy: { try recoverLegacyPending(directory: directory, expectedOwner: expectedOwner) },
            fleet: {
                try SessionCapsMappingFleet(directory: directory, backend: SessionCapsHIDUtilTransport.backend())
                    .recover(expectedOwner: expectedOwner, bootSessionUUID: boot)
            }
        )
    }

    static func recoverIndependent(legacy: () throws -> Void, fleet: () throws -> Void) throws {
        var firstFailure: Error?
        do { try legacy() }
        catch { firstFailure = error }
        do { try fleet() }
        catch {
            if firstFailure == nil { firstFailure = error }
        }
        if let firstFailure { throw firstFailure }
    }

    private static func recoverLegacyPending(directory: URL, expectedOwner: Policy.Owner?) throws {
        var metadata = stat()
        if lstat(directory.appendingPathComponent("caps-mapping-intent.json").path, &metadata) != 0 {
            guard errno == ENOENT else { throw SessionCapsMappingLease.Refusal.unsafeFile }
            // An orphan marker has no validated boot identity. Retain it.
            if lstat(directory.appendingPathComponent("caps-mapping-mutation-in-flight.json").path, &metadata) == 0 {
                throw SessionCapsMappingLease.Refusal.mutationUncertain
            }
            guard errno == ENOENT else { throw SessionCapsMappingLease.Refusal.unsafeFile }
            return
        }
        let lease = SessionCapsMappingLease(directory: directory, backend: SessionCapsHIDUtilTransport.backend())
        let currentBoot = try bootSessionUUID()
        if try lease.retirePreviousBoot(bootSessionUUID: currentBoot) { return }
        guard let record = try lease.pendingRecord() else { return }
        if let expectedOwner {
            guard record.owner == expectedOwner else { throw SessionCapsMappingLease.Refusal.wrongOwner }
        } else {
            guard !SystemStateProvider.isProcessAlive(pid: record.owner.parentPID),
                  !SystemStateProvider.isProcessAlive(pid: record.owner.workerPID)
            else { throw Refusal.liveOwner }
        }
        try lease.restore(expectedOwner: record.owner, bootSessionUUID: currentBoot)
    }
}
