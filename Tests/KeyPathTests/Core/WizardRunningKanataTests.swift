import Foundation
@testable import KeyPathCore
import XCTest

final class WizardRunningKanataTests: XCTestCase {
    func testExternalProcessAndQuotedConfigArePreserved() async throws {
        let runner = ProbeRunner(output: "123 /opt/homebrew/bin/kanata --cfg \"/tmp/my config.kbd\"\n")
        let info = try await WizardSystemPaths.detectRunningKanataProcess(runner: runner)
        XCTAssertEqual(info?.pid, 123)
        XCTAssertEqual(info?.configPath, "/tmp/my config.kbd")
        XCTAssertEqual(info?.isKeyPathManaged, false)
        let invocation = await runner.invocation
        XCTAssertEqual(invocation?.0, "/bin/ps")
        XCTAssertEqual(invocation?.1, ["-eo", "pid,args"])
        XCTAssertEqual(invocation?.2, 5)
    }

    func testFailedProbeDoesNotUsePartialOutput() async {
        let runner = ProbeRunner(output: "123 /opt/homebrew/bin/kanata -c /tmp/config.kbd", status: 1)
        do {
            _ = try await WizardSystemPaths.detectRunningKanataProcess(runner: runner)
            XCTFail("An unreadable process table must remain unknown")
        } catch {}
    }

    func testProbeFailureRemainsUnknown() async {
        let runner = ProbeRunner(output: "", fails: true)
        do {
            _ = try await WizardSystemPaths.detectRunningKanataProcess(runner: runner)
            XCTFail("An unreadable process table must remain unknown")
        } catch {}
    }

    func testExternalProcessTakesPriorityOverManagedProcess() {
        let output = "123 /opt/homebrew/bin/kanata -c /tmp/external.kbd\n456 \(WizardSystemPaths.legacySystemBinaryPath) -c /tmp/managed.kbd\n"
        XCTAssertEqual(WizardSystemPaths.runningKanataProcess(in: output)?.pid, 123)
    }

    func testUnrelatedProcessesAreIgnored() {
        XCTAssertNil(WizardSystemPaths.runningKanataProcess(in: "123 /bin/echo kanata\n456 /usr/bin/grep kanata\n"))
    }
}

private actor ProbeRunner: SubprocessRunning {
    let output: String
    let status: Int32
    let fails: Bool
    private(set) var invocation: (String, [String], TimeInterval?)?

    init(output: String, status: Int32 = 0, fails: Bool = false) {
        self.output = output
        self.status = status
        self.fails = fails
    }

    func run(_ executable: String, args: [String], timeout: TimeInterval?) async throws -> ProcessResult {
        invocation = (executable, args, timeout)
        if fails { throw NSError(domain: "ProbeTest", code: 1) }
        return ProcessResult(exitCode: status, stdout: output, stderr: "", duration: 0)
    }

    func launchctl(_: String, _: [String]) async throws -> ProcessResult {
        XCTFail("Migration detection must not call launchctl")
        return ProcessResult(exitCode: 1, stdout: "", stderr: "", duration: 0)
    }
}
