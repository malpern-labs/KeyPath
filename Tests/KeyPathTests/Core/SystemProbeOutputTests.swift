import Foundation
@testable import KeyPathCore
import XCTest

final class SystemProbeOutputTests: XCTestCase {
    func testProbeDrainsBothStreamsWhileChildRuns() {
        let result = runProcessSynchronously(
            "/usr/bin/python3",
            args: ["-c", "import os; os.write(1,b'x'*262144); os.write(2,b'y'*262144)"],
            timeout: 5
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, String(repeating: "x", count: 262_144))
        XCTAssertEqual(result.stderr, String(repeating: "y", count: 262_144))
    }

    func testFailedLaunchReturnsWithoutWaitingForReaders() {
        let result = runProcessSynchronously("/no-such-keypath-probe", args: [], timeout: 1)
        XCTAssertEqual(result.exitCode, 127)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertFalse(result.stderr.isEmpty)
    }
}
