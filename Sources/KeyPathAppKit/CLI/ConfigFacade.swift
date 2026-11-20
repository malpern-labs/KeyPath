import Darwin
import Foundation
import KeyPathCore
import KeyPathRulesCore
import Synchronization

public struct ConfigFacade: Sendable {
    private var operation: CLIConfigurationOperation?
    private var engineAccessOverride: EngineAccess?
    private var controlSocketPath = RuntimeControl.socketURL.path
    private let configDirectory: String
    private let ruleCollectionLoader: @Sendable () async -> [RuleCollection]
    private let customRuleLoader: @Sendable () async -> [CustomRule]
    private let preferenceDefaultsOverride: RecoverableRuleWrite.PreferenceDefaults?
    private let reloadHandler: (@Sendable () async -> Bool)?

    public init(configDirectory: String = KeyPathConstants.Config.directory) {
        self.configDirectory = configDirectory
        let directory = URL(fileURLWithPath: configDirectory, isDirectory: true)
        let collectionStore = RuleCollectionStore(fileURL: directory.appendingPathComponent("RuleCollections.json"))
        let customStore = CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))
        ruleCollectionLoader = { await collectionStore.loadCollections() }
        customRuleLoader = { await customStore.loadRules() }
        preferenceDefaultsOverride = nil
        reloadHandler = nil
    }

    init(
        configDirectory: String,
        ruleCollectionLoader: @escaping @Sendable () async -> [RuleCollection],
        customRuleLoader: @escaping @Sendable () async -> [CustomRule],
        preferenceDefaults: UserDefaults? = nil,
        reloadHandler: (@Sendable () async -> Bool)? = nil
    ) {
        self.configDirectory = configDirectory
        self.ruleCollectionLoader = ruleCollectionLoader
        self.customRuleLoader = customRuleLoader
        preferenceDefaultsOverride = preferenceDefaults.map(RecoverableRuleWrite.PreferenceDefaults.init)
        self.reloadHandler = reloadHandler
    }

    init(operation: CLIConfigurationOperation) {
        self.init(configDirectory: operation.directory)
        self.operation = operation
    }

    /// An owned fake app endpoint, without changing routing for other facades.
    init(appControlSocketPath: String) {
        self.init()
        engineAccessOverride = .viaApp
        controlSocketPath = appControlSocketPath
    }

    // MARK: - Configuration

    @MainActor
    public func currentConfig() async -> String {
        let service = ConfigurationService(configDirectory: configDirectory)
        let config = await service.current()
        return config.content
    }

    @MainActor
    public func validateConfig() async -> CLIValidationResult {
        let service = ConfigurationService(configDirectory: configDirectory)
        let config = await service.current()
        if config.content.isEmpty {
            return CLIValidationResult(isValid: false, errors: ["No configuration generated yet. Run 'keypath apply' first."])
        }
        let result = await service.validateConfiguration(config.content)
        return CLIValidationResult(isValid: result.isValid, errors: result.errors)
    }

    // MARK: - Apply

    public func applyConfiguration(dryRun: Bool = false) async throws -> CLIApplyResult {
        let service: ConfigurationService = if let operation { operation.service }
        else { await MainActor.run { ConfigurationService(configDirectory: configDirectory) } }
        return try await service.operationGate.withOperation(using: operation?.permit) { permit in
            try await applyConfiguration(dryRun: dryRun, service: service, permit: permit)
        }
    }

    private func applyConfiguration(
        dryRun: Bool, service: ConfigurationService, permit: ConfigurationOperationGate.Permit
    ) async throws -> CLIApplyResult {
        if dryRun {
            // Recovery can restore files and defaults and reload the running engine.
            // Refuse an ambiguous preview instead of doing those writes under --dry-run.
            try requireNoPendingRecoveryForPreview()
        } else {
            try await service.recoverPendingRuleWrite(
                mutationPermit: permit,
                preferenceDefaults: preferenceDefaults
            )
            _ = try await service.applyRecoveredRuntimeIfNeeded(
                mutationPermit: permit,
                reloadHandler: { await reloadResult() }
            )
        }
        await refreshSharedLeaderPreference()
        let collections = await ruleCollectionLoader()
        let customRules = await customRuleLoader()
        let enabledCount = collections.filter(\.isEnabled).count

        // Reconcile the leader key from the Leader Key collection's explicit `selectedOutput`
        // before generating config. Config generation (ConfigurationService →
        // KanataConfiguration) derives the primary leader binding from `leaderKeyPreference`
        // AND emits a `;; Input:` binding per collection activator — the standalone CLI kept
        // neither in sync with the collection, so `keypath collection`/JSON edits to
        // `selectedOutput` were silently ignored by `keypath apply`. Reconcile both, mirroring
        // the in-process reconcile the app does on load (RuleCollectionsManager). See #889.
        let previousData = preferenceDefaults.data(forKey: PreferencesService.leaderKeyPreferenceKey)
        let current = previousData.flatMap { try? JSONDecoder().decode(LeaderKeyPreference.self, from: $0) } ?? .default
        let reconcile = LeaderKeyPreference.reconciled(from: collections, current: current)
        if let reconcile {
            AppLogger.shared.log(
                "🔑 [ConfigFacade] Reconciling leader key from collection selectedOutput: '\(reconcile.key)' (was '\(current.key)')"
            )
        }
        let reconciledCollections = reconcile.map { r in
            LeaderKeyPreference.reconcileLeaderActivators(
                in: collections,
                key: r.key,
                targetLayer: r.targetLayer
            )
        } ?? collections

        if dryRun {
            let previewConfig = try await service.generateConfiguration(
                ruleCollections: reconciledCollections,
                customRules: customRules,
                leaderKeyPreference: reconcile ?? (preferenceDefaultsOverride == nil ? nil : current),
                preferenceDefaults: preferenceDefaultsOverride?.value
            )
            try await validateDryRunConfig(previewConfig.content)

            return CLIApplyResult(
                collectionsCount: collections.count,
                enabledCount: enabledCount,
                customRulesCount: customRules.count,
                reloadSuccess: false,
                changeset: changeset(collections: collections, customRules: customRules),
                dryRun: true
            )
        }

        if let reconcile {
            let preferenceChange = try RecoverableRuleWrite.PreferenceChange.leader(
                before: previousData,
                after: JSONEncoder().encode(reconcile)
            )
            try await service.saveConfiguration(
                ruleCollections: reconciledCollections,
                customRules: customRules,
                leaderKeyPreference: reconcile,
                preferenceDefaults: preferenceDefaults,
                preferenceChanges: [preferenceChange],
                mutationPermit: permit
            )
            await refreshSharedLeaderPreference()
        } else {
            try await service.saveConfiguration(
                ruleCollections: reconciledCollections,
                customRules: customRules,
                mutationPermit: permit,
                preferenceDefaults: preferenceDefaults
            )
        }

        let reloadSuccess = await reloadRuntime()

        return CLIApplyResult(
            collectionsCount: collections.count,
            enabledCount: enabledCount,
            customRulesCount: customRules.count,
            reloadSuccess: reloadSuccess,
            changeset: changeset(collections: collections, customRules: customRules)
        )
    }

    private func reloadResult() async -> ReloadResult {
        let success = await reloadRuntime()
        return ReloadResult(
            success: success, response: nil,
            errorMessage: success ? nil : "CLI reload failed",
            disposition: success ? .applied : .failed
        )
    }

    private func reloadRuntime() async -> Bool {
        if let reloadHandler { return await reloadHandler() }
        return await tcpReload()
    }

    private var preferenceDefaults: UserDefaults {
        preferenceDefaultsOverride?.value ?? PreferencesService.canonicalDefaults
    }

    @MainActor
    private func refreshSharedLeaderPreference() {
        if preferenceDefaultsOverride == nil {
            PreferencesService.shared.reloadLeaderKeyPreference()
        }
    }

    // MARK: - Engine

    /// How this process reaches the engine. Only the app that launched the
    /// worker may connect to it (ADR-046): the app sets `.direct` at startup;
    /// the CLI and anything else asks the app over runtime control.
    public enum EngineAccess: Sendable {
        case direct
        case viaApp
    }

    private static let engineAccessState = Mutex<EngineAccess>(.viaApp)

    public static var engineAccess: EngineAccess {
        get { engineAccessState.withLock { $0 } }
        set { engineAccessState.withLock { $0 = newValue } }
    }

    private var resolvedEngineAccess: EngineAccess {
        engineAccessOverride ?? Self.engineAccess
    }

    /// Engine requests answered by the app. A missing app, or one that cannot
    /// answer, reads as "not available".
    private func askApp(_ operation: RuntimeControl.Operation, argument: String? = nil) async throws
        -> RuntimeControl.Response
    {
        try await RuntimeControl.requestEngine(operation, argument: argument, socketPath: controlSocketPath)
    }

    func engineClient() -> KanataTCPClient {
        KanataTCPClient()
    }

    public func tcpCheckHealth() async -> Bool {
        switch resolvedEngineAccess {
        case .direct: await engineClient().checkServerStatus()
        // The engine must answer, not only the app report "running".
        case .viaApp: await (try? askApp(.layer))?.layer != nil
        }
    }

    public func tcpGetCurrentLayer() async throws -> String {
        switch resolvedEngineAccess {
        case .direct: return try await engineClient().requestCurrentLayerName()
        case .viaApp:
            guard let layer = try await askApp(.layer).layer else { throw Self.error("No current layer reported") }
            return layer
        }
    }

    public func tcpGetLayers() async throws -> [String] {
        switch resolvedEngineAccess {
        case .direct: try await engineClient().requestLayerNames()
        case .viaApp: try await askApp(.layers).layers ?? []
        }
    }

    public func tcpReload() async -> Bool {
        switch resolvedEngineAccess {
        case .direct:
            if case .success = await engineClient().reloadConfig() { return true }
            return false
        case .viaApp: return await (try? askApp(.reload)) != nil
        }
    }

    public func tcpGetHrmStats() async throws -> CLIHrmStats {
        switch resolvedEngineAccess {
        case .direct:
            let stats = try await engineClient().requestHrmStats()
            return CLIHrmStats(
                totalDecisions: stats.decisionsTotal,
                tapCount: stats.tapCount,
                holdCount: stats.holdCount
            )
        case .viaApp:
            guard let stats = try await askApp(.hrmStats).hrmStats else { throw Self.error("No HRM statistics reported") }
            return CLIHrmStats(totalDecisions: stats.totalDecisions, tapCount: stats.tapCount, holdCount: stats.holdCount)
        }
    }

    public func tcpResetHrmStats() async throws {
        switch resolvedEngineAccess {
        case .direct: try await engineClient().resetHrmStats()
        case .viaApp: _ = try await askApp(.resetHrmStats)
        }
    }

    public func tcpChangeLayer(_ layerName: String) async -> Bool {
        switch resolvedEngineAccess {
        case .direct:
            if case .success = await engineClient().changeLayer(layerName) { return true }
            return false
        case .viaApp: return await (try? askApp(.changeLayer, argument: layerName)) != nil
        }
    }

    private func validateDryRunConfig(_ content: String) async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-cli-dry-run-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let service = await MainActor.run { ConfigurationService(configDirectory: tempDirectory.path) }
        let validation = await service.validateConfiguration(content)
        guard validation.isValid else {
            throw KeyPathError.configuration(.validationFailed(errors: validation.errors))
        }
    }

    private func changeset(
        collections: [RuleCollection],
        customRules: [CustomRule]
    ) -> CLIApplyChangeset {
        CLIApplyChangeset(
            enabledCollections: collections.filter(\.isEnabled).map(\.name),
            disabledCollections: collections.filter { !$0.isEnabled }.map(\.name),
            customRules: customRules.filter(\.isEnabled).map { "\($0.input) → \($0.action.outputString)" }
        )
    }

    private func requireNoPendingRecoveryForPreview() throws {
        let directory = URL(fileURLWithPath: configDirectory, isDirectory: true)
        let scopes: [RecoverableRuleWrite.Scope] = [.rules, .appKeymaps, .packRules, .rawConfig, .deviceRules]
        for scope in scopes {
            let journal = RecoverableRuleWrite.journalURL(directory, scope: scope)
            var metadata = stat()
            // lstat also catches dangling journal symlinks. An unreadable path must
            // not be interpreted as proof that no recovery is pending.
            if lstat(journal.path, &metadata) == 0 || errno != ENOENT {
                throw Self.error("Configuration recovery is pending. Run a normal apply before previewing; dry run left existing files and settings unchanged.")
            }
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "KeyPath.ConfigFacade", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - Config Types

public struct CLIApplyResult: Codable, Sendable {
    public let collectionsCount: Int
    public let enabledCount: Int
    public let customRulesCount: Int
    public let reloadSuccess: Bool
    public let changeset: CLIApplyChangeset?
    public let dryRun: Bool?

    public init(
        collectionsCount: Int,
        enabledCount: Int,
        customRulesCount: Int,
        reloadSuccess: Bool,
        changeset: CLIApplyChangeset?,
        dryRun: Bool? = nil
    ) {
        self.collectionsCount = collectionsCount
        self.enabledCount = enabledCount
        self.customRulesCount = customRulesCount
        self.reloadSuccess = reloadSuccess
        self.changeset = changeset
        self.dryRun = dryRun
    }
}

public struct CLIApplyChangeset: Codable, Sendable {
    public let enabledCollections: [String]
    public let disabledCollections: [String]
    public let customRules: [String]
}

public struct CLIValidationResult: Codable, Sendable {
    public let isValid: Bool
    public let errors: [String]
    public let configPath: String?
    public let configBytes: Int?
    public let collectionsCount: Int?
    public let customRulesCount: Int?

    public init(isValid: Bool, errors: [String], configPath: String? = nil, configBytes: Int? = nil, collectionsCount: Int? = nil, customRulesCount: Int? = nil) {
        self.isValid = isValid
        self.errors = errors
        self.configPath = configPath
        self.configBytes = configBytes
        self.collectionsCount = collectionsCount
        self.customRulesCount = customRulesCount
    }
}

public struct CLIHrmStats: Codable, Sendable {
    public let totalDecisions: Int
    public let tapCount: Int
    public let holdCount: Int
}
