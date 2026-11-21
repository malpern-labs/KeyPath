import ArgumentParser
import Foundation

package struct ServiceRestart: AsyncParsableCommand {
    package init() {}

    package static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Restart remapping (launches KeyPath.app if needed)",
        discussion: "Waits until KeyPath.app has finished. Exit codes: 0 done, 1 the runtime refused or failed, 6 KeyPath.app is not running or did not answer."
    )

    @OptionGroup var globals: GlobalOptions

    package mutating func run() async throws {
        try RuntimeControlClient.run(.restart, globals: globals, launch: true)
    }
}
