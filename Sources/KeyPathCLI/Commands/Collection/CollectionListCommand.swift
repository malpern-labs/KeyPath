import ArgumentParser
import Foundation
import KeyPathRulesCore

struct CollectionList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all rule collections"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let collections = await RuleCollectionStore.shared.listCollections()

        CLIOutput.write(collections, context: ctx) {
            if collections.isEmpty {
                return "No rule collections found."
            }
            var lines = ["Rule Collections:", String(repeating: "-", count: 60)]
            for collection in collections {
                let status = collection.isEnabled ? "+" : "-"
                lines.append("  [\(status)] \(collection.name) (\(collection.mappingCount) rules) — id: \(collection.id)")
            }
            return lines.joined(separator: "\n")
        }
    }
}
