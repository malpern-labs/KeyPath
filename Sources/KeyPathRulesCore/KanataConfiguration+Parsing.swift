import CryptoKit
import Foundation
import KeyPathCore

extension KanataConfiguration {
    /// Rebuild the editor’s view of an existing config. Worker eligibility
    /// still comes from the Kanata session parser.
    package static func parse(_ content: String, path: String, lastModified: Date) throws -> Self {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeyPathError.configuration(.invalidFormat(reason: String(localized: "Configuration content is empty")))
        }

        // Extract key mappings from content (simplified - could be enhanced)
        let keyMappings = extractKeyMappingsFromContent(content)
        let chordGroups = KanataDefchordsParser.parseGroups(from: content)

        if !chordGroups.isEmpty {
            let knownGroups = Set(chordGroups.map(\.name))
            let referencedGroups = KanataDefchordsParser.referencedChordGroups(in: keyMappings)
            let missing = referencedGroups.subtracting(knownGroups)
            if !missing.isEmpty {
                AppLogger.shared.warn(
                    "⚠️ [ConfigService] Chord group references missing definitions: \(missing.sorted().joined(separator: ", "))"
                )
            }
        }

        // Parse sequences from config
        let sequences = KanataDefseqParser.parseSequences(from: content)

        return Self(
            content: content,
            keyMappings: keyMappings,
            lastModified: lastModified,
            path: path,
            chordGroups: chordGroups,
            sequences: sequences
        )
    }

    /// Extract key mappings from Kanata configuration content
    private static func extractKeyMappingsFromContent(_ configContent: String) -> [KeyMapping] {
        var mappings: [KeyMapping] = []
        let lines = configContent.components(separatedBy: .newlines)

        var inDefsrc = false
        var inDeflayer = false
        var srcKeys: [String] = []
        var layerKeys: [String] = []

        for line in lines {
            let trimmed = KanataConfigTokenizer.stripInlineComment(line)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("(defsrc") {
                inDefsrc = true
                inDeflayer = false
                continue
            } else if trimmed.hasPrefix("(deflayer") {
                inDefsrc = false
                inDeflayer = true
                continue
            } else if trimmed == ")" {
                inDefsrc = false
                inDeflayer = false
                continue
            }

            if inDefsrc, !trimmed.isEmpty, !trimmed.hasPrefix(";") {
                srcKeys.append(contentsOf: KanataConfigTokenizer.tokenize(trimmed))
            } else if inDeflayer, !trimmed.isEmpty, !trimmed.hasPrefix(";") {
                layerKeys.append(contentsOf: KanataConfigTokenizer.tokenize(trimmed))
            }
        }

        // Match up src and layer keys, filtering out invalid keys
        var tempMappings: [KeyMapping] = []
        for (index, srcKey) in srcKeys.enumerated() where index < layerKeys.count {
            // Skip obviously invalid keys
            if srcKey != "invalid", !srcKey.isEmpty {
                let layerOutput = layerKeys[index]
                let action: KeyAction = layerOutput.hasPrefix("(") ? .rawKanata(layerOutput) : .keystroke(key: layerOutput)
                tempMappings.append(KeyMapping(input: srcKey, action: action))
            }
        }

        // Deduplicate mappings - keep only the last mapping for each input key
        var seenInputs: Set<String> = []
        for mapping in tempMappings.reversed() where !seenInputs.contains(mapping.input) {
            mappings.insert(mapping, at: 0)
            seenInputs.insert(mapping.input)
        }

        AppLogger.shared.log(
            "🔍 [Parse] Found \(srcKeys.count) src keys, \(layerKeys.count) layer keys, deduplicated to \(mappings.count) unique mappings"
        )
        return mappings
    }
}

package extension KanataConfiguration {
    static func managedFingerprint(_ content: String) -> String {
        let normalized = content.components(separatedBy: "\n")
            .filter { !$0.hasPrefix(";; Generated: ") }
            .joined(separator: "\n")
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
