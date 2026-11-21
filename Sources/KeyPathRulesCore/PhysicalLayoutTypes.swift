import Foundation

// MARK: - Layout Preferences Keys

/// UserDefaults/AppStorage keys for physical layout preferences
package enum LayoutPreferences {
    /// Key for storing the selected physical keyboard layout ID
    package static let layoutIdKey = "overlayLayoutId"

    /// Default layout ID when none is set
    package static let defaultLayoutId = "macbook-us"

    /// Key for enabling QMK keyboard search (default: true)
    package static let qmkSearchEnabledKey = "qmkSearchEnabled"
    /// Default value for QMK search enabled flag
    package static let qmkSearchEnabledDefault = true
}

// MARK: - Layout Categories

/// Categories for organizing physical keyboard layouts in the UI
package enum LayoutCategory: String, CaseIterable, Identifiable {
    case usStandard = "US Standard"
    case international = "International"
    case ergonomic = "Ergonomic / Split"
    case custom = "Custom"

    package var id: String {
        rawValue
    }

    package var displayName: String {
        switch self {
        case .usStandard: String(localized: "US Standard")
        case .international: String(localized: "International")
        case .ergonomic: String(localized: "Ergonomic / Split")
        case .custom: String(localized: "Custom")
        }
    }
}

/// Represents a single physical key on a keyboard layout
package struct PhysicalKey: Identifiable, Hashable, Sendable {
    /// Sentinel keyCode for keys with no macOS equivalent (layer switches, transparent, macros).
    /// Uses 0xFFFF which is outside the valid macOS virtual keyCode range (0x00–0x7F).
    package static let unmappedKeyCode: UInt16 = 0xFFFF

    /// Base for placeholder keyCodes assigned to unrecognized keys during QMK import.
    /// Uses 0xF000+ to avoid collision with real macOS keyCodes (0x00–0x7F range).
    /// Range 0xF000–0xFFFE supports up to 4094 placeholder keys per layout.
    package static let placeholderKeyCodeBase: UInt16 = 0xF000

    /// Safe placeholder keyCode for a given index, clamped to avoid overflow past unmappedKeyCode.
    package static func placeholderKeyCode(for index: Int) -> UInt16 {
        let clamped = UInt16(clamping: min(max(0, index), 0xFFE))
        return placeholderKeyCodeBase + clamped
    }

    package let id: UUID
    package let keyCode: UInt16 // CGEvent key code (matches KeyboardCapture)
    package let label: String // Display label ("A", "Shift", "⌘", "🔅")
    package let x: Double // In keyboard units (0-based)
    package let y: Double
    package let width: Double // 1.0 = standard key
    package let height: Double
    package let rotation: Double // Rotation in degrees (for ergonomic keyboards)
    package let rotationPivotX: Double? // Rotation pivot X (for QMK rotation)
    package let rotationPivotY: Double? // Rotation pivot Y (for QMK rotation)

    // MARK: - Multi-Legend Support (JIS/ISO)

    /// Shifted character legend (top position on keycap)
    /// Example: "!" for the "1" key, "@" for "2", etc.
    package let shiftLabel: String?

    /// Sub-label for alternate input (front/bottom-right on keycap)
    /// Example: Hiragana characters on JIS keyboards ("ぬ" on "1" key)
    package let subLabel: String?

    /// Tertiary label for additional legends (front/bottom-left on keycap)
    /// Example: Additional symbols or alternate character sets
    package let tertiaryLabel: String?

    /// Whether this key has multi-legend content requiring special rendering
    package var hasMultipleLegends: Bool {
        shiftLabel != nil || subLabel != nil || tertiaryLabel != nil
    }

    package init(
        id: UUID = UUID(),
        keyCode: UInt16,
        label: String,
        x: Double,
        y: Double,
        width: Double = 1.0,
        height: Double = 1.0,
        rotation: Double = 0.0,
        rotationPivotX: Double? = nil,
        rotationPivotY: Double? = nil,
        shiftLabel: String? = nil,
        subLabel: String? = nil,
        tertiaryLabel: String? = nil
    ) {
        self.id = id
        self.keyCode = keyCode
        self.label = label
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.rotationPivotX = rotationPivotX
        self.rotationPivotY = rotationPivotY
        self.shiftLabel = shiftLabel
        self.subLabel = subLabel
        self.tertiaryLabel = tertiaryLabel
    }

    /// Computed visual position after applying rotation transform
    /// For keys with rotation, the x/y in QMK format are pre-rotation coordinates
    /// that need to be rotated around the pivot point (rx, ry)
    package var visualX: Double {
        guard rotation != 0, let rx = rotationPivotX, let ry = rotationPivotY else {
            return x
        }
        // Translate to pivot origin, rotate, translate back
        let relX = x + width / 2 - rx // Use key center
        let relY = y + height / 2 - ry
        let radians = rotation * .pi / 180
        let rotatedX = relX * cos(radians) - relY * sin(radians)
        return rotatedX + rx - width / 2
    }

    package var visualY: Double {
        guard rotation != 0, let rx = rotationPivotX, let ry = rotationPivotY else {
            return y
        }
        // Translate to pivot origin, rotate, translate back
        let relX = x + width / 2 - rx // Use key center
        let relY = y + height / 2 - ry
        let radians = rotation * .pi / 180
        let rotatedY = relX * sin(radians) + relY * cos(radians)
        return rotatedY + ry - height / 2
    }
}
