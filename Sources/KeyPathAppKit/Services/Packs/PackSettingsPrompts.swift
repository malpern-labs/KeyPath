import AppKit
import Foundation
import KeyPathRulesCore

/// Decisions about replacing or restoring a user's customized pack settings.
@MainActor
enum PackSettingsPrompts {
    static func useRecommended(
        packName: String,
        collectionName: String,
        diffs: [RuleCollectionConfiguration.SettingDiff]
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "\(packName) will configure \(collectionName)")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Use Recommended"))
        alert.addButton(withTitle: String(localized: "Keep My Settings"))

        if !diffs.isEmpty {
            alert.informativeText = String(localized: "Your current settings will be saved and can be restored when you uninstall \(packName).")
            alert.accessoryView = Self.buildComparisonView(
                diffs: diffs,
                currentLabel: String(localized: "Current"),
                proposedLabel: String(localized: "Recommended")
            )
        } else {
            alert
                .informativeText =
                String(localized: "Your current \(collectionName) settings will be changed. Your current settings will be saved and can be restored when you uninstall \(packName).")
        }

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    static func restorePrevious(
        packName: String,
        diffs: [RuleCollectionConfiguration.SettingDiff]
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Restore Previous Settings?")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Restore Previous"))
        alert.addButton(withTitle: String(localized: "Keep Current"))

        if !diffs.isEmpty {
            alert.informativeText = String(localized: "You modified settings after installing \(packName). Restore your previous configuration?")
            alert.accessoryView = Self.buildComparisonView(
                diffs: diffs,
                currentLabel: String(localized: "Current"),
                proposedLabel: String(localized: "Previous")
            )
        } else {
            alert.informativeText = String(localized: "You modified settings after installing \(packName). Restore your previous configuration, or keep the current settings?")
        }

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    private static func buildComparisonView(
        diffs: [RuleCollectionConfiguration.SettingDiff],
        currentLabel: String,
        proposedLabel: String
    ) -> NSView {
        let grid = NSGridView(numberOfColumns: 3, rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.columnSpacing = 12
        grid.rowSpacing = 4

        func headerCell(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 11, weight: .semibold)
            field.textColor = .secondaryLabelColor
            return field
        }

        func cell(_ text: String, bold: Bool = false) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = bold
                ? .systemFont(ofSize: 12, weight: .medium)
                : .systemFont(ofSize: 12)
            field.textColor = .labelColor
            field.lineBreakMode = .byTruncatingTail
            return field
        }

        grid.addRow(with: [
            headerCell(""),
            headerCell(currentLabel),
            headerCell(proposedLabel),
        ])

        for diff in diffs {
            grid.addRow(with: [
                cell(diff.label, bold: true),
                cell(diff.current),
                cell(diff.proposed),
            ])
        }

        grid.column(at: 0).width = 80
        grid.column(at: 1).width = 110
        grid.column(at: 2).width = 110

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: CGFloat(diffs.count + 1) * 24 + 8))
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        return container
    }
}
