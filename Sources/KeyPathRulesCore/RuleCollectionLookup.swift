import Foundation

package enum RuleCollectionLookup {
    package static func index(nameOrId: String, in collections: [RuleCollection]) throws -> Int? {
        if let index = collections.firstIndex(where: { $0.id.uuidString == nameOrId }) {
            return index
        }

        let exactMatches = collections.enumerated().filter {
            $0.element.name.caseInsensitiveCompare(nameOrId) == .orderedSame
        }
        if exactMatches.count == 1 {
            return exactMatches[0].offset
        }
        if exactMatches.count > 1 {
            throw AmbiguousCollectionMatch(
                query: nameOrId,
                matches: exactMatches.map { .init(name: $0.element.name, id: $0.element.id.uuidString) },
                hint: "Multiple collections share this name. Use the ID to disambiguate."
            )
        }

        let normalizedQuery = nameOrId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let slugMatches = collections.enumerated().filter {
            Self.slug(for: $0.element.name) == normalizedQuery
        }
        if slugMatches.count == 1 {
            return slugMatches[0].offset
        }
        if slugMatches.count > 1 {
            throw AmbiguousCollectionMatch(
                query: nameOrId,
                matches: slugMatches.map { .init(name: $0.element.name, id: $0.element.id.uuidString) },
                hint: "Multiple collections match this slug. Use the ID to disambiguate."
            )
        }

        if let aliasID = Self.collectionAliasIDs[normalizedQuery],
           let index = collections.firstIndex(where: { $0.id == aliasID })
        {
            return index
        }

        let substringMatches = collections.enumerated().filter {
            $0.element.name.localizedCaseInsensitiveContains(nameOrId)
        }
        if substringMatches.count == 1 {
            return substringMatches[0].offset
        }
        if substringMatches.count > 1 {
            throw AmbiguousCollectionMatch(
                query: nameOrId,
                matches: substringMatches.map { .init(name: $0.element.name, id: $0.element.id.uuidString) }
            )
        }

        return nil
    }

    private static let collectionAliasIDs: [String: UUID] = [
        "home-row": RuleCollectionIdentifier.homeRowMods,
        "home-row-mod": RuleCollectionIdentifier.homeRowMods,
        "hrm": RuleCollectionIdentifier.homeRowMods,
    ]

    private static func slug(for name: String) -> String {
        var result = ""
        var previousWasSeparator = false
        for scalar in name.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
