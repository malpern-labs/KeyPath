import ArgumentParser
import KeyPathCore

struct ConfigPath: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "path",
        abstract: "Print the configuration file path"
    )

    @OptionGroup var globals: GlobalOptions

    func run() {
        let ctx = globals.outputContext
        let path = KeyPathConstants.Config.mainConfigPath

        CLIOutput.write(["path": path], context: ctx) {
            path
        }
    }
}
