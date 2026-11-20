@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class PackOwnershipTests: XCTestCase {
    private var fixture: CLIStoreFixture!
    private var tracker: InstalledPackTracker!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try CLIStoreFixture()
        tracker = InstalledPackTracker(fileURL: fixture.directory.appendingPathComponent("installed-packs.json"))
    }

    override func tearDown() async throws {
        tracker = nil
        try fixture.remove()
        fixture = nil
        try await super.tearDown()
    }

    // MARK: - managedCollectionIDs

    func testManagedCollectionIDsSinglePack() throws {
        let pack = try XCTUnwrap(PackRegistry.pack(id: "com.keypath.pack.home-row-mods"))
        XCTAssertEqual(pack.managedCollectionIDs, [RuleCollectionIdentifier.homeRowMods])
    }

    func testManagedCollectionIDsVallack() throws {
        let pack = try XCTUnwrap(PackRegistry.pack(id: "com.keypath.pack.vallack-system"))
        let ids = Set(pack.managedCollectionIDs)
        XCTAssertEqual(ids.count, 4)
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.vallackNavigation))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowMods))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowLayerToggles))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowArrows))
    }

    func testManagedCollectionIDsVisualOnly() throws {
        let pack = try XCTUnwrap(PackRegistry.pack(id: "com.keypath.pack.kindavim"))
        XCTAssertTrue(pack.managedCollectionIDs.isEmpty)
    }

    // MARK: - packManagingCollection

    func testPackManagingCollectionWhenInstalled() async throws {
        // Ensure vallack-system is not installed so HRM is self-managed
        try? await tracker.remove(packID: "com.keypath.pack.vallack-system")

        let record = InstalledPackRecord(
            packID: "com.keypath.pack.home-row-mods",
            version: "1.0.0"
        )
        try await tracker.upsert(record)

        let owner = await tracker.packManagingCollection(
            RuleCollectionIdentifier.homeRowMods
        )
        XCTAssertNotNil(owner)
        XCTAssertEqual(owner?.packName, "Home Row Mods")
    }

    func testPackManagingCollectionWhenNotInstalled() async throws {
        if await tracker.isInstalled(packID: "com.keypath.pack.chord-groups") {
            try await tracker.remove(packID: "com.keypath.pack.chord-groups")
        }

        let owner = await tracker.packManagingCollection(
            RuleCollectionIdentifier.chordGroups
        )
        XCTAssertNil(owner)
    }

    func testVallackOwnsManagedCollections() async throws {
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.vallack-system",
            version: "1.0.0"
        )
        try await tracker.upsert(record)

        let navOwner = await tracker.packManagingCollection(
            RuleCollectionIdentifier.vallackNavigation
        )
        let hrmOwner = await tracker.packManagingCollection(
            RuleCollectionIdentifier.homeRowMods
        )
        let togglesOwner = await tracker.packManagingCollection(
            RuleCollectionIdentifier.homeRowLayerToggles
        )
        let arrowsOwner = await tracker.packManagingCollection(
            RuleCollectionIdentifier.homeRowArrows
        )

        XCTAssertEqual(navOwner?.packName, "Home Row Navigation System")
        XCTAssertEqual(hrmOwner?.packName, "Home Row Navigation System")
        XCTAssertEqual(togglesOwner?.packName, "Home Row Navigation System")
        XCTAssertEqual(arrowsOwner?.packName, "Home Row Navigation System")
    }

    // MARK: - Self-managed badge filtering

    func testSelfManagedPackShouldNotShowBadge() async throws {
        let packID = "com.keypath.pack.key-repeat-control"
        let record = InstalledPackRecord(packID: packID, version: "1.0.0")
        try await tracker.upsert(record)

        let collectionID = RuleCollectionIdentifier.keyRepeatControl
        let owner = await tracker.packManagingCollection(collectionID)
        XCTAssertNotNil(owner, "Pack should report owning its collection")

        let pack = try PackRegistry.pack(id: XCTUnwrap(owner?.packID))
        XCTAssertEqual(
            pack?.associatedCollectionID, collectionID,
            "Fast Navigation's associatedCollectionID should match its own collection — badge must be hidden"
        )
    }

    func testVallackExternallyManagedCollectionShouldShowBadge() async throws {
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.vallack-system",
            version: "1.0.0"
        )
        try await tracker.upsert(record)

        let owner = await tracker.packManagingCollection(
            RuleCollectionIdentifier.homeRowMods
        )
        XCTAssertNotNil(owner)

        let pack = try XCTUnwrap(try PackRegistry.pack(id: XCTUnwrap(owner?.packID)))
        XCTAssertNotEqual(
            pack.associatedCollectionID, RuleCollectionIdentifier.homeRowMods,
            "Vallack's associatedCollectionID is vallackNavigation, not homeRowMods — badge should show"
        )
    }

    func testAllPacksWithAssociatedCollectionAreSelfManaged() throws {
        for pack in PackRegistry.starterKit where pack.associatedCollectionID != nil {
            XCTAssertTrue(
                try pack.managedCollectionIDs.contains(XCTUnwrap(pack.associatedCollectionID)),
                "\(pack.name) manages collections \(pack.managedCollectionIDs) but its associatedCollectionID \(pack.associatedCollectionID!) is missing"
            )
        }
    }

    func testOwnershipClearsOnUninstall() async throws {
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.chord-groups",
            version: "1.0.0"
        )
        try await tracker.upsert(record)

        let before = await tracker.packManagingCollection(
            RuleCollectionIdentifier.chordGroups
        )
        XCTAssertNotNil(before)

        try await tracker.remove(packID: "com.keypath.pack.chord-groups")

        let after = await tracker.packManagingCollection(
            RuleCollectionIdentifier.chordGroups
        )
        XCTAssertNil(after)
    }

    // MARK: - CLI facade blocks managed collections

    func testCollectionsFacadeBlocksEnableOnManagedCollection() async throws {
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.chord-groups",
            version: "1.0.0"
        )
        try await tracker.upsert(record)

        let facade = CollectionsFacade(store: fixture.collections, installedPackTracker: tracker)
        do {
            _ = try await facade.enableCollection(nameOrId: "Chord Groups")
            XCTFail("Should throw PackManagedCollectionError")
        } catch is PackManagedCollectionError {
            // expected
        }
    }

    func testCollectionsFacadeBlocksDisableOnManagedCollection() async throws {
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.chord-groups",
            version: "1.0.0"
        )
        try await tracker.upsert(record)

        let facade = CollectionsFacade(store: fixture.collections, installedPackTracker: tracker)
        do {
            _ = try await facade.disableCollection(nameOrId: "Chord Groups")
            XCTFail("Should throw PackManagedCollectionError")
        } catch is PackManagedCollectionError {
            // expected
        }
    }

    func testPackOwnershipDoesNotLeakIntoAnotherFacade() async throws {
        let other = try CLIStoreFixture()
        defer { try? other.remove() }
        let otherTracker = InstalledPackTracker(fileURL: other.directory.appendingPathComponent("installed-packs.json"))
        try await tracker.upsert(InstalledPackRecord(packID: "com.keypath.pack.chord-groups", version: "1.0.0"))

        let otherFacade = CollectionsFacade(store: other.collections, installedPackTracker: otherTracker)
        let enabled = try await otherFacade.enableCollection(nameOrId: "Chord Groups")
        XCTAssertNotNil(enabled)
        let otherPacks = await otherTracker.allInstalled()
        XCTAssertTrue(otherPacks.isEmpty)
        let retained = await tracker.isInstalled(packID: "com.keypath.pack.chord-groups")
        XCTAssertTrue(retained)
    }

    // MARK: - Rules-tab coverage (no orange boxes)

    /// Every catalog collection the Rules tab renders as its own row
    /// (not a system default, not hidden behind an owningPackID) must have
    /// an associated pack in the starter kit. Rows without one render with
    /// the orange "no detail page" border in RulesSummaryView+RowBuilder —
    /// Neovim Terminal and Sequences shipped that way until their packs
    /// were added for 1.0. This pins the invariant.
    func testEveryRenderedCatalogCollectionHasAnAssociatedPack() {
        let packCoveredIDs = Set(PackRegistry.starterKit.compactMap(\.associatedCollectionID))
        let uncovered = RuleCollectionCatalog().defaultCollections().filter { collection in
            !collection.isSystemDefault
                && collection.owningPackID == nil
                && !packCoveredIDs.contains(collection.id)
        }
        XCTAssertTrue(
            uncovered.isEmpty,
            "Collections rendered without a pack detail page (orange box): \(uncovered.map(\.name))"
        )
    }
}
