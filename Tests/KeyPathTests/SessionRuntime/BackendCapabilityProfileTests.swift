@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
import Synchronization
import XCTest

/// Phase 1 of docs/architecture/rules-admission-review.md: what the backend can
/// emit comes from the bridge, and every former hard-coded list gives the same
/// answer through it.
final class BackendCapabilityProfileTests: XCTestCase {
    private func bridgeProfile() throws -> BackendCapabilityProfile {
        try SessionBridgeTestFixture.requireAvailable()
        let host = SessionBridgeTestFixture.runtimeHost
        return BackendCapabilityProfile { key in
            KanataHostBridge.sessionOutputKeySupported(
                runtimeHost: host, keyName: key, supportedUsages: SessionKeyMap.sessionOutputUsages
            )
        }
    }

    func testBridgeAnswersTheSessionOutputRule() throws {
        let profile = try bridgeProfile()
        for key in ["a", "f1", "f12", "home", "del", "kp5", "caps", "C-S-n", "M-spc",
                    // Phase 6: the media keys the worker posts as system-defined events.
                    "volu", "vold", "voldwn", "mute", "pp", "next", "prev", "brup", "brdn", "brdown"]
        {
            XCTAssertTrue(profile.canEmit(kanataKey: key), key)
        }
        // Consumer page, but not a key the worker posts.
        XCTAssertFalse(profile.canEmit(kanataKey: "calc"))
    }

    func testFormerHardCodedListsGiveTheSameAnswersThroughTheBridge() throws {
        try BackendCapabilityProfile.$testOverride.withValue(bridgeProfile()) {
            // SystemActionInfo: every offered action, media included (phase 6).
            let unsupported = Set(SystemActionInfo.allActions.filter { !$0.isSupportedInDriverlessSession }.map(\.id))
            XCTAssertEqual(unsupported, [])
            // FunctionKeyMode: both modes emit what the worker can post.
            XCTAssertTrue(FunctionKeyMode.media.isSupportedInDriverlessSession)
            XCTAssertTrue(FunctionKeyMode.function.isSupportedInDriverlessSession)
            // Catalog: nothing built in is unavailable any more.
            let unavailable = RuleCollectionCatalog().originalCollections()
                .filter { RuleCollectionCatalog.driverlessUnavailableReason(for: $0.id) != nil }.map(\.id)
            XCTAssertEqual(unavailable, [])
        }
    }

    func testConcurrentScopesKeepIndependentProfiles() async {
        let original = BackendCapabilityProfile.shared
        let supportsOutput = BackendCapabilityProfile { _ in true }
        let refusesOutput = BackendCapabilityProfile { _ in false }
        let answers = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for profile in [supportsOutput, refusesOutput] {
                group.addTask {
                    await BackendCapabilityProfile.$testOverride.withValue(profile) {
                        await Task {
                            BackendCapabilityProfile.shared === profile
                                && BackendCapabilityProfile.shared.canEmit(kanataKey: "volu") == (profile === supportsOutput)
                        }.value
                    }
                }
            }
            var answers: [Bool] = []
            for await answer in group {
                answers.append(answer)
            }
            return answers
        }
        XCTAssertEqual(answers, [true, true])
        XCTAssertTrue(BackendCapabilityProfile.shared === original)
    }

    func testModifierPrefixesAreStrippedBeforeAsking() {
        XCTAssertEqual(BackendCapabilityProfile.baseKey(of: "C-S-n"), "n")
        XCTAssertEqual(BackendCapabilityProfile.baseKey(of: "RA-x"), "x")
        XCTAssertEqual(BackendCapabilityProfile.baseKey(of: "C-down"), "down")
        XCTAssertEqual(BackendCapabilityProfile.baseKey(of: "M-"), "m-")
    }

    func testNoBridgeAnswerKeepsPreviousBehaviour() {
        let profile = BackendCapabilityProfile { _ in nil }
        XCTAssertTrue(profile.canEmit(kanataKey: "home"))
        XCTAssertFalse(profile.canEmit(kanataKey: "volu"))
        XCTAssertFalse(profile.canEmit(kanataKey: "brdn"))
    }

    func testAnswersAreCachedPerKey() {
        let calls = Mutex(0)
        let profile = BackendCapabilityProfile { _ in calls.withLock { $0 += 1 }; return true }
        _ = profile.canEmit(kanataKey: "a")
        _ = profile.canEmit(kanataKey: "C-a")
        XCTAssertEqual(calls.withLock { $0 }, 1)
    }

    func testConcurrentQueriesKeepIndependentCaches() async {
        let profile = BackendCapabilityProfile { key in
            switch key {
            case "a": true
            case "calc": false
            default: nil
            }
        }
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    profile.canEmit(kanataKey: "C-a")
                        && !profile.canEmit(kanataKey: "calc")
                        && profile.knowsKey("calc") == true
                        && profile.knowsKey("unknown-key") == false
                }
            }
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        XCTAssertEqual(results.count, 100)
        XCTAssertTrue(results.allSatisfy { $0 })
    }
}
