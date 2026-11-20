import AppKit
import KeyPathRulesCore
import SwiftUI

/// Shared search and keyboard navigation for the Mapper and chord output controls.
struct OutputActionSearch<Browse: View>: View {
    var apps: [AppLaunchInfo] = []
    let onSelect: (KeyAction) -> Void
    let onDismiss: () -> Void
    @ViewBuilder let browse: () -> Browse

    @State private var query = ""
    @State private var highlightedIndex = 0

    private struct Result: Identifiable {
        let id: String
        let title: String
        let icon: String
        let action: KeyAction
    }

    private var searchQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var keys: [Result] {
        KeystrokePresetGridView.presets.map { key, label, icon in
            let title = switch key {
            case "esc": String(localized: "Escape")
            case "left": String(localized: "Left Arrow")
            case "right": String(localized: "Right Arrow")
            case "up": String(localized: "Up Arrow")
            case "down": String(localized: "Down Arrow")
            default: label
            }
            return Result(id: "key-\(key)", title: title, icon: icon, action: .keystroke(key: key))
        }
    }

    private var results: [Result] {
        let systemActions = SystemActionInfo.allActions.filter(\.isSupportedInDriverlessSession).map {
            Result(id: "system-\($0.id)", title: $0.name, icon: $0.sfSymbol, action: .systemAction(id: $0.id))
        }
        let appActions = apps.map {
            Result(
                id: "app-\($0.bundleIdentifier ?? $0.name)",
                title: $0.name,
                icon: "app",
                action: .launchApp(name: $0.name, bundleId: $0.bundleIdentifier)
            )
        }
        return (keys + systemActions + appActions).filter { result in
            result.title.localizedStandardContains(searchQuery)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                AutoFocusTextField(
                    text: $query,
                    placeholder: String(localized: "Search actions"),
                    onCommand: handleSearchCommand
                )
                .frame(height: 20)
                .accessibilityLabel("Search actions")
                .accessibilityIdentifier("output-action-search")
            }
            .padding(6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .onChange(of: query) { _, _ in highlightedIndex = 0 }

            if searchQuery.isEmpty {
                browse()
            } else {
                searchResults
            }
        }
        .onExitCommand(perform: onDismiss)
    }

    private var searchResults: some View {
        let matches = results
        return ScrollViewReader { proxy in
            ScrollView {
                if matches.isEmpty {
                    Text("No matching actions")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, result in
                    Button {
                        onSelect(result.action)
                    } label: {
                        Label(result.title, systemImage: result.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                index == highlightedIndex ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("output-action-\(result.id)")
                    .id(result.id)
                }
            }
            .onChange(of: highlightedIndex) { _, index in
                if matches.indices.contains(index) {
                    proxy.scrollTo(matches[index].id)
                }
            }
        }
    }

    private func handleSearchCommand(_ selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            onDismiss()
            return true
        }
        guard !searchQuery.isEmpty else { return false }
        let matches = results
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            if highlightedIndex + 1 < matches.count { highlightedIndex += 1 }
        case #selector(NSResponder.moveUp(_:)):
            if highlightedIndex > 0 { highlightedIndex -= 1 }
        case #selector(NSResponder.insertNewline(_:)):
            if matches.indices.contains(highlightedIndex) {
                onSelect(matches[highlightedIndex].action)
            }
        default:
            return false
        }
        return true
    }
}
