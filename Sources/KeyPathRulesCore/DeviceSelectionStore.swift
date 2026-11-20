import Foundation
import KeyPathCore
import Synchronization

/// Thread-safe synchronous cache for UI and service-layer device snapshots.
/// Configuration rendering receives a point-in-time `DeviceGenerationInput`
/// instead of consulting this mutable cache directly.
package final class DeviceSelectionCache: Sendable {
    package static let shared = DeviceSelectionCache()

    private struct State {
        var selections: [String: DeviceSelection] = [:]
        var connectedDevices: [ConnectedDevice] = []
    }

    private let state = Mutex(State())

    package init() {}

    /// Update the cache with the latest selections from the store.
    package func update(_ newSelections: [DeviceSelection]) {
        let selections = Dictionary(newSelections.map { ($0.hash, $0) }, uniquingKeysWith: { _, new in new })
        state.withLock { $0.selections = selections }
    }

    /// Update the cached connected devices (from kanata --list).
    package func updateConnectedDevices(_ devices: [ConnectedDevice]) {
        state.withLock { $0.connectedDevices = devices }
    }

    /// Get the cached connected devices. Returns empty if never populated.
    package func getConnectedDevices() -> [ConnectedDevice] {
        state.withLock { $0.connectedDevices }
    }

    /// Check if a device hash is enabled. Devices not in the cache default to enabled.
    package func isEnabled(hash: String) -> Bool {
        state.withLock { $0.selections[hash]?.isEnabled ?? true }
    }

    /// Get all cached selections.
    package func allSelections() -> [DeviceSelection] {
        state.withLock { Array($0.selections.values) }
    }

    /// Reset all cached state. Used in tests to avoid pollution.
    package func reset() {
        state.withLock { $0 = State() }
    }
}

/// Actor-based store for device selection persistence.
/// File: `~/.config/keypath/DeviceSelection.json`
package actor DeviceSelectionStore {
    package static let shared = DeviceSelectionStore()

    private static var defaultFileURL: URL {
        let directory = TestEnvironment.isRunningTests
            ? AppPaths.configDirectory
            : URL(fileURLWithPath: WizardSystemPaths.userConfigDirectory, isDirectory: true)
        return directory.appendingPathComponent("DeviceSelection.json")
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let fileManager: FileManager
    private let cache: DeviceSelectionCache

    package init(
        fileURL: URL? = nil,
        fileManager: FileManager = Foundation.FileManager(),
        cache: DeviceSelectionCache = .shared
    ) {
        self.fileManager = fileManager
        self.cache = cache
        self.fileURL = fileURL ?? Self.defaultFileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// The transaction owner journals this exact file with the generated
    /// configuration. Keeping the URL here prevents a second path convention.
    package var persistenceURL: URL {
        fileURL
    }

    package func loadSelections() -> [DeviceSelection] {
        AppLogger.shared.log("📂 [DeviceSelectionStore] loadSelections from: \(fileURL.path)")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            AppLogger.shared.log("📂 [DeviceSelectionStore] File does not exist, returning []")
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let selections = try decoder.decode([DeviceSelection].self, from: data)
            AppLogger.shared.log("📂 [DeviceSelectionStore] Loaded \(selections.count) device selection(s)")
            return selections
        } catch {
            AppLogger.shared.log("⚠️ [DeviceSelectionStore] Failed to load selections: \(error)")
            return []
        }
    }

    /// Mutation paths must not treat corrupt selection data as an empty choice:
    /// doing so could make a later rollback or apply target every keyboard.
    package func loadForMutation() throws -> [DeviceSelection] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([DeviceSelection].self, from: data)
    }

    package func encodedSelections(_ selections: [DeviceSelection]) throws -> Data {
        try encoder.encode(selections)
    }

    /// Cache publication happens only after the corresponding durable write has
    /// settled. Candidate data must never leak into synchronous generation.
    package func publishSelectionsToCache(_ selections: [DeviceSelection]) {
        cache.update(selections)
    }

    /// Capture all device-dependent generation inputs from the same injected
    /// cache used by this store. A retained transaction must not mix its
    /// candidate selection with the process-global device cache.
    package func generationInput(for selections: [DeviceSelection]) -> DeviceGenerationInput {
        DeviceGenerationInput(selections: selections, connectedDevices: cache.getConnectedDevices())
    }

    package func saveSelections(_ selections: [DeviceSelection]) throws {
        AppLogger.shared.log("💾 [DeviceSelectionStore] saveSelections: \(selections.count) device(s) to \(fileURL.path)")
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(selections)
        try data.write(to: fileURL, options: .atomic)
        // Sync to cache for synchronous config generator reads
        cache.update(selections)
        AppLogger.shared.log("💾 [DeviceSelectionStore] Saved \(data.count) bytes")
    }

    /// Load selections and sync to cache. Call at startup.
    package func syncToCache() {
        let selections = loadSelections()
        cache.update(selections)
    }

    /// Synchronously prime the shared cache before startup tasks can regenerate config.
    package static func primeCacheFromDisk(
        fileURL: URL? = nil,
        cache: DeviceSelectionCache = .shared
    ) {
        let fileURL = fileURL ?? Self.defaultFileURL

        let fileManager = Foundation.FileManager()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            cache.update([])
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: fileURL)
            let selections = try decoder.decode([DeviceSelection].self, from: data)
            cache.update(selections)
            AppLogger.shared.log("📂 [DeviceSelectionStore] Primed shared cache with \(selections.count) device selection(s)")
        } catch {
            cache.update([])
            AppLogger.shared.warn("⚠️ [DeviceSelectionStore] Failed to prime shared cache: \(error)")
        }
    }
}

#if DEBUG
    package extension DeviceSelectionStore {
        nonisolated static func testStore(
            at url: URL,
            cache: DeviceSelectionCache = DeviceSelectionCache()
        ) -> DeviceSelectionStore {
            DeviceSelectionStore(fileURL: url, cache: cache)
        }
    }
#endif
