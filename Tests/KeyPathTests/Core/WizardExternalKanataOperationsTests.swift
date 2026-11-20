import Foundation
@testable import KeyPathCore
import KeyPathWizardCore
import XCTest

@MainActor
final class WizardExternalKanataOperationsTests: XCTestCase {
    func testVerifiedAbsenceCompletesStopPage() async throws {
        var completed = false
        let operations = ExternalKanataOperations(info: { nil }, stop: { _ in .success(()) }, isRunning: { false })
        let process = try await operations.prepareStop { completed = true }
        XCTAssertNil(process)
        XCTAssertTrue(completed)
    }

    func testFailedDiscoveryDoesNotCompleteStopPage() async {
        var completed = false
        let operations = ExternalKanataOperations(info: {
            throw NSError(domain: "ProbeTest", code: 1)
        }, stop: { _ in .success(()) }, isRunning: { nil })
        do {
            _ = try await operations.prepareStop { completed = true }
            XCTFail("Failed discovery must remain unknown")
        } catch {}
        XCTAssertFalse(completed)
    }

    func testExistingProcessRequiresStop() async throws {
        var completed = false
        let process = WizardSystemPaths.runningKanataProcess(in: "123 /opt/homebrew/bin/kanata -c /tmp/config.kbd")
        let operations = ExternalKanataOperations(info: { process }, stop: { _ in .success(()) }, isRunning: { true })
        let found = try await operations.prepareStop { completed = true }
        XCTAssertEqual(found?.pid, 123)
        XCTAssertFalse(completed)
    }
}
