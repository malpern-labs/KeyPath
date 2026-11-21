import Foundation

public struct CLIRuleCollection: Codable, Sendable {
    public let id: String
    public let name: String
    public let isEnabled: Bool
    public let mappingCount: Int
    public let summary: String

    public init(from collection: RuleCollection) {
        id = collection.id.uuidString
        name = collection.name
        isEnabled = collection.isEnabled
        mappingCount = collection.mappings.count
        summary = collection.summary
    }
}

public struct CLIRuleCollectionDetail: Codable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let category: String
    public let displayStyle: String
    public let isEnabled: Bool
    public let isSystemDefault: Bool
    public let owningPackID: String?
    public let icon: String?
    public let tags: [String]
    public let targetLayer: String
    public let activationHint: String?
    public let mappingCount: Int
    public let mappings: [KeyMapping]
    public let configuration: RuleCollectionConfiguration
    public let windowKeyConvention: String?
    public let windowSnappingActivationMode: String?
    public let functionKeyMode: String?

    public init(from collection: RuleCollection) {
        id = collection.id.uuidString
        name = collection.name
        summary = collection.summary
        category = collection.category.rawValue
        displayStyle = collection.displayStyle.rawValue
        isEnabled = collection.isEnabled
        isSystemDefault = collection.isSystemDefault
        owningPackID = collection.owningPackID
        icon = collection.icon
        tags = collection.tags
        targetLayer = collection.targetLayer.kanataName
        activationHint = collection.activationHint
        mappingCount = collection.mappings.count
        mappings = collection.mappings
        configuration = collection.configuration
        windowKeyConvention = collection.windowKeyConvention?.rawValue
        windowSnappingActivationMode = collection.windowSnappingActivationMode?.rawValue
        functionKeyMode = collection.functionKeyMode?.rawValue
    }
}

public struct AmbiguousCollectionMatch: Error, CustomStringConvertible {
    public struct Match: Sendable {
        public let name: String
        public let id: String

        package init(name: String, id: String) {
            self.name = name
            self.id = id
        }
    }

    public let query: String
    public let matches: [Match]
    public let hint: String

    public init(query: String, matches: [Match], hint: String = "Use the full name or ID to disambiguate.") {
        self.query = query
        self.matches = matches
        self.hint = hint
    }

    public var description: String {
        var lines = ["Found \(matches.count) collections matching \"\(query)\":"]
        for match in matches {
            lines.append("  - \(match.name) (id: \(match.id))")
        }
        lines.append(hint)
        return lines.joined(separator: "\n")
    }
}
