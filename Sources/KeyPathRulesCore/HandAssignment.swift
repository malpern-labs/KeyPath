import Foundation

/// Assigns keyboard keys to left/right hands for opposite-hand activation in HRM.
///
/// Used to generate Kanata `defhands` blocks. The assignment is position-based
/// (first 5 columns = left, last 5 = right), so it works for any logical keymap
/// (QWERTY, Dvorak, Colemak, etc.) without change.
package struct HandAssignment: Equatable, Sendable {
    /// QWERTY scancode names for left-hand keys (3 rows × 5 columns)
    package let leftKeys: [String]

    /// QWERTY scancode names for right-hand keys (3 rows × 5 columns)
    package let rightKeys: [String]

    package init(leftKeys: [String], rightKeys: [String]) {
        self.leftKeys = leftKeys
        self.rightKeys = rightKeys
    }

    /// Default QWERTY hand assignment (standard 5/5 column split)
    package static let qwertyDefault = HandAssignment(
        leftKeys: [
            "q", "w", "e", "r", "t",
            "a", "s", "d", "f", "g",
            "z", "x", "c", "v", "b"
        ],
        rightKeys: [
            "y", "u", "i", "o", "p",
            "h", "j", "k", "l", ";",
            "n", "m", ",", ".", "/"
        ]
    )
}
