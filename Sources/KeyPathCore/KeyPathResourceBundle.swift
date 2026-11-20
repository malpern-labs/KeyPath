import Foundation

/// Finds a SwiftPM resource bundle both beside build products and inside a signed app.
package enum KeyPathResourceBundle {
    package static func resolve(
        named bundleName: String, mainBundle: Bundle, codeBundle: Bundle,
        accepting includesRequiredResources: (Bundle) -> Bool = { _ in true }
    ) -> Bundle {
        let candidates = [
            mainBundle.resourceURL?.appendingPathComponent(bundleName),
            codeBundle.resourceURL?.appendingPathComponent(bundleName),
            mainBundle.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
            codeBundle.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
            mainBundle.resourceURL,
            codeBundle.resourceURL,
        ].compactMap { $0 }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate), includesRequiredResources(bundle) {
                return bundle
            }
        }

        return mainBundle
    }
}
