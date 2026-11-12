import XCTest
import GalmuriCore
@testable import GalmuriApp

final class EditorNavigationTests: XCTestCase {
    @MainActor
    private func fixture() throws -> (store: AppStore, parent: String, child: String, first: String, second: String, deep: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriNavigation-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory)
        var parent = "", child = "", first = "", second = "", deep = ""
        XCTAssertTrue(store.edit { tree in
            parent = try tree.add(name: "Navigation fixture", url: nil, to: SampleData.bar)
            first = try tree.add(name: "Direct A", url: "https://example.com/a", to: parent)
            child = try tree.add(name: "Nested", url: nil, to: parent)
            deep = try tree.add(name: "Nested link", url: "https://example.com/nested", to: child)
            second = try tree.add(name: "Direct B", url: "https://example.com/b", to: parent)
        })
        return (store, parent, child, first, second, deep)
    }

    @MainActor
    func testFolderShowsDirectChildrenAndSearchIncludesDescendants() throws {
        let f = try fixture(), store = f.store
        let before = store.tree, saved = try Data(contentsOf: store.workspaceURL)
        store.navigation = f.parent
        XCTAssertEqual(store.rows.map(\.id), [f.child, f.first, f.second])
        XCTAssertFalse(store.rows.contains { $0.id == f.deep })
        store.search = "nested"
        XCTAssertEqual(store.rows.map(\.id), [f.child, f.deep])
        XCTAssertEqual(store.tree, before)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), saved)
    }

    @MainActor
    func testBackForwardAndUpAreDifferentAndRestoreSearchContext() throws {
        let f = try fixture(), store = f.store
        store.navigation = "duplicates"; store.search = "interface"
        store.navigation = f.parent; store.navigation = f.child
        XCTAssertEqual(store.folderPath.map(\.id), [SampleData.bar, f.parent, f.child])
        XCTAssertTrue(store.canGoBack); XCTAssertFalse(store.canGoForward)
        store.selection = [f.deep]; store.goBack()
        XCTAssertEqual(store.navigation, f.parent); XCTAssertTrue(store.selection.isEmpty)
        store.goBack()
        XCTAssertEqual(store.navigation, "duplicates"); XCTAssertEqual(store.search, "interface")
        store.goForward()
        XCTAssertEqual(store.navigation, f.parent); XCTAssertTrue(store.search.isEmpty)
        store.goForward(); store.goUp()
        XCTAssertEqual(store.navigation, f.parent)
        store.goUp(); XCTAssertEqual(store.navigation, SampleData.bar)
        store.goUp(); XCTAssertEqual(store.navigation, "all")
        store.goUp(); XCTAssertEqual(store.navigation, "all")
    }

    @MainActor
    func testNewDestinationDiscardsForwardHistoryAndRepeatedSelectionIsNoOp() throws {
        let f = try fixture(), store = f.store
        store.navigation = f.parent; store.navigation = f.child; store.goBack()
        XCTAssertTrue(store.canGoForward)
        store.navigation = f.parent
        XCTAssertTrue(store.canGoForward)
        store.navigation = "changes"
        XCTAssertFalse(store.canGoForward)
        store.goForward(); XCTAssertEqual(store.navigation, "changes")
    }

    @MainActor
    func testHistorySkipsDeletedFoldersAndCurrentDeletionReturnsToAll() throws {
        let f = try fixture(), store = f.store
        store.navigation = f.parent; store.navigation = f.child
        XCTAssertTrue(store.edit { try $0.remove([f.child]) })
        XCTAssertEqual(store.navigation, "all")
        store.goBack(); XCTAssertEqual(store.navigation, f.parent)
        store.goBack(); XCTAssertEqual(store.navigation, "all")
        XCTAssertFalse(store.canGoBack)
        store.undo()
        store.navigation = f.child
        XCTAssertEqual(store.folderPath.map(\.id), [SampleData.bar, f.parent, f.child])
    }

    @MainActor
    func testProfileSwitchClearsHistoryEvenWithIdenticalFolderIDs() throws {
        let f = try fixture(), store = f.store, first = try XCTUnwrap(store.profile)
        store.navigation = f.parent; store.navigation = f.child
        let second = ConnectedProfile(name: "Other", source: first.source, base: first.base)
        store.workspace.profiles.append(second); store.switchProfile(second.id)
        XCTAssertEqual(store.navigation, "all"); XCTAssertFalse(store.canGoBack); XCTAssertFalse(store.canGoForward)
        store.switchProfile(first.id); store.goBack()
        XCTAssertEqual(store.navigation, "all"); XCTAssertTrue(store.folderPath.isEmpty)
    }

    @MainActor
    func testGroupingPreservesStoredOrderAndReorderMovesWithinType() throws {
        let f = try fixture(), store = f.store, profile = try XCTUnwrap(store.profile)
        let original = try Data(contentsOf: profile.source)
        store.navigation = f.parent
        XCTAssertEqual(store.tree?.nodes[f.parent]?.children, [f.first, f.child, f.second])
        XCTAssertEqual(store.rows.map(\.id), [f.child, f.first, f.second])
        store.reorder(f.second, direction: -1)
        XCTAssertEqual(store.tree?.nodes[f.parent]?.children, [f.second, f.child, f.first])
        XCTAssertEqual(store.rows.map(\.id), [f.child, f.second, f.first])
        XCTAssertEqual(try Workspace.load(from: store.workspaceURL).profiles[0].working, store.tree)
        store.undo(); XCTAssertEqual(store.tree, profile.working)
        let before = try Data(contentsOf: store.workspaceURL)
        store.reorder(f.child, direction: -1); store.reorder(f.first, direction: -1); store.reorder(f.second, direction: Int.max)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertEqual(try Data(contentsOf: profile.source), original)
    }

    @MainActor
    func testUndoCreationLeavesNoMissingFolderDestination() throws {
        let f = try fixture(), store = f.store
        store.navigation = f.child
        store.undo()
        XCTAssertEqual(store.navigation, "all")
        XCTAssertTrue(store.folderPath.isEmpty)
        store.goBack()
        XCTAssertEqual(store.navigation, "all")
        XCTAssertFalse(store.canGoBack)
    }

    @MainActor
    func testGlobalGroupingKeepsEveryDistinctItemAndNavigationIsTransient() throws {
        let f = try fixture(), store = f.store, profile = try XCTUnwrap(store.profile)
        let expected = Set(profile.working.nodes.keys).subtracting(profile.working.roots.values)
        XCTAssertEqual(Set(store.rows.map(\.id)), expected)
        let firstLink = try XCTUnwrap(store.rows.firstIndex { !$0.isFolder })
        XCTAssertTrue(store.rows[..<firstLink].allSatisfy(\.isFolder))
        XCTAssertTrue(store.rows[firstLink...].allSatisfy { !$0.isFolder })
        store.navigation = f.child; store.goBack(); store.goForward()
        let reopened = AppStore(sampleData: true, directory: store.directory)
        XCTAssertEqual(reopened.tree, profile.working); XCTAssertEqual(reopened.navigation, "all")
        XCTAssertFalse(reopened.canGoBack); XCTAssertFalse(reopened.canGoForward)
    }
}
