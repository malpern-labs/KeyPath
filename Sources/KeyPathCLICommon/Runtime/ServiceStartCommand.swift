import ArgumentParser
import Foundation

package struct ServiceStart: AsyncParsableCommand {
    package init() {}

    package static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start remapping (launches KeyPath.app if needed)",
        discussion: "Waits until KeyPath.app has finished. Exit codes: 0 done, 1 the runtime refused or failed, 6 KeyPath.app is not running or did not answer."
    )

    @OptionGroup var globals: GlobalOptions

    package mutating func run() async throws {
        try RuntimeControlClient.run(.start, globals: globals, launch: true)
    }
}
