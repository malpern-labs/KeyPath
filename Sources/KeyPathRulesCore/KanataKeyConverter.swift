import Foundation
import KeyPathCore

// MARK: - Key Conversion Utilities

/// Utility class for converting keys between KeyPath and Kanata formats
public enum KanataKeyConverter {
    /// Convert KeyPath key to Kanata key format for use inside macros
    /// Inside macros, chord syntax like M-right requires UPPERCASE modifier prefixes
    /// This method preserves the case of modifier prefixes (M-, A-, C-, S-)
    public static func convertToKanataKeyForMacro(_ input: String) -> String {
        // Known modifier prefixes that must remain uppercase in macro context
        // Order matters - check longer prefixes first
        let modifierPrefixes = ["M-S-", "C-S-", "A-S-", "M-", "A-", "C-", "S-"]
        let uppercasedInput = input.uppercased()

        for prefix in modifierPrefixes {
            if uppercasedInput.hasPrefix(prefix) {
                // Preserve canonical uppercase prefix, convert base key
                let baseKey = String(input.dropFirst(prefix.count))
                let convertedBase = convertToKanataKey(baseKey)
                return prefix + convertedBase
            }
        }

        // No modifier prefix - use standard conversion
        return convertToKanataKey(input)
    }

    /// Convert KeyPath input key to Kanata key format
    public static func convertToKanataKey(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        // Action keywords used throughout rule collections and behavior rendering.
        // Keep these as-is so they don't fall through to unknown-key warnings.
        if lowercased == "hyper" || lowercased == "meh" {
            return lowercased
        }

        // Canonicalize modified keys (e.g. M-right, A-bspc) to a stable uppercase prefix.
        // This prevents false "unknown key" warnings for valid modified actions.
        let modifierPrefixes = ["M-S-", "C-S-", "A-S-", "M-", "A-", "C-", "S-"]
        let uppercasedInput = trimmed.uppercased()
        for prefix in modifierPrefixes where uppercasedInput.hasPrefix(prefix) {
            let baseKey = String(trimmed.dropFirst(prefix.count))
            let convertedBase = convertToKanataKey(baseKey)
            return prefix + convertedBase
        }

        // Use the same key mapping logic as the original RuntimeCoordinator
        let keyMap: [String: String] = [
            "caps": "caps",
            "capslock": "caps",
            "caps lock": "caps",
            "space": "spc",
            "spacebar": "spc",
            "enter": "ret",
            "return": "ret",
            "tab": "tab",
            "escape": "esc",
            "esc": "esc",
            "backspace": "bspc",
            "delete": "del",
            "cmd": "lmet",
            "command": "lmet",
            "lcmd": "lmet",
            "rcmd": "rmet",
            "leftcmd": "lmet",
            "rightcmd": "rmet",
            "left command": "lmet",
            "right command": "rmet",
            "left shift": "lsft",
            "lshift": "lsft",
            "right shift": "rsft",
            "rshift": "rsft",
            "left control": "lctl",
            "lctrl": "lctl",
            "ctrl": "lctl",
            "right control": "rctl",
            "rctrl": "rctl",
            "left option": "lalt",
            "lalt": "lalt",
            "right option": "ralt",
            "ralt": "ralt",
            "(": "lpar",
            ")": "rpar",
            // Punctuation keys - must be converted to kanata's abbreviated names
            "apostrophe": "'",
            "semicolon": ";",
            "comma": ",",
            "dot": ".",
            "period": ".",
            "slash": "/",
            "minus": "min",
            "equal": "eql",
            "equals": "eql",
            "grave": "grv",
            "backslash": "\\",
            "leftbrace": "[",
            "rightbrace": "]",
            "leftbracket": "[",
            "rightbracket": "]",
            // Short aliases produced internally (e.g. AutoShiftSymbolsConfig.allSymbolKeys)
            // that kanata itself doesn't accept in defsrc. Map them to the literal
            // single-char tokens kanata does accept.
            "apos": "'",
            "bsls": "\\",
            "comm": ",",
            "lbrc": "[",
            "rbrc": "]",
            "scln": ";",
            "slsh": "/",
            // International/locale-specific keys
            // Korean keyboard keys
            "hangeul": "kana", // Korean Hanja key → maps to Japanese kana (similar input mode toggle)
            "hanja": "eisu", // Korean Han/Eng toggle → maps to Japanese eisu (alphanumeric mode)
            // ISO/International keys
            "intlbackslash": "nubs", // ISO key between Left Shift and Z (Non-US Backslash)
            "intlro": "ro", // ABNT2/JIS Ro key (extra key between slash and right shift)
            // JIS keys (already have native Kanata names, but add aliases)
            "eisu": "eisu", // Japanese alphanumeric key
            "kana": "kana", // Japanese kana key
            // Modifier names from keyCodeToKanataName (concatenated form without space)
            "leftshift": "lsft",
            "rightshift": "rsft",
            "leftctrl": "lctl",
            "rightctrl": "rctl",
            "leftalt": "lalt",
            "rightalt": "ralt",
            "leftmeta": "lmet",
            "rightmeta": "rmet",
            // Navigation keys (keyCodeToKanataName returns long names, kanata expects short)
            "pageup": "pgup",
            "pagedown": "pgdn",
            "home": "home",
            "end": "end",
            "help": "help"
        ]

        // Check if we have a specific mapping
        if let mapped = keyMap[lowercased] {
            return mapped
        }

        // For single characters, return as-is
        if lowercased.count == 1 {
            return lowercased
        }

        // For tokens that would break Kanata syntax, replace parens explicitly
        if lowercased.contains("(") { return "lpar" }
        if lowercased.contains(")") { return "rpar" }

        // Function keys (f1-f24) are valid kanata names
        if lowercased.hasPrefix("f"), let num = Int(lowercased.dropFirst()), (1 ... 24).contains(num) {
            return lowercased
        }

        // Known valid kanata key names that need no conversion (pass-through is safe)
        let validKanataPassthrough: Set = [
            // Arrow keys
            "up", "down", "left", "right",
            // Navigation
            "home", "end", "pgup", "pgdn", "del", "ins",
            // Media/system
            "brdn", "brup", "prev", "pp", "next", "mute", "vold", "volu",
            // Modifiers (kanata native names)
            "lsft", "rsft", "lctl", "rctl", "lalt", "ralt", "lmet", "rmet",
            "caps", "esc", "ret", "spc", "tab", "bspc", "grv", "min", "eql",
            // International
            "nubs", "ro", "eisu", "kana", "help",
            // Numpad
            "kp0", "kp1", "kp2", "kp3", "kp4", "kp5", "kp6", "kp7", "kp8", "kp9",
            "kprt", "kp+", "kp-", "kp*", "kp/", "kp.", "nlck",
            // Other
            "prtsc", "slck", "pause", "menu", "comp", "fn",
            "ssrq", "102d"
        ]

        if validKanataPassthrough.contains(lowercased) {
            return lowercased
        }

        // Unknown key name - log warning and return as-is to avoid silent breakage.
        // The downstream CLI validation (kanata --check) will catch this before save.
        AppLogger.shared.warnUnlessQuietTest(
            "⚠️ [KanataKeyConverter] Unknown key name '\(trimmed)' - may not be valid kanata key",
            file: #file,
            function: #function,
            line: #line
        )
        return lowercased
    }

