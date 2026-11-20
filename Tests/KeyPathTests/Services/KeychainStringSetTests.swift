import Foundation
@testable import KeyPathAppKit
import Security
import XCTest

/// Routine tests never touch the host login Keychain.
@MainActor
final class KeychainStringSetTests: XCTestCase {
    func testInsertRemoveAndReloadFromStorage() {
        let memory = MemoryKeychain()
        let account = "keypath-tests-\(UUID().uuidString)"
        let set = KeychainStringSet(service: "com.keypath.tests", account: account, access: memory.access)
        defer { set.removeAll() }
        XCTAssertTrue(set.insert("a"))
        XCTAssertTrue(set.insert("b"))

        let reloaded = KeychainStringSet(service: "com.keypath.tests", account: account, access: memory.access)
        XCTAssertEqual(reloaded.members, ["a", "b"])

        XCTAssertTrue(reloaded.remove("a"))
        XCTAssertEqual(KeychainStringSet(service: "com.keypath.tests", account: account, access: memory.access).members, ["b"])

        reloaded.removeAll()
        XCTAssertTrue(KeychainStringSet(service: "com.keypath.tests", account: account, access: memory.access).members.isEmpty)
    }

    func testScriptApprovalsRoundTrip() {
        let memory = MemoryKeychain()
        let items = KeychainStringSet(service: "com.keypath.tests", account: "keypath-tests-\(UUID().uuidString)", access: memory.access)
        defer { items.removeAll() }
        let store = KeychainScriptApprovalStore(items: items)
        XCTAssertTrue(store.approve(path: "/tmp/x.sh", digest: "d1"))
        XCTAssertTrue(store.isApproved(path: "/tmp/x.sh", digest: "d1"))
        XCTAssertFalse(store.isApproved(path: "/tmp/x.sh", digest: "d2"))
        XCTAssertEqual(store.count, 1)
    }

    func testFailedReadCannotOverwriteStoredApprovals() throws {
        let memory = MemoryKeychain()
        memory.data = try JSONEncoder().encode(["existing"])
        let original = memory.data
        memory.readStatus = errSecInteractionNotAllowed
        let set = KeychainStringSet(account: "isolated", access: memory.access)
        XCTAssertFalse(set.insert("replacement"))
        XCTAssertEqual(memory.data, original)
        memory.readStatus = nil
        XCTAssertEqual(set.members, ["existing"])
    }

    func testFailedWritePreservesTheCachedMembers() {
        let memory = MemoryKeychain()
        let set = KeychainStringSet(account: "isolated", access: memory.access)
        XCTAssertTrue(set.insert("existing"))
        memory.writeStatus = errSecInteractionNotAllowed
        XCTAssertFalse(set.insert("replacement"))
        XCTAssertEqual(set.members, ["existing"])
    }

    @MainActor
    private final class MemoryKeychain {
        var data: Data?
        var readStatus: OSStatus?
        var writeStatus: OSStatus?

        var access: KeychainStringSet.Access {
            .init(
                read: { _ in
                    if let status = self.readStatus { return (status, nil) }
                    return (self.data == nil ? errSecItemNotFound : errSecSuccess, self.data)
                },
                update: { _, data in
                    if let status = self.writeStatus { return status }
                    guard self.data != nil else { return errSecItemNotFound }
                    self.data = data
                    return errSecSuccess
                },
                add: { _, data in
                    if let status = self.writeStatus { return status }
                    self.data = data
                    return errSecSuccess
                },
                delete: { _ in self.data = nil; return errSecSuccess }
            )
        }
    }
}

/// Explicit integration coverage for a disposable, unlocked test machine.
@MainActor
final class KeychainStringSetIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment["KEYPATH_KEYCHAIN_INTEGRATION"] == "1" else {
            throw XCTSkip("Set KEYPATH_KEYCHAIN_INTEGRATION=1 on an unlocked test machine")
        }
    }

    func testInsertRemoveAndReloadFromKeychain() throws {
        let account = "keypath-tests-\(UUID().uuidString)"
        let set = KeychainStringSet(service: "com.keypath.tests", account: account)
        defer { set.removeAll() }
        guard set.insert("a") else { throw XCTSkip("The Keychain refused the write here") }
        XCTAssertTrue(set.insert("b"))

        let reloaded = KeychainStringSet(service: "com.keypath.tests", account: account)
        XCTAssertEqual(reloaded.members, ["a", "b"])

        XCTAssertTrue(reloaded.remove("a"))
        XCTAssertEqual(KeychainStringSet(service: "com.keypath.tests", account: account).members, ["b"])

        reloaded.removeAll()
        XCTAssertTrue(KeychainStringSet(service: "com.keypath.tests", account: account).members.isEmpty)
    }

    func testScriptApprovalsRoundTrip() throws {
        let items = KeychainStringSet(service: "com.keypath.tests", account: "keypath-tests-\(UUID().uuidString)")
        defer { items.removeAll() }
        let store = KeychainScriptApprovalStore(items: items)
        guard store.approve(path: "/tmp/x.sh", digest: "d1") else { throw XCTSkip("The Keychain refused the write here") }
        XCTAssertTrue(store.isApproved(path: "/tmp/x.sh", digest: "d1"))
        XCTAssertFalse(store.isApproved(path: "/tmp/x.sh", digest: "d2"))
        XCTAssertEqual(store.count, 1)
    }
}
