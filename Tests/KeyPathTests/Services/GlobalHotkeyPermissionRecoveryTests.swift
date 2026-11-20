import AppKit
@testable import KeyPathAppKit
import XCTest

@MainActor
final class GlobalHotkeyPermissionRecoveryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuite: String!

    override func setUp() async throws {
        try await super.setUp()
        defaultsSuite = "keypath-preference-test-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
    }

    override func tearDown() async throws {
        if let defaultsSuite { defaults?.removePersistentDomain(forName: defaultsSuite) }
        defaults = nil
        defaultsSuite = nil
        try await super.tearDown()
    }

    func testInjectedDisabledPreferencePreventsMonitorInstallation() {
        defaults.set(false, forKey: "KeyPath.GlobalHotkey.Enabled")
        let service = GlobalHotkeyService(
            defaults: defaults,
            permissionsReady: { true },
            addGlobalMonitor: { _ in XCTFail("Disabled hotkey must not install a global monitor"); return nil },
            addLocalMonitor: { _ in XCTFail("Disabled hotkey must not install a local monitor"); return nil },
            removeMonitor: { _ in }
        )
        service.startMonitoring()
        XCTAssertFalse(service.isEnabled)
    }

    func testGrantAfterInitialDeniedStartInstallsMonitorsOnce() {
        let center = NotificationCenter()
        var granted = false
        var globalCount = 0
        var localCount = 0
        let service = GlobalHotkeyService(
            defaults: defaults,
            notificationCenter: center, permissionsReady: { granted },
            addGlobalMonitor: { _ in globalCount += 1; return NSObject() },
            addLocalMonitor: { _ in localCount += 1; return NSObject() },
            removeMonitor: { _ in }
        )
        let key = "KeyPath.GlobalHotkey.Enabled"
        let previous = defaults.object(forKey: key)
        defaults.set(true, forKey: key)
        defer {
            service.stopMonitoring()
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        service.startMonitoring()
        XCTAssertEqual(globalCount, 0)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(globalCount, 0)
        granted = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(globalCount, 1)
        XCTAssertEqual(localCount, 1)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(globalCount, 1)
        XCTAssertEqual(localCount, 1)
    }

    func testFailedGlobalMonitorRetryDoesNotLeakLocalMonitor() {
        let center = NotificationCenter()
        var globalCount = 0
        var localCount = 0
        var removedCount = 0
        let service = GlobalHotkeyService(
            defaults: defaults,
            notificationCenter: center, permissionsReady: { true },
            addGlobalMonitor: { _ in
                globalCount += 1
                return globalCount == 1 ? nil : NSObject()
            },
            addLocalMonitor: { _ in localCount += 1; return NSObject() },
            removeMonitor: { _ in removedCount += 1 }
        )
        let key = "KeyPath.GlobalHotkey.Enabled"
        let previous = defaults.object(forKey: key)
        defaults.set(true, forKey: key)
        defer {
            service.stopMonitoring()
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        service.startMonitoring()
        XCTAssertEqual(localCount, 1)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(globalCount, 2)
        XCTAssertEqual(localCount, 1, "Retry must retain the already-installed local monitor")
        service.stopMonitoring()
        XCTAssertEqual(removedCount, 2, "Every installed monitor must remain owned until removal")
    }

    func testStopCancelsPendingGrantRecovery() {
        let center = NotificationCenter()
        var granted = false
        var installed = 0
        let service = GlobalHotkeyService(
            defaults: defaults,
            notificationCenter: center, permissionsReady: { granted },
            addGlobalMonitor: { _ in installed += 1; return NSObject() },
            addLocalMonitor: { _ in NSObject() }, removeMonitor: { _ in }
        )
        let key = "KeyPath.GlobalHotkey.Enabled"
        let previous = defaults.object(forKey: key)
        defaults.set(true, forKey: key)
        defer {
            service.stopMonitoring()
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        service.startMonitoring()
        service.stopMonitoring()
        granted = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(installed, 0)
    }
}
