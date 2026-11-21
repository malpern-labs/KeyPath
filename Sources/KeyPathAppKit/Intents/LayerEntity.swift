import AppIntents
import Foundation
import KeyPathCLISupport

struct LayerEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Layer")
    static let defaultQuery = LayerEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct LayerEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LayerEntity] {
        let allLayers = await (try? fetchLayers()) ?? []
        return allLayers.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [LayerEntity] {
        await (try? fetchLayers()) ?? []
    }

    private func fetchLayers() async throws -> [LayerEntity] {
        let names = if OneShotProbeEnvironment.isActive() {
            try await ConfigFacade().tcpGetLayers()
        } else {
            try await KanataTCPClient().requestLayerNames()
        }
        return names.map { LayerEntity(id: $0, name: $0) }
    }
}
