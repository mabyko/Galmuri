import XCTest
import GalmuriCore
@testable import GalmuriApp

@MainActor final class PendingChangesTests: XCTestCase {
    private func fixture() throws -> AppStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriPending-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(sampleData: true, directory: root)
        store.navigation = "changes"
        return store
    }
    func testDeletionShowsBothDeletedItemAndParentChangeWithoutTouchingOriginal() throws {
        let store = try fixture(), profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        var initial = profile.working
        try initial.move([item.id], to: SampleData.bar)
        let base = try BookmarkFile(data: profile.base.serialize(initial))
        try base.original.write(to: profile.source)
        store.workspace.profiles[0].base = base; store.workspace.profiles[0].working = base.tree
        let parent = SampleData.bar, original = try Data(contentsOf: profile.source)
        XCTAssertTrue(store.edit { try $0.remove([item.id]) })
        XCTAssertEqual(store.pendingCount, 2)
        XCTAssertEqual(Set(store.rows.map(\.id)), [parent, item.id])
        XCTAssertEqual(store.rows.count, store.pendingCount)
        XCTAssertTrue(store.isRemovedRow(item.id)); XCTAssertFalse(store.canEditRow(item.id))
        XCTAssertEqual(store.rowFolderPath(try XCTUnwrap(store.rows.first { $0.id == item.id })), base.tree.path(to: parent))
        store.selection = [item.id]; XCTAssertFalse(store.canMutateSelection)
        let restore = try XCTUnwrap(store.revertRequest(for: [item.id]))
        XCTAssertTrue(store.resetWorkingCopy(restore)); XCTAssertEqual(store.pendingCount, 0); XCTAssertTrue(store.rows.isEmpty)
        XCTAssertEqual(try Data(contentsOf: profile.source), original)
    }
    func testRootOrderChangeIsVisibleButCannotBeEditedMovedOrDeletedAsAnItem() throws {
        let store = try fixture(), root = SampleData.bar
        let first = try XCTUnwrap(store.tree?.nodes[root]?.children.first)
        XCTAssertTrue(store.edit { try $0.reorder(first, offset: 1) })
        XCTAssertEqual(store.pendingCount, 1); XCTAssertEqual(store.rows.map(\.id), [root])
        store.selection = [root]; XCTAssertFalse(store.canEditRow(root)); XCTAssertFalse(store.canMutateSelection)
        XCTAssertNil(store.deletionRequest(for: [root]))
        XCTAssertNotNil(store.revertRequest(for: [root]))
    }
    func testConnectionDetailsCapturesCurrentProfileWithoutChangingSavedWork() throws {
        let store = try fixture(), before = try XCTUnwrap(store.profile)
        let workspace = try Data(contentsOf: store.workspaceURL)
        store.showConnectionDetails()
        XCTAssertEqual(store.connectionDetails?.id, before.id)
        XCTAssertEqual(store.connectionDetails?.working, before.working)
        XCTAssertEqual(store.connectionDetails?.base, before.base)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), workspace)
        store.connectionDetails = nil; store.selectedProfileID = nil; store.showConnectionDetails()
        XCTAssertNil(store.connectionDetails)
    }
    func testPendingListCoversWholeChangedSetAcrossMoveAddAndDeletedSubtreeAfterRelaunch() throws {
        let store = try fixture(), profile = try XCTUnwrap(store.profile)
        let folder = try XCTUnwrap(profile.working.nodes[SampleData.bar]?.children.first)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil && $0.parent != folder })
        let removed = profile.working.descendants(of: folder)
        XCTAssertTrue(store.edit { tree in
            try tree.move([item.id], to: SampleData.other)
            try tree.remove([folder])
            _ = try tree.add(name: "New", url: "https://example.test/new", to: SampleData.bar)
        })
        let reopened = AppStore(sampleData: true, directory: store.directory); reopened.navigation = "changes"
        XCTAssertFalse(reopened.canUndo)
        XCTAssertEqual(Set(reopened.rows.map(\.id)), reopened.profile?.changedIDs)
        XCTAssertEqual(reopened.rows.count, reopened.pendingCount)
        XCTAssertTrue(removed.isSubset(of: Set(reopened.rows.map(\.id))))
        reopened.search = profile.working.nodes[folder]!.name
        XCTAssertTrue(reopened.rows.contains { $0.id == folder })
        reopened.navigation = "all"
        XCTAssertTrue(Set(reopened.rows.map(\.id)).isDisjoint(with: removed))
    }
}
