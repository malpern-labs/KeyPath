import Foundation
import KeyPathCore
import KeyPathRulesCore

public struct CollectionsFacade: Sendable {
    private let store: RuleCollectionStore
    private let operation: CLIConfigurationOperation?
    private let installedPackTracker: InstalledPackTracker

    public init() {
        store = .shared
        installedPackTracker = .shared
        operation = nil
    }

    init(operation: CLIConfigurationOperation) {
        store = RuleCollectionStore(fileURL: URL(fileURLWithPath: operation.directory)
            .appendingPathComponent("RuleCollections.json"))
        self.operation = operation
        installedPackTracker = operation.installedPackTracker
    }

    init(store: RuleCollectionStore, installedPackTracker: InstalledPackTracker = .shared) {
        self.store = store
        self.installedPackTracker = installedPackTracker
        operation = nil
    }

    private func withMutation<Result: Sendable>(
        _ body: @Sendable () async throws -> Result
    ) async throws -> Result {
        if let operation {
            return try await operation.service.operationGate.withOperation(using: operation.permit) { _ in
                try await body()
            }
        }
        let directory = await store.persistenceURL.deletingLastPathComponent()
        let gate = ConfigurationOperationGate(configurationDirectory: directory)
        return try await gate.withOperation { _ in try await body() }
    }

    // MARK: - Collection CRUD

    public func loadRuleCollections() async -> [CLIRuleCollection] {
        await store.listCollections()
    }

