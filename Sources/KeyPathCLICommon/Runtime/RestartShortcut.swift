import ArgumentParser
import Foundation

package struct RestartShortcut: AsyncParsableCommand {
    package init() {}

    package static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Restart remapping (shortcut for 'service restart')",
        shouldDisplay: false
    )

    @OptionGroup var globals: GlobalOptions

    package mutating func run() async throws {
        var cmd = ServiceRestart()
        cmd.globals = globals
        try await cmd.run()
    }
}
