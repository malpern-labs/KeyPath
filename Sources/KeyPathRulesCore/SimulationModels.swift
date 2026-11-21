import Foundation

// MARK: - Input Models

/// A key tap event to simulate (press + delay + release)
package struct SimulatorKeyTap: Identifiable, Equatable, Hashable, Sendable {
    package let id = UUID()
    package let kanataKey: String // e.g., "a", "lctl", "spc", "lsft"
    package let displayLabel: String // e.g., "A", "Ctrl", "Space", "Shift"
    package let delayAfterMs: UInt64 // Default: 200ms for tap, 400ms for hold
    package let isHold: Bool // Whether this is a long-press (hold) vs tap

    package init(kanataKey: String, displayLabel: String, delayAfterMs: UInt64, isHold: Bool = false) {
        self.kanataKey = kanataKey
        self.displayLabel = displayLabel
        self.delayAfterMs = delayAfterMs
        self.isHold = isHold
    }

    package static func == (lhs: SimulatorKeyTap, rhs: SimulatorKeyTap) -> Bool {
        lhs.id == rhs.id
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Output Models (matching Kanata JSON schema)

/// Complete simulation result from kanata-simulator --json
package struct SimulationResult: Codable, Equatable, Sendable {
    package let events: [SimEvent]
    package let finalLayer: String?
    package let durationMs: UInt64

    package init(events: [SimEvent], finalLayer: String?, durationMs: UInt64) {
        self.events = events
        self.finalLayer = finalLayer
        self.durationMs = durationMs
    }

    enum CodingKeys: String, CodingKey {
        case events
        case finalLayer
        case durationMs = "duration_ms"
    }
}

/// Structured simulation event from Kanata
/// Uses internally-tagged enum format: {"type": "input", "t": 0, ...}
package enum SimEvent: Codable, Equatable, Sendable {
    case input(t: UInt64, action: SimKeyAction, key: String)
    case output(t: UInt64, action: SimKeyAction, key: String)
    case layer(t: UInt64, from: String, to: String)
    case unicode(t: UInt64, char: String)
    case mouse(t: UInt64, action: SimMouseAction, data: String)

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case type, t, action, key, from, to, char, data
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "input":
            let t = try container.decode(UInt64.self, forKey: .t)
            let action = try container.decode(SimKeyAction.self, forKey: .action)
            let key = try container.decode(String.self, forKey: .key)
            self = .input(t: t, action: action, key: key)

        case "output":
            let t = try container.decode(UInt64.self, forKey: .t)
            let action = try container.decode(SimKeyAction.self, forKey: .action)
            let key = try container.decode(String.self, forKey: .key)
            self = .output(t: t, action: action, key: key)

        case "layer":
            let t = try container.decode(UInt64.self, forKey: .t)
            let from = try container.decode(String.self, forKey: .from)
            let to = try container.decode(String.self, forKey: .to)
            self = .layer(t: t, from: from, to: to)

        case "unicode":
            let t = try container.decode(UInt64.self, forKey: .t)
            let char = try container.decode(String.self, forKey: .char)
            self = .unicode(t: t, char: char)

        case "mouse":
            let t = try container.decode(UInt64.self, forKey: .t)
            let action = try container.decode(SimMouseAction.self, forKey: .action)
            let data = try container.decode(String.self, forKey: .data)
            self = .mouse(t: t, action: action, data: data)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown event type: \(type)"
            )
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .input(t, action, key):
            try container.encode("input", forKey: .type)
            try container.encode(t, forKey: .t)
            try container.encode(action, forKey: .action)
            try container.encode(key, forKey: .key)

        case let .output(t, action, key):
            try container.encode("output", forKey: .type)
            try container.encode(t, forKey: .t)
            try container.encode(action, forKey: .action)
            try container.encode(key, forKey: .key)

        case let .layer(t, from, to):
            try container.encode("layer", forKey: .type)
            try container.encode(t, forKey: .t)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)

        case let .unicode(t, char):
            try container.encode("unicode", forKey: .type)
            try container.encode(t, forKey: .t)
            try container.encode(char, forKey: .char)

        case let .mouse(t, action, data):
            try container.encode("mouse", forKey: .type)
            try container.encode(t, forKey: .t)
            try container.encode(action, forKey: .action)
            try container.encode(data, forKey: .data)
        }
    }

    // MARK: - Convenience

    /// Timestamp in milliseconds from simulation start
    package var timestamp: UInt64 {
        switch self {
        case let .input(t, _, _): t
        case let .output(t, _, _): t
        case let .layer(t, _, _): t
        case let .unicode(t, _): t
        case let .mouse(t, _, _): t
        }
    }

    /// Human-readable description for display
    package var displayDescription: String {
        switch self {
        case let .input(_, action, key):
            "\(action.symbol)\(key)"
        case let .output(_, action, key):
            "\(action.symbol)\(key)"
        case let .layer(_, from, to):
            "\(from) → \(to)"
        case let .unicode(_, char):
            "'\(char)'"
        case let .mouse(_, action, data):
            "\(action.rawValue): \(data)"
        }
    }

    /// Whether this is an input event (user pressed)
    package var isInput: Bool {
        if case .input = self { return true }
        return false
    }

    /// Whether this is an output event (Kanata would emit)
    package var isOutput: Bool {
        if case .output = self { return true }
        return false
    }

    /// Whether this is a layer change
    package var isLayerChange: Bool {
        if case .layer = self { return true }
        return false
    }
}

/// Key action type matching Kanata's SimKeyAction
package enum SimKeyAction: String, Codable, Equatable, Sendable {
    case press
    case release
    case `repeat`

    /// Symbol for display (↓ for press, ↑ for release, ⟳ for repeat)
    package var symbol: String {
        switch self {
        case .press: "↓"
        case .release: "↑"
        case .repeat: "⟳"
        }
    }
}

/// Mouse action type matching Kanata's SimMouseAction
package enum SimMouseAction: String, Codable, Equatable, Sendable {
    case click
    case release
    case move
    case scroll
}

// MARK: - Errors

package enum SimulatorError: Error, LocalizedError {
    case featureDisabled
    case simulatorNotFound
    case configNotFound(String)
    case processFailedWithCode(Int, String)
    case invalidJSON(String)

    package var errorDescription: String? {
        switch self {
        case .featureDisabled:
            String(localized: "Simulator is disabled by feature flag")
        case .simulatorNotFound:
            String(localized: "Simulator binary not found in app bundle")
        case let .configNotFound(path):
            String(localized: "Config not found: \(path)")
        case let .processFailedWithCode(code, msg):
            String(localized: "Simulator failed (\(String(code))): \(msg)")
        case let .invalidJSON(msg):
            String(localized: "Invalid JSON output: \(msg)")
        }
    }
}
