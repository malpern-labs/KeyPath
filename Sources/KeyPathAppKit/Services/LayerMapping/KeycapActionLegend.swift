import Foundation
import KeyPathRulesCore

/// One action assigned to a key on the layer being displayed.
struct KeycapActionLegend: Equatable, Sendable {
    enum Trigger: Equatable, Sendable {
        case tap
        case hold
        case repeatedTap(Int)
    }

    static let visibleLimit = 4

    let trigger: Trigger
    let action: KeyAction

    static func actions(for behavior: MappingBehavior) -> [Self] {
        switch behavior {
        case let .dualRole(dualRole):
            [
                Self(trigger: .tap, action: dualRole.tapAction),
                Self(trigger: .hold, action: dualRole.holdAction)
            ]
        case let .tapOrTapDance(.tapDance(dance)):
            dance.steps.enumerated().map { index, step in
                Self(trigger: index == 0 ? .tap : .repeatedTap(index + 1), action: step.action)
            }
        default:
            []
        }
    }

    /// Momentary and toggled layers are still represented as raw actions in
    /// the config model. Only recognize the layer forms the generator emits.
    var targetLayer: String? {
        if case let .activateLayer(name) = action { return name }
        guard case let .rawKanata(expression) = action,
              expression.hasPrefix("("), expression.hasSuffix(")")
        else { return nil }
        let tokens = expression.dropFirst().dropLast().split(whereSeparator: \.isWhitespace)
        guard tokens.count == 2,
              ["layer-while-held", "layer-toggle"].contains(tokens[0])
        else { return nil }
        return String(tokens[1])
    }

    var hoverLine: String {
        "\(triggerName) — \(actionName)"
    }

    var triggerName: String {
        switch trigger {
        case .tap: String(localized: "Tap")
        case .hold: String(localized: "Hold")
        case let .repeatedTap(count): String(localized: "Tap \(count) times", bundle: .module, comment: "Keycap hover trigger for a tap dance step")
        }
    }

    var actionName: String {
        if let targetLayer {
            String(localized: "Activate \(LayerInfo.displayName(for: targetLayer)) layer")
        } else {
            hoverActionName
        }
    }

    private var hoverActionName: String {
        switch action {
        case let .keystroke(key):
            action.commonDisplayInfo?.label ?? KeyDisplayFormatter.formatSequence(key)
        case let .rawKanata(expression):
            action.commonDisplayInfo?.label ?? (
                expression.hasPrefix("(") ? String(localized: "Custom action", bundle: .module) : KeyDisplayFormatter.formatSequence(expression)
            )
        default:
            action.commonDisplayInfo?.label ?? action.displayName
        }
    }

    var glyph: String {
        if let targetLayer { return LayerInfo.displayName(for: targetLayer) }
        switch action {
        case let .keystroke(key):
            return KeyDisplayFormatter.formatSequence(key)
        case let .rawKanata(expression) where !expression.hasPrefix("("):
            return KeyDisplayFormatter.formatSequence(expression)
        default:
            return action.commonDisplayInfo?.label ?? "…"
        }
    }

    var symbol: String? {
        if let targetLayer { return LayerInfo.iconName(for: targetLayer) }
        switch action {
        case .keystroke, .rawKanata:
            return action.commonDisplayInfo?.icon
        default:
            return action.commonDisplayInfo?.icon ?? "ellipsis"
        }
    }
}
