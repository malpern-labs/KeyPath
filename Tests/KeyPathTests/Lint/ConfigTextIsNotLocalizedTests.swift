import Foundation
@testable import KeyPathRulesCore
@preconcurrency import XCTest

/// Generated config must be the same bytes in every language, so names written
/// into config comments come from `configName`, never the localized `displayName`.
final class ConfigTextIsNotLocalizedTests: XCTestCase {
    func testLayerConfigNamesAreFixedEnglish() {
        XCTAssertEqual(RuleCollectionLayer.base.configName, "Base")
        XCTAssertEqual(RuleCollectionLayer.navigation.configName, "Navigation")
        XCTAssertEqual(RuleCollectionLayer.custom("window").configName, "Window")
    }

    func testConfigRenderingDoesNotUseLocalizedLayerNames() throws {
        let folders = [
            LintScanner.path("Sources/KeyPathRulesCore"),
            LintScanner.path("Sources/KeyPathAppKit/Infrastructure/Config")
        ]
        let files = try folders.flatMap { folder in
            try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        }.filter { $0.lastPathComponent.hasPrefix("KanataConfiguration") && $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("Layer.displayName"), "\(file.lastPathComponent) writes a localized layer name into config")
        }
    }
}
