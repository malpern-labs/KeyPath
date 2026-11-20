import Foundation
import KeyPathCore
import KeyPathRulesCore

public struct PacksFacade: Sendable {
    /// Test seam: overrides the manager used by install/uninstall/configure so tests
    /// can inject temp-backed stores instead of the shared persistent ones (#953).
    /// Construct only; source hydration happens after admission.
    private let managerFactory: (@Sendable @MainActor () async -> RuleCollectionsManager)?

    private let installedPackTracker: InstalledPackTracker

    private let operation: CLIConfigurationOperation?

    init(operation: CLIConfigurationOperation) {
        managerFactory = nil
        installedPackTracker = operation.installedPackTracker
        self.operation = operation
    }

    public init() {
        managerFactory = nil
        installedPackTracker = .shared
        operation = nil
    }

    init(
        installedPackTracker: InstalledPackTracker,
        managerFactory: @escaping @Sendable @MainActor () async -> RuleCollectionsManager
    ) {
        self.installedPackTracker = installedPackTracker
        self.managerFactory = managerFactory
        operation = nil
    }

    // MARK: - Pack Management

    public func listPacks() async -> [CLIPack] {
        await CLIPackCatalog(installedPackTracker: installedPackTracker).listPacks()
    }

    public func showPack(nameOrId: String) async throws -> CLIPackDetail? {
        try await CLIPackCatalog(installedPackTracker: installedPackTracker).showPack(nameOrId: nameOrId)
    }

