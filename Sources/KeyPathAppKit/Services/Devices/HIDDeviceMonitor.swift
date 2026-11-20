import Foundation
import IOKit
import IOKit.hid
import KeyPathCore
import Observation

/// Monitors keyboard connect/disconnect events via I/O Registry notifications.
/// Needs no privacy permission: it reads registry properties and never opens a device.
///
/// Publishes `connectedKeyboards` as keyboards are plugged in and removed.
/// Filters out VirtualHID devices and devices with VID:PID 0:0 (BLE with no identity).
///
/// ## Thread safety
///
/// This class is `@MainActor` for its published UI state. IOKit callbacks arrive on a
/// dedicated `Thread` (not GCD — GCD can reclaim threads, killing the run loop).
/// The boundary works as follows:
///
/// - `monitorThread`, `trackedDeviceIDs`, `connectedKeyboards`, `lastConnectedKeyboard`
///   are MainActor-isolated and only accessed from MainActor code.
/// - Each start owns a locked HIDMonitorSession. Cancellation before setup is
///   remembered, and a queued run-loop stop covers cancellation before run.
/// - `setupHIDManager` runs entirely on the IOKit thread. Its callback context
///   stays alive until registry notifications and their run-loop source are removed.
/// - `handleDeviceConnected`/`handleDeviceRemoved` run on the IOKit thread, extract
///   Sendable data, then hop to MainActor via `Task { @MainActor }`.
@Observable
@MainActor
final class HIDDeviceMonitor {
    static let shared = HIDDeviceMonitor()

    struct HIDKeyboardEvent: Sendable, Equatable, Identifiable {
        let vendorID: Int
        let productID: Int
        let productName: String
        let isConnected: Bool

        var id: String {
            "\(vendorID):\(productID):\(productName)"
        }

        var vidPidKey: String {
            String(format: "%04X:%04X", vendorID, productID)
        }
    }

    private(set) var connectedKeyboards: [HIDKeyboardEvent] = []

    private(set) var lastConnectedKeyboard: HIDKeyboardEvent?

    /// Dedicated thread for the IOKit run loop. Non-nil means monitoring is active.
    /// Only accessed from MainActor (startMonitoring/stopMonitoring).
    private var monitorThread: Thread?

    private var monitorSession: HIDMonitorSession?

    private final class CallbackContext: Sendable {
        let monitor: HIDDeviceMonitor
        let session: HIDMonitorSession

        init(monitor: HIDDeviceMonitor, session: HIDMonitorSession) {
            self.monitor = monitor
            self.session = session
        }
    }

    private var trackedDeviceIDs: [UInt64: HIDKeyboardEvent] = [:]

    static func currentKeyboardSnapshot() -> [HIDKeyboardEvent] {
        RegistryKeyboards.current().compactMap { event(from: $0, isConnected: true) }
            .sorted { lhs, rhs in
                if lhs.vendorID != rhs.vendorID {
                    return lhs.vendorID < rhs.vendorID
                }
                if lhs.productID != rhs.productID {
                    return lhs.productID < rhs.productID
                }
                return lhs.productName < rhs.productName
            }
    }

    func startMonitoring() {
        guard monitorThread == nil else { return }

        let session = HIDMonitorSession()
        monitorSession = session
        let thread = Thread { [weak self] in
            self?.setupHIDManager(session: session)
        }
        thread.name = "com.keypath.hid-monitor"
        thread.qualityOfService = .utility
        monitorThread = thread
        thread.start()

        AppLogger.shared.log("🔌 [HIDDeviceMonitor] Started monitoring keyboard connections")
    }

    func stopMonitoring() {
        guard let session = monitorSession else { return }
        session.cancel()
        monitorSession = nil
        monitorThread = nil

        AppLogger.shared.log("🔌 [HIDDeviceMonitor] Stopped monitoring keyboard connections")
    }

    // MARK: - IOKit Setup (runs entirely on the dedicated IOKit thread)

