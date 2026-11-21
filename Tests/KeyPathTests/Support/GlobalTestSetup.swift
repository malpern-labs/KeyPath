@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
import XCTest

/// Configures test-wide behavior that cannot be injected at the call site.
///
/// Called from KeyPathTestCase setup.
@MainActor
enum TestGlobalSetup {
    /// Keep test logging quiet unless a run explicitly requests console logs.
    static func configure() {
        // Negative-path tests log expected [ERROR]/[WARN] lines, and the test
        // log guardrail counts them. Keep app logs in the log file unless the
        // run asks for verbose output. (This used to happen by accident: the
        // first CLI test configured CLIRuntimeBootstrap, which turns console
        // logging off process-wide.)
        AppLogger.shared.setConsoleLoggingEnabled(
            ProcessInfo.processInfo.environment["KEYPATH_TEST_VERBOSE_LOGS"] == "1"
        )
    }
}
