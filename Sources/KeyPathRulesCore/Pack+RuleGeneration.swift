import Foundation

package extension Pack {
    /// Convert a pack's binding templates into concrete CustomRules tagged
    /// with the pack's id.
    func renderBindings(quickSettings: [String: Int]) -> [CustomRule] {
        // Hold timeout from quick settings, falling back to home-row-mod
        // friendly default. Only used by templates that have a hold output.
        let holdMs = quickSettings["holdTimeout"] ?? 200

        return bindings.map { template in
            let title = template.title
                ?? "\(name) · \(template.input.uppercased())"

            // If the template has a hold output, attach a dual-role behavior
            // (tap-hold with `activateHoldOnOtherKey`, matching the
            // Kanata tap-hold-press variant used by the Home-Row Mods
            // convenience factory). Otherwise this is a simple remap.
            let behavior: MappingBehavior? = template.holdOutput.map { holdOutput in
                .dualRole(
                    DualRoleBehavior(
                        tapAction: KanataBehaviorRenderer.parseActionString(template.output),
                        holdAction: KanataBehaviorRenderer.parseActionString(holdOutput),
                        tapTimeout: holdMs,
                        holdTimeout: holdMs,
                        activateHoldOnOtherKey: true,
                        quickTap: false
                    )
                )
            }

            return CustomRule(
                id: UUID(),
                title: title,
                input: template.input,
                action: .keystroke(key: template.output),
                shiftedOutput: nil,
                isEnabled: true,
                notes: template.notes,
                createdAt: Date(),
                behavior: behavior,
                targetLayer: .base,
                deviceOverrides: nil,
                packSource: id
            )
        }
    }

    func resolvedQuickSettings(overrides: [String: Int]) -> [String: Int] {
        var resolved: [String: Int] = [:]
        for setting in quickSettings {
            if let override = overrides[setting.id] {
                // Clamp to the pack-defined slider bounds so a malformed
                // override (negative, out-of-range, serialized garbage) can't
                // produce a kanata config with nonsense timing values.
                resolved[setting.id] = clamp(override, to: setting.kind)
            } else if let defaultVal = setting.defaultSliderValue {
                resolved[setting.id] = defaultVal
            }
        }
        return resolved
    }

    private func clamp(_ value: Int, to kind: PackQuickSetting.Kind) -> Int {
        switch kind {
        case let .slider(_, minValue, maxValue, _, _):
            min(max(value, minValue), maxValue)
        }
    }
}
