import KeyPathCore
import XCTest

final class FeatureFlagsTestSeamTests: XCTestCase {
    func testScopedSetterIsIsolatedFromProcessDefaults() {
        FeatureFlags.$testOverrides.withValue(.init()) {
            FeatureFlags.setSimulatorAndVirtualKeysEnabled(false)
            XCTAssertFalse(FeatureFlags.simulatorAndVirtualKeysEnabled)
        }

        XCTAssertTrue(FeatureFlags.simulatorAndVirtualKeysEnabled)
    }

    func testNestedScopeHasIndependentDefaultsAndRestoresOuterValues() {
        FeatureFlags.$testOverrides.withValue(.init()) {
            FeatureFlags.setCaptureListenOnlyEnabled(false)
            FeatureFlags.setLearningTipsMode(.alwaysOn)

            FeatureFlags.$testOverrides.withValue(.init()) {
                XCTAssertTrue(FeatureFlags.captureListenOnlyEnabled)
                XCTAssertEqual(FeatureFlags.learningTipsMode, .off)
                FeatureFlags.setLearningTipsMode(.untilLearned)
            }

            XCTAssertFalse(FeatureFlags.captureListenOnlyEnabled)
            XCTAssertEqual(FeatureFlags.learningTipsMode, .alwaysOn)
        }

        XCTAssertTrue(FeatureFlags.captureListenOnlyEnabled)
        XCTAssertEqual(FeatureFlags.learningTipsMode, .off)
    }

    @MainActor
    func testOnlyChildTasksInheritTheScope() async {
        await FeatureFlags.$testOverrides.withValue(.init()) {
            FeatureFlags.setSimulatorAndVirtualKeysEnabled(false)
            let child = Task { FeatureFlags.simulatorAndVirtualKeysEnabled }
            let independent = Task.detached { FeatureFlags.simulatorAndVirtualKeysEnabled }

            let scopedValue = await child.value
            let independentValue = await independent.value
            XCTAssertFalse(scopedValue)
            XCTAssertTrue(independentValue)
        }
    }

    func testUnscopedSetterUsesCompiledDefaultInTests() {
        FeatureFlags.setSimulatorAndVirtualKeysEnabled(false)

        XCTAssertTrue(FeatureFlags.simulatorAndVirtualKeysEnabled)
    }
}
