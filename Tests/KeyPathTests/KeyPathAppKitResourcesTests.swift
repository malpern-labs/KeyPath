import Foundation
import KeyPathCore
import XCTest

final class KeyPathAppKitResourcesTests: XCTestCase {
    func testResolverFindsResourcesInPackagedAppLayout() throws {
        for bundleName in ["KeyPath_KeyPathAppKit.bundle", "KeyPath_KeyPathRulesCore.bundle"] {
            let fixture = try PackagedResourceBundleFixture(bundleName: bundleName)
            defer { fixture.remove() }

            let resolved = KeyPathResourceBundle.resolve(
                named: bundleName,
                mainBundle: fixture.appBundle,
                codeBundle: fixture.appBundle
            )
            XCTAssertEqual(resolved.bundleURL.standardizedFileURL, fixture.resourceBundleURL.standardizedFileURL)
            XCTAssertNotNil(resolved.url(forResource: "packaged-probe", withExtension: "txt"))
        }
    }
}

private struct PackagedResourceBundleFixture {
    let rootURL: URL
    let appBundle: Bundle
    let resourceBundleURL: URL

    init(bundleName: String) throws {
        let fileManager = FileManager.default
        rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("keypath-packaged-resources-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("KeyPath.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        resourceBundleURL = resourcesURL.appendingPathComponent(bundleName, isDirectory: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try Self.writeInfoPlist(
            to: contentsURL.appendingPathComponent("Info.plist"),
            identifier: "com.keypath.tests.packaged-resources",
            packageType: "APPL"
        )

        try fileManager.createDirectory(at: resourceBundleURL, withIntermediateDirectories: true)
        try Self.writeInfoPlist(
            to: resourceBundleURL.appendingPathComponent("Info.plist"),
            identifier: "com.keypath.tests.appkit-resources",
            packageType: "BNDL"
        )
        try Data("packaged".utf8).write(
            to: resourceBundleURL.appendingPathComponent("packaged-probe.txt")
        )

        appBundle = try XCTUnwrap(Bundle(url: appURL))
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func writeInfoPlist(
        to url: URL,
        identifier: String,
        packageType: String
    ) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": identifier,
                "CFBundleName": "KeyPath Resource Fixture",
                "CFBundlePackageType": packageType,
                "CFBundleVersion": "1",
            ],
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }
}
