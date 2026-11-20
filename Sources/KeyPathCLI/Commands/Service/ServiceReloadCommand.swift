import ArgumentParser
import Foundation
import KeyPathCore

struct ServiceReload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reload",
        abstract: "Hot-reload Kanata configuration"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        CLIOutput.progress("Reloading Kanata configuration...", context: ctx)

        let success = await (try? RuntimeControl.requestEngine(.reload)) != nil

        if success {
            CLIOutput.write(["reloaded": true], context: ctx) {
                "Configuration reloaded successfully."
            }
        } else {
            let error = CLIError.serviceUnreachable()
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