    public func enableCollection(nameOrId: String) async throws -> String? {
        try await withMutation {
            var collections = await store.loadCollections()
            guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
                return nil
            }
            let tracker = installedPackTracker
            try await tracker.validateForMutation()
            if let owner = await tracker.packManagingCollection(collections[index].id) {
                throw PackManagedCollectionError(
                    collectionName: collections[index].name,
                    packName: owner.packName,
                    packID: owner.packID
                )
            }
            collections[index].isEnabled = true
            try await store.saveCollections(collections)
            return collections[index].name
        }
    }

    public func disableCollection(nameOrId: String) async throws -> String? {
        try await withMutation {
            var collections = await store.loadCollections()
            guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
                return nil
            }
            let tracker = installedPackTracker
            try await tracker.validateForMutation()
            if let owner = await tracker.packManagingCollection(collections[index].id) {
                throw PackManagedCollectionError(
                    collectionName: collections[index].name,
                    packName: owner.packName,
                    packID: owner.packID
                )
            }
            collections[index].isEnabled = false
            try await store.saveCollections(collections)
            return collections[index].name
        }
    }

    public func showCollection(nameOrId: String) async throws -> CLIRuleCollection? {
        try await store.showCollection(nameOrId: nameOrId)
    }

    public func showCollectionDetail(nameOrId: String) async throws -> CLIRuleCollectionDetail? {
        try await store.showCollectionDetail(nameOrId: nameOrId)
    }

    public func createCollection(name: String, category: String?, summary: String?) async throws -> CLIRuleCollection {
        try await withMutation {
            var collections = await store.loadCollections()
            let cat: RuleCollectionCategory = if let category {
                RuleCollectionCategory(rawValue: category) ?? .custom
            } else {
                .custom
            }
            let collection = RuleCollection(
                name: name,
                summary: summary ?? "",
                category: cat,
                mappings: []
            )
            collections.append(collection)
            try await store.saveCollections(collections)
            return CLIRuleCollection(from: collection)
        }
    }

    public func renameCollection(nameOrId: String, newName: String) async throws -> String? {
        try await withMutation {
            var collections = await store.loadCollections()
            guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
                return nil
            }
            let oldName = collections[index].name
            collections[index].name = newName
            try await store.saveCollections(collections)
            return oldName
        }
    }

    public func deleteCollection(nameOrId: String) async throws -> Bool {
        try await withMutation {
            var collections = await store.loadCollections()
            guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
                return false
            }
            collections.remove(at: index)
            try await store.saveCollections(collections)
            return true
        }
    }

    public func duplicateCollection(nameOrId: String, newName: String?) async throws -> CLIRuleCollection? {
        try await withMutation {
            var collections = await store.loadCollections()
            guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
                return nil
            }
            var duplicate = collections[index]
            duplicate = RuleCollection(
                name: newName ?? "\(duplicate.name) (Copy)",
                summary: duplicate.summary,
                category: duplicate.category,
                mappings: duplicate.mappings,
                isEnabled: false
            )
            collections.insert(duplicate, at: index + 1)
            try await store.saveCollections(collections)
            return CLIRuleCollection(from: duplicate)
        }
    }

    public func reorderCollection(nameOrId: String, position: Int) async throws -> Bool {
        try await withMutation {
            var collections = await store.loadCollections()
            guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
                return false
            }
            let collection = collections.remove(at: index)
            let targetIndex = min(max(0, position), collections.count)
            collections.insert(collection, at: targetIndex)
            try await store.saveCollections(collections)
            return true
        }
    }

    // MARK: - Export / Import

    public func exportCollection(nameOrId: String) async throws -> CLIExportedCollection? {
        let collections = await store.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        return CLIExportedCollection(from: collections[index])
    }

    public func exportAllCollections() async -> [CLIExportedCollection] {
        let collections = await store.loadCollections()
        return collections.map { CLIExportedCollection(from: $0) }
    }

    public func importCollection(_ exported: CLIExportedCollection, onConflict: CLIConflictStrategy = .fail) async throws -> CLIRuleCollection {
        try await withMutation {
            var collections = await store.loadCollections()
            let existingIndex = collections.firstIndex(where: { $0.name == exported.name })

            if let existingIndex {
                switch onConflict {
                case .fail:
                    throw AmbiguousCollectionMatch(
                        query: exported.name,
                        matches: [.init(name: collections[existingIndex].name, id: collections[existingIndex].id.uuidString)],
                        hint: "Use --on-conflict=replace to overwrite or --on-conflict=skip to no-op"
                    )
                case .skip:
                    return CLIRuleCollection(from: collections[existingIndex])
                case .replace, .merge:
                    collections.remove(at: existingIndex)
                }
            }

            let collection = exported.toRuleCollection()
            collections.append(collection)
            try await store.saveCollections(collections)
            return CLIRuleCollection(from: collection)
        }
    }

    // MARK: - Karabiner Import

    public func importFromKarabiner(data: Data, collectionName: String?, profileIndex: Int?) throws -> CLIKarabinerImportResult {
        let service = KarabinerConverterService()

        let result: KarabinerConversionResult
        do {
            result = try service.convert(data: data, profileIndex: profileIndex)
        } catch {
            if let complexResult = try? convertComplexModsFile(data: data, service: service) {
                result = complexResult
            } else {
                throw error
            }
        }

        let exportedCollections: [CLIExportedCollection]
        if let name = collectionName {
            let allMappings = result.collections.flatMap(\.mappings)
            let merged = RuleCollection(
                name: name,
                summary: "Imported from Karabiner profile: \(result.profileName)",
                category: .custom,
                mappings: allMappings
            )
            exportedCollections = [CLIExportedCollection(from: merged)]
        } else {
            exportedCollections = result.collections.map { CLIExportedCollection(from: $0) }
        }

        var warnings = result.warnings

        if !result.appKeymaps.isEmpty {
            let count = result.appKeymaps.map(\.overrides.count).reduce(0, +)
            warnings.append("\(count) app-specific override(s) found -- use the GUI to configure app keymaps")
        }

        if !result.launcherMappings.isEmpty {
            warnings.append("\(result.launcherMappings.count) launcher mapping(s) found -- use the GUI to configure launcher shortcuts")
        }

        let skipped = result.skippedRules.map {
            CLISkippedRule(description: $0.description, reason: $0.reason)
        }

        return CLIKarabinerImportResult(
            profileName: result.profileName,
            collections: exportedCollections,
            skippedRules: skipped,
            warnings: warnings
        )
    }

    public func listKarabinerProfiles(data: Data) throws -> [CLIKarabinerProfile] {
        let service = KarabinerConverterService()
        let profiles = try service.getProfiles(from: data)
        return profiles.map {
            CLIKarabinerProfile(name: $0.name, index: $0.index, isSelected: $0.isSelected)
        }
    }

    private func convertComplexModsFile(data: Data, service: KarabinerConverterService) throws -> KarabinerConversionResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["rules"] != nil
        else {
            throw KarabinerImportError.invalidJSON("Not a recognized Karabiner format")
        }

        let title = json["title"] as? String ?? "Imported Rules"
        let wrapped: [String: Any] = [
            "profiles": [[
                "name": title,
                "selected": true,
                "complex_modifications": json,
            ]],
        ]

        let wrappedData = try JSONSerialization.data(withJSONObject: wrapped)
        return try service.convert(data: wrappedData, profileIndex: 0)
    }

    // MARK: - Layer CRUD

    public func listDefinedLayers() async -> [String] {
        let collections = await store.loadCollections()
        var layers = Set<String>()
        layers.insert("base")
        for collection in collections {
            layers.insert(collection.targetLayer.kanataName)
        }
        return layers.sorted()
    }

    public func createLayer(name: String) async throws -> CLIRuleCollection {
        try await withMutation {
            var collections = await store.loadCollections()
            let layer = Self.parseLayer(name)
            let collection = RuleCollection(
                name: "\(name) Layer",
                summary: "Rules for the \(name) layer",
                category: .layers,
                mappings: [],
                targetLayer: layer
            )
            collections.append(collection)
            try await store.saveCollections(collections)
            return CLIRuleCollection(from: collection)
        }
    }

    public func deleteLayer(name: String) async throws -> Int {
        try await withMutation {
            var collections = await store.loadCollections()
            let targetName = Self.parseLayer(name).kanataName
            let before = collections.count
            collections.removeAll { $0.targetLayer.kanataName == targetName }
            let removed = before - collections.count
            if removed > 0 {
                try await store.saveCollections(collections)
            }
            return removed
        }
    }

    public func renameLayer(oldName: String, newName: String) async throws -> Int {
        try await withMutation {

            var collections = await store.loadCollections()
            let oldLayerName = Self.parseLayer(oldName).kanataName
            let newLayer = Self.parseLayer(newName)
            var updated = 0
            for i in collections.indices {
                if collections[i].targetLayer.kanataName == oldLayerName {
                    collections[i].targetLayer = newLayer
                    updated += 1
                }
            }
            if updated > 0 {
                try await store.saveCollections(collections)
            }
            return updated
        }
    }

    // MARK: - Helpers

    public func resolveCollectionIndex(nameOrId: String, in collections: [RuleCollection]) throws -> Int? {
        try RuleCollectionLookup.index(nameOrId: nameOrId, in: collections)
    }

    static func parseLayer(_ name: String) -> RuleCollectionLayer {
        switch name.lowercased() {
        case "base": .base
        case "nav", "navigation": .navigation
        default: .custom(name)
        }
    }
}

