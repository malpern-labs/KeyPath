import Foundation
import KeyPathCore

private final class KeyPathAppKitBundleSentinel {}

/// Resolves this target's SwiftPM resources without using `Bundle.module`.
/// KeyPath wraps a SwiftPM command-line executable in a signed macOS `.app`, so
/// target bundles live in `Contents/Resources` rather than beside the app root
/// where SwiftPM's generated accessor searches.
enum KeyPathAppKitResources {
    static let bundle = KeyPathResourceBundle.resolve(
        named: "KeyPath_KeyPathAppKit.bundle",
        mainBundle: .main,
        codeBundle: Bundle(for: KeyPathAppKitBundleSentinel.self)
    )

    static var resourceURL: URL? {
        bundle.resourceURL ?? Bundle.main.resourceURL
    }

    static func url(forResource name: String, withExtension ext: String?) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
}
