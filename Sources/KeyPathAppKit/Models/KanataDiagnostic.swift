import Foundation

// MARK: - Diagnostic Types

/// Detailed diagnostic information for Kanata issues
struct KanataDiagnostic: Sendable {
    let timestamp: Date
    let severity: DiagnosticSeverity
    let category: DiagnosticCategory
    let title: String
    let description: String
    let technicalDetails: String
    let suggestedAction: String
    let canAutoFix: Bool
}

enum DiagnosticSeverity: String, CaseIterable, Sendable {
    case info
    case warning
    case error
    case critical

    var emoji: String {
        switch self {
        case .info: "ℹ️"
        case .warning: "⚠️"
        case .error: "❌"
        case .critical: "🚨"
        }
    }
}

enum DiagnosticCategory: String, CaseIterable, Sendable {
    case configuration = "Configuration"
    case permissions = "Permissions"
    case process = "Process"
    case system = "System"
    case conflict = "Conflict"
}
