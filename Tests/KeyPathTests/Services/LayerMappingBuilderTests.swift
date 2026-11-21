@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import Testing

@Suite("LayerMappingBuilder")
struct LayerMappingBuilderTests {
    @Test("Tap dance legends are ordered and scoped to the displayed layer")
    func tapDanceLegendsFollowDisplayedLayer() throws {
        let dance = TapDanceBehavior(
            windowMs: 500,
            steps: ["left", "down", "up", "right", "home"].map {
                TapDanceStep(label: $0, action: .keystroke(key: $0))
            }
        )
        let rule = CustomRule(
            input: "h",
            action: .keystroke(key: "left"),
            behavior: .tapOrTapDance(.tapDance(dance)),
            targetLayer: .custom("nav")
        )
        // The one-tap simulator can miss outputs when the dance window is long.
        let fallback = LayerKeyInfo.transparent(fallbackLabel: "H")
        let base = LayerMappingBuilder.enrichWithActionLegends(
            mapping: [4: fallback], customRules: [rule], ruleCollections: [], currentLayerName: "Base"
        )
        #expect(base[4] == fallback)

        let nav = LayerMappingBuilder.enrichWithActionLegends(
            mapping: [4: fallback], customRules: [rule], ruleCollections: [], currentLayerName: "Nav"
        )
        let legends = try #require(nav[4]?.actionLegends)
        #expect(legends.map(\.trigger) == [.tap, .repeatedTap(2), .repeatedTap(3), .repeatedTap(4), .repeatedTap(5)])
        #expect(legends.prefix(KeycapActionLegend.visibleLimit).map(\.glyph) == ["←", "↓", "↑", "→"])
        #expect(nav[4]?.isTransparent == fallback.isTransparent)
        #expect(nav[4]?.outputKeyCode == fallback.outputKeyCode)
    }

