import Foundation
import Synchronization

/// What the session runtime can emit, in one place.
///
/// The answer comes from the Kanata host
/// bridge, which applies the same output rule as session validation (keyboard
/// page only, within `SessionKeyMap`). Swift keeps no list of its own, so the
/// UI, catalog and pack checks cannot drift from what the runtime accepts.
/// See docs/architecture/rules-admission-review.md §4.1 (phase 1).
public final class BackendCapabilityProfile: Sendable {
    public static var shared: BackendCapabilityProfile {
        #if DEBUG
            if let override = testOverride { return override }
        #endif
        return live
    }

    #if DEBUG
        /// A fixture follows the test task and its children. Other tests and
        /// production tasks continue to use the real bridge.
        @TaskLocal package static var testOverride: BackendCapabilityProfile?
    #endif

    private static let live = BackendCapabilityProfile { key in
        KanataHostBridge.sessionOutputKeySupported(
            runtimeHost: .current(), keyName: key, supportedUsages: SessionKeyMap.sessionOutputUsages
        )
    }

    private let query: @Sendable (String) -> Bool?
    private struct Cache: Sendable {
        var emission: [String: Bool] = [:]
        var known: [String: Bool] = [:]
    }

    private let cache = Mutex(Cache())

    /// `query` answers for one base key name: true/false, or nil for "no answer".
    public init(query: @escaping @Sendable (String) -> Bool?) {
        self.query = query
    }

    /// Whether a Kanata keystroke output (optionally with modifier prefixes such
    /// as `C-S-` or `M-`) can be emitted by the session runtime.
    public func canEmit(kanataKey: String) -> Bool {
        let base = Self.baseKey(of: kanataKey)
        guard !base.isEmpty else { return true }
        if let known = cache.withLock({ $0.emission[base] }) { return known }
        // No answer (old bridge, or a name Kanata does not know): keep the
        // previous behaviour, which refused only consumer-page keys. Session
        // validation remains the backstop for anything else.
        let answer = query(base) ?? !Self.fallbackConsumerKeys.contains(base)
        cache.withLock { $0.emission[base] = answer }
        return answer
    }

    /// Whether Kanata knows `name` as a key at all (whatever the backend can
    /// emit): true/false from the bridge, nil when there is no bridge to ask.
    /// The generator uses this to tell a key name (`f21`, `calc`) from a word
    /// to type (`hello`), instead of a hand-kept list that drifts from Kanata.
    public func knowsKey(_ name: String) -> Bool? {
        let key = name.lowercased()
        guard !key.isEmpty else { return nil }
        if let known = cache.withLock({ $0.known[key] }) { return known }
        let answer: Bool
        if query(key) != nil {
            answer = true
        } else if query("a") != nil {
            answer = false // the bridge answers, so nil meant "not a Kanata key"
        } else {
            return nil // no bridge: the caller keeps its own fallback
        }
        cache.withLock { $0.known[key] = answer }
        return answer
    }

    /// Strip Kanata modifier prefixes: `C-S-n` → `n`, `RA-x` → `x`, `C-down` → `down`.
    public static func baseKey(of output: String) -> String {
        var key = Substring(output.trimmingCharacters(in: .whitespaces))
        let prefixes = ["RA-", "RC-", "RS-", "RM-", "AG-", "A-", "C-", "S-", "M-"]
        while let prefix = prefixes.first(where: { key.hasPrefix($0) && key.count > $0.count }) {
            key = key.dropFirst(prefix.count)
        }
        return key.lowercased()
    }

    /// Used only when the bridge cannot answer, so an older or missing bridge
    /// behaves as KeyPath did before this profile existed.
    static let fallbackConsumerKeys: Set<String> = [
        "pp", "next", "prev", "mute", "volu", "vold", "voldwn", "brup", "brdn", "brdown"
    ]
}

public extension SessionKeyMap {
    /// The keyboard-page usages the session posts as outputs, as passed to the
    /// bridge. Caps (57) is excluded here; the bridge adds native Caps output.
    static var sessionOutputUsages: [UInt32] {
        keyCodeToUsage.values.filter { $0 != 57 }.sorted()
    }
}
