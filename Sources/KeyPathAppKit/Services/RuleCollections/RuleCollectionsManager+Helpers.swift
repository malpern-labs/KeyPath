import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathRulesCore

extension RuleCollectionsManager {
    // MARK: - Private Helpers

    func ensureDefaultCollectionsIfNeeded() {
        if ruleCollections.isEmpty {
            ruleCollections = RuleCollectionCatalog().defaultCollections()
        }
        refreshLayerIndicatorState()
    }
}