    @Test("Disabled overrides and punctuation aliases preserve the effective hold legend")
    func dualRoleLegendsResolvePunctuationAliases() throws {
        let behavior = MappingBehavior.dualRole(.homeRowMod(letter: "semicolon", modifier: "lctl"))
        let rule = CustomRule(input: "scln", action: .keystroke(key: "semicolon"), behavior: behavior)
        let disabled = CustomRule(input: ";", action: .keystroke(key: "a"), isEnabled: false)
        let layer = LayerMappingBuilder.enrichWithActionLegends(
            mapping: [41: .mapped(displayLabel: ";", outputKey: ";", outputKeyCode: 41)],
            customRules: [disabled, rule],
            ruleCollections: [],
            currentLayerName: "base"
        )
        let legends = try #require(layer[41]?.actionLegends)
        #expect(legends.map(\.trigger) == [.tap, .hold])
        #expect(legends.map(\.glyph) == [";", "⌃"])
        let keyInfo = try #require(layer[41])
        #expect(OverlayKeyboardView.shouldHideFloatingLabel(for: keyInfo, baseLabel: ";", inputKeyName: ";"))
        #expect(!OverlayKeyboardView.shouldHideFloatingLabel(
            for: keyInfo, baseLabel: ";", inputKeyName: ";", showsActionLegends: false
        ))
    }

    @Test("A layer activator displays its tap and hold on its source layer")
    func baseActivatorUsesItsSourceLayer() throws {
        let nav = RuleCollection(
            name: "Navigation",
            summary: "",
            category: .custom,
            mappings: [],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )
        let competingRule = CustomRule(input: "spc", action: .keystroke(key: "esc"))
        let key = LayerKeyInfo.layerSwitch(displayLabel: "Space")

        let base = LayerMappingBuilder.enrichWithActionLegends(
            mapping: [49: key], customRules: [competingRule], ruleCollections: [nav], currentLayerName: "base"
        )
        let legends = try #require(base[49]?.actionLegends)
        #expect(legends.map(\.trigger) == [.tap, .hold])
        #expect(legends.map(\.action) == [.keystroke(key: "spc"), .activateLayer(name: nav.targetLayer.kanataName)])
        #expect(base[49]?.isLayerSwitch == true)

        let target = LayerMappingBuilder.enrichWithActionLegends(
            mapping: [49: key], customRules: [competingRule], ruleCollections: [nav], currentLayerName: nav.targetLayer.kanataName
        )
        #expect(target[49] == key)
    }

    // MARK: - mergeAugmentation

    @Test("vimLabel preserved from original through merge")
    func mergePreservesVimLabel() {
        let original = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123,
            vimLabel: "←"
        )
        let augmented = LayerKeyInfo(
            displayLabel: "h — left",
            outputKey: "left",
            outputKeyCode: 123,
            isTransparent: false,
            isLayerSwitch: false
        )

        let result = LayerMappingBuilder.mergeAugmentation(augmented, with: original)

        #expect(result.vimLabel == "←")
        #expect(result.displayLabel == "←")
    }

    @Test("collectionId preserved from original through merge")
    func mergePreservesCollectionId() {
        let id = RuleCollectionIdentifier.vimNavigation
        let original = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123,
            collectionId: id,
            vimLabel: "←"
        )
        let augmented = LayerKeyInfo(
            displayLabel: "h — left",
            outputKey: "left",
            outputKeyCode: 123,
            isTransparent: false,
            isLayerSwitch: false
        )

        let result = LayerMappingBuilder.mergeAugmentation(augmented, with: original)

        #expect(result.collectionId == id)
    }

    // MARK: - buildRemapOutputMap

    @Test("remapped keys appear in output map")
    func remapOutputMapIncludesRemaps() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "B", outputKey: "b", outputKeyCode: 11)
        ]

        let result = LayerMappingBuilder.buildRemapOutputMap(from: mapping)

        #expect(result[0] == 11)
    }

    @Test("identity mappings excluded from output map")
    func remapOutputMapExcludesIdentity() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "A", outputKey: "a", outputKeyCode: 0)
        ]

        let result = LayerMappingBuilder.buildRemapOutputMap(from: mapping)

        #expect(result.isEmpty)
    }

    @Test("transparent keys excluded from output map")
    func remapOutputMapExcludesTransparent() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: LayerKeyInfo(
                displayLabel: "B",
                outputKey: "b",
                outputKeyCode: 11,
                isTransparent: true,
                isLayerSwitch: false
            )
        ]

        let result = LayerMappingBuilder.buildRemapOutputMap(from: mapping)

        #expect(result.isEmpty)
    }

    // MARK: - extractPushMsgInfo

    @Test("extracts app launch from push-msg")
    func extractAppLaunch() {
        let output = #"(push-msg "launch:Safari")"#
        let result = LayerMappingBuilder.extractPushMsgInfo(from: output, description: nil)

        #expect(result?.appLaunchIdentifier == "Safari")
    }

    @Test("extracts system action from push-msg")
    func extractSystemAction() {
        let output = #"(push-msg "system:spotlight")"#
        let result = LayerMappingBuilder.extractPushMsgInfo(from: output, description: nil)

        #expect(result?.systemActionIdentifier == "spotlight")
    }

    @Test("extracts URL from push-msg")
    func extractURL() {
        let output = #"(push-msg "open:github.com")"#
        let result = LayerMappingBuilder.extractPushMsgInfo(from: output, description: nil)

        #expect(result?.urlIdentifier != nil)
    }

    @Test("returns nil for non-push-msg output")
    func nonPushMsgReturnsNil() {
        let result = LayerMappingBuilder.extractPushMsgInfo(from: "a", description: nil)

        #expect(result == nil)
    }

    // MARK: - Static push-msg regex compilation guards (#854 — fail at test time, not app launch)

    @Test("extractAppLaunchIdentifier exercises pushMsgLaunchRegex")
    func extractAppLaunchIdentifierMatches() {
        let output = #"(push-msg "launch:Safari")"#

        #expect(LayerMappingBuilder.extractAppLaunchIdentifier(from: output) == "Safari")
        #expect(LayerMappingBuilder.extractAppLaunchIdentifier(from: "noop") == nil)
    }

    @Test("extractUrlIdentifier exercises pushMsgOpenRegex")
    func extractURLIdentifierMatches() {
        let output = #"(push-msg "open:github.com")"#

        #expect(LayerMappingBuilder.extractUrlIdentifier(from: output) != nil)
        #expect(LayerMappingBuilder.extractUrlIdentifier(from: "noop") == nil)
    }

    @Test("extractSystemActionIdentifier exercises pushMsgSystemRegex")
    func extractSystemActionIdentifierMatches() {
        let output = #"(push-msg "system:spotlight")"#

        #expect(LayerMappingBuilder.extractSystemActionIdentifier(from: output) == "spotlight")
        #expect(LayerMappingBuilder.extractSystemActionIdentifier(from: "noop") == nil)
    }

    @Test("extractPushMsgInfo exercises pushMsgTypeValueRegex")
    func extractPushMsgInfoMatches() {
        let output = #"(push-msg "launch:Safari")"#

        #expect(LayerMappingBuilder.extractPushMsgInfo(from: output, description: nil) != nil)
        #expect(LayerMappingBuilder.extractPushMsgInfo(from: "noop", description: nil) == nil)
    }

    // MARK: - Pipeline invariant: vimLabels survive augmentation

    @Test("all four HJKL vimLabels survive mergeAugmentation")
    func allArrowVimLabelsSurviveMerge() {
        let arrows: [(key: String, label: String, code: UInt16)] = [
            ("left", "←", 123), ("down", "↓", 125),
            ("up", "↑", 126), ("right", "→", 124)
        ]

        for arrow in arrows {
            let original = LayerKeyInfo.mapped(
                displayLabel: arrow.label,
                outputKey: arrow.key,
                outputKeyCode: arrow.code,
                vimLabel: arrow.label
            )
            let augmented = LayerKeyInfo(
                displayLabel: "\(arrow.key) — \(arrow.key)",
                outputKey: arrow.key,
                outputKeyCode: arrow.code,
                isTransparent: false,
                isLayerSwitch: false
            )

            let result = LayerMappingBuilder.mergeAugmentation(augmented, with: original)

            #expect(result.vimLabel == arrow.label, "vimLabel for \(arrow.key) should survive")
            #expect(result.displayLabel == arrow.label, "displayLabel for \(arrow.key) should use original")
        }
    }

    // MARK: - systemActionDisplayLabel

    @Test("known system actions get friendly names")
    func systemActionLabels() {
        #expect(LayerMappingBuilder.systemActionDisplayLabel("spotlight") == "Spotlight")
        #expect(LayerMappingBuilder.systemActionDisplayLabel("dnd") == "Do Not Disturb")
        #expect(LayerMappingBuilder.systemActionDisplayLabel("mission-control") == "Mission Control")
        #expect(LayerMappingBuilder.systemActionDisplayLabel("notification-center") == "Notification Center")
    }

    @Test("unknown system actions get capitalized")
    func unknownSystemActionCapitalized() {
        #expect(LayerMappingBuilder.systemActionDisplayLabel("custom-thing") == "Custom-Thing")
    }

    // MARK: - mediaKeyDisplayLabel

    @Test("media keys get display labels")
    func mediaKeyLabels() {
        #expect(LayerMappingBuilder.mediaKeyDisplayLabel("brup") == "Brightness Up")
        #expect(LayerMappingBuilder.mediaKeyDisplayLabel("volu") == "Volume Up")
        #expect(LayerMappingBuilder.mediaKeyDisplayLabel("pp") == "Play/Pause")
    }

    @Test("non-media keys return nil")
    func nonMediaKeyReturnsNil() {
        #expect(LayerMappingBuilder.mediaKeyDisplayLabel("a") == nil)
    }

    // MARK: - Home Row Mods augmentation

    @Test("home row mods augment base layer with hold modifier labels")
    func homeRowModsAugmentBaseLayerWithHoldModifierLabels() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: LayerKeyInfo(
                displayLabel: "A",
                outputKey: "a",
                outputKeyCode: 0,
                isTransparent: true,
                isLayerSwitch: false
            ),
            1: LayerKeyInfo(
                displayLabel: "S",
                outputKey: "s",
                outputKeyCode: 1,
                isTransparent: true,
                isLayerSwitch: false
            ),
            41: LayerKeyInfo(
                displayLabel: ";",
                outputKey: "semicolon",
                outputKeyCode: 41,
                isTransparent: true,
                isLayerSwitch: false
            ),
        ]
        let config = HomeRowModsConfig(
            enabledKeys: ["a", "s", ";"],
            modifierAssignments: ["a": "lsft", "s": "lctl", ";": "rsft"]
        )
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            isSystemDefault: true,
            configuration: .homeRowMods(config)
        )

        let result = LayerMappingBuilder.augmentWithPushMsgActions(
            mapping: mapping,
            customRules: [],
            ruleCollections: [collection],
            currentLayerName: "base"
        )

        #expect(result[0]?.displayLabel == "⇧")
        #expect(result[1]?.displayLabel == "⌃")
        // Semicolon verifies the dual-registration path for config aliases like ";" vs overlay names.
        #expect(result[41]?.displayLabel == "⇧")
        #expect(result[0]?.collectionId == RuleCollectionIdentifier.homeRowMods)
        #expect(result[0]?.isTransparent == false)
    }

    @Test("home row mods augmentation ignores non-base layer")
    func homeRowModsAugmentationIgnoresNonBaseLayer() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "←", outputKey: "left", outputKeyCode: 123)
        ]
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lsft"]
        )
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            isSystemDefault: true,
            configuration: .homeRowMods(config)
        )

        let result = LayerMappingBuilder.augmentWithPushMsgActions(
            mapping: mapping,
            customRules: [],
            ruleCollections: [collection],
            currentLayerName: "nav"
        )

        #expect(result[0]?.displayLabel == "←")
    }

    @Test("home row mods layer hold mode injects assigned layer labels")
    func homeRowModsLayerHoldModeInjectsAssignedLayerLabels() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: LayerKeyInfo(
                displayLabel: "A",
                outputKey: "a",
                outputKeyCode: 0,
                isTransparent: true,
                isLayerSwitch: false
            ),
            41: LayerKeyInfo(
                displayLabel: ";",
                outputKey: "semicolon",
                outputKeyCode: 41,
                isTransparent: true,
                isLayerSwitch: false
            ),
        ]
        let config = HomeRowModsConfig(
            enabledKeys: ["a", ";"],
            modifierAssignments: ["a": "lsft"],
            layerAssignments: ["a": "nav", ";": "fun"],
            holdMode: .layers
        )
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            isSystemDefault: true,
            configuration: .homeRowMods(config)
        )

        let result = LayerMappingBuilder.augmentWithPushMsgActions(
            mapping: mapping,
            customRules: [],
            ruleCollections: [collection],
            currentLayerName: "base"
        )

        #expect(result[0]?.displayLabel == "Nav")
        #expect(result[41]?.displayLabel == "Fun")
        #expect(result[0]?.collectionId == RuleCollectionIdentifier.homeRowMods)
        #expect(result[0]?.isTransparent == false)
    }
}
