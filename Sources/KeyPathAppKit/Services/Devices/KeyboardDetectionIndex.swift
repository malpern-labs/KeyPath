import Foundation
import KeyPathCore

/// Looks up known keyboards by USB Vendor ID and Product ID using a normalized
/// detection index generated from VIA, QMK, and local overrides.
struct KeyboardDetectionIndex: Sendable {
    enum MatchType: String, Codable, Sendable, Equatable {
        case exactVIDPID
        case vendorOnly
    }

    enum Source: String, Codable, Sendable, Equatable {
        case override
        case via
        case qmk
    }

    enum Confidence: String, Codable, Sendable, Equatable {
        case high
        case low
    }

    struct Record: Codable, Sendable, Equatable {
        let matchKey: String
        let matchType: MatchType
        let source: Source
        let confidence: Confidence
        let displayName: String
        let manufacturer: String?
        let qmkPath: String?
        let builtInLayoutId: String?
    }

    struct Match: Sendable, Equatable {
        let record: Record
    }

    private struct IndexFile: Codable {
        let version: String
        let generated: String
        let exactEntries: [Record]
        let vendorFallbackEntries: [Record]
    }

    private struct OverridesFile: Codable {
        struct OverrideExactEntry: Codable {
            let vendorId: String
            let productId: String
            let displayName: String
            let qmkPath: String?
            let builtInLayoutId: String?
        }

        let version: String
        let exactEntries: [OverrideExactEntry]
    }

    private let exactEntries: [String: Record]
    private let vendorFallbackEntries: [String: Record]

    static let bundled = loadBundledIndex()

    init(exactEntries: [Record], vendorFallbackEntries: [Record] = []) {
        self.exactEntries = Dictionary(uniqueKeysWithValues: exactEntries.map { ($0.matchKey, $0) })
        self.vendorFallbackEntries = Dictionary(uniqueKeysWithValues: vendorFallbackEntries.map { ($0.matchKey, $0) })
    }

    private init(exactEntries: [String: Record], vendorFallbackEntries: [String: Record]) {
        self.exactEntries = exactEntries
        self.vendorFallbackEntries = vendorFallbackEntries
    }

    func lookup(vendorID: Int, productID: Int) -> Match? {
        let vidPidKey = Self.formatKey(vendorID: vendorID, productID: productID)
        if let record = exactEntries[vidPidKey] {
            return Match(record: record)
        }

        let vidKey = Self.formatVIDKey(vendorID: vendorID)
        return vendorFallbackEntries[vidKey].map { Match(record: $0) }
    }

    static func formatKey(vendorID: Int, productID: Int) -> String {
        String(format: "%04X:%04X", vendorID, productID)
    }

    static func formatVIDKey(vendorID: Int) -> String {
        String(format: "%04X", vendorID)
    }

    private static func loadBundledIndex() -> Self {
        guard let url = KeyPathAppKitResources.url(forResource: "keyboard-detection-index", withExtension: "json") else {
            AppLogger.shared.warn("⚠️ [KeyboardDetectionIndex] keyboard-detection-index.json not found in bundle")
            return Self(exactEntries: [])
        }

        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(IndexFile.self, from: data)
            let overrideEntries = loadOverrideEntries()
            var exactEntries = Dictionary(uniqueKeysWithValues: file.exactEntries.map { ($0.matchKey, $0) })
            for overrideEntry in overrideEntries {
                exactEntries[overrideEntry.matchKey] = overrideEntry
            }
            let index = Self(
                exactEntries: exactEntries,
                vendorFallbackEntries: Dictionary(uniqueKeysWithValues: file.vendorFallbackEntries.map { ($0.matchKey, $0) })
            )
            AppLogger.shared.log(
                "🔌 [KeyboardDetectionIndex] Loaded \(exactEntries.count) exact and \(file.vendorFallbackEntries.count) vendor fallback entries (v\(file.version))"
            )
            return index
        } catch {
            AppLogger.shared.warn("⚠️ [KeyboardDetectionIndex] Failed to load keyboard-detection-index.json: \(error)")
            return Self(exactEntries: [])
        }
    }

    private static func loadOverrideEntries() -> [Record] {
        guard let url = KeyPathAppKitResources.url(forResource: "keyboard-detection-overrides", withExtension: "json") else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(OverridesFile.self, from: data)
            return file.exactEntries.compactMap { entry in
                guard let vendorID = parseHex(entry.vendorId),
                      let productID = parseHex(entry.productId)
                else {
                    AppLogger.shared.warn("⚠️ [KeyboardDetectionIndex] Skipping invalid override entry \(entry.vendorId):\(entry.productId)")
                    return nil
                }

                return Record(
                    matchKey: formatKey(vendorID: vendorID, productID: productID),
                    matchType: .exactVIDPID,
                    source: .override,
                    confidence: .high,
                    displayName: entry.displayName,
                    manufacturer: nil,
                    qmkPath: entry.qmkPath,
                    builtInLayoutId: entry.builtInLayoutId
                )
            }
        } catch {
            AppLogger.shared.warn("⚠️ [KeyboardDetectionIndex] Failed to load keyboard-detection-overrides.json: \(error)")
            return []
        }
    }

    private static func parseHex(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased().hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        return Int(normalized, radix: 16)
    }
}
