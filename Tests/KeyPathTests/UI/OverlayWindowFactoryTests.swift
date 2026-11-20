import AppKit
@testable import KeyPathAppKit
import XCTest

@MainActor
final class OverlayWindowFactoryTests: XCTestCase {
    func testWindowStyleForAccessibilityTestMode() {
        let style = OverlayWindowFactory.windowStyle(useAccessibilityTestMode: true)

        XCTAssertTrue(style.contains(.titled))
        XCTAssertTrue(style.contains(.resizable))
        XCTAssertTrue(style.contains(.closable))
    }

    func testWindowStyleForNormalMode() {
        let style = OverlayWindowFactory.windowStyle(useAccessibilityTestMode: false)

        XCTAssertTrue(style.contains(.borderless))
        XCTAssertTrue(style.contains(.resizable))
        XCTAssertFalse(style.contains(.titled))
    }

    func testOverlayOffersNativeUndoOnlyWhenItOwnsKeyboardFocus() {
        let window = OverlayWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        let command = NSMenuItem(title: "Undo", action: #selector(OverlayWindow.undoOverlayRemap(_:)), keyEquivalent: "z")
        let target = NSObject()
        window.remapUndoManager.beginUndoGrouping()
        window.remapUndoManager.registerUndo(withTarget: target) { _ in }
        window.remapUndoManager.setActionName("Test Remap")
        window.remapUndoManager.endUndoGrouping()

        XCTAssertTrue(window.responds(to: command.action!))
        XCTAssertFalse(window.validateUserInterfaceItem(command))
        XCTAssertEqual(command.title, window.remapUndoManager.undoMenuItemTitle)
        window.undoOverlayRemap(nil)
        XCTAssertTrue(window.remapUndoManager.canUndo)
    }

    func testDefaultOriginUsesBottomRightMargin() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let windowSize = CGSize(width: 200, height: 100)
        let origin = OverlayWindowFactory.defaultOrigin(
            visibleFrame: visibleFrame,
            windowSize: windowSize,
            margin: 20
        )

        XCTAssertEqual(origin.x, 780, accuracy: 0.001)
        XCTAssertEqual(origin.y, 20, accuracy: 0.001)
    }
}