    /// Watches the I/O Registry for keyboards arriving and leaving. Reading a
    /// registry entry needs no privacy permission, unlike opening the device
    /// through IOHIDManager, which requires Input Monitoring.
    private nonisolated func setupHIDManager(session: HIDMonitorSession) {
        defer {
            session.finish()
            Task { @MainActor [weak self] in
                guard let self, monitorSession === session else { return }
                monitorSession = nil
                monitorThread = nil
            }
        }
        guard !session.isCancelled,
              let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        let callbackContext = CallbackContext(monitor: self, session: session)
        defer { withExtendedLifetime(callbackContext) {} }
        let context = Unmanaged.passUnretained(callbackContext).toOpaque()
        var addedIterator: io_iterator_t = 0
        var removedIterator: io_iterator_t = 0

        let addedResult = IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, RegistryKeyboards.hidDeviceMatching(),
            { context, iterator in
                guard let context else { return }
                let owner = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
                owner.monitor.handleDevicesConnected(RegistryKeyboards.drain(iterator), session: owner.session)
            }, context, &addedIterator
        )
        let removedResult = IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, RegistryKeyboards.hidDeviceMatching(),
            { context, iterator in
                guard let context else { return }
                let owner = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
                owner.monitor.handleDevicesRemoved(RegistryKeyboards.drainIDs(iterator), session: owner.session)
            }, context, &removedIterator
        )
        defer {
            if addedIterator != 0 { IOObjectRelease(addedIterator) }
            if removedIterator != 0 { IOObjectRelease(removedIterator) }
            IONotificationPortDestroy(port)
        }
        guard addedResult == KERN_SUCCESS, removedResult == KERN_SUCCESS else {
            AppLogger.shared.error("❌ [HIDDeviceMonitor] Registry notifications failed (added=\(addedResult), removed=\(removedResult))")
            return
        }
        // Arm both notifications and report the keyboards already present.
        handleDevicesConnected(RegistryKeyboards.drain(addedIterator), session: session)
        _ = RegistryKeyboards.drainIDs(removedIterator)

        let runLoop = CFRunLoopGetCurrent()!
        guard session.attach(runLoop) else { return }

        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(runLoop, source, .defaultMode)

        // Blocks until this session's queued stop runs.
        CFRunLoopRun()

        CFRunLoopRemoveSource(runLoop, source, .defaultMode)
    }

    // MARK: - Device Callbacks (called on IOKit thread, hop to MainActor)

    private nonisolated func handleDevicesConnected(_ entries: [RegistryKeyboards.Entry], session: HIDMonitorSession) {
        let events = entries.compactMap { entry in
            Self.event(from: entry, isConnected: true).map { (entry.registryID, $0) }
        }
        guard !events.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for (deviceID, event) in events {
                guard monitorSession === session, !session.isCancelled else { return }
                trackedDeviceIDs[deviceID] = event
                if !connectedKeyboards.contains(where: { $0.id == event.id }) {
                    connectedKeyboards.append(event)
                    lastConnectedKeyboard = event
                    AppLogger.shared.log("🔌 [HIDDeviceMonitor] Keyboard connected: \(event.productName) (\(event.vidPidKey))")
                    NotificationCenter.default.post(name: .hidKeyboardConnected, object: nil, userInfo: ["event": event])
                }
            }
        }
    }

    private nonisolated func handleDevicesRemoved(_ deviceIDs: [UInt64], session: HIDMonitorSession) {
        guard !deviceIDs.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for deviceID in deviceIDs {
                guard monitorSession === session, !session.isCancelled else { return }
                guard let event = trackedDeviceIDs.removeValue(forKey: deviceID) else { continue }
                // A keyboard can expose several HID interfaces with the same identity.
                guard !trackedDeviceIDs.values.contains(where: { $0.id == event.id }) else { continue }
                connectedKeyboards.removeAll { $0.id == event.id }
                AppLogger.shared.log("🔌 [HIDDeviceMonitor] Keyboard disconnected: \(event.productName) (\(event.vidPidKey))")
                NotificationCenter.default.post(name: .hidKeyboardDisconnected, object: nil, userInfo: ["event": event])
            }
        }
    }

    // MARK: - Device Info Extraction

    nonisolated static func event(from entry: RegistryKeyboards.Entry, isConnected: Bool) -> HIDKeyboardEvent? {
        let isAppleInternalKeyboard = entry.productName.lowercased().contains("apple internal keyboard")
        guard entry.vendorID != 0 || entry.productID != 0 || isAppleInternalKeyboard else { return nil }
        guard !entry.productName.contains("VirtualHID") else { return nil }
        return HIDKeyboardEvent(
            vendorID: entry.vendorID,
            productID: entry.productID,
            productName: entry.productName,
            isConnected: isConnected
        )
    }
}
