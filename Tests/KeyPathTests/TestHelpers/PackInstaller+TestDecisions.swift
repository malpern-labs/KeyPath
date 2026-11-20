@testable import KeyPathAppKit

extension PackInstaller {
    static func testInstaller(
        applyManagedDefault: Bool = true,
        restoreManagedDefaults: Bool = true
    ) -> PackInstaller {
        PackInstaller(
            applyManagedDefault: { applyManagedDefault },
            restoreManagedDefaults: { restoreManagedDefaults }
        )
    }
}
