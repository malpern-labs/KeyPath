import Foundation
import KeyPathCore
import KeyPathRulesCore

extension RuleCollectionCatalog {
    /// Why a built-in collection cannot run on the active backend, or nil. Derived
    /// from the keys the collection's catalog definition emits, so a collection
    /// becomes unavailable (or available) with the backend, not a hard-coded id.
    ///
    /// Uses the collection as a profile receives it (the fresh-profile default),
    /// not the raw catalog entry: macOS Function Keys is stored as its media
    /// definition but always installed in function mode, and media mode's own
    /// availability is `FunctionKeyMode.isSupportedInDriverlessSession`.
    ///
    /// The sentence is the admission engine's (phase 4d), so the gallery, the
    /// rules list and the toggle all say the same thing. Only the backend's
    /// own limits count here: whether a companion app is installed is a
    /// question for install or toggle time, with the user's real files.
    static func driverlessUnavailableReason(for id: UUID, profile: BackendCapabilityProfile = .shared) -> String? {
        guard let collection = installedDefinitions.first(where: { $0.id == id }) else { return nil }
        var enabled = collection
        enabled.isEnabled = true
        let state = AdmissionEngine.State(collections: [enabled])
        let verdicts = AdmissionEngine.evaluate(state, profile: profile, fileExists: { _ in true })
        guard let verdict = verdicts.first(where: { if case .unmetNeed = $0.reason { return true }; return false })
        else { return nil }
        return AdmissionVerdictPresenter.present(verdict) { _ in collection.name }.explanation
    }

    private static let installedDefinitions = RuleCollectionCatalog().defaultCollections()

    /// True when any key these mappings emit is outside the backend's profile.
    static func emitsUnsupportedOutput(_ mappings: [KeyMapping],
                                       profile: BackendCapabilityProfile = .shared) -> Bool
    {
        !RuleCollectionNeedsExtractor.unmet(RuleCollectionNeedsExtractor.needs(for: mappings), profile: profile).isEmpty
    }
}

public extension FunctionKeyMode {
    /// Whether the active backend can emit every key this mode maps F1–F12 to.
    /// Media mode needs consumer-page output, which the driverless session lacks.
    var isSupportedInDriverlessSession: Bool {
        !RuleCollectionCatalog.emitsUnsupportedOutput(RuleCollectionCatalog.functionKeyMappings(for: self))
    }
}
