import Foundation

package struct CLIPackCatalog: Sendable {
    private let installedPackTracker: InstalledPackTracker

    package init(installedPackTracker: InstalledPackTracker = .shared) {
        self.installedPackTracker = installedPackTracker
    }

    /// Previous user-facing names that remain accepted by the CLI after a pack
    /// receives a clearer display name. Pack IDs remain the durable identity.
    private static let legacyNamesByPackID = [
        PackRegistry.vallackSystem.id: ["Ben Vallack Nav"]
    ]

    package func listPacks() async -> [CLIPack] {
        let allPacks = PackRegistry.starterKit
        let installed = await installedPackTracker.allInstalled()
        let installedMap = Dictionary(uniqueKeysWithValues: installed.map { ($0.packID, $0) })

        return allPacks.map { pack in
            let record = installedMap[pack.id]
            return CLIPack(
                id: pack.id,
                name: pack.name,
                version: pack.version,
                category: pack.category,
                tagline: pack.tagline,
                isInstalled: record != nil,
                installedAt: record?.installedAt
            )
        }
    }

    package func showPack(nameOrId: String) async throws -> CLIPackDetail? {
        guard let pack = try Self.resolvePack(nameOrId: nameOrId) else { return nil }
        let record = await installedPackTracker.record(for: pack.id)
        return CLIPackDetail(from: pack, record: record)
    }

    package static func resolvePack(nameOrId: String) throws -> Pack? {
        let allPacks = PackRegistry.starterKit

        if let pack = allPacks.first(where: { $0.id == nameOrId }) {
            return pack
        }

        let prefix = "com.keypath.pack."
        let slugMatches = allPacks.filter { pack in
            guard pack.id.hasPrefix(prefix) else { return false }
            let slug = String(pack.id.dropFirst(prefix.count))
            return slug.caseInsensitiveCompare(nameOrId) == .orderedSame
        }
        if slugMatches.count == 1 { return slugMatches[0] }
        if slugMatches.count > 1 {
            throw AmbiguousPackMatch(
                query: nameOrId,
                matches: slugMatches.map { .init(name: $0.name, id: $0.id) },
                hint: "Multiple packs match this slug. Use the full ID to disambiguate."
            )
        }

        let exactMatches = allPacks.filter {
            $0.name.caseInsensitiveCompare(nameOrId) == .orderedSame
        }
        if exactMatches.count == 1 { return exactMatches[0] }
        if exactMatches.count > 1 {
            throw AmbiguousPackMatch(
                query: nameOrId,
                matches: exactMatches.map { .init(name: $0.name, id: $0.id) },
                hint: "Multiple packs share this name. Use the ID to disambiguate."
            )
        }

        let substringMatches = allPacks.filter { pack in
            pack.name.localizedCaseInsensitiveContains(nameOrId)
                || Self.legacyNamesByPackID[pack.id, default: []].contains {
                    $0.localizedCaseInsensitiveContains(nameOrId)
                }
        }
        if substringMatches.count == 1 { return substringMatches[0] }
        if substringMatches.count > 1 {
            throw AmbiguousPackMatch(
                query: nameOrId,
                matches: substringMatches.map { .init(name: $0.name, id: $0.id) }
            )
        }

        return nil
    }
}

public struct CLIPack: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let category: String
    public let tagline: String
    public let isInstalled: Bool
    public let installedAt: Date?

    package init(id: String, name: String, version: String, category: String, tagline: String, isInstalled: Bool, installedAt: Date?) {
        self.id = id
        self.name = name
        self.version = version
        self.category = category
        self.tagline = tagline
        self.isInstalled = isInstalled
        self.installedAt = installedAt
    }
}

public struct CLIPackDetail: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let category: String
    public let tagline: String
    public let shortDescription: String
    public let longDescription: String
    public let author: String
    public let isInstalled: Bool
    public let installedAt: Date?
    public let visualOnly: Bool
    public let bindings: [CLIPackBinding]
    public let quickSettings: [CLIPackQuickSetting]
    public let dependencies: [CLIPackDep]
    public let quickSettingValues: [String: Int]

    public init(from pack: Pack, record: InstalledPackRecord?) {
        id = pack.id
        name = pack.name
        version = pack.version
        category = pack.category
        tagline = pack.tagline
        shortDescription = pack.shortDescription
        longDescription = pack.longDescription
        author = pack.author
        isInstalled = record != nil
        installedAt = record?.installedAt
        visualOnly = pack.visualOnly
        bindings = pack.bindings.map { CLIPackBinding(input: $0.input, output: $0.output, holdOutput: $0.holdOutput) }
        quickSettings = pack.quickSettings.map { CLIPackQuickSetting(from: $0) }
        dependencies = pack.dependencies.map { CLIPackDep(from: $0) }
        quickSettingValues = record?.quickSettingValues ?? [:]
    }
}

public struct CLIPackBinding: Codable, Sendable {
    public let input: String
    public let output: String
    public let holdOutput: String?

    package init(input: String, output: String, holdOutput: String?) {
        self.input = input
        self.output = output
        self.holdOutput = holdOutput
    }
}

public struct CLIPackQuickSetting: Codable, Sendable {
    public let id: String
    public let label: String
    public let defaultValue: Int
    public let min: Int
    public let max: Int
    public let step: Int
    public let unitSuffix: String

    public init(from setting: PackQuickSetting) {
        id = setting.id
        label = setting.label
        switch setting.kind {
        case let .slider(defaultValue, min, max, step, unitSuffix):
            self.defaultValue = defaultValue
            self.min = min
            self.max = max
            self.step = step
            self.unitSuffix = unitSuffix
        }
    }
}

public struct CLIPackDep: Codable, Sendable {
    public let packID: String
    public let kind: String
    public let description: String?

    public init(from dep: PackDependency) {
        packID = dep.packID
        kind = dep.kind.rawValue
        description = dep.description
    }
}

public struct AmbiguousPackMatch: Error, CustomStringConvertible {
    public struct Match: Sendable {
        public let name: String
        public let id: String

        package init(name: String, id: String) {
            self.name = name
            self.id = id
        }
    }

    public let query: String
    public let matches: [Match]
    public let hint: String

    public init(query: String, matches: [Match], hint: String = "Use the full name or ID to disambiguate.") {
        self.query = query
        self.matches = matches
        self.hint = hint
    }

    public var description: String {
        var lines = ["Found \(matches.count) packs matching \"\(query)\":"]
        for match in matches {
            lines.append("  - \(match.name) (id: \(match.id))")
        }
        lines.append(hint)
        return lines.joined(separator: "\n")
    }
}
