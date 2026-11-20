import AppKit
import KeyPathCore
import KeyPathRulesCore
import SwiftUI

struct OverlayAssignmentCommands {
    let canCopy: (PhysicalKey) -> Bool
    let canPaste: (PhysicalKey) -> Bool
    let copy: (PhysicalKey) -> Void
    let paste: (PhysicalKey) -> Void
    let beginSwap: (PhysicalKey) -> Void
    let swapSource: UInt16?
}

extension EnvironmentValues {
    @Entry var overlayAssignmentCommands: OverlayAssignmentCommands?
}

struct SelectedAssignmentCommands {
    let copy: (() -> Void)?
    let paste: (() -> Void)?
    let swap: (() -> Void)?
}

extension FocusedValues {
    @Entry var selectedAssignmentCommands: SelectedAssignmentCommands?
}

extension LiveKeyboardOverlayView {
    private static let assignmentClipboardType = NSPasteboard.PasteboardType("com.keypath.key-assignment")

    private var clipboardAssignment: KeyAssignment? {
        guard let data = NSPasteboard.general.data(forType: Self.assignmentClipboardType),
              data.count <= 32768,
              let assignment = try? JSONDecoder().decode(KeyAssignment.self, from: data),
              assignment.isSupported else { return nil }
        return assignment
    }

    func assignmentCommands(layer: RuleCollectionLayer) -> OverlayAssignmentCommands {
        let rules = kanataViewModel?.customRules ?? []
        return OverlayAssignmentCommands(
            canCopy: { key in
                RuleCollectionsManager.assignmentRule(input: Self.assignmentInput(key), layer: layer, in: rules) != nil
            },
            canPaste: { key in
                let input = Self.assignmentInput(key)
                return clipboardAssignment != nil && (RuleCollectionsManager.assignmentRule(input: input, layer: layer, in: rules) != nil
                    || !rules.contains { $0.targetLayer == layer && $0.input.caseInsensitiveCompare(input) == .orderedSame })
            },
            copy: { key in
                guard let rule = RuleCollectionsManager.assignmentRule(input: Self.assignmentInput(key), layer: layer, in: rules),
                      let assignment = KeyAssignment(rule: rule),
                      let data = try? JSONEncoder().encode(assignment) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(data, forType: Self.assignmentClipboardType)
            },
            paste: { key in
                guard let assignment = clipboardAssignment else { return }
                applyAssignmentEdit(.paste(assignment, Self.assignmentInput(key)), layer: layer, actionName: String(localized: "Paste Assignment"))
            },
            beginSwap: { key in
                assignmentFeedback = nil
                assignmentSwapSource = key
            },
            swapSource: assignmentSwapSource?.keyCode
        )
    }

    func selectedAssignmentCommands() -> SelectedAssignmentCommands? {
        guard let code = viewModel.selectedKeyCode,
              let key = activeLayout.keys.first(where: { $0.keyCode == code && $0.layoutRole != .touchId })
        else { return nil }
        let commands = assignmentCommands(layer: RuleCollectionLayer(kanataName: viewModel.currentLayerName))
        let canCopy = commands.canCopy(key)
        return SelectedAssignmentCommands(
            copy: canCopy ? { commands.copy(key) } : nil,
            paste: commands.canPaste(key) ? { commands.paste(key) } : nil,
            swap: canCopy ? { commands.beginSwap(key) } : nil
        )
    }

    func selectAssignmentKey(_ key: PhysicalKey, info: LayerKeyInfo?) {
        guard let source = assignmentSwapSource else {
            onKeyClick?(key, info)
            return
        }
        if source.keyCode == key.keyCode {
            assignmentSwapSource = nil
            return
        }
        let layer = RuleCollectionLayer(kanataName: viewModel.currentLayerName)
        guard assignmentCommands(layer: layer).canCopy(key) else {
            assignmentFeedback = String(localized: "Choose a key with a supported assignment.")
            return
        }
        assignmentSwapSource = nil
        applyAssignmentEdit(.swap(Self.assignmentInput(source), Self.assignmentInput(key)), layer: layer, actionName: String(localized: "Swap Assignments"))
    }

    private static func assignmentInput(_ key: PhysicalKey) -> String {
        OverlayKeyboardView.keyCodeToKanataName(key.keyCode)
    }

    private func applyAssignmentEdit(_ edit: RuleCollectionsManager.AssignmentEdit, layer: RuleCollectionLayer, actionName: String) {
        guard let runtime = kanataViewModel?.underlyingManager else { return }
        assignmentFeedback = nil
        Task { @MainActor in
            let result = await runtime.rulesManager.editAssignments(edit, layer: layer)
            guard result.saved else {
                assignmentFeedback = String(localized: "Could not change these assignments. Your current rules were kept.")
                return
            }
            runtime.refreshRuleMappings()
            guard let undo = result.undo,
                  let window = NSApp.windows.compactMap({ $0 as? OverlayWindow }).first else { return }
            let manager = window.remapUndoManager
            manager.registerUndo(withTarget: viewModel) { _ in
                Task { @MainActor in
                    if await runtime.rulesManager.undoRemap(undo) {
                        runtime.refreshRuleMappings()
                    } else {
                        assignmentFeedback = String(localized: "Could not undo the assignment change. Your current rules were kept.")
                    }
                }
            }
            manager.setActionName(actionName)
        }
    }
}
