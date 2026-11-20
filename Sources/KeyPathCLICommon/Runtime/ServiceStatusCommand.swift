import ArgumentParser
import Foundation
import KeyPathCore

package struct ServiceStatus: AsyncParsableCommand {
    package init() {}

    package static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show whether remapping is running, as KeyPath.app sees it",
        discussion: "Exit codes: 0 running, 1 not running, 6 KeyPath.app is not running or did not answer."
    )

    @OptionGroup var globals: GlobalOptions

    package mutating func run() async throws {
        let ctx = globals.outputContext
        let response: RuntimeControl.Response
        do {
            response = try RuntimeControlClient.send(.status, timeout: globals.timeout)
        } catch {
            let failure = RuntimeControlClient.appUnreachable(error, action: "status")
            CLIOutput.writeError(failure, context: ctx)
            throw failure.code.exitCode
        }
        CLIOutput.write(response, context: ctx) {
            RuntimeControlClient.humanStatus(response, noColor: ctx.noColor)
        }
        if response.state != .running { throw RuntimeControlClient.notRunningExit }
    }
}
