import AppIntents
import Foundation
import KeyPathCLISupport

struct GetCurrentLayerIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Layer"
    static let description = IntentDescription("Returns the currently active keyboard layer.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let layer = if OneShotProbeEnvironment.isActive() {
            try await ConfigFacade().tcpGetCurrentLayer()
        } else {
            try await KanataTCPClient().requestCurrentLayerName()
        }
        return .result(value: layer)
    }

    static let openAppWhenRun: Bool = false
}
