import ArgumentParser
import Foundation

package struct StopShortcut: AsyncParsableCommand {
    package init() {}

    package static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop remapping (shortcut for 'service stop')",
        shouldDisplay: false
    )

    @OptionGroup var globals: GlobalOptions

    package mutating func run() async throws {
        var cmd = ServiceStop()
        cmd.globals = globals
        try await cmd.run()
    }
}
