import Foundation
import KeyPathCore
import KeyPathRulesCore

extension AppConfigGenerator {
    private static func createOrVerifyInclude(from keymaps: [AppKeymap], configService: ConfigurationService) async throws {
        // Detect within-app duplicate keys before generating — kanata accepts the
        // resulting config (the duplicate switch case is just dead), so this would
        // otherwise silently drop the user's second mapping (#465).
        let duplicates = detectDuplicateKeys(in: keymaps)
        if !duplicates.isEmpty {
            AppLogger.shared.error(
                "❌ [AppConfigGenerator] Duplicate keys within app keymap(s): "
                    + duplicates.map { "\($0.app): \($0.keys.joined(separator: ", "))" }.joined(separator: "; ")
            )
            throw AppConfigError.duplicateKeys(duplicates: duplicates)
        }

        let content = generate(from: keymaps)
        let path = appConfigPath
        if FileManager.default.fileExists(atPath: path) {
            let existing = try String(contentsOfFile: path, encoding: .utf8)
            guard matchesManagedContent(existing, expected: content) else {
                throw AppConfigError
                    .validationFailed(
                        errors: [
                            String(
                                localized: "Your app-specific configuration was preserved. The visual editor cannot safely reproduce it. Editing requires an explicit conversion with a backup first."
                            )
                        ]
                    )
            }
            return
        }

        // Ensure directory exists
        let directory = (path as NSString).deletingLastPathComponent
        try Foundation.FileManager().createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: nil as [FileAttributeKey: Any]?
        )

        // VALIDATE BEFORE WRITING - prevent broken configs from being saved
        // This is the key fix: we validate generated configs just like we validate user configs
        //
        // NOTE: keypath-apps.kbd is an INCLUDE file, not a standalone config.
        // Kanata requires defsrc/deflayer for validation, so we wrap the content
        // in a minimal valid config context for validation purposes only.
        let service = configService
        AppLogger.shared.log("🔍 [AppConfigGenerator] Validating generated config before save...")

        // Wrap content in minimal valid config for validation (include files need context)
        let validationWrapper = wrapForValidation(content)
        let validation = await service.validateConfiguration(validationWrapper)

        if !validation.isValid {
            AppLogger.shared.error(
                "❌ [AppConfigGenerator] Validation failed with \(validation.errors.count) errors: \(validation.errors)"
            )
            throw AppConfigError.validationFailed(errors: validation.errors)
        }

        AppLogger.shared.log("✅ [AppConfigGenerator] Validation passed, writing config...")

        // Write validated file
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw AppConfigError.writeFailed(path: path, underlying: error.localizedDescription)
        }

        AppLogger.shared.log("💾 [AppConfigGenerator] Saved app config to \(path)")
        AppLogger.shared.log("💾 [AppConfigGenerator] Content:\n\(content.prefix(500))...")
    }

    /// Startup repair creates a missing include or verifies the existing one.
    /// It never updates differing content; edits belong to SaveCoordinator.
    static func ensureIncludeFromStore() async throws {
        let owner = await ConfigurationService.forApp(configDirectory: AppKeymapStore.defaultDirectory.path)
        try await owner.operationGate.withOperation { permit in
            try await owner.recoverPendingAppKeymapWrite(mutationPermit: permit)
            let keymaps = try await AppKeymapStore.shared.loadForMutation()
            try await createOrVerifyInclude(from: keymaps, configService: owner)
        }
    }

    // MARK: - Private Helpers

    /// Wrap app config content in a minimal valid Kanata config for validation.
    ///
    /// Since keypath-apps.kbd is an include file (not standalone), Kanata's --check
    /// requires defsrc/deflayer context. This wrapper provides that context for
    /// validation only - the actual file written is just the app config content.
    private static func wrapForValidation(_ content: String) -> String {
        """
        ;; Validation wrapper - provides minimal context for include file validation
        \(KanataDefcfg.validationWrapper.render())

        (defsrc a b c d e f g h i j k l m n o p q r s t u v w x y z)

        (deflayer base a b c d e f g h i j k l m n o p q r s t u v w x y z)

        ;; === BEGIN APP CONFIG CONTENT ===
        \(content)
        ;; === END APP CONFIG CONTENT ===
        """
    }
}
