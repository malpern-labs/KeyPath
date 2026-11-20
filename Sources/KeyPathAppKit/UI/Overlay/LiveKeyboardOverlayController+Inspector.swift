import AppKit
import KeyPathCore
import SwiftUI

extension LiveKeyboardOverlayController {
    // MARK: - Inspector Panel

    func openInspector(animated: Bool) {
        guard let window else { return }
        // Opening the editor is an explicit interaction. The passive overlay
        // can stay in front without taking keyboard focus from another app.
        NSApp.activate()
        window.makeKey()
        let token = UUID()
        inspectorAnimationToken = token
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let baseFrame = window.frame
        collapsedFrameBeforeInspector = baseFrame

        let maxVisibleX = window.screen?.visibleFrame.maxX
        let expandedFrame = InspectorPanelLayout.expandedFrame(
            baseFrame: baseFrame,
            inspectorWidth: inspectorTotalWidth,
            maxVisibleX: maxVisibleX
        )

        if inspectorDebugEnabled {
            AppLogger.shared.log(
                "📤 [OverlayInspector] open start frame=\(baseFrame.debugDescription) " +
                    "expanded=\(expandedFrame.debugDescription) totalW=\(inspectorTotalWidth.rounded())"
            )
        }

        uiState.isInspectorClosing = false
        uiState.isInspectorAnimating = shouldAnimate

        if shouldAnimate {
            animateInspectorReveal(to: 1)
            setWindowFrame(expandedFrame, animated: true, duration: inspectorAnimationDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + inspectorAnimationDuration) { [weak self] in
                guard let self, inspectorAnimationToken == token else { return }
                finalizeInspectorAnimation()
                uiState.isInspectorOpen = true
                uiState.inspectorReveal = 1
                lastWindowFrame = expandedFrame
                if inspectorDebugEnabled {
                    AppLogger.shared.log(
                        "📤 [OverlayInspector] open end frame=\(expandedFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                    )
                }
            }
        } else {
            finalizeInspectorAnimation()
            uiState.inspectorReveal = 1
            setWindowFrame(expandedFrame, animated: false)
            uiState.isInspectorOpen = true
            uiState.isInspectorAnimating = false
            lastWindowFrame = expandedFrame
            if inspectorDebugEnabled {
                AppLogger.shared.log(
                    "📤 [OverlayInspector] open instant frame=\(expandedFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                )
            }
        }
    }

    func closeInspector(animated: Bool) {
        guard let window else { return }
        guard uiState.isInspectorOpen || uiState.inspectorReveal > 0 || uiState.isInspectorAnimating else {
            uiState.isInspectorClosing = false
            return
        }
        let targetFrame = collapsedFrameBeforeInspector ?? InspectorPanelLayout.collapsedFrame(
            expandedFrame: window.frame,
            inspectorWidth: inspectorTotalWidth
        )
        let token = UUID()
        inspectorAnimationToken = token
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if inspectorDebugEnabled {
            AppLogger.shared.log(
                "📥 [OverlayInspector] close start frame=\(window.frame.debugDescription) " +
                    "target=\(targetFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
            )
        }

        uiState.isInspectorAnimating = shouldAnimate
        uiState.isInspectorClosing = shouldAnimate

        if shouldAnimate {
            animateInspectorReveal(to: 0)
            setWindowFrame(targetFrame, animated: true, duration: inspectorAnimationDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + inspectorAnimationDuration) { [weak self] in
                guard let self, inspectorAnimationToken == token else { return }
                finalizeInspectorAnimation()
                uiState.inspectorReveal = 0
                uiState.isInspectorOpen = false
                uiState.isInspectorClosing = false
                collapsedFrameBeforeInspector = nil
                lastWindowFrame = targetFrame
                if inspectorDebugEnabled {
                    AppLogger.shared.log(
                        "📥 [OverlayInspector] close end frame=\(targetFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                    )
                }
            }
        } else {
            finalizeInspectorAnimation()
            setWindowFrame(targetFrame, animated: false)
            uiState.inspectorReveal = 0
            uiState.isInspectorOpen = false
            uiState.isInspectorAnimating = false
            uiState.isInspectorClosing = false
            collapsedFrameBeforeInspector = nil
            lastWindowFrame = targetFrame
            if inspectorDebugEnabled {
                AppLogger.shared.log(
                    "📥 [OverlayInspector] close instant frame=\(targetFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                )
            }
        }
    }

    /// Animate inspector reveal from current value to target (0 or 1)
    func animateInspectorReveal(to targetReveal: CGFloat) {
        let token = inspectorAnimationToken
        let startTime = CACurrentMediaTime()
        let startReveal = uiState.inspectorReveal
        inspectorAnimationTimer?.invalidate()
        inspectorAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            // This timer is scheduled on the main run loop. Its work must not
            // survive invalidation when a new reveal replaces the old one.
            MainActor.assumeIsolated {
                guard inspectorAnimationToken == token, inspectorAnimationTimer != nil else { return }
                let elapsed = CACurrentMediaTime() - startTime
                let progress = min(1.0, elapsed / inspectorAnimationDuration)
                uiState.inspectorReveal = OverlayInspectorMath.revealValue(
                    start: startReveal,
                    target: targetReveal,
                    elapsed: elapsed,
                    duration: inspectorAnimationDuration
                )

                if progress >= 1.0 {
                    inspectorAnimationTimer?.invalidate()
                    inspectorAnimationTimer = nil
                }
            }
        }
    }

    /// Clean up animation state after completion
    func finalizeInspectorAnimation() {
        inspectorAnimationTimer?.invalidate()
        inspectorAnimationTimer = nil
        uiState.isInspectorAnimating = false
    }

    func handleWindowFrameChange() {
        guard let window else { return }
        if uiState.isInspectorOpen, !uiState.isInspectorClosing {
            updateCollapsedFrame(forExpandedFrame: window.frame)
        }
        if uiState.isInspectorAnimating {
            updateInspectorRevealFromWindow()
            if inspectorDebugEnabled {
                let now = CFAbsoluteTimeGetCurrent()
                if now - inspectorDebugLastLog > 0.2 {
                    inspectorDebugLastLog = now
                    let revealStr = String(format: "%.3f", uiState.inspectorReveal)
                    AppLogger.shared.log(
                        "🪟 [OverlayInspector] frame=\(window.frame.debugDescription) " +
                            "reveal=\(revealStr) " +
                            "animating=\(uiState.isInspectorAnimating) closing=\(uiState.isInspectorClosing)"
                    )
                }
            }
            return
        }
        saveWindowFrame()
        lastWindowFrame = window.frame
    }

    func updateInspectorRevealFromWindow() {
        guard let window else { return }
        let collapsedWidth = collapsedFrameBeforeInspector?.width ?? max(0, window.frame.width - inspectorTotalWidth)
        uiState.inspectorReveal = OverlayInspectorMath.clampedReveal(
            expandedWidth: window.frame.width,
            collapsedWidth: collapsedWidth,
            inspectorWidth: inspectorTotalWidth
        )
    }

    func updateCollapsedFrame(forExpandedFrame expandedFrame: NSRect) {
        var baseFrame = collapsedFrameBeforeInspector ?? expandedFrame
        if let lastFrame = lastWindowFrame {
            let deltaX = expandedFrame.origin.x - lastFrame.origin.x
            let deltaY = expandedFrame.origin.y - lastFrame.origin.y
            baseFrame.origin.x += deltaX
            baseFrame.origin.y += deltaY
        } else {
            baseFrame.origin = expandedFrame.origin
        }
        baseFrame.size.width = max(0, expandedFrame.width - inspectorTotalWidth)
        baseFrame.size.height = expandedFrame.height
        collapsedFrameBeforeInspector = baseFrame
    }

    func setWindowFrame(_ frame: NSRect, animated: Bool, duration: TimeInterval? = nil) {
        guard let window else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration ?? inspectorAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }

    func observeDesiredContentHeight() {
        Task { @MainActor [weak self] in
            var lastHeight: CGFloat?
            while let self {
                let height = uiState.desiredContentHeight
                if height != lastHeight {
                    lastHeight = height
                    if !isUserResizing {
                        applyDesiredContentHeight(height)
                    }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func observeDesiredContentWidth() {
        Task { @MainActor [weak self] in
            var lastWidth: CGFloat?
            while let self {
                let width = uiState.desiredContentWidth
                if width != lastWidth {
                    lastWidth = width
                    if !isUserResizing {
                        applyDesiredContentWidth(width)
                    }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Give the health indicator priority, then show the hint above the same overlay.
    func showHintBubbleAfterHealthIndicator(
        wait: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        hintBubbleObserver?.cancel()
        guard let window else {
            hintBubbleObserver = nil
            return
        }

        hintBubbleObserver = Task { @MainActor [weak self, weak window] in
            do {
                while !Task.isCancelled, let state = self?.uiState.healthIndicatorState,
                      let window, self?.window === window, window.isVisible
                {
                    if state == .dismissed || state == .healthy {
                        try await wait(.milliseconds(500))
                        guard !Task.isCancelled, let self, self.window === window, window.isVisible else { return }
                        hintBubbleObserver = nil
                        if hintWindowController == nil {
                            hintWindowController = HideHintWindowController()
                        }
                        hintWindowController?.show(above: window)
                        return
                    }
                    try await wait(.milliseconds(50))
                }
            } catch {
                // A dismissal cancels both the health wait and the presentation delay.
                return
            }
        }
    }

    /// Dismiss the hide hint bubble if visible
    func dismissHintBubble() {
        hintBubbleObserver?.cancel()
        hintBubbleObserver = nil
        hintWindowController?.dismiss()
    }

    func observeKeyboardAspectRatio() {
        Task { @MainActor [weak self] in
            var lastRatio: CGFloat?
            while let self {
                let ratio = uiState.keyboardAspectRatio
                if ratio != lastRatio {
                    lastRatio = ratio
                    if !isUserResizing {
                        resizeWindowForNewAspectRatio(ratio)
                    }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func resizeWindowForNewAspectRatio(_ newAspectRatio: CGFloat) {
        guard let window else { return }
        guard !isAdjustingHeight, !isAdjustingWidth else { return }

        // Include title bar height so frame→keyboard conversion is correct for titled windows
        let verticalChrome = OverlayLayoutMetrics.verticalChrome + windowTitleBarHeight
        let currentFrame = window.frame

        // Calculate new keyboard width based on new aspect ratio
        // Calculate horizontal chrome (padding + inspector if open)
        let horizontalChrome = OverlayLayoutMetrics.horizontalChrome(
            inspectorVisible: uiState.isInspectorOpen,
            inspectorWidth: inspectorPanelWidth
        )

        let newWindowWidth = OverlayWindowResizer.widthForAspect(
            currentHeight: currentFrame.height,
            aspect: newAspectRatio,
            verticalChrome: verticalChrome,
            horizontalChrome: horizontalChrome
        )

        // Only resize if there's a meaningful difference
        guard abs(currentFrame.width - newWindowWidth) > 1.0 else { return }

        isAdjustingWidth = true
        var newFrame = currentFrame
        newFrame.size.width = newWindowWidth

        // Keep right edge anchored (window moves left as it shrinks, right as it grows)
        newFrame.origin.x = currentFrame.maxX - newWindowWidth

        let constrained = window.constrainFrameRect(newFrame, to: window.screen)
        window.setFrame(constrained, display: true, animate: true)

        isAdjustingWidth = false
    }

    func applyDesiredContentHeight(_ height: CGFloat) {
        guard let window else { return }
        guard height > 0 else { return }
        guard !isAdjustingHeight else { return }

        // desiredContentHeight is content-based; for titled windows, add title bar for frame height
        let frameHeight = height + windowTitleBarHeight
        let currentFrame = window.frame
        if abs(currentFrame.height - frameHeight) < 0.5 {
            return
        }

        isAdjustingHeight = true
        var newFrame = currentFrame
        newFrame.size.height = frameHeight
        newFrame.origin.y = currentFrame.maxY - frameHeight
        let constrained = window.constrainFrameRect(newFrame, to: window.screen)
        window.setFrame(constrained, display: true, animate: false)
        isAdjustingHeight = false
    }

    func applyDesiredContentWidth(_ width: CGFloat) {
        guard let window else { return }
        guard width > 0 else { return }
        guard !isAdjustingWidth else { return }
        guard uiState.isInspectorOpen else { return } // Only resize when inspector is open

        let currentFrame = window.frame
        if abs(currentFrame.width - width) < 0.5 {
            return
        }

        isAdjustingWidth = true
        var newFrame = currentFrame
        newFrame.size.width = width
        // Keep right edge anchored (inspector stays in place)
        newFrame.origin.x = currentFrame.maxX - width
        let constrained = window.constrainFrameRect(newFrame, to: window.screen)
        window.setFrame(constrained, display: true, animate: true)
        // Update collapsed frame reference to maintain correct keyboard width
        updateCollapsedFrame(forExpandedFrame: constrained)
        isAdjustingWidth = false
    }

    func resolveResizeAnchor(widthDelta: CGFloat, heightDelta: CGFloat) -> OverlayResizeAnchor {
        let threshold: CGFloat = 6
        let currentMouse = NSEvent.mouseLocation
        let resolved = OverlayWindowResizer.resolveAnchor(
            existing: resizeAnchor,
            startFrame: resizeStartFrame,
            currentFrame: window?.frame,
            startMouse: resizeStartMouse,
            currentMouse: currentMouse,
            widthDelta: widthDelta,
            heightDelta: heightDelta,
            threshold: threshold
        )
        resizeAnchor = resolved
        return resolved
    }
}
