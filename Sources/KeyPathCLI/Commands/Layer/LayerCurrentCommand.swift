import ArgumentParser
import Foundation
import KeyPathCore

struct LayerCurrent: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "current",
        abstract: "Show the currently active layer"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext

        guard let layer = try? await RuntimeControl.requestEngine(.layer).layer else {
            let cliError = CLIError.serviceUnreachable()
            CLIOutput.writeError(cliError, context: ctx)
            throw cliError.code.exitCode
        }

        CLIOutput.write(["layer": layer], context: ctx) {
            layer
        }
    }
}
