import ArgumentParser
import Foundation

package struct StartShortcut: AsyncParsableCommand {
    package init() {}

    package static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start remapping (shortcut for 'service start')",
        shouldDisplay: false
    )

    @OptionGroup var globals: GlobalOptions

    package mutating func run() async throws {
        var cmd = ServiceStart()
        cmd.globals = globals
        try await cmd.run()
    }
}
