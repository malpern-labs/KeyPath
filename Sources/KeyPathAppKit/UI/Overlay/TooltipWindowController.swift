import AppKit
import SwiftUI

/// A floating tooltip window that appears after hovering over a target.
/// Only one tooltip is visible at a time (managed via shared instance).
@MainActor
final class TooltipWindowController {
    static let shared = TooltipWindowController()

    private var window: NSWindow?
    private var showTask: Task<Void, Never>?
    private var currentTooltipId: String?

    /// Delay before showing tooltip (seconds)
    private let showDelay: TimeInterval = 0.6

    private init() {}

    /// Show hover details beneath the target after the hover delay.
    func show(content: OverlayTooltipContent, id: String, anchor: TooltipAnchor) {
        // Cancel any pending show
        showTask?.cancel()

        // If same tooltip is already showing, do nothing
        if currentTooltipId == id, window != nil {
            return
        }

        // Dismiss any existing tooltip immediately if different
        if currentTooltipId != id {
            dismissImmediately()
        }

        currentTooltipId = id

        showTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(showDelay))
            guard !Task.isCancelled, currentTooltipId == id,
                  let anchorRect = anchor.screenRect
            else { return }
            showWindow(content: content, anchorRect: anchorRect)
        }
    }

    /// Dismiss the tooltip for a specific id
    func dismiss(id: String) {
        guard currentTooltipId == id else { return }
        showTask?.cancel()
        showTask = nil
        dismissWithFade()
    }

    /// Dismiss any visible tooltip immediately
    func dismissImmediately() {
        showTask?.cancel()
        showTask = nil
        currentTooltipId = nil

        guard let window else { return }
        window.orderOut(nil)
        self.window = nil
    }

    private func dismissWithFade() {
        currentTooltipId = nil

        guard let window else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            MainActor.assumeIsolated {
                guard let window else { return }
                window.orderOut(nil)
                if self?.window === window {
                    self?.window = nil
                }
            }
        }
    }

    private func showWindow(content: OverlayTooltipContent, anchorRect: CGRect) {
        let tooltipView = TooltipView(content: content)
        let hostingView = NSHostingView(rootView: tooltipView)

        // Size to fit content
        let fittingSize = hostingView.fittingSize
        hostingView.frame.size = fittingSize

        // Create borderless, transparent window
        let tooltipWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        tooltipWindow.isOpaque = false
        tooltipWindow.backgroundColor = .clear
        tooltipWindow.level = .floating + 1 // Above other floating windows
        tooltipWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        tooltipWindow.hidesOnDeactivate = false
        tooltipWindow.hasShadow = true
        tooltipWindow.ignoresMouseEvents = true
        tooltipWindow.contentView = hostingView

        let gap: CGFloat = 5
        let center = CGPoint(x: anchorRect.midX, y: anchorRect.midY)
        var origin = CGPoint(x: center.x - fittingSize.width / 2, y: anchorRect.minY - gap - fittingSize.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            let visible = screen.visibleFrame.insetBy(dx: 6, dy: 6)
            origin.x = min(max(visible.minX, origin.x), visible.maxX - fittingSize.width)
            if origin.y < visible.minY {
                origin.y = min(anchorRect.maxY + gap, visible.maxY - fittingSize.height)
            }
        }
        tooltipWindow.setFrameOrigin(origin)

        // Fade in
        tooltipWindow.alphaValue = 0
        tooltipWindow.orderFrontRegardless()
        window = tooltipWindow

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            tooltipWindow.animator().alphaValue = 1.0
        }
    }
}

enum OverlayTooltipContent: Equatable {
    case text(String)
    case actions(key: String, layer: String, actions: [KeycapActionLegend])

    var isEmpty: Bool {
        switch self {
        case let .text(text): text.isEmpty
        case let .actions(_, _, actions): actions.isEmpty
        }
    }
}

/// Resolves the hovered view's screen bounds, including the overlay's transforms.
@MainActor
final class TooltipAnchor {
    weak var view: NSView?

    var screenRect: CGRect? {
        guard let view, let window = view.window, window.isVisible else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

private struct TooltipAnchorView: NSViewRepresentable {
    let anchor: TooltipAnchor

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        anchor.view = view
    }
}

/// Displays a card for a hovered overlay control without taking keyboard focus.
private struct WindowTooltip: ViewModifier {
    let tooltip: OverlayTooltipContent
    let id: String

    @State private var anchor = TooltipAnchor()

    func body(content: Content) -> some View {
        content
            .background {
                if !tooltip.isEmpty {
                    TooltipAnchorView(anchor: anchor)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovering in
                if hovering, !tooltip.isEmpty {
                    TooltipWindowController.shared.show(content: tooltip, id: id, anchor: anchor)
                } else {
                    TooltipWindowController.shared.dismiss(id: id)
                }
            }
            .onChange(of: tooltip) { _, _ in TooltipWindowController.shared.dismiss(id: id) }
            .onDisappear { TooltipWindowController.shared.dismiss(id: id) }
    }
}

extension View {
    func windowTooltip(_ tooltip: OverlayTooltipContent, id: String) -> some View {
        modifier(WindowTooltip(tooltip: tooltip, id: id))
    }
}

private struct TooltipView: View {
    let content: OverlayTooltipContent

    private let triggerColor = Color(red: 193 / 255, green: 177 / 255, blue: 1)
    private let layerColor = Color(red: 178 / 255, green: 178 / 255, blue: 190 / 255)

    var body: some View {
        switch content {
        case let .text(text):
            Text(text)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                .fixedSize()
        case let .actions(key, layer, actions):
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(key)
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    Label(LayerInfo.displayName(for: layer), systemImage: LayerInfo.iconName(for: layer))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(layerColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                    ForEach(actions.indices, id: \.self) { index in
                        let legend = actions[index]
                        GridRow {
                            Text(legend.triggerName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(triggerColor)
                                .fixedSize()
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                if let layer = legend.targetLayer {
                                    Image(systemName: LayerInfo.iconName(for: layer))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(triggerColor)
                                        .accessibilityHidden(true)
                                }
                                Text(legend.actionName)
                                    .font(.system(size: 12, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .foregroundStyle(Color(red: 237 / 255, green: 240 / 255, blue: 245 / 255))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 222, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                Color(red: 36 / 255, green: 36 / 255, blue: 38 / 255),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color(red: 94 / 255, green: 86 / 255, blue: 110 / 255), lineWidth: 0.5)
            )
        }
    }
}
