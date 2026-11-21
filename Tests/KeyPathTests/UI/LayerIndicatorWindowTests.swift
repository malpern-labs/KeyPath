import AppKit
@testable import KeyPathAppKit
import XCTest

@MainActor
final class LayerIndicatorWindowTests: XCTestCase {
    func testEarlierFadeCompletionLeavesReplacementVisible() async throws {
        let oldFadeStarted = XCTestExpectation(description: "First presentation started fading")
        let newFadeStarted = XCTestExpectation(description: "Replacement started fading")
        var completions: [@MainActor @Sendable () -> Void] = []
        let window = LayerIndicatorWindow { _, completion in
            completions.append(completion)
            if completions.count == 1 { oldFadeStarted.fulfill() }
            if completions.count == 2 { newFadeStarted.fulfill() }
        }
        window.isReleasedWhenClosed = false
        defer { window.dismissImmediately() }

        window.show(layerName: "nav")
        try XCTUnwrap(window.hideTimer).fire()
        let first = await XCTWaiter.fulfillment(of: [oldFadeStarted], timeout: 2)
        XCTAssertEqual(first, .completed)

        window.show(layerName: "symbols")
        let replacementTimer = try XCTUnwrap(window.hideTimer)
        try XCTUnwrap(completions.first)()
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(replacementTimer === window.hideTimer)

        replacementTimer.fire()
        let second = await XCTWaiter.fulfillment(of: [newFadeStarted], timeout: 2)
        XCTAssertEqual(second, .completed)
        XCTAssertEqual(completions.count, 2)
        try XCTUnwrap(completions.last)()
        XCTAssertFalse(window.isVisible)
    }
}