// MARK: - Export/Import Types

public struct CLIExportedCollection: Codable, Sendable {
    public let name: String
    public let summary: String
    public let category: String
    public let isEnabled: Bool
    public let targetLayer: String
    public let configuration: RuleCollectionConfiguration?
    public let mappings: [CLIExportedMapping]

    public init(from collection: RuleCollection) {
        name = collection.name
        summary = collection.summary
        category = collection.category.rawValue
        isEnabled = collection.isEnabled
        targetLayer = collection.targetLayer.kanataName
        configuration = collection.configuration
        mappings = collection.mappings.map { CLIExportedMapping(from: $0) }
    }

    public func toRuleCollection() -> RuleCollection {
        let cat = RuleCollectionCategory(rawValue: category) ?? .custom
        let layer: RuleCollectionLayer = switch targetLayer {
        case "base": .base
        case "nav": .navigation
        default: .custom(targetLayer)
        }
        return RuleCollection(
            name: name,
            summary: summary,
            category: cat,
            mappings: mappings.map { $0.toKeyMapping() },
            isEnabled: isEnabled,
            targetLayer: layer,
            configuration: configuration ?? .list
        )
    }
}

public struct CLIExportedMapping: Codable, Sendable {
    public let input: String
    public let action: KeyAction
    public let shiftedOutput: String?
    public let behavior: MappingBehavior?

    public init(from mapping: KeyMapping) {
        input = mapping.input
        action = mapping.action
        shiftedOutput = mapping.shiftedOutput
        behavior = mapping.behavior
    }

    public func toKeyMapping() -> KeyMapping {
        KeyMapping(input: input, action: action, shiftedOutput: shiftedOutput, behavior: behavior)
    }
}

// MARK: - Karabiner Import Types

public struct CLIKarabinerImportResult: Codable, Sendable {
    public let profileName: String
    public let collections: [CLIExportedCollection]
    public let skippedRules: [CLISkippedRule]
    public let warnings: [String]
}

public struct CLISkippedRule: Codable, Sendable {
    public let description: String
    public let reason: String
}

public struct CLIKarabinerProfile: Codable, Sendable {
    public let name: String
    public let index: Int
    public let isSelected: Bool
}