    /// Convert KeyPath output sequence to Kanata output format
    public static func convertToKanataSequence(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Already a Kanata S-expression (e.g., "(layer-while-held nav)", "(multi ...)") — pass through unchanged
        if trimmed.hasPrefix("("), trimmed.hasSuffix(")") {
            return trimmed
        }

        // Split on any whitespace
        let tokens = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        // No tokens -> nothing to emit (avoid indexing empty array)
        if tokens.isEmpty {
            return ""
        }

        // Multiple whitespace-separated tokens are a sequence to type in order
        // (a chord arrives as one token with modifier prefixes, "M-S-C-4"). A
        // bare list "(mute M-S-C-4)" is not Kanata; a macro is.
        if tokens.count > 1 {
            // Use convertToKanataKeyForMacro to preserve uppercase modifier prefixes
            let kanataKeys = tokens.map { convertToKanataKeyForMacro($0) }
            return "(macro \(kanataKeys.joined(separator: " ")))"
        }

        // Single token - check if it's a text sequence to type (e.g., "123", "hello")
        let singleToken = tokens[0]

        // If it's a multi-character string that looks like text to type (not a key name)
        // Convert to macro for typing each character
        if singleToken.count > 1, shouldConvertToMacro(singleToken) {
            // Split into individual characters and convert each to a key
            let characters = Array(singleToken)
            let keys = characters.map { String($0) }
            return "(macro \(keys.joined(separator: " ")))"
        }

        // Single key: use convertToKanataKeyForMacro to preserve uppercase modifier prefixes
        // (e.g., A-right, M-left, M-S-g) which are valid in both macro and deflayer contexts
        return convertToKanataKeyForMacro(singleToken)
    }

