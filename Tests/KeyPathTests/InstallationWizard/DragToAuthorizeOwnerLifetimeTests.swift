import AppKit
@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

/// Closes or replaces a drag-to-authorize presentation while its delayed work
/// is pending, and checks that the stale work changes nothing (review item P6).
/// The scheduler is a manual queue, so no test waits on real time, opens
/// System Settings, or creates an AppKit panel.
@MainActor
final class DragToAuthorizeOwnerLifetimeTests: XCTestCase {
    @MainActor
    private final class ManualScheduler {
        struct Item {
            let delay: TimeInterval
            let work: @MainActor () -> Void
        }

        var pending: [Item] = []

        func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
            pending.append(Item(delay: delay, work: work))
        }

        /// Runs the item scheduled at `index` (in scheduling order) and removes it.
        func run(at index: Int) {
            let item = pending.remove(at: index)
            item.work()
        }

        /// Index of the oldest pending item with this delay.
        func index(ofDelay delay: TimeInterval) -> Int? {
            pending.firstIndex { $0.delay == delay }
        }

        /// Runs every pending item, shortest delay first, including work they schedule.
        func runAll() {
            while let next = pending.indices.min(by: { pending[$0].delay < pending[$1].delay }) {
                run(at: next)
            }
        }
    }

    private var scheduler: ManualScheduler!
    private var openedURLs: [URL] = []
    private var shownGenerations: [UInt64] = []
    private var controller: DragToAuthorizeController!

    override func setUp() async throws {
        try await super.setUp()
        let scheduler = ManualScheduler()
        self.scheduler = scheduler
        openedURLs = []
        shownGenerations = []
        controller = DragToAuthorizeController(
            schedule: { delay, work in scheduler.schedule(delay, work) },
            openSettings: { [weak self] url in self?.openedURLs.append(url) },
            presentPanel: { [weak self] _, _, _, _, _, generation in
                self?.shownGenerations.append(generation)
            }
        )
    }

    override func tearDown() async throws {
        controller = nil
        scheduler = nil
        try await super.tearDown()
    }

    /// Presents and runs the panel creation and entrance animation, leaving the
    /// overlay visible. Returns the presentation's generation.
    @discardableResult
    private func presentToVisible() throws -> UInt64 {
        controller.present(for: .accessibility)
        let panelIndex = try XCTUnwrap(scheduler.index(ofDelay: 0.8))
        scheduler.run(at: panelIndex)
        let generation = try XCTUnwrap(shownGenerations.last)
        controller.presentationAnimationDidFinish(generation: generation)
        XCTAssertEqual(controller.state, .visible)
        return generation
    }

    func testDismissBeforePanelIsDueShowsNoPanel() {
        controller.present(for: .accessibility)
        XCTAssertEqual(controller.state, .presenting)

        controller.dismiss(animated: false)
        scheduler.runAll()

        XCTAssertTrue(shownGenerations.isEmpty, "the panel must not appear after its presentation was dismissed")
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.currentTarget)
    }

    func testAnimatedDismissDoesNotTearDownAReplacementPresentation() throws {
        try presentToVisible()

        controller.dismiss(animated: true)
        XCTAssertEqual(controller.state, .dismissing)
        // Present again before the 0.3 s fade-out teardown has run.
        controller.present(for: .accessibility)
        scheduler.runAll()

        XCTAssertEqual(shownGenerations.count, 2, "the replacement presentation must show its own panel")
        let replacement = try XCTUnwrap(shownGenerations.last)
        controller.presentationAnimationDidFinish(generation: replacement)
        XCTAssertEqual(controller.state, .visible)
        XCTAssertEqual(controller.currentTarget, .accessibility)
    }

    func testEntranceAnimationFinishingAfterDismissDoesNotReviveTheOverlay() throws {
        controller.present(for: .accessibility)
        try scheduler.run(at: XCTUnwrap(scheduler.index(ofDelay: 0.8)))
        let generation = try XCTUnwrap(shownGenerations.last)

        controller.dismiss(animated: false)
        controller.presentationAnimationDidFinish(generation: generation)

        XCTAssertEqual(controller.state, .idle)
    }

    func testRetryResetFromAReplacedPresentationIsIgnored() throws {
        try presentToVisible()
        controller.dragDidEnd(accepted: false)
        XCTAssertEqual(controller.state, .retrying)
        let staleReset = try XCTUnwrap(scheduler.index(ofDelay: 2.0))
        XCTAssertEqual(staleReset, 0)

        controller.dismiss(animated: false)
        try presentToVisible()
        controller.dragDidEnd(accepted: false)
        XCTAssertEqual(controller.state, .retrying)

        // The first presentation's reset fires inside the second one's retry.
        scheduler.run(at: staleReset)
        XCTAssertEqual(controller.state, .retrying, "a stale reset must not end the current retry early")

        try scheduler.run(at: XCTUnwrap(scheduler.index(ofDelay: 2.0)))
        XCTAssertEqual(controller.state, .visible)
    }

    func testSuccessDismissalFromAReplacedPresentationIsIgnored() throws {
        try presentToVisible()
        controller.dragDidEnd(accepted: true)
        XCTAssertEqual(controller.state, .success)
        let staleDismissal = try XCTUnwrap(scheduler.index(ofDelay: 1.8))

        controller.dismiss(animated: false)
        try presentToVisible()

        scheduler.run(at: staleDismissal)
        XCTAssertEqual(controller.state, .visible, "the old success must not dismiss the new presentation")
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testLatePermissionPollIsIgnoredAfterDismissAndReplacement() throws {
        let first = try presentToVisible()

        controller.dismiss(animated: false)
        controller.permissionPollDidResolve(granted: true, generation: first)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(scheduler.pending.isEmpty, "a stale grant must not schedule a dismissal")

        let second = try presentToVisible()
        controller.permissionPollDidResolve(granted: true, generation: first)
        XCTAssertEqual(controller.state, .visible)

        controller.permissionPollDidResolve(granted: true, generation: second)
        XCTAssertEqual(controller.state, .success)
    }

    func testDismissCancelsAPendingRetryOfPresent() throws {
        try presentToVisible()

        // Presenting while visible tears down and retries after 0.1 s.
        controller.present(for: .accessibility)
        XCTAssertEqual(controller.state, .idle)
        controller.dismiss()
        scheduler.runAll()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(openedURLs.count, 1, "the cancelled retry must not reopen System Settings")
        XCTAssertEqual(shownGenerations.count, 1)
    }
}
