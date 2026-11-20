import SwiftUI

// MARK: - Reset Mapping Button

/// Toolbar button that resets current mapping on single click, shows reset all confirmation on double click.
struct ResetMappingButton: View {
    let viewModel: MapperViewModel
    let onDoubleClick: () -> Void

    @State private var pendingClick: Task<Void, Never>?
    private let doubleClickDelay: Duration = .milliseconds(300)

    var body: some View {
        Button {
            // Handle via gesture below for double-click support
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .help("Click: Reset mapping. Double-click: Reset all to defaults")
        .accessibilityIdentifier("mapper-reset-button")
        .accessibilityLabel("Reset mapping")
        .simultaneousGesture(TapGesture().onEnded { handleClick() })
        .onDisappear { cancelPendingClick() }
    }

    private func handleClick() {
        if pendingClick != nil {
            cancelPendingClick()
            onDoubleClick()
            return
        }

        let reset = viewModel.resetActionForCurrentMapping()
        pendingClick = Task {
            try? await Task.sleep(for: doubleClickDelay)
            guard !Task.isCancelled else { return }
            pendingClick = nil
            reset()
        }
    }

    private func cancelPendingClick() {
        pendingClick?.cancel()
        pendingClick = nil
    }
}
