import Foundation
import KeyPathCore

extension KanataConfiguration {
    // MARK: - App-Specific Key Support

    /// Uses the same sanitization as AppConfigGenerator.
    static func appSpecificAliasName(for key: String) -> String {
        let sanitized = key.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        guard !sanitized.isEmpty else {
            let hash = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            return "@kp-key-\(String(format: "%04x", hash % 65521))"
        }

        if let first = sanitized.first, !first.isLetter {
            return "@kp-key-\(sanitized)"
        }

        return "@kp-\(sanitized)"
    }
}
