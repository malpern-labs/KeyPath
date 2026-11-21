import ArgumentParser
import Foundation

package struct StatusShortcut: AsyncParsableCommand {
    package init() {}

    package static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show remapping status (shortcut for 'service status')",
        shouldDisplay: false
    )

    @OptionGroup package var globals: GlobalOptions

    package mutating func run() async throws {
        var cmd = ServiceStatus()
        cmd.globals = globals
        try await cmd.run()
    }
}
