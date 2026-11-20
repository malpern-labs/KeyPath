import Foundation
import KeyPathCore

/// Persists user-defined custom rules alongside the main configuration directory.
package actor CustomRulesStore {
    package static let shared = CustomRulesStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let fileManager: FileManager

    package init(fileURL: URL? = nil, fileManager: FileManager = Foundation.FileManager()) {
        self.fileManager = fileManager
        // Under test, use the per-process sandbox like RuleCollectionStore, so a
        // plain `swift test` (no KEYPATH_HOME_DIR_OVERRIDE) can never overwrite the
        // developer's real ~/.config/keypath/CustomRules.json. Production is unchanged.
        let defaultDirectory = TestEnvironment.isRunningTests
            ? AppPaths.configDirectory
            : URL(fileURLWithPath: WizardSystemPaths.userConfigDirectory, isDirectory: true)
        self.fileURL = fileURL ?? defaultDirectory.appendingPathComponent("CustomRules.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    package func loadRules() -> [CustomRule] {
        AppLogger.shared.log("📂 [CustomRulesStore] loadRules from: \(fileURL.path)")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            AppLogger.shared.log("📂 [CustomRulesStore] File does not exist, returning []")
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            AppLogger.shared.log("📂 [CustomRulesStore] Read \(data.count) bytes from file")
            let rules = try decoder.decode([CustomRule].self, from: data)
            AppLogger.shared.log("📂 [CustomRulesStore] Decoded \(rules.count) rules:")
            for rule in rules {
                AppLogger.shared.log("📂 [CustomRulesStore]   - '\(rule.input)' → '\(rule.action.displayName)' (enabled: \(rule.isEnabled))")
            }
            return rules
        } catch {
            AppLogger.shared.log("⚠️ [CustomRulesStore] Failed to load rules: \(error)")
            return []
        }
    }

    package func listRules(enabledOnly: Bool = false) -> [CLIRuleDetail] {
        let rules = loadRules()
        return (enabledOnly ? rules.filter(\.isEnabled) : rules).map(CLIRuleDetail.init(from:))
    }

    package func showRule(input: String) -> CLIRuleDetail? {
        loadRules().first(where: { $0.input == input }).map(CLIRuleDetail.init(from:))
    }

    package func loadForMutation() throws -> [CustomRule] {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return [] }
        return try decoder.decode([CustomRule].self, from: data)
    }

    package func encodedRules(_ rules: [CustomRule]) throws -> Data {
        try encoder.encode(rules)
    }

    /// Round-trip through the store's codecs so transaction comparisons use persisted precision.
    package func rulesInPersistenceFormat(_ rules: [CustomRule]) throws -> [CustomRule] {
        try decoder.decode([CustomRule].self, from: encodedRules(rules))
    }

    package var persistenceURL: URL {
        fileURL
    }

    package func saveRules(_ rules: [CustomRule]) throws {
        AppLogger.shared.log("💾 [CustomRulesStore] saveRules: \(rules.count) rules to \(fileURL.path)")
        for rule in rules {
            AppLogger.shared.log("💾 [CustomRulesStore]   - '\(rule.input)' → '\(rule.action.displayName)' (enabled: \(rule.isEnabled))")
        }
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encodedRules(rules)
        try data.write(to: fileURL, options: .atomic)
        AppLogger.shared.log("💾 [CustomRulesStore] Saved \(data.count) bytes")
    }
}

#if DEBUG
    package extension CustomRulesStore {
        nonisolated static func testStore(at url: URL) -> CustomRulesStore {
            CustomRulesStore(fileURL: url)
        }
    }
#endif
