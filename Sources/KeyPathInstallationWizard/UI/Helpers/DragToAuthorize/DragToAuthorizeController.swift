import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import Observation
import SwiftUI

/// Orchestrates the drag-to-authorize overlay lifecycle.
/// Manages panel presentation, Settings window tracking, permission polling,
/// and state transitions with animations.
@Observable
@MainActor
public final class DragToAuthorizeController {
    public static let shared = DragToAuthorizeController()

    // MARK: - Public Types

    public enum PermissionTarget: Sendable {
        case accessibility

        var settingsURL: URL {
            switch self {
            case .accessibility:
                URL(string: KeyPathConstants.URLs.accessibilityPrivacy)!
            }
        }

        var displayName: String {
            switch self {
            case .accessibility: AccessibilityPermissionPresentation.current.name
            }
        }
    }

    /// Which app the overlay authorizes — i.e. which file the user drags into the
    /// privacy list and whose permission is polled. KeyPath.app is the only
    /// permission identity; the session runtime runs from its bundle.
    public enum PermissionSubject: Equatable, Sendable {
        /// KeyPath.app's own grant. Drags the app bundle and polls `snapshot.accessibility`.
        case keyPath

        /// File dragged into the System Settings privacy list for this subject.
        var fileURL: URL {
            switch self {
            case .keyPath: URL(fileURLWithPath: Bundle.main.bundlePath)
            }
        }

        /// Primary label shown on the draggable tile.
        var displayName: String {
            switch self {
            case .keyPath: "KeyPath"
            }
        }

        /// Secondary label shown under the tile's primary label.
        var subtitle: String {
            switch self {
            case .keyPath: String(localized: "Main application")
            }
        }
    }

    public enum OverlayState: Equatable {
        case idle
        case presenting
        case visible
        case dragging
        case success
        case retrying
        case dismissing
    }

    // MARK: - Observable State

    public private(set) var state: OverlayState = .idle
    public private(set) var currentTarget: PermissionTarget?
    public private(set) var currentSubject: PermissionSubject = .keyPath

    // MARK: - Private Properties

    private var panel: DragToAuthorizePanel?
    private var tracker: SettingsWindowTracker?
    private var stateModel: DragToAuthorizeStateModel?
    private var permissionPollTimer: Timer?

    /// Identifies the presentation that delayed work belongs to. `present` and
    /// `dismiss` advance it, so a callback scheduled for an earlier presentation
    /// (panel creation, the animated teardown, the retry reset, the success
    /// dismissal, an animation completion or a permission poll) does nothing
    /// once that presentation has been dismissed or replaced.
    @ObservationIgnored private(set) var presentationGeneration: UInt64 = 0

    /// Runs `work` on the main actor after a delay. Injected so tests can close
    /// or replace the presentation while work is pending, without real sleeps.
    typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void
    /// Opens System Settings at the target pane.
    typealias SettingsOpener = @MainActor (URL) -> Void
    /// Builds and shows the floating panel for one presentation.
    typealias PanelPresenter = @MainActor (
        DragToAuthorizeController, PermissionTarget, PermissionSubject, NSRect?, NSWindow?, UInt64
    ) -> Void

    @ObservationIgnored private let schedule: Scheduler
    @ObservationIgnored private let openSettings: SettingsOpener
    @ObservationIgnored private let presentPanel: PanelPresenter?

