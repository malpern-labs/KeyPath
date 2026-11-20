import Foundation
@testable import KeyPathAppKit

/// Each CLI test owns its persistence files; teardown never restores another
/// test's snapshot over a concurrently committed rule or collection.
@MainActor
final class CLIStoreFixture {
    let directory: URL
    let rules: CustomRulesStore
    let collections: RuleCollectionStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-cli-stores-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        rules = CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))
        collections = RuleCollectionStore(fileURL: directory.appendingPathComponent("RuleCollections.json"))
    }

    func remove() throws {
        try FileManager.default.removeItem(at: directory)
    }
}
