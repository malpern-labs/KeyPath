@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathPermissions
@preconcurrency import XCTest

@MainActor
final class PermissionOracleXCTests: XCTestCase {
    override func setUp() async throws {}

    override func tearDown() async throws {}

    func testSnapshotInTestModeIsFastAndNonBlocking() async {
        let oracle = PermissionOracle()
        let start = Date()
        let snapshot = await oracle.currentSnapshot()
        let duration = Date().timeIntervalSince(start)

        XCTAssertLessThan(duration, 1.0, "Oracle snapshot should be fast in test mode")
        XCTAssertEqual(snapshot.accessibility, .unknown)
        XCTAssertEqual(snapshot.runtimeKeyAccess.confidence, .low)
    }

    func testSnapshotCachingHonorsTTLInTestMode() async {
        let oracle = PermissionOracle()
        let first = await oracle.currentSnapshot()
        let second = await oracle.currentSnapshot()
        // In test mode, immediate second call should return cached snapshot with same timestamp
        XCTAssertEqual(first.timestamp.timeIntervalSince1970, second.timestamp.timeIntervalSince1970)
    }
}
