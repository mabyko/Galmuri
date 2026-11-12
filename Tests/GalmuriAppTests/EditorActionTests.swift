import XCTest
import GalmuriCore
@testable import GalmuriApp

final class EditorActionTests: XCTestCase {
    @MainActor
    func testSingleDeletePersistsOnlyRequestedIdentityAndUndoRestoresIt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory)
        let profile = try XCTUnwrap(store.profile)
        let groups = Dictionary(grouping: profile.working.nodes.values.filter { $0.url != nil }, by: { $0.url! })
        let duplicates = try XCTUnwrap(groups.values.first { $0.count > 1 })
        let target = duplicates[0], other = duplicates[1]
        let original = try Data(contentsOf: profile.source)
        let request = try XCTUnwrap(store.deletionRequest(for: [target.id]))
        XCTAssertFalse(request.requiresConfirmation)
        store.selection = [other.id]
        XCTAssertTrue(store.delete(request))
        XCTAssertNil(store.tree?.nodes[target.id])
        XCTAssertNotNil(store.tree?.nodes[other.id])
        XCTAssertEqual(store.selection, [other.id])
        XCTAssertNil(try Workspace.load(from: store.workspaceURL).profiles[0].working.nodes[target.id])
        XCTAssertEqual(try Data(contentsOf: profile.source), original)
        store.undo()
        XCTAssertEqual(store.tree, profile.working)
        XCTAssertEqual(store.selection, [target.id])
        XCTAssertEqual(try Workspace.load(from: store.workspaceURL).profiles[0].working, profile.working)
    }

    @MainActor
    func testFolderImpactDeduplicatesDescendantsAndBatchRequiresConfirmation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory)
        let tree = try XCTUnwrap(store.tree)
        let folder = try XCTUnwrap(tree.nodes.values.first { $0.parent != nil && $0.isFolder && !$0.children.isEmpty })
        let child = try XCTUnwrap(folder.children.first)
        let request = try XCTUnwrap(store.deletionRequest(for: [folder.id, child]))
        XCTAssertTrue(request.requiresConfirmation)
        XCTAssertEqual(request.removedIDs, tree.descendants(of: folder.id))
        XCTAssertTrue(store.delete(request))
        XCTAssertTrue(request.removedIDs.isDisjoint(with: Set(store.tree!.nodes.keys)))
        try store.tree?.validate()
        store.undo()
        XCTAssertEqual(store.tree, tree)
        let links = Array(tree.nodes.values.filter { $0.url != nil }.prefix(2).map(\.id))
        XCTAssertTrue(try XCTUnwrap(store.deletionRequest(for: Set(links))).requiresConfirmation)
        XCTAssertNil(store.deletionRequest(for: []))
        XCTAssertNil(store.deletionRequest(for: ["missing"]))
        XCTAssertNil(store.deletionRequest(for: Set(tree.roots.values)))
    }

    @MainActor
    func testReviewedDeleteAndFormEditRejectInterveningWorkAndProfileSwitch() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory)
        let profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        let request = try XCTUnwrap(store.deletionRequest(for: [item.id]))
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Newer work", url: item.url) })
        let newer = store.tree
        XCTAssertFalse(store.delete(request))
        XCTAssertFalse(store.edit(profileID: profile.id, expectedWorking: profile.working) { $0 = profile.working })
        XCTAssertEqual(store.tree, newer)
        store.undo()
        let other = ConnectedProfile(name: "Other synthetic profile", source: profile.source, base: profile.base)
        store.workspace.profiles.append(other)
        store.switchProfile(other.id)
        XCTAssertEqual(store.tree, profile.working)
        XCTAssertFalse(store.delete(request))
        XCTAssertFalse(store.edit(profileID: profile.id, expectedWorking: profile.working) { try $0.edit(item.id, name: "Wrong profile", url: item.url) })
        XCTAssertEqual(store.workspace.profiles[0].working, profile.working)
        XCTAssertEqual(store.workspace.profiles[1].working, profile.working)
    }

    @MainActor
    func testEditsClearSelectionsHiddenByFolderSearchDuplicateAndChangeFilters() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory)
        let tree = try XCTUnwrap(store.tree)
        let item = try XCTUnwrap(tree.nodes.values.first { $0.url != nil && $0.parent != nil && !tree.roots.values.contains($0.parent!) })
        let folder = try XCTUnwrap(item.parent)
        let destination = try XCTUnwrap(tree.roots["other"])
        store.navigation = folder; store.selection = [item.id]
        XCTAssertTrue(store.edit { try $0.move([item.id], to: destination) })
        XCTAssertTrue(store.selection.isEmpty)
        XCTAssertFalse(store.rows.contains { $0.id == item.id })
        store.undo()
        XCTAssertTrue(store.selection.contains(item.id))

        store.navigation = "all"; store.search = item.name; store.selection = [item.id]
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "No longer matches", url: item.url) })
        XCTAssertTrue(store.selection.isEmpty)
        store.undo()

        store.navigation = "duplicates"; store.search = ""
        let duplicates = try XCTUnwrap(Dictionary(grouping: tree.nodes.values.filter { $0.url != nil }, by: { $0.url! }).values.first { $0.count == 2 })
        store.selection = [duplicates[1].id]
        XCTAssertTrue(store.edit { try $0.remove([duplicates[0].id]) })
        XCTAssertTrue(store.selection.isEmpty)
        store.undo()

        store.navigation = "changes"
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Changed", url: item.url) })
        store.selection = [item.id]
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: item.name, url: item.url) })
        XCTAssertTrue(store.selection.isEmpty)
        XCTAssertFalse(store.rows.contains { $0.id == item.id })
    }

    @MainActor
    func testFailedPersistenceKeepsDeleteRecoverableAndDoesNotAddUndo() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory)
        let profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        let request = try XCTUnwrap(store.deletionRequest(for: [item.id]))
        let original = try Data(contentsOf: profile.source)
        try FileManager.default.removeItem(at: store.workspaceURL)
        try FileManager.default.createDirectory(at: store.workspaceURL, withIntermediateDirectories: false)
        XCTAssertFalse(store.delete(request))
        XCTAssertEqual(store.tree, profile.working)
        XCTAssertFalse(store.canUndo)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(try Data(contentsOf: profile.source), original)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriEditorAction-\(UUID().uuidString)")
    }
}
