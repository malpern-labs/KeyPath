import Foundation
import KeyPathCore

extension ConfigurationService {
    // MARK: - Validation

    /// Validate the unchanged candidate with the engine's parsed session contract.
    /// This gate runs before staging source/config files and before direct writes.
    func requireSessionEligibleConfiguration(_ config: String) async throws {
        // Kanata resolves relative includes beside the main file. Validate an
        // isolated candidate in that same directory without replacing any user
        // configuration or source store.
        let directory = URL(fileURLWithPath: configDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(".keypath-session-validation-\(UUID().uuidString).kbd")
        defer { try? FileManager.default.removeItem(at: path) }
        try await writeFileURLAsync(string: config, to: path)
        let result = SessionCapsRuntimeSupport.validate(
            configPath: path.path, runtimeHost: sessionValidationRuntimeHost, requireSelection: false
        ).result
        if case .valid = result { return }
        let attribution = await MainActor.run { sessionRefusalAttribution?() ?? [] }
        let errors = [SessionConfigurationRefusal.message(result, attribution: attribution) ?? result.logSummary]
        notifyValidationFailure(errors, context: "session")
        throw KeyPathError.configuration(.validationFailed(errors: errors))
    }

    /// Validate through the same parsed Kanata contract used by the session worker.
    public func validateConfiguration(_ config: String) async -> (isValid: Bool, errors: [String]) {
        guard !config.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (false, [String(localized: "Configuration content is empty")])
        }
        do {
            try await requireSessionEligibleConfiguration(config)
            return (true, [])
        } catch {
            return (false, [error.localizedDescription])
        }
    }

    private func notifyValidationFailure(_ errors: [String], context: String) {
        guard !errors.isEmpty, !TestEnvironment.isRunningTests else { return }
        NotificationCenter.default.post(
            name: .configValidationFailed,
            object: nil,
            userInfo: [
                "errors": errors,
                "context": context
            ]
        )
    }
}
