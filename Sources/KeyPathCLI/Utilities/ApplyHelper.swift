import ArgumentParser
import Foundation
import KeyPathAppKit

func applyConfigurationOrHint(apply: Bool, context: OutputContext, facade: ConfigFacade) async throws {
    if apply {
        let result = try await facade.applyConfiguration()
        if result.reloadSuccess {
            CLIOutput.write(["applied": true], context: context) {
                "Config applied and Kanata reloaded."
            }
        } else {
            let error = CLIError.serviceUnreachable(hint: "Config written but Kanata reload failed. Run 'keypath service reload' once Kanata is running.")
            CLIOutput.writeError(error, context: context)
            throw error.code.exitCode
        }
    } else {
        CLIOutput.progress("Run 'keypath config apply' to regenerate config and reload Kanata.", context: context)
    }
}
