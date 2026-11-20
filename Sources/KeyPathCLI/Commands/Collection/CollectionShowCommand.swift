import ArgumentParser
import Foundation
import KeyPathRulesCore

struct CollectionShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show details of a rule collection"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Collection name or ID")
    var nameOrId: String

    @Flag(name: .customLong("full"), help: "Show full collection model including display configuration")
    var full: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let store = RuleCollectionStore.shared

        if full {
            try await showFullCollection(ctx: ctx, store: store)
            return
        }

        let collection: CLIRuleCollection
        do {
            guard let found = try await store.showCollection(nameOrId: nameOrId) else {
                let candidates = await store.listCollections().map(\.name)
                let suggestions = FuzzyMatch.suggestions(for: nameOrId, from: candidates)
                let error = CLIError.notFound("Collection", query: nameOrId, listCommand: "keypath collection list", suggestions: suggestions)
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
            collection = found
        } catch let ambiguous as AmbiguousCollectionMatch {
            let error = CLIError.ambiguous(
                ambiguous.description,
                matches: ambiguous.matches.map { "\($0.name) (id: \($0.id))" }
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(collection, context: ctx) {
            """
            Name: \(collection.name)
            ID: \(collection.id)
            Enabled: \(collection.isEnabled)
            Mappings: \(collection.mappingCount)
            Summary: \(collection.summary)
            """
        }
    }

    private func showFullCollection(ctx: OutputContext, store: RuleCollectionStore) async throws {
        let collection: CLIRuleCollectionDetail
        do {
            guard let found = try await store.showCollectionDetail(nameOrId: nameOrId) else {
                let candidates = await store.listCollections().map(\.name)
                let suggestions = FuzzyMatch.suggestions(for: nameOrId, from: candidates)
                let error = CLIError.notFound("Collection", query: nameOrId, listCommand: "keypath collection list", suggestions: suggestions)
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
            collection = found
        } catch let ambiguous as AmbiguousCollectionMatch {
            let error = CLIError.ambiguous(
                ambiguous.description,
                matches: ambiguous.matches.map { "\($0.name) (id: \($0.id))" }
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(collection, context: ctx) {
            """
            Name: \(collection.name)
            ID: \(collection.id)
            Enabled: \(collection.isEnabled)
            Style: \(collection.displayStyle)
            Mappings: \(collection.mappingCount)
            Target layer: \(collection.targetLayer)
            Configuration: \(collection.displayStyle)
            Summary: \(collection.summary)
            """
        }
    }
}
