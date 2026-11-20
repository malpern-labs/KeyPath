import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

@MainActor
final class PackPersistenceIsolationTests: XCTestCase {
    func testSamePackIDHasIndependentSnapshotsAndCleanup() throws {
        let fixture = try CLIStoreFixture()
        defer { try? fixture.remove() }
        let firstDirectory = fixture.directory.appendingPathComponent("first")
        let secondDirectory = fixture.directory.appendingPathComponent("second")
        let first = PackCollectionSnapshot(packID: "same-pack", entries: [])
        let second = PackCollectionSnapshot(packID: "same-pack", snapshotDate: .distantPast, entries: [])
        try PackCollectionSnapshot.save(first, configDirectory: firstDirectory)
        try PackCollectionSnapshot.save(second, configDirectory: secondDirectory)

        XCTAssertEqual(try PackCollectionSnapshot.loadForMutation(for: "same-pack", configDirectory: firstDirectory), first)
        XCTAssertEqual(try PackCollectionSnapshot.loadForMutation(for: "same-pack", configDirectory: secondDirectory), second)
        PackCollectionSnapshot.remove(for: "same-pack", configDirectory: firstDirectory)
        XCTAssertNil(try PackCollectionSnapshot.loadForMutation(for: "same-pack", configDirectory: firstDirectory))
        XCTAssertEqual(try PackCollectionSnapshot.loadForMutation(for: "same-pack", configDirectory: secondDirectory), second)
    }

    func testLegacySnapshotFailureAndCleanupDoNotReachAnotherDirectory() throws {
        let fixture = try CLIStoreFixture()
        defer { try? fixture.remove() }
        let firstDirectory = fixture.directory.appendingPathComponent("first")
        let secondDirectory = fixture.directory.appendingPathComponent("second")
        for directory in [firstDirectory, secondDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let filename = "vallack-system-snapshot.json"
        try Data("not-json".utf8).write(to: firstDirectory.appendingPathComponent(filename))
        let legacy = try JSONSerialization.data(withJSONObject: [
            "homeRowModsEnabled": true, "homeRowLayerTogglesEnabled": false,
        ])
        try legacy.write(to: secondDirectory.appendingPathComponent(filename))

        XCTAssertThrowsError(try PackCollectionSnapshot.loadLegacyVallackForMutation(configDirectory: firstDirectory))
        let second = try XCTUnwrap(PackCollectionSnapshot.loadLegacyVallackForMutation(configDirectory: secondDirectory))
        XCTAssertEqual(second.packID, "com.keypath.pack.vallack-system")
        XCTAssertEqual(second.entries.first?.wasEnabled, true)
        try PackCollectionSnapshot.removeLegacyVallackIfPresent(configDirectory: firstDirectory)
        XCTAssertNil(try PackCollectionSnapshot.loadLegacyVallackForMutation(configDirectory: firstDirectory))
        XCTAssertEqual(try Data(contentsOf: secondDirectory.appendingPathComponent(filename)), legacy)
    }
}
