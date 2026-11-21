@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

final class DuplicateAppDetectorTests: XCTestCase {
    func testDetectDuplicateAppCopiesFiltersBuildPathsAndSortsApplicationsFirst() {
        let copies = DuplicateAppDetector.filteredCopies([
            "/Users/test/Downloads/KeyPath.app",
            "/dist/KeyPath.app",
            "/Volumes/Cache/Sparkle_generate_appcast/abc123/KeyPath.app",
            "/Applications/KeyPath.app",
            "/Users/test/KeyPath.app"
        ], isReadOnly: { _ in false })

        XCTAssertEqual(copies, [
            "/Applications/KeyPath.app",
            "/Users/test/Downloads/KeyPath.app",
            "/Users/test/KeyPath.app"
        ])
    }

    func testDetectDuplicateAppCopiesUsesBoundedSpotlightScan() async {
        let runner = SubprocessRunnerFake()
        await runner.configureRunResult { _, _ in
            ProcessResult(
                exitCode: 0,
                stdout: "/Applications/KeyPath.app\n/Users/test/Downloads/KeyPath.app\n",
                stderr: "",
                duration: 0.01
            )
        }

        let copies = await DuplicateAppDetector.detectDuplicateAppCopies(runner: runner)

        XCTAssertEqual(copies, ["/Applications/KeyPath.app", "/Users/test/Downloads/KeyPath.app"])
        let commands = await runner.executedCommands
        XCTAssertEqual(commands.first?.executable, "/usr/bin/mdfind")
        XCTAssertEqual(DuplicateAppDetector.duplicateScanTimeout, 2)
        XCTAssertTrue(DuplicateAppDetector.duplicateScanExcludedPathFragments.contains("/Sparkle_generate_appcast/"))
    }

    func testDetectDuplicateAppCopiesFallsBackWhenSpotlightTimesOut() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let installed = directory.appendingPathComponent("KeyPath.app", isDirectory: true)
        let missing = directory.appendingPathComponent("Missing/KeyPath.app", isDirectory: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runner = SubprocessRunnerFake()
        await runner.setShouldTimeout(true)
        let copies = await DuplicateAppDetector.detectDuplicateAppCopies(runner: runner) {
            [installed.path, missing.path]
        }

        XCTAssertEqual(copies, [installed.path])
    }

    func testConcurrentScansKeepTheirRunnersAndResultsSeparate() async {
        let firstRunner = SubprocessRunnerFake()
        let secondRunner = SubprocessRunnerFake()
        let firstPath = "/Users/test/First/KeyPath.app"
        let secondPath = "/Users/test/Second/KeyPath.app"
        await firstRunner.configureRunResult { _, _ in
            ProcessResult(exitCode: 0, stdout: firstPath, stderr: "", duration: 0)
        }
        await secondRunner.configureRunResult { _, _ in
            ProcessResult(exitCode: 0, stdout: secondPath, stderr: "", duration: 0)
        }

        async let first = DuplicateAppDetector.detectDuplicateAppCopies(runner: firstRunner)
        async let second = DuplicateAppDetector.detectDuplicateAppCopies(runner: secondRunner)
        let (firstCopies, secondCopies) = await (first, second)

        XCTAssertEqual(firstCopies, [firstPath])
        XCTAssertEqual(secondCopies, [secondPath])
    }

    /// A mounted installer image is not an installed copy that can be moved to the Trash.
    func testDetectDuplicateAppCopiesIgnoresReadOnlyVolumes() {
        let copies = DuplicateAppDetector.filteredCopies(
            ["/Applications/KeyPath.app", "/Volumes/KeyPath/KeyPath.app", "/Users/test/Old/KeyPath.app"],
            isReadOnly: { $0.hasPrefix("/Volumes/KeyPath/") }
        )
        XCTAssertEqual(copies, ["/Applications/KeyPath.app", "/Users/test/Old/KeyPath.app"])
    }

    func testDisplayLocationUsesFinderNamesForHomeAndICloud() {
        let home = "/Users/test"
        XCTAssertEqual(
            DuplicateAppDetector.displayLocation(
                forAppAt: home + "/Library/Mobile Documents/com~apple~CloudDocs/Documents/Codex/KeyPath.app", home: home
            ),
            "iCloud Drive \u{203A} Documents \u{203A} Codex"
        )
        XCTAssertEqual(DuplicateAppDetector.displayLocation(forAppAt: home + "/Downloads/KeyPath.app", home: home),
                       "Home \u{203A} Downloads")
        XCTAssertEqual(DuplicateAppDetector.displayLocation(forAppAt: "/Volumes/Backup/KeyPath.app", home: home),
                       "Volumes \u{203A} Backup")
    }
}
