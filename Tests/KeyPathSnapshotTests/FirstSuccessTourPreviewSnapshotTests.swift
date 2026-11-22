@testable import KeyPathAppKit
import KeyPathCore
import SwiftUI
import XCTest

/// Capture the composed tour, including the copy column, footer, and app label.
@MainActor
final class FirstSuccessTourPreviewSnapshotTests: ScreenshotTestCase {
    func testComposedTourPages() {
        FeatureFlags.$testOverrides.withValue(.init()) {
            FeatureFlags.setKeyboardStageRendererPreference(.swiftUI)
            let model = FirstSuccessTourPreviewModel()
            for page in FirstSuccessOnboardingSession.Step.allCases {
                model.select(page: page, scenario: page == .launcher ? .selected : .installed)
                assertScreenshot(
                    of: model.dialog(),
                    size: CGSize(width: 1120, height: 720),
                    named: "tour-page-\(page.ordinal)", precision: 0.99
                )
            }
        }
    }

    /// The window's minimum size, which a short screen or larger display
    /// scaling forces. Each page's controls must stay in view here.
    func testComposedTourPagesAtMinimumWindowSize() {
        FeatureFlags.$testOverrides.withValue(.init()) {
            FeatureFlags.setKeyboardStageRendererPreference(.swiftUI)
            let model = FirstSuccessTourPreviewModel()
            for page in FirstSuccessOnboardingSession.Step.allCases {
                model.select(page: page, scenario: page == .launcher ? .selected : .installed)
                assertScreenshot(
                    of: model.dialog(),
                    size: CGSize(width: 960, height: 520),
                    named: "tour-page-\(page.ordinal)-minimum", precision: 0.99
                )
            }
        }
    }
}
