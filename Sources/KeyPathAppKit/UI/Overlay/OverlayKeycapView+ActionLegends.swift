import AppKit
import KeyPathRulesCore
import SwiftUI

extension OverlayKeycapView {
    var showsActionLegends: Bool {
        guard !isLauncherMode, key.layoutRole != .touchId,
              !useFloatingLabels, customIcon == nil,
              !(isPressed && isHoldActive && holdLabel != nil),
              (layerKeyInfo?.actionLegends.count ?? 0) > 1,
              !services.preferences.overlayHidesActionLegends
        else { return false }

        switch colorway.legendStyle {
        case .blank, .dots:
            return false
        case .iconMods:
            return key.layoutRole != .bottomAligned && key.layoutRole != .narrowModifier
        case .standard:
            return true
        }
    }

    var actionLegendsForDetails: [KeycapActionLegend] {
        guard !isLauncherMode, key.layoutRole != .touchId,
              let legends = layerKeyInfo?.actionLegends, isInspectorVisible || legends.count > 1
        else { return [] }
        return legends
    }

    var hoverActionLegends: [KeycapActionLegend] {
        fadeAmount == 0 ? actionLegendsForDetails : []
    }

    /// Keep compact keys readable by removing secondary glyphs before shrinking their text.
    static func actionLegendCapacity(width: CGFloat, height: CGFloat) -> Int {
        switch min(width, height) {
        case ..<24: 1
        case ..<28: 2
        case ..<32: 3
        default: KeycapActionLegend.visibleLimit
        }
    }

    var actionLegendContent: some View {
        let legends = (layerKeyInfo?.actionLegends ?? []).prefix(actionLegendCapacity)
        let hold = legends.first(where: { $0.trigger == .hold })
        let repeatLegends = legends.filter {
            if case .repeatedTap = $0.trigger { return true }
            return false
        }

        let tapVerticalOffset: CGFloat = if hold != nil {
            repeatLegends.isEmpty ? 3 : 0
        } else {
            repeatLegends.isEmpty ? 0 : -4
        }

        return ZStack {
            if let tap = legends.first {
                let identityLabel = tapIdentityLabel(tap)
                legend(tap, size: 13, color: foregroundColor, labelOverride: identityLabel)
                    .padding(.horizontal, 4 * scale)
                    .offset(
                        x: hold == nil ? 0 : -3 * scale,
                        y: tapVerticalOffset * scale
                    )
            }
            if let hold {
                legend(hold, size: 9, color: secondaryLegendColor)
                    .padding(3 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            if !repeatLegends.isEmpty {
                HStack(spacing: 0) {
                    ForEach(repeatLegends.indices, id: \.self) { index in
                        legend(repeatLegends[index], size: 9, color: secondaryLegendColor)
                            .frame(maxWidth: .infinity, alignment: repeatAlignment(index, count: repeatLegends.count))
                    }
                }
                .padding(.horizontal, 3 * scale)
                .padding(.bottom, 2 * scale)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private func tapIdentityLabel(_ legend: KeycapActionLegend) -> String? {
        guard !isLayerMode, !baseLabel.isEmpty,
              case let .keystroke(output) = legend.action,
              KanataKeyConverter.convertToKanataKey(output) == KanataKeyConverter.convertToKanataKey(inputKeyName)
        else { return nil }
        return baseLabel.count == 1 ? baseLabel.uppercased() : baseLabel
    }

    private func repeatAlignment(_ index: Int, count: Int) -> Alignment {
        if index == 0 { return .leading }
        if index == count - 1 { return .trailing }
        return .center
    }

    private var secondaryLegendColor: Color {
        // Follow the keycap palette, including light GMK themes used in a dark overlay.
        let background = NSColor(backgroundColor).usingColorSpace(.deviceRGB)
        let luminance = background.map {
            0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent
        } ?? (isDarkMode ? 0 : 1)
        return luminance < 0.5
            ? Color(red: 170 / 255, green: 152 / 255, blue: 1)
            : Color(red: 88 / 255, green: 54 / 255, blue: 171 / 255)
    }

    private func legend(
        _ legend: KeycapActionLegend,
        size: CGFloat,
        color: Color,
        labelOverride: String? = nil
    ) -> some View {
        let triggerIsTap = legend.trigger == .tap
        let fontSize = max(triggerIsTap ? 10 : 8, size * scale)
        return Group {
            if labelOverride == nil, let symbol = legend.symbol {
                Image(systemName: symbol)
            } else {
                Text(labelOverride ?? legend.glyph)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .font(.system(size: fontSize, weight: triggerIsTap ? .semibold : .medium))
        .foregroundStyle(color)
    }
}
