import Foundation
import KeyPathCore
import KeyPathRulesCore

/// Snapshot of managed collections' state before a pack was installed.
/// Used to restore previous configuration on uninstall.
public struct PackCollectionSnapshot: Codable, Equatable, Sendable {
    public let packID: String
    public let snapshotDate: Date
    public var entries: [Entry]

    public struct Entry: Codable, Equatable, Sendable {
        public let collectionID: UUID
        public var wasEnabled: Bool
        public var configurationJSON: Data
    }

    public init(packID: String, snapshotDate: Date = Date(), entries: [Entry]) {
        self.packID = packID
        self.snapshotDate = snapshotDate
        self.entries = entries
    }

    // MARK: - Persistence

    private static func snapshotsDirectory(in configDirectory: URL) -> URL {
        configDirectory
            .appendingPathComponent("pack-snapshots", isDirectory: true)
    }

    static func snapshotURL(for packID: String, configDirectory: URL = AppPaths.configDirectory) -> URL {
        snapshotsDirectory(in: configDirectory).appendingPathComponent("\(packID).json")
    }

    static func save(_ snapshot: PackCollectionSnapshot, configDirectory: URL = AppPaths.configDirectory) throws {
        let dir = snapshotsDirectory(in: configDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotURL(for: snapshot.packID, configDirectory: configDirectory), options: .atomic)
    }

    static func load(for packID: String, configDirectory: URL = AppPaths.configDirectory) -> PackCollectionSnapshot? {
        let url = snapshotURL(for: packID, configDirectory: configDirectory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PackCollectionSnapshot.self, from: data)
    }

    /// Mutation paths distinguish an absent legacy snapshot from unreadable data.
    static func loadForMutation(for packID: String, configDirectory: URL = AppPaths.configDirectory) throws -> PackCollectionSnapshot? {
        let data: Data
        do { data = try Data(contentsOf: snapshotURL(for: packID, configDirectory: configDirectory)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        return try JSONDecoder().decode(PackCollectionSnapshot.self, from: data)
    }

    static func remove(for packID: String, configDirectory: URL = AppPaths.configDirectory) {
        try? FileManager.default.removeItem(at: snapshotURL(for: packID, configDirectory: configDirectory))
    }

    // MARK: - Legacy Vallack Migration

    private static func legacyVallackURL(in configDirectory: URL) -> URL {
        configDirectory
            .appendingPathComponent("vallack-system-snapshot.json")
    }

    private struct LegacyVallackSnapshot: Codable {
        var homeRowModsConfig: HomeRowModsConfig?
        var homeRowModsEnabled: Bool
        var homeRowLayerTogglesConfig: HomeRowLayerTogglesConfig?
        var homeRowLayerTogglesEnabled: Bool
    }

    static func loadLegacyVallack(configDirectory: URL = AppPaths.configDirectory) -> PackCollectionSnapshot? {
        try? loadLegacyVallackForMutation(configDirectory: configDirectory)
    }

    static func loadLegacyVallackForMutation(configDirectory: URL = AppPaths.configDirectory) throws -> PackCollectionSnapshot? {
        let data: Data
        do { data = try Data(contentsOf: legacyVallackURL(in: configDirectory)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        let legacy = try JSONDecoder().decode(LegacyVallackSnapshot.self, from: data)

        var entries: [Entry] = []

        let modsConfig: RuleCollectionConfiguration = legacy.homeRowModsConfig.map {
            .homeRowMods($0)
        } ?? .homeRowMods(HomeRowModsConfig())
        let modsJSON = try JSONEncoder().encode(modsConfig)
        entries.append(Entry(
            collectionID: RuleCollectionIdentifier.homeRowMods,
            wasEnabled: legacy.homeRowModsEnabled,
            configurationJSON: modsJSON
        ))

        let togglesConfig: RuleCollectionConfiguration = legacy.homeRowLayerTogglesConfig.map {
            .homeRowLayerToggles($0)
        } ?? .homeRowLayerToggles(HomeRowLayerTogglesConfig())
        let togglesJSON = try JSONEncoder().encode(togglesConfig)
        entries.append(Entry(
            collectionID: RuleCollectionIdentifier.homeRowLayerToggles,
            wasEnabled: legacy.homeRowLayerTogglesEnabled,
            configurationJSON: togglesJSON
        ))

        return PackCollectionSnapshot(
            packID: "com.keypath.pack.vallack-system",
            snapshotDate: Date(),
            entries: entries
        )
    }

    static func removeLegacyVallack(configDirectory: URL = AppPaths.configDirectory) {
        try? removeLegacyVallackIfPresent(configDirectory: configDirectory)
    }

    /// Throwing cleanup for callers that need to report a legacy-file failure.
    static func removeLegacyVallackIfPresent(configDirectory: URL = AppPaths.configDirectory) throws {
        guard FileManager.default.fileExists(atPath: legacyVallackURL(in: configDirectory).path) else {
            return
        }
        try FileManager.default.removeItem(at: legacyVallackURL(in: configDirectory))
    }
}
