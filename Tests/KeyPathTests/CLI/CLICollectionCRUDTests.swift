import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class CLICollectionCRUDTests: XCTestCase {
    private var facade: CollectionsFacade!
    private var fixture: CLIStoreFixture!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try CLIStoreFixture()
        facade = CollectionsFacade(store: fixture.collections)
    }

    override func tearDown() async throws {
        facade = nil
        try fixture?.remove()
        fixture = nil
        try await super.tearDown()
    }

    // MARK: - createCollection

    func testCollectionCreate() async throws {
        let result = try await facade.createCollection(name: "Test CLI", category: nil, summary: "A test collection")
        XCTAssertEqual(result.name, "Test CLI")
        XCTAssertEqual(result.summary, "A test collection")
        XCTAssertTrue(result.isEnabled)
        XCTAssertEqual(result.mappingCount, 0)
    }

    func testCollectionCreateWithCategory() async throws {
        let result = try await facade.createCollection(name: "Nav Keys", category: "navigation", summary: "")
        XCTAssertEqual(result.name, "Nav Keys")

        let collections = await fixture.collections.loadCollections()
        let created = collections.first(where: { $0.id.uuidString == result.id })
        XCTAssertEqual(created?.category, .navigation)
    }

    func testConcurrentFacadesKeepCollectionsInTheirOwnDirectories() async throws {
        let otherFixture = try CLIStoreFixture()
        defer { try? otherFixture.remove() }
        let firstFacade = try XCTUnwrap(facade)
        let otherFacade = CollectionsFacade(store: otherFixture.collections)

        async let first = firstFacade.createCollection(name: "First fixture", category: nil, summary: "")
        async let second = otherFacade.createCollection(name: "Second fixture", category: nil, summary: "")
        _ = try await (first, second)

        let firstCollections = await firstFacade.loadRuleCollections()
        let otherCollections = await otherFacade.loadRuleCollections()
        XCTAssertTrue(firstCollections.contains { $0.name == "First fixture" })
        XCTAssertFalse(firstCollections.contains { $0.name == "Second fixture" })
        XCTAssertTrue(otherCollections.contains { $0.name == "Second fixture" })
        XCTAssertFalse(otherCollections.contains { $0.name == "First fixture" })
    }

    // MARK: - renameCollection

    func testCollectionRename() async throws {
        _ = try await facade.createCollection(name: "Old Name", category: nil, summary: "")
        let oldName = try await facade.renameCollection(nameOrId: "Old Name", newName: "New Name")
        XCTAssertEqual(oldName, "Old Name")

        let shown = try await facade.showCollection(nameOrId: "New Name")
        XCTAssertNotNil(shown)
        XCTAssertEqual(shown?.name, "New Name")
    }

    // MARK: - deleteCollection

    func testCollectionDelete() async throws {
        _ = try await facade.createCollection(name: "Doomed", category: nil, summary: "")
        let deleted = try await facade.deleteCollection(nameOrId: "Doomed")
        XCTAssertTrue(deleted)

        let shown = try await facade.showCollection(nameOrId: "Doomed")
        XCTAssertNil(shown)
    }

    func testCollectionDeleteNonexistentFails() async throws {
        let deleted = try await facade.deleteCollection(nameOrId: "NoSuchCollection-ZZZZZ")
        XCTAssertFalse(deleted)
    }

    // MARK: - duplicateCollection

    func testCollectionDuplicate() async throws {
        _ = try await facade.createCollection(name: "Original", category: nil, summary: "The original")
        let dup = try await facade.duplicateCollection(nameOrId: "Original", newName: "Clone")
        XCTAssertNotNil(dup)
        XCTAssertEqual(dup?.name, "Clone")
        XCTAssertFalse(dup?.isEnabled ?? true)
    }

    // MARK: - reorderCollection

    func testCollectionReorder() async throws {
        _ = try await facade.createCollection(name: "First", category: nil, summary: "")
        _ = try await facade.createCollection(name: "Second", category: nil, summary: "")
        _ = try await facade.createCollection(name: "Third", category: nil, summary: "")

        let moved = try await facade.reorderCollection(nameOrId: "Third", position: 0)
        XCTAssertTrue(moved)

        let collections = await facade.loadRuleCollections()
        let names = collections.map(\.name)
        XCTAssertEqual(names.first, "Third")
    }
}
