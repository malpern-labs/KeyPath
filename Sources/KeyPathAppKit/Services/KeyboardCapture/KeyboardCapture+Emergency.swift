import AppKit
import Foundation
import KeyPathCore

@MainActor
extension KeyboardCapture {
    // MARK: - Emergency Stop Sequence Detection

    func startEmergencyMonitoring(callback: @escaping () -> Void) {
        guard !isMonitoringEmergency else { return }

        // Avoid event taps in test/CI to prevent hangs
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug(
                "🧪 [KeyboardCapture] Test environment – skipping emergency monitoring tap"
            )
            return
        }

        emergencyCallback = callback
        isMonitoringEmergency = true

        // Only start monitoring if we already have permissions
        // Don't prompt for permissions - let the wizard handle that
        if !checkAccessibilityPermissionsSilently() {
            // Silently fail - we'll start monitoring once permissions are granted
            isMonitoringEmergency = false
            return
        }

        setupEmergencyEventTap()
    }

    func stopEmergencyMonitoring() {
        guard isMonitoringEmergency else { return }

        isMonitoringEmergency = false
        pressedKeys.removeAll()

        emergencyObserver?.stop()
        emergencyObserver = nil
    }

    func setupEmergencyEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // The tap runs on its own thread so a busy main thread never delays typing;
        // chord detection hops back to the main actor in event order.
        emergencyObserver = ObservingEventTap.start(
            place: .headInsertEventTap,
            events: CGEventMask(eventMask),
            threadName: "com.keypath.emergency-stop-tap"
        ) { [weak self] type, event in
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handleEmergencyKey(keyCode: keyCode, type: type) }
            }
        }

        if let emergencyObserver {
            AppLogger.shared.log("🛑 [KeyboardCapture] Emergency stop tap active (passThrough=\(emergencyObserver.passThrough))")
        } else {
            AppLogger.shared.error("❌ [KeyboardCapture] Failed to create emergency event tap")
        }
    }

    func handleEmergencyKey(keyCode: Int64, type: CGEventType) {
        // Key codes for the emergency sequence: Ctrl (59), Space (49), Esc (53)
        let leftControlKey: Int64 = 59
        let spaceKey: Int64 = 49
        let escapeKey: Int64 = 53

        if type == .keyDown {
            pressedKeys.insert(keyCode)

            // Check if all three keys are pressed simultaneously
            if pressedKeys.contains(leftControlKey),
               pressedKeys.contains(spaceKey),
               pressedKeys.contains(escapeKey)
            {
                AppLogger.shared.log("🚨 [Emergency] Kanata emergency stop sequence detected!")

                Task { @MainActor [weak self] in
                    self?.emergencyCallback?()
                }

                // Clear the set to prevent repeated triggers
                pressedKeys.removeAll()
            }
        } else if type == .keyUp {
            pressedKeys.remove(keyCode)
        }
    }
}
