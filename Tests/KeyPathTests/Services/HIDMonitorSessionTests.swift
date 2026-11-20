import Foundation
@testable import KeyPathAppKit
import XCTest

final class HIDMonitorSessionTests: XCTestCase {
    func testStopBeforeSetupRefusesRunLoopAttachment() async {
        await withWorkerRunLoop { loop in
            let session = HIDMonitorSession()
            session.cancel()
            XCTAssertFalse(session.attach(loop))
        }
    }

    func testStopAfterAttachmentBeforeRunIsNotLost() async {
        await withWorkerRunLoop { loop in
            let session = HIDMonitorSession()
            XCTAssertTrue(session.attach(loop))
            session.cancel()
            // Exercise the real CoreFoundation boundary, not a business delay.
            // One second is a failure bound; the queued stop returns immediately.
            XCTAssertEqual(CFRunLoopRunInMode(.defaultMode, 1, false), .stopped)
            session.finish()
        }
    }

    func testFinishedSessionCannotAttachAgain() async {
        await withWorkerRunLoop { loop in
            let session = HIDMonitorSession()
            XCTAssertTrue(session.attach(loop))
            session.finish()
            XCTAssertFalse(session.attach(loop))
            XCTAssertTrue(session.isCancelled)
        }
    }

    func testRetiredSessionDoesNotStopReplacement() async {
        await withWorkerRunLoop { loop in
            let old = HIDMonitorSession()
            let replacement = HIDMonitorSession()
            XCTAssertTrue(old.attach(loop))
            old.finish()
            XCTAssertTrue(replacement.attach(loop))
            old.cancel()
            // A timer keeps the loop valid; no time needs to elapse. An old
            // owner's cancellation must not stop this replacement's loop.
            XCTAssertEqual(CFRunLoopRunInMode(.defaultMode, 0, false), .timedOut)
            XCTAssertFalse(replacement.isCancelled)
            replacement.finish()
        }
    }

    private func withWorkerRunLoop(_ exercise: @escaping @Sendable (CFRunLoop) -> Void) async {
        let finished = XCTestExpectation(description: "owned run-loop worker finished")
        Thread {
            let loop = CFRunLoopGetCurrent()!
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 10, 0, 0, 0) { _ in }
            CFRunLoopAddTimer(loop, timer, .defaultMode)
            defer {
                CFRunLoopRemoveTimer(loop, timer, .defaultMode)
                finished.fulfill()
            }
            exercise(loop)
        }.start()
        let outcome = await XCTWaiter.fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(outcome, .completed)
    }
}
