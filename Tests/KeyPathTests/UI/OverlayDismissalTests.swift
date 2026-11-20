import AppKit
@testable import KeyPathAppKit
import XCTest

@MainActor
final class OverlayDismissalTests: XCTestCase {
    func testInstantCloseRejectsAlreadyQueuedOpeningTick() async throws {
        let preferences = try IsolatedPreferenceDefaults()
        let controller = LiveKeyboardOverlayController(defaults: preferences.defaults)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.window = window
        defer {
            controller.finalizeInspectorAnimation()
            window.close()
        }
        controller.uiState.inspectorReveal = 0
        controller.uiState.isInspectorOpen = false
        controller.uiState.isInspectorAnimating = true
        controller.animateInspectorReveal(to: 1)
        let openingTimer = try XCTUnwrap(controller.inspectorAnimationTimer)
        openingTimer.fire() // Queues a MainActor update that must not survive the close.
        controller.closeInspector(animated: false)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        XCTAssertFalse(openingTimer.isValid)
        XCTAssertNil(controller.inspectorAnimationTimer)
        XCTAssertEqual(controller.uiState.inspectorReveal, 0)
        XCTAssertFalse(controller.uiState.isInspectorOpen)
        XCTAssertFalse(controller.uiState.isInspectorAnimating)
    }

    func testExplicitClosePreventsAutomaticShowOnlyInItsOwnDomain() throws {
        let preferences = try IsolatedPreferenceDefaults()
        let otherPreferences = try IsolatedPreferenceDefaults()
        let controller = LiveKeyboardOverlayController(defaults: preferences.defaults)
        let otherController = LiveKeyboardOverlayController(defaults: otherPreferences.defaults)

        XCTAssertTrue(controller.canAutoShow)
        XCTAssertTrue(otherController.canAutoShow)
        controller.hideExplicitly()

        XCTAssertTrue(preferences.defaults.bool(forKey: "LiveKeyboardOverlay.userExplicitlyHidden"))
        XCTAssertFalse(controller.canAutoShow)
        XCTAssertTrue(otherController.canAutoShow)
    }
}
