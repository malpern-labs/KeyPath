import AppKit
import SwiftUI

extension OverlayMapperSection {
    // MARK: - Launch Apps Expanded Content

    /// Content shown when Launch Apps section is expanded
    var launchAppsExpandedContent: some View {
        let query = viewModel.launchAppSearchText.trimmingCharacters(in: .whitespaces)
        let filteredApps = query.isEmpty
            ? knownApps
            : knownApps.filter { $0.name.localizedCaseInsensitiveContains(query) }

        return VStack(spacing: 0) {
            // Search / filter field
            launchAppSearchField

            // List of known apps (filtered)
            if knownApps.isEmpty {
                HStack {
                    Text("No apps configured yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else if filteredApps.isEmpty {
                HStack {
                    Text("No apps match “\(query)”")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                ForEach(filteredApps, id: \.name) { app in
                    knownAppRow(app)
                }
            }

            // "Add App..." option
            Button {
                pickAppForOutput()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.body)
                        .frame(width: 20)
                    Text("Add App...")
                        .font(.body)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerItemButtonStyle())
            .focusable(false)
            .accessibilityIdentifier("overlay-add-app-button")
        }
    }

    /// Search box that filters the known-apps list by name.
    private var launchAppSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            AutoFocusTextField(text: $viewModel.launchAppSearchText)
                .frame(height: 18)
                .accessibilityLabel("Search apps")
                .accessibilityIdentifier("overlay-launch-app-search")
            if !viewModel.launchAppSearchText.isEmpty {
                Button {
                    viewModel.launchAppSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityIdentifier("overlay-launch-app-search-clear")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// Button for a known app in the list
    private func knownAppRow(_ app: AppLaunchInfo) -> some View {
        let isSelected = viewModel.selectedApp?.bundleIdentifier == app.bundleIdentifier
        let appIdentifier = (app.bundleIdentifier ?? app.name)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return Button {
            selectKnownOutputApp(app)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(app.name)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
        .accessibilityIdentifier("overlay-known-app-\(appIdentifier)")
    }

    func selectKnownOutputApp(_ app: AppLaunchInfo) {
        viewModel.selectOutputApp(app)
        isSystemActionPickerOpen = false
    }

    func loadKnownApps() {
        Task {
            knownApps = await AppLaunchInfo.knownApps(in: services.appKeymapStore)
        }
    }
}
