import Foundation
import KeyPathRulesCore

extension KarabinerConverterService {
    /// Persist launcher mappings into the existing launcher rule collection.
    /// Shared implementation used by both KarabinerImportSheet and WizardKarabinerImportPage.
    static func persistLauncherMappings(_ newMappings: [LauncherMapping]) async throws {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) else { return }
        var collection = collections[index]
        guard var config = collection.configuration.launcherGridConfig else { return }

        config.mappings.append(contentsOf: newMappings)
        collection.configuration = .launcherGrid(config)
        collections[index] = collection
        try await RuleCollectionStore.shared.saveCollections(collections)
        Foundation.NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
    }
}