    /// Determine if a string should be converted to a macro (typed character by character)
    /// vs treated as a single key name like "escape" or "tab"
    private static func shouldConvertToMacro(_ token: String) -> Bool {
        // Check for Kanata modifier prefixes (e.g., A-right, M-left, C-S-a)
        // These should NOT be converted to macros - they are valid Kanata modified key outputs
        let modifierPattern = #"^(A-|M-|C-|S-|RA-|RM-|RC-|RS-|AG-)+"#
        if let regex = try? NSRegularExpression(pattern: modifierPattern, options: .caseInsensitive) {
            let range = NSRange(token.startIndex..., in: token)
            if regex.firstMatch(in: token, options: [], range: range) != nil {
                return false
            }
        }

        // Kanata decides what is a key. A name it knows (`f21`, `calc`) is
        // emitted as a key, so admission can refuse it with a reason if the
        // backend cannot send it, rather than typing its letters. Only a word
        // Kanata does not know is text to type. The list below is the fallback
        // when no bridge is available to ask.
        if let known = BackendCapabilityProfile.shared.knowsKey(token) {
            return !known
        }

        // Known key names that shouldn't be split into macros
        let keyNames: Set = [
            "escape", "esc", "return", "ret", "enter",
            "backspace", "bspc", "delete", "del",
            "tab", "space", "spc",
            "capslock", "caps", "capslk",
            "leftshift", "lsft", "rightshift", "rsft",
            "leftctrl", "lctl", "rightctrl", "rctl", "ctrl",
            "leftalt", "lalt", "rightalt", "ralt",
            "leftmeta", "lmet", "rightmeta", "rmet",
            "leftcmd", "rightcmd", "cmd", "command", "lcmd", "rcmd",
            "up", "down", "left", "right",
            "home", "end", "pageup", "pgup", "pagedown", "pgdn",
            "f1", "f2", "f3", "f4", "f5", "f6",
            "f7", "f8", "f9", "f10", "f11", "f12", "f13", "f14", "f15",
            "f16", "f17", "f18", "f19", "f20",
            // Kanata media/system outputs
            "brdn", "brup", "mission_control", "launchpad",
            "prev", "pp", "next", "mute", "vold", "volu",
            // Numpad keys
            "kp0", "kp1", "kp2", "kp3", "kp4", "kp5", "kp6", "kp7", "kp8", "kp9",
            "kprt", "kp+", "kp-", "kp*", "kp/", "kp.", "nlck",
            // Other hardware keys
            "prtsc", "slck", "pause", "menu", "comp", "fn", "ins",
            "ssrq", "102d", "nubs", "ro", "eisu", "kana", "help",
            "grv", "min", "eql"
        ]

        // If it's a known key name, don't convert to macro
        if keyNames.contains(token.lowercased()) {
            return false
        }

        // If it contains multiple alphanumeric characters or symbols, treat as text to type
        return token.count > 1
    }
}
