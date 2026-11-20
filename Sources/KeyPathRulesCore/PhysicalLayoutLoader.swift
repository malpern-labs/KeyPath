import Foundation
import KeyPathCore

// MARK: - Native Layout JSON Format

/// Codable representation of a physical key for JSON serialization.
/// This is the "native" format used by MacBook and other layouts that store
/// pre-computed key geometry directly (as opposed to the QMK format which
/// requires a keyMapping function to resolve keyCodes and labels).
package struct PhysicalKeyDTO: Codable {
    package let keyCode: UInt16
    package let label: String
    package let x: Double
    package let y: Double
    package let width: Double
    package let height: Double
    package let rotation: Double?
    package let rotationPivotX: Double?
    package let rotationPivotY: Double?
    package let shiftLabel: String?
    package let subLabel: String?
    package let tertiaryLabel: String?

    package func toPhysicalKey() -> PhysicalKey {
        PhysicalKey(
            keyCode: keyCode,
            label: label,
            x: x,
            y: y,
            width: width,
            height: height,
            rotation: rotation ?? 0.0,
            rotationPivotX: rotationPivotX,
            rotationPivotY: rotationPivotY,
            shiftLabel: shiftLabel,
            subLabel: subLabel,
            tertiaryLabel: tertiaryLabel
        )
    }
}

/// Codable representation of a complete physical layout for JSON serialization.
package struct PhysicalLayoutDTO: Codable {
    package let id: String
    package let name: String
    package let keys: [PhysicalKeyDTO]
    package let totalWidth: Double?
    package let totalHeight: Double?

    package func toPhysicalLayout() -> PhysicalLayout {
        let physicalKeys = keys.map { $0.toPhysicalKey() }
        if let totalWidth, let totalHeight {
            return PhysicalLayout(
                id: id,
                name: name,
                keys: physicalKeys,
                totalWidth: totalWidth,
                totalHeight: totalHeight
            )
        }
        return PhysicalLayout(
            id: id,
            name: name,
            keys: physicalKeys
        )
    }
}

// MARK: - Loader

/// Loads physical keyboard layouts from native JSON files bundled in the app.
///
/// Native JSON files contain pre-computed key geometry with keyCodes and labels
/// already resolved. This is used for MacBook layouts and other layouts that
/// don't use QMK keyMapping functions.
package enum PhysicalLayoutLoader {
    private static let resourceBundle = KeyPathResourceBundle.resolve(
        named: "KeyPath_KeyPathRulesCore.bundle",
        mainBundle: .main,
        codeBundle: Bundle(for: KeyboardLayoutBundleSentinel.self)
    )

    static func bundledJSON(named filename: String) -> URL? {
        resourceBundle.url(forResource: filename, withExtension: "json", subdirectory: "Keyboards")
    }

    /// Load a native-format layout JSON from the app bundle.
    ///
    /// - Parameters:
    ///   - filename: The JSON filename without extension (e.g., "macbook-us")
    ///   - idOverride: Optional override for the layout ID
    ///   - nameOverride: Optional override for the layout display name
    /// - Returns: A `PhysicalLayout` if loading succeeds, nil otherwise
    package static func loadFromBundle(
        filename: String,
        idOverride: String? = nil,
        nameOverride: String? = nil
    ) -> PhysicalLayout? {
        guard let url = bundledJSON(named: filename) else {
            #if DEBUG
                print("PhysicalLayoutLoader: Could not find \(filename).json in bundle")
            #endif
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            #if DEBUG
                print("PhysicalLayoutLoader: Could not read data from \(filename).json")
            #endif
            return nil
        }
        return load(from: data, idOverride: idOverride, nameOverride: nameOverride)
    }

    /// Parse a native-format layout from JSON data.
    ///
    /// - Parameters:
    ///   - data: The JSON data
    ///   - idOverride: Optional override for the layout ID
    ///   - nameOverride: Optional override for the layout display name
    /// - Returns: A `PhysicalLayout` if parsing succeeds, nil otherwise
    package static func load(
        from data: Data,
        idOverride: String? = nil,
        nameOverride: String? = nil
    ) -> PhysicalLayout? {
        guard let dto = try? JSONDecoder().decode(PhysicalLayoutDTO.self, from: data) else {
            #if DEBUG
                print("PhysicalLayoutLoader: Failed to decode layout JSON")
            #endif
            return nil
        }
        var layout = dto.toPhysicalLayout()
        if let idOverride {
            layout = PhysicalLayout(
                id: idOverride,
                name: nameOverride ?? layout.name,
                keys: layout.keys,
                totalWidth: layout.totalWidth,
                totalHeight: layout.totalHeight
            )
        } else if let nameOverride {
            layout = PhysicalLayout(
                id: layout.id,
                name: nameOverride,
                keys: layout.keys,
                totalWidth: layout.totalWidth,
                totalHeight: layout.totalHeight
            )
        }
        return layout
    }
}

private final class KeyboardLayoutBundleSentinel {}
