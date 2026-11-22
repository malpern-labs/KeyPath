import AppKit
import KeyPathCore
import KeyPathRulesCore
import SwiftUI

extension OverlayMapperSection {
    // MARK: - Layers Expanded Content

    /// Content shown when Go to Layer section is expanded
    var layersExpandedContent: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Available Layers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // List of available layers
            ForEach(viewModel.availableLayers, id: \.self) { layer in
                layerRow(layer)
            }

            // "Create New Layer..." option
            Button {
                newLayerName = ""
                showingNewLayerDialog = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.body)
                        .frame(width: 20)
                    Text("Create New Layer...")
                        .font(.body)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerItemButtonStyle())
            .focusable(false)
            .accessibilityIdentifier("overlay-output-create-layer")
        }
    }

    /// Button for a layer in the list
    private func layerRow(_ layer: String) -> some View {
        let isHold = selectedBehaviorSlot == .hold
        let isSelected = isHold
            ? currentHoldLegend?.targetLayer == layer
            : viewModel.selectedLayerOutput == layer
        let layerIdentifier = layer
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        return Button {
            selectLayerOutput(layer)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: LayerInfo.iconName(for: layer))
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 20)
                Text(LayerInfo.displayName(for: layer))
                    .font(.body)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
        .disabled(isHold && (layerIdentifier == "base" || layerIdentifier == viewModel.currentLayer.lowercased()))
        .accessibilityIdentifier("overlay-layer-\(layerIdentifier)")
    }

    /// Select a layer as the output action
    func selectLayerOutput(_ layer: String) {
        if selectedBehaviorSlot == .hold {
            selectHeldLayer(layer)
            return
        }
        viewModel.selectedLayerOutput = layer
        viewModel.selectedApp = nil
        viewModel.selectedSystemAction = nil
        viewModel.selectedURL = nil
        viewModel.clearShiftedOutput()
        viewModel.outputLabel = "→ \(layer.capitalized)"
        isSystemActionPickerOpen = false

        // Save the layer switch mapping
        if let manager = kanataViewModel?.underlyingManager, viewModel.inputKeyCode != nil {
            Task {
                await saveLayerSwitchMapping(layer: layer, kanataManager: manager)
            }
        }
    }

    var currentHoldLegend: KeycapActionLegend? {
        let action = viewModel.holdAction
        if !action.isEmpty {
            return KeycapActionLegend(trigger: .hold, action: KanataBehaviorRenderer.parseActionString(action))
        }
        return viewModel.inputKeyCode.flatMap { layerKeyMap[$0] }?.actionLegends.first { $0.trigger == .hold }
    }

    private func selectHeldLayer(_ name: String) {
        isSystemActionPickerOpen = false
        guard let manager = kanataViewModel?.underlyingManager, let keyCode = viewModel.inputKeyCode,
              !viewModel.isSaving else { return }
        let input = OverlayKeyboardView.keyCodeToKanataName(keyCode)
        let source = RuleCollectionLayer(kanataName: viewModel.currentLayer)
        let target = RuleCollectionLayer(kanataName: name.lowercased())
        let fallbackTap = layerKeyMap[keyCode]?.actionLegends.first { $0.trigger == .tap }?.action
            ?? KanataBehaviorRenderer.parseActionString(
                layerKeyMap[keyCode]?.outputKey ?? input
            )
        guard viewModel.selectedAppCondition == nil, viewModel.selectedDeviceCondition == nil,
              let assignment = manager.rulesManager.prepareHoldLayerRemap(
                  input: input, source: source, target: target, fallbackTap: fallbackTap
              )
        else {
            viewModel.statusMessage = String(localized: "This assignment needs to be changed before adding a layer to Hold.")
            viewModel.statusIsError = true
            return
        }

        if assignment.previousHold != nil || assignment.conflict != nil {
            pendingHoldLayerRemap = assignment
        } else {
            applyHoldLayerRemap(assignment)
        }
    }

    func holdLayerReplacementSheet(_ assignment: RuleCollectionsManager.HoldLayerRemap) -> some View {
        let key = KeyDisplayFormatter.format(assignment.rule.input)
        let target = LayerInfo.displayName(for: assignment.target.kanataName)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Replace the assignment on \(key)?")
                .font(.headline)
            if let hold = assignment.previousHold {
                let previous = KeycapActionLegend(trigger: .hold, action: hold).actionName
                Text("Current Hold: \(previous)")
            }
            Text("New Hold: Activate \(target) layer")
            if let conflict = assignment.conflict {
                Text("This will turn off \(conflict.displayName), including its other mappings.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { pendingHoldLayerRemap = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("overlay-hold-layer-cancel")
                Button("Replace") {
                    pendingHoldLayerRemap = nil
                    applyHoldLayerRemap(assignment)
                }
                .accessibilityIdentifier("overlay-hold-layer-replace")
            }
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
    }

    private func applyHoldLayerRemap(_ assignment: RuleCollectionsManager.HoldLayerRemap) {
        guard let manager = kanataViewModel?.underlyingManager, let keyCode = viewModel.inputKeyCode,
              !viewModel.isSaving,
              OverlayKeyboardView.keyCodeToKanataName(keyCode) == assignment.rule.input,
              RuleCollectionLayer(kanataName: viewModel.currentLayer) == assignment.rule.targetLayer
        else { return }

        viewModel.isSaving = true
        Task {
            defer { viewModel.isSaving = false }
            let result = await manager.rulesManager.saveHoldLayerRemap(assignment)
            manager.refreshRuleMappings()
            if let undo = result.undo {
                onRemapApplied?(keyCode, assignment.rule.targetLayer.kanataName, undo, viewModel)
            }
            guard viewModel.inputKeyCode == keyCode,
                  RuleCollectionLayer(kanataName: viewModel.currentLayer) == assignment.rule.targetLayer else { return }
            if result.saved {
                viewModel.loadBehaviorFromExistingRule(kanataManager: manager)
                viewModel.showTransientStatus(String(localized: "✓ Saved"))
                SoundManager.shared.playGlassSound()
            } else {
                viewModel.statusMessage = String(localized: "Could not save Hold. Your current assignment was kept.")
                viewModel.statusIsError = true
            }
        }
    }

    /// Save a mapping that switches to a layer
    func saveLayerSwitchMapping(layer: String, kanataManager: RuntimeCoordinator) async {
        guard let inputSeq = viewModel.inputKeyCode else { return }

        let inputKey = OverlayKeyboardView.keyCodeToKanataName(inputSeq)
        let outputKanata = "(layer-switch \(layer))"

        let source = RuleCollectionLayer(kanataName: viewModel.currentLayer)
        var customRule = kanataManager.makeCustomRule(input: inputKey, output: outputKanata, layer: source)
        customRule.notes = "Switch to \(layer) layer"
        customRule.shiftedOutput = nil

        let success = await kanataManager.saveCustomRule(customRule, skipReload: false)
        if success {
            viewModel.statusMessage = String(localized: "✓ Saved")
            SoundPlayer.shared.playSuccessSound()
            AppLogger.shared.log("✅ [OverlayMapper] Saved layer switch: \(inputKey) → layer:\(layer)")
        } else {
            viewModel.statusMessage = String(localized: "Failed to save")
            viewModel.statusIsError = true
        }
    }

    /// Dialog for creating a new layer
    var newLayerDialogContent: some View {
        VStack(spacing: 16) {
            Text("Create New Layer")
                .font(.headline)

            TextField("Layer name", text: $newLayerName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .accessibilityIdentifier("overlay-layer-dialog-name")

            HStack(spacing: 12) {
                Button("Cancel") {
                    showingNewLayerDialog = false
                }
                .keyboardShortcut(.escape)
                .accessibilityIdentifier("overlay-layer-dialog-cancel")

                Button("Create") {
                    let name = newLayerName
                    let keyCode = viewModel.inputKeyCode
                    let source = viewModel.currentLayer
                    let slot = selectedBehaviorSlot
                    guard let rules = kanataViewModel?.underlyingManager.rulesManager, !name.isEmpty else { return }
                    showingNewLayerDialog = false
                    Task {
                        guard let layer = await rules.createLayer(name) else {
                            viewModel.statusMessage = String(localized: "Could not create the layer.")
                            viewModel.statusIsError = true
                            return
                        }
                        await viewModel.refreshAvailableLayers()
                        guard viewModel.inputKeyCode == keyCode, viewModel.currentLayer == source,
                              selectedBehaviorSlot == slot else { return }
                        selectLayerOutput(layer)
                    }
                }
                .keyboardShortcut(.return)
                .disabled(newLayerName.isEmpty)
                .accessibilityIdentifier("overlay-layer-dialog-create")
            }
        }
        .padding(20)
        .frame(minWidth: 280)
    }

    /// Open file picker to choose an app for the output action
    func pickAppForOutput() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose an app to launch when this key is pressed")

        if panel.runModal() == .OK, let url = panel.url {
            let displayName = url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            let bundleId = Bundle(url: url)?.bundleIdentifier ?? url.lastPathComponent
            viewModel.selectedApp = AppLaunchInfo(name: displayName, bundleIdentifier: bundleId, icon: icon)
            viewModel.clearShiftedOutput()
            isSystemActionPickerOpen = false
        }
    }

    var shouldShowHealthGate: Bool {
        if healthIndicatorState == .checking { return true }
        if case .unhealthy = healthIndicatorState { return true }
        return false
    }

    @ViewBuilder
    var healthGateContent: some View {
        if healthIndicatorState == .checking {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text("Starting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.orange)
                    Text(healthGateTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Text(healthGateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: onHealthTap) {
                    Text(healthGateButtonTitle)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("overlay-mapper-fix-issues")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.orange.opacity(isDark ? 0.18 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private var healthGateTitle: String {
        switch healthIndicatorState {
        case .checking:
            String(localized: "System Not Ready")
        case let .unhealthy(issueCount):
            issueCount == 1 ? String(localized: "1 Issue Found") : String(localized: "\(issueCount) Issues Found")
        case .healthy, .dismissed:
            String(localized: "System Ready")
        }
    }

    private var healthGateMessage: String {
        switch healthIndicatorState {
        case .checking:
            String(localized: "Checking system health before enabling the mapper.")
        case let .unhealthy(issueCount):
            issueCount == 1
                ? String(localized: "Fix the issue to enable quick remapping in the drawer.")
                : String(localized: "Fix the issues to enable quick remapping in the drawer.")
        case .healthy, .dismissed:
            String(localized: "System health is good.")
        }
    }

    private var healthGateButtonTitle: String {
        switch healthIndicatorState {
        case .checking:
            String(localized: "Open Setup")
        case .unhealthy:
            String(localized: "Fix Issues")
        case .healthy, .dismissed:
            String(localized: "Open Setup")
        }
    }
}
