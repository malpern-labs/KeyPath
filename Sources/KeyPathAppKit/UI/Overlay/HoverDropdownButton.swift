import AppKit
import SwiftUI

struct HoverDropdownButton: View {
    let text: String
    var sfSymbol: String?
    var icon: (name: String, image: NSImage?)?
    var accessibilityIdentifier: String = "hover-dropdown-button"
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon, let nsImage = icon.image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 12, height: 12)
                } else if let icon, !icon.name.isEmpty {
                    Image(systemName: icon.name)
                        .font(.system(size: 10))
                } else if let sfSymbol {
                    Image(systemName: sfSymbol)
                        .font(.system(size: 10))
                }
                // Labels sit under a keycap-width column. Shrink a little before
                // truncating, so longer translations ("キーストローク") stay readable.
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(isHovering ? 1 : 0.4)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .onHover { isHovering = $0 }
    }
}