    private convenience init() {
        self.init(
            schedule: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    MainActor.assumeIsolated { work() }
                }
            },
            openSettings: { url in
                NSWorkspace.shared.open(url)
                // Record that we opened System Settings so the wizard's cleanup
                // closes it when the flow finishes.
                WizardWindowManager.shared.markSystemSettingsOpened()
            },
            presentPanel: nil
        )
    }

    /// `presentPanel` nil means the real AppKit panel. Tests pass a recorder.
    init(schedule: @escaping Scheduler, openSettings: @escaping SettingsOpener, presentPanel: PanelPresenter?) {
        self.schedule = schedule
        self.openSettings = openSettings
        self.presentPanel = presentPanel
    }

    // MARK: - Public API

    /// Present the drag-to-authorize overlay for the given permission target.
    /// Opens System Settings and shows the floating panel anchored below it.
    ///
    /// - Parameter subject: which app the user drags into the list.
    public func present(
        for target: PermissionTarget,
        subject: PermissionSubject = .keyPath,
        sourceRect: NSRect? = nil,
        in sourceWindow: NSWindow? = nil
    ) {
        guard state == .idle else {
            dismiss(animated: false)
            let generation = presentationGeneration
            schedule(0.1) { [weak self] in
                // A later present or dismiss supersedes this retry.
                guard let self, presentationGeneration == generation else { return }
                present(for: target, subject: subject, sourceRect: sourceRect, in: sourceWindow)
            }
            return
        }

        presentationGeneration &+= 1
        let generation = presentationGeneration
        currentTarget = target
        currentSubject = subject
        state = .presenting

        openSettings(target.settingsURL)

        schedule(0.8) { [weak self] in
            // Dismissed or replaced before the panel was due: show nothing.
            guard let self, presentationGeneration == generation else { return }
            if let presentPanel {
                presentPanel(self, target, subject, sourceRect, sourceWindow, generation)
            } else {
                createAndShowPanel(
                    for: target, subject: subject, sourceRect: sourceRect, sourceWindow: sourceWindow,
                    generation: generation
                )
            }
        }

        AppLogger.shared.log("🎯 [DragToAuthorize] Presenting \(subject.displayName) for \(target.displayName)")
    }

    /// Dismiss the overlay with optional animation.
    public func dismiss(animated: Bool = true) {
        // Advance even when idle, so a pending retry of `present` is dropped too.
        presentationGeneration &+= 1
        guard state != .idle else { return }

        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
        tracker?.stopTracking()
        tracker = nil

        if animated {
            state = .dismissing
            stateModel?.transitionTo(.dismissing)

            let generation = presentationGeneration
            schedule(0.3) { [weak self] in
                // A presentation started during the fade must not be torn down.
                guard let self, presentationGeneration == generation else { return }
                tearDown()
            }
        } else {
            tearDown()
        }
    }

    // MARK: - Internal Callbacks (from drag source)

    func dragDidBegin() {
        state = .dragging
        stateModel?.transitionTo(.dragging)
        AppLogger.shared.log("🎯 [DragToAuthorize] Drag began")
    }

    func dragDidEnd(accepted: Bool) {
        if accepted {
            transitionToSuccess()
        } else {
            state = .retrying
            stateModel?.transitionTo(.retrying)
            AppLogger.shared.log("❌ [DragToAuthorize] Drop rejected — showing retry")

            let generation = presentationGeneration
            schedule(2.0) { [weak self] in
                guard let self, presentationGeneration == generation, state == .retrying else { return }
                state = .visible
                stateModel?.transitionTo(.visible)
            }
        }
    }

    /// Called by permission polling when the target permission is granted.
    func permissionGrantDetected() {
        guard state == .visible || state == .dragging || state == .retrying else { return }
        transitionToSuccess()
    }

    // MARK: - Private Implementation

    private func createAndShowPanel(
        for target: PermissionTarget,
        subject: PermissionSubject,
        sourceRect: NSRect?,
        sourceWindow: NSWindow?,
        generation: UInt64
    ) {
        let panelWidth: CGFloat = 300
        let panelHeight: CGFloat = 170

        let newPanel = DragToAuthorizePanel(contentRect: NSRect(
            x: 0, y: 0, width: panelWidth, height: panelHeight
        ))

        let model = DragToAuthorizeStateModel(target: target, subject: subject, controller: self)
        stateModel = model

        let overlayView = DragToAuthorizeOverlayView(model: model)
        let hosting = NSHostingView(rootView: overlayView)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hosting.autoresizingMask = [.width, .height]

        // Embed drag source on top of the tile area
        let dragSource = DragToAuthorizeDragSource(fileURL: subject.fileURL, frame: NSRect(
            x: 24, y: 16, width: panelWidth - 48, height: 52
        ))
        dragSource.onDragBegan = { [weak self] in
            self?.dragDidBegin()
        }
        dragSource.onDragEnded = { [weak self] operation in
            self?.dragDidEnd(accepted: operation != [])
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        container.wantsLayer = true
        container.addSubview(hosting)
        container.addSubview(dragSource)

        newPanel.contentView = container

        // Start with panel invisible for animation
        newPanel.alphaValue = 0
        panel = newPanel

        // Start tracking Settings window
        let newTracker = SettingsWindowTracker()
        newTracker.onFrameUpdate = { [weak self, weak newPanel] settingsFrame in
            guard let panel = newPanel else { return }
            let x = settingsFrame.midX - panelWidth / 2
            let y = settingsFrame.minY - panelHeight - 12
            panel.setFrameOrigin(NSPoint(x: x, y: y))

            if !panel.isVisible {
                panel.orderFront(nil)
                self?.animatePresentation(
                    panel: panel, sourceRect: sourceRect, sourceWindow: sourceWindow, generation: generation
                )
            }
        }
        newTracker.onWindowDisappeared = { [weak self] in
            AppLogger.shared.log("⚠️ [DragToAuthorize] Settings window disappeared")
            self?.dismiss(animated: true)
        }
        newTracker.startTracking()
        tracker = newTracker

        startPermissionPolling(for: target, subject: subject, generation: generation)
    }

    private func animatePresentation(
        panel: DragToAuthorizePanel, sourceRect: NSRect?, sourceWindow: NSWindow?, generation: UInt64
    ) {
        if let sourceRect, let sourceWindow {
            // Animate from source rect (wizard button)
            let screenSourceRect = sourceWindow.convertToScreen(sourceRect)
            let finalFrame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: screenSourceRect.midX - finalFrame.width / 2,
                y: screenSourceRect.midY - finalFrame.height / 2
            ))
            panel.alphaValue = 0.3

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
                panel.animator().setFrameOrigin(finalFrame.origin)
                panel.animator().alphaValue = 1.0
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.presentationAnimationDidFinish(generation: generation)
                }
            }
        } else {
            // Simple fade + slide up
            let finalOrigin = panel.frame.origin
            panel.setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y - 20))

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(finalOrigin)
                panel.animator().alphaValue = 1.0
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.presentationAnimationDidFinish(generation: generation)
                }
            }
        }
    }

    /// The panel's entrance animation finished. It applies only while that
    /// presentation is still being presented: a dismissal during the animation
    /// must not bring the overlay back to `.visible`.
    func presentationAnimationDidFinish(generation: UInt64) {
        guard presentationGeneration == generation, state == .presenting else { return }
        state = .visible
        stateModel?.transitionTo(.visible)
    }

    private func transitionToSuccess() {
        state = .success
        stateModel?.transitionTo(.success)
        AppLogger.shared.log("✅ [DragToAuthorize] Permission granted!")

        let generation = presentationGeneration
        schedule(1.8) { [weak self] in
            // A newer presentation replaced this one: leave it alone.
            guard let self, presentationGeneration == generation else { return }
            dismiss(animated: true)
        }
    }

    private func startPermissionPolling(for target: PermissionTarget, subject: PermissionSubject, generation: UInt64) {
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkPermission(for: target, subject: subject, generation: generation)
            }
        }
    }

    private func checkPermission(for target: PermissionTarget, subject: PermissionSubject, generation: UInt64) async {
        let snapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
        permissionPollDidResolve(
            granted: Self.grantResolved(target: target, subject: subject, snapshot: snapshot),
            generation: generation
        )
    }

    /// A permission poll finished. The refresh is asynchronous, so a result can
    /// arrive after its presentation was dismissed or replaced; it then has no effect.
    func permissionPollDidResolve(granted: Bool, generation: UInt64) {
        guard granted, presentationGeneration == generation else { return }
        permissionGrantDetected()
    }

    /// Pure decision: is `subject`'s `target` permission granted in this snapshot?
    /// Extracted so the decision is unit-testable without AppKit
    /// (mirrors the resolver pattern in #931/#937/#939).
    nonisolated static func grantResolved(
        target: PermissionTarget,
        subject: PermissionSubject,
        snapshot: PermissionOracle.Snapshot
    ) -> Bool {
        switch (target, subject) {
        case (.accessibility, .keyPath): snapshot.accessibility == .granted
        }
    }

    private func tearDown() {
        panel?.orderOut(nil)
        panel = nil
        stateModel = nil
        currentTarget = nil
        currentSubject = .keyPath
        state = .idle
    }
}
