import Foundation

public struct CLIRuleDetail: Codable, Sendable {
    public let input: String
    public let action: KeyAction
    public let behavior: MappingBehavior?
    public let shiftedOutput: String?
    public let title: String?
    public let notes: String?
    public let targetLayer: String
    public let deviceOverrides: [CLIDeviceOverride]?
    public let isEnabled: Bool
    public let createdAt: Date

    public init(from rule: CustomRule) {
        input = rule.input
        action = rule.action
        behavior = rule.behavior
        shiftedOutput = rule.shiftedOutput
        title = rule.title.isEmpty ? nil : rule.title
        notes = rule.notes
        targetLayer = rule.targetLayer.kanataName
        deviceOverrides = rule.deviceOverrides?.map { CLIDeviceOverride(from: $0) }
        isEnabled = rule.isEnabled
        createdAt = rule.createdAt
    }

    public static func dryRunPreview(
        input: String,
        action: KeyAction?,
        behavior: MappingBehavior?,
        shiftedOutput: String?,
        title: String?,
        notes: String?,
        targetLayer: String?
    ) -> CLIRuleDetail {
        CLIRuleDetail(
            input: input,
            action: action ?? .empty,
            behavior: behavior,
            shiftedOutput: shiftedOutput,
            title: title,
            notes: notes,
            targetLayer: targetLayer ?? "base",
            deviceOverrides: nil,
            isEnabled: true,
            createdAt: Date()
        )
    }

    public init(
        input: String,
        action: KeyAction,
        behavior: MappingBehavior?,
        shiftedOutput: String?,
        title: String?,
        notes: String?,
        targetLayer: String,
        deviceOverrides: [CLIDeviceOverride]?,
        isEnabled: Bool,
        createdAt: Date
    ) {
        self.input = input
        self.action = action
        self.behavior = behavior
        self.shiftedOutput = shiftedOutput
        self.title = title
        self.notes = notes
        self.targetLayer = targetLayer
        self.deviceOverrides = deviceOverrides
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

public struct CLIDeviceOverride: Codable, Sendable {
    public let deviceHash: String
    public let action: KeyAction
    public let behavior: MappingBehavior?

    public init(from override: DeviceKeyOverride) {
        deviceHash = override.deviceHash
        action = override.output
        behavior = override.behavior
    }
}
