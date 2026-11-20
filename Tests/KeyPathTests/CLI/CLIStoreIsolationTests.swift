import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

@MainActor
final class CLIStoreIsolationTests: XCTestCase {
    func testConcurrentFacadesAndCleanupKeepOtherRulesIntact() async throws {
        let first = try CLIStoreFixture()
        let second = try CLIStoreFixture()
        defer {
            if FileManager.default.fileExists(atPath: first.directory.path) { try? first.remove() }
            try? second.remove()
        }
        let firstRules = RulesFacade(store: first.rules)
        let secondRules = RulesFacade(store: second.rules)

        async let firstWrite = firstRules.addRule(input: "caps", action: .keystroke(key: "esc"))
        async let secondWrite = secondRules.addRule(input: "caps", action: .keystroke(key: "tab"))
        _ = try await (firstWrite, secondWrite)
        let firstSaved = await first.rules.loadRules()
        let secondSaved = await second.rules.loadRules()
        XCTAssertEqual(firstSaved.map(\.action), [.keystroke(key: "esc")])
        XCTAssertEqual(secondSaved.map(\.action), [.keystroke(key: "tab")])

        try first.remove()
        let reloaded = CustomRulesStore(fileURL: second.directory.appendingPathComponent("CustomRules.json"))
        let afterCleanup = await reloaded.loadRules()
        XCTAssertEqual(afterCleanup.map(\.action), [.keystroke(key: "tab")])
    }
}
