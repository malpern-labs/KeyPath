import ArgumentParser
import Foundation
import KeyPathCore

struct LayerList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available layers"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext

        let layers: [String]
        do {
            layers = try await RuntimeControl.requestEngine(.layers).layers ?? []
        } catch {
            let cliError = CLIError.serviceUnreachable()
            CLIOutput.writeError(cliError, context: ctx)
            throw cliError.code.exitCode
        }

        CLIOutput.write(layers, context: ctx) {
            if layers.isEmpty {
                return "No layers found."
            }
            var lines = ["Layers:"]
            for layer in layers {
                lines.append("  \(layer)")
            }
            return lines.joined(separator: "\n")
        }
    }
}
