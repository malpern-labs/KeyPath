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

    func testAssignmentCommandsJoinTheNativeEditMenuWithoutTakingTextShortcuts() {
        let main = NSMenu()
        let rootItem = NSMenuItem(title: "Localized menu", action: nil, keyEquivalent: "")
        main.addItem(rootItem)
        let edit = NSMenu()
        rootItem.submenu = edit
        let paste = NSMenuItem(title: "Text Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(paste)
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        OverlayWindow.installAssignmentMenuItems(in: main)
        OverlayWindow.installAssignmentMenuItems(in: main)
        XCTAssertEqual(edit.items.count, 5)
        XCTAssertEqual(paste.keyEquivalent, "v")
        let window = OverlayWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        for (item, action) in zip(edit.items.suffix(3), OverlayWindow.AssignmentMenuAction.allCases) {
            XCTAssertEqual(item.action, action.selector)
            XCTAssertNil(item.target)
            XCTAssertTrue(item.keyEquivalent.isEmpty)
            XCTAssertFalse(window.validateUserInterfaceItem(item))
        }
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
