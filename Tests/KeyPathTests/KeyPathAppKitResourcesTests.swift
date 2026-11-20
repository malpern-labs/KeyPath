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

    func testResolverSkipsAnEarlierCopyWithoutTheRequestedResources() throws {
        let name = "KeyPath_KeyPathRulesCore.bundle"
        let fixture = try PackagedResourceBundleFixture(bundleName: name)
        defer { fixture.remove() }
        let sibling = try fixture.addSiblingBundle(named: name)

        let resolved = KeyPathResourceBundle.resolve(
            named: name, mainBundle: fixture.appBundle, codeBundle: fixture.appBundle
        ) { bundle in
            bundle.url(forResource: "macbook-us", withExtension: "json", subdirectory: "Keyboards") != nil
        }

        XCTAssertEqual(resolved.bundleURL.standardizedFileURL, sibling.standardizedFileURL)
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

    func addSiblingBundle(named name: String) throws -> URL {
        let sibling = rootURL.appendingPathComponent(name, isDirectory: true)
        let keyboards = sibling.appendingPathComponent("Keyboards", isDirectory: true)
        try FileManager.default.createDirectory(at: keyboards, withIntermediateDirectories: true)
        try Self.writeInfoPlist(
            to: sibling.appendingPathComponent("Info.plist"),
            identifier: "com.keypath.tests.rules-resources",
            packageType: "BNDL"
        )
        try Data("{}".utf8).write(to: keyboards.appendingPathComponent("macbook-us.json"))
        return sibling
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