    @MainActor
    public func installPack(
        nameOrId: String,
        settingValues: [String: Int] = [:],
        dryRun: Bool = false
    ) async throws -> CLIPackInstallResult {
        try await withPackOperation { manager, permit in
            guard let pack = try resolvePack(nameOrId: nameOrId) else {
                throw CLIPackNotFound(query: nameOrId)
            }

            let isAlready = await installedPackTracker.isInstalled(packID: pack.id)
            if isAlready {
                return CLIPackInstallResult(
                    packID: pack.id,
                    packName: pack.name,
                    action: "already-installed",
                    warnings: [],
                    quickSettingValues: [:]
                )
            }

            try validateQuickSettings(settingValues, for: pack)

            if dryRun {
                var warnings: [String] = []
                let installedIDs = await Set(installedPackTracker.allInstalled().map(\.packID))
                let suggestions = PackDependencyChecker.suggestions(for: pack.id, installedPackIDs: installedIDs)
                for dep in suggestions {
                    let depName = PackRegistry.pack(id: dep.packID)?.name ?? dep.packID
                    warnings.append("Enhanced by '\(depName)' — install it for best results")
                }
                return CLIPackInstallResult(
                    packID: pack.id,
                    packName: pack.name,
                    action: "would-install",
                    warnings: warnings,
                    quickSettingValues: settingValues
                )
            }

            await loadPackSources(into: manager)
            let record = try await PackInstaller.shared.install(
                pack,
                quickSettingValues: settingValues,
                manager: manager,
                installedPackTracker: installedPackTracker,
                mutationPermit: permit
            )

            var warnings: [String] = []
            let installedIDs = await Set(installedPackTracker.allInstalled().map(\.packID))
            let suggestions = PackDependencyChecker.suggestions(for: pack.id, installedPackIDs: installedIDs)
            for dep in suggestions {
                let depName = PackRegistry.pack(id: dep.packID)?.name ?? dep.packID
                warnings.append("Enhanced by '\(depName)' — install it for best results")
            }

            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "installed",
                warnings: warnings,
                quickSettingValues: record.quickSettingValues
            )
        }
    }

    @MainActor
    public func uninstallPack(
        nameOrId: String,
        dryRun: Bool = false
    ) async throws -> CLIPackInstallResult {
        try await withPackOperation { manager, permit in
            guard let pack = try resolvePack(nameOrId: nameOrId) else {
                throw CLIPackNotFound(query: nameOrId)
            }

            let isInstalled = await installedPackTracker.isInstalled(packID: pack.id)
            guard isInstalled else {
                return CLIPackInstallResult(
                    packID: pack.id,
                    packName: pack.name,
                    action: "not-installed",
                    warnings: [],
                    quickSettingValues: [:]
                )
            }

            if dryRun {
                return CLIPackInstallResult(
                    packID: pack.id,
                    packName: pack.name,
                    action: "would-uninstall",
                    warnings: [],
                    quickSettingValues: [:]
                )
            }

            await loadPackSources(into: manager)
            try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager, installedPackTracker: installedPackTracker, mutationPermit: permit)

            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "uninstalled",
                warnings: [],
                quickSettingValues: [:]
            )
        }
    }

    @MainActor
    public func configurePack(
        nameOrId: String,
        settingValues: [String: Int],
        dryRun: Bool = false
    ) async throws -> CLIPackInstallResult {
        try await withPackOperation { manager, permit in
            guard let pack = try resolvePack(nameOrId: nameOrId) else {
                throw CLIPackNotFound(query: nameOrId)
            }

            let isInstalled = await installedPackTracker.isInstalled(packID: pack.id)
            guard isInstalled else {
                return CLIPackInstallResult(
                    packID: pack.id,
                    packName: pack.name,
                    action: "not-installed",
                    warnings: ["Pack must be installed before configuring settings."],
                    quickSettingValues: [:]
                )
            }

            guard !pack.quickSettings.isEmpty else {
                throw CLIPackSettingError(
                    packName: pack.name,
                    settingKey: settingValues.keys.first ?? "",
                    validKeys: []
                )
            }

            try validateQuickSettings(settingValues, for: pack)

            if dryRun {
                let current = await installedPackTracker.record(for: pack.id)?.quickSettingValues ?? [:]
                var merged = current
                for (k, v) in settingValues {
                    merged[k] = v
                }
                return CLIPackInstallResult(
                    packID: pack.id,
                    packName: pack.name,
                    action: "would-configure",
                    warnings: [],
                    quickSettingValues: merged
                )
            }

            await loadPackSources(into: manager)
            try await PackInstaller.shared.updateQuickSettings(
                packID: pack.id,
                newValues: settingValues,
                manager: manager,
                installedPackTracker: installedPackTracker,
                mutationPermit: permit
            )

            let updatedSettings = await installedPackTracker.record(for: pack.id)?.quickSettingValues ?? [:]

            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "configured",
                warnings: [],
                quickSettingValues: updatedSettings
            )
        }
    }

    func resolvePack(nameOrId: String) throws -> Pack? {
        try CLIPackCatalog.resolvePack(nameOrId: nameOrId)
    }

    @MainActor
    private func withPackOperation<Result: Sendable>(
        _ operation: @MainActor @Sendable (RuleCollectionsManager, ConfigurationOperationGate.Permit) async throws -> Result
    ) async throws -> Result {
        let manager = await makePackManager()
        return try await manager.configurationService.operationGate.withOperation(using: self.operation?.permit) { @MainActor permit in
            try await PackInstaller.shared.recoverAndValidateState(manager: manager, tracker: installedPackTracker, permit: permit)
            return try await operation(manager, permit)
        }
    }

    /// Load source state only after admission, immediately before a real mutation.
    /// Dry-run and already-installed/not-installed exits do not hydrate or write sources.
    @MainActor
    private func loadPackSources(into manager: RuleCollectionsManager) async {
        manager.ruleCollections = await RuleCollectionDeduplicator.dedupe(manager.ruleCollectionStore.loadCollections())
        manager.customRules = await manager.customRulesStore.loadRules()
    }

    @MainActor
    func makePackManager() async -> RuleCollectionsManager {
        if let managerFactory {
            return await managerFactory()
        }

        if let operation {
            let directory = URL(fileURLWithPath: operation.directory)
            return RuleCollectionsManager(
                ruleCollectionStore: RuleCollectionStore(fileURL: directory.appendingPathComponent("RuleCollections.json")),
                customRulesStore: CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json")),
                configurationService: operation.service, installedPackTracker: installedPackTracker
            )
        }
        let configService = ConfigurationService()
        return RuleCollectionsManager(
            ruleCollectionStore: .shared,
            customRulesStore: .shared,
            configurationService: configService, installedPackTracker: installedPackTracker
        )
    }

    private func validateQuickSettings(_ values: [String: Int], for pack: Pack) throws {
        let settingsByID = Dictionary(uniqueKeysWithValues: pack.quickSettings.map { ($0.id, $0) })
        for (key, value) in values {
            guard let setting = settingsByID[key] else {
                throw CLIPackSettingError(
                    packName: pack.name,
                    settingKey: key,
                    validKeys: pack.quickSettings.map(\.id)
                )
            }
            try validateQuickSettingValue(value, setting: setting, packName: pack.name)
        }
    }

    private func validateQuickSettingValue(_ value: Int, setting: PackQuickSetting, packName: String) throws {
        switch setting.kind {
        case let .slider(_, min, max, _, unitSuffix):
            guard value >= min, value <= max else {
                throw CLIPackSettingValueError(
                    packName: packName,
                    settingKey: setting.id,
                    value: value,
                    reason: "must be between \(min)\(unitSuffix) and \(max)\(unitSuffix)"
                )
            }
        }
    }
}

// MARK: - Pack CLI Types

public struct CLIPackInstallResult: Codable, Sendable {
    public let packID: String
    public let packName: String
    public let action: String
    public let warnings: [String]
    public let quickSettingValues: [String: Int]
}

public struct CLIPackNotFound: Error, CustomStringConvertible {
    public let query: String
    public var description: String {
        "No pack found matching \"\(query)\""
    }
}

public struct CLIPackSettingError: Error, CustomStringConvertible {
    public let packName: String
    public let settingKey: String
    public let validKeys: [String]
    public var description: String {
        if validKeys.isEmpty {
            return "Pack '\(packName)' has no quick settings, but --setting \(settingKey) was provided"
        }
        return "Unknown setting '\(settingKey)' for pack '\(packName)'. Valid keys: \(validKeys.joined(separator: ", "))"
    }
}

public struct CLIPackSettingValueError: Error, CustomStringConvertible {
    public let packName: String
    public let settingKey: String
    public let value: Int
    public let reason: String

    public var description: String {
        "Invalid value \(value) for setting '\(settingKey)' on pack '\(packName)': \(reason)"
    }
}
