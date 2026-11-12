import XCTest
import GalmuriCore
@testable import GalmuriApp

final class PreUseTests: XCTestCase {
    @MainActor private func store() -> AppStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriPreUse-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppStore(sampleData: true, directory: directory)
    }
    @MainActor private func items(_ store: AppStore) -> [Bookmark] { store.tree!.nodes.values.filter { $0.url != nil }.sorted { $0.id < $1.id } }
    @MainActor private func changeSource(_ store: AppStore, name: String, item: String) throws {
        let p = store.profile!; var tree = p.base.tree
        try tree.edit(item, name: name, url: tree.nodes[item]?.url)
        try p.base.serialize(tree).write(to: p.source, options: .atomic)
    }

    @MainActor func testRemovalArchivesPendingWorkAndKeepsOriginalAndBackups() throws {
        let store = store(), p = store.profile!, item = items(store)[0]
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Keep archived", url: item.url) })
        let saved = store.workspace, request = ProfileRemoval(profile: store.profile!)
        let before = try Data(contentsOf: p.source)
        let marker = store.directory.appendingPathComponent("OriginalBackups/marker")
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: marker)
        let archive = try XCTUnwrap(store.removeProfile(request))
        XCTAssertTrue(store.workspace.profiles.isEmpty); XCTAssertNil(store.selectedProfileID)
        XCTAssertEqual(try Workspace.load(from: archive).profiles[0].working, saved.profiles[0].working)
        XCTAssertTrue(try Workspace.load(from: store.workspaceURL).profiles.isEmpty)
        XCTAssertEqual(try Data(contentsOf: p.source), before); XCTAssertEqual(try Data(contentsOf: marker), Data("keep".utf8))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: archive.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    @MainActor func testStaleRemovalAndFailedPersistenceKeepStateAndUndo() throws {
        let store = store(), request = ProfileRemoval(profile: store.profile!), item = items(store)[0]
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Later", url: item.url) })
        XCTAssertNil(store.removeProfile(request))
        let fresh = ProfileRemoval(profile: store.profile!), before = store.workspace, undo = store.undoStacks
        let saved = store.directory.appendingPathComponent("last-good.json")
        try FileManager.default.moveItem(at: store.workspaceURL, to: saved)
        try FileManager.default.createDirectory(at: store.workspaceURL, withIntermediateDirectories: false)
        XCTAssertNil(store.removeProfile(fresh))
        XCTAssertEqual(store.workspace.profiles[0].working, before.profiles[0].working)
        XCTAssertEqual(store.undoStacks, undo); XCTAssertEqual(store.selectedProfileID, fresh.profile.id)
    }
    @MainActor func testRemovingUnselectedProfileDoesNotRetargetCurrentEditor() throws {
        let store = store(), first = store.profile!
        let second = ConnectedProfile(name: "Other", source: first.source, base: first.base)
        store.workspace.profiles.append(second); try store.persist()
        store.navigation = "duplicates"; store.selection = [items(store)[0].id]
        let selected = store.selection
        XCTAssertNotNil(store.removeProfile(ProfileRemoval(profile: second)))
        XCTAssertEqual(store.selectedProfileID, first.id); XCTAssertEqual(store.navigation, "duplicates"); XCTAssertEqual(store.selection, selected)
    }
    @MainActor func testRefreshMergesIndependentEditsUpdatesBaseAndArchivesOldWorkspace() async throws {
        let store = store(), p = store.profile!, ids = items(store)
        XCTAssertTrue(store.edit { try $0.edit(ids[0].id, name: "Local edit", url: ids[0].url) })
        let working = store.tree!
        try changeSource(store, name: "Browser edit", item: ids[1].id)
        let source = try Data(contentsOf: p.source)
        await store.refreshProfile()
        let session = try XCTUnwrap(store.review)
        XCTAssertEqual(session.mode, .refresh); XCTAssertTrue(session.result!.unresolved.isEmpty)
        XCTAssertEqual(store.tree, working)
        session.acknowledged = true; await store.acceptRefresh(session)
        XCTAssertEqual(session.phase, .complete)
        XCTAssertEqual(store.tree?.nodes[ids[0].id]?.name, "Local edit")
        XCTAssertEqual(store.tree?.nodes[ids[1].id]?.name, "Browser edit")
        XCTAssertEqual(store.profile?.base.tree.nodes[ids[1].id]?.name, "Browser edit")
        XCTAssertEqual(store.profile?.base.tree.nodes[ids[0].id]?.name, p.base.tree.nodes[ids[0].id]?.name)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(try Workspace.load(from: XCTUnwrap(session.localArchive)).profiles[0].working, working)
        XCTAssertEqual(try Data(contentsOf: p.source), source)
        XCTAssertEqual(try Workspace.load(from: store.workspaceURL).profiles[0].working, store.tree)
    }
    @MainActor func testRefreshNeedsAcknowledgementAndExplicitConflictResolution() async throws {
        let store = store(), item = items(store)[0]
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Local", url: item.url) })
        try changeSource(store, name: "Browser", item: item.id)
        await store.refreshProfile(); let session = try XCTUnwrap(store.review), before = store.tree
        await store.acceptRefresh(session); XCTAssertEqual(store.tree, before)
        session.acknowledged = true; await store.acceptRefresh(session); XCTAssertEqual(store.tree, before)
        XCTAssertFalse(session.result!.unresolved.isEmpty)
        for c in session.result!.conflicts { store.resolve(c.id, side: .ours, in: session) }
        session.acknowledged = true; await store.acceptRefresh(session)
        XCTAssertEqual(store.tree?.nodes[item.id]?.name, "Local"); XCTAssertEqual(store.profile?.base.tree.nodes[item.id]?.name, "Browser")
    }
    @MainActor func testRefreshRejectsSameBytesSourceReplacementAndPreservesWork() async throws {
        let store = store(), item = items(store)[0]
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Local", url: item.url) })
        await store.refreshProfile(); let session = try XCTUnwrap(store.review), before = store.profile!, undo = store.undoStacks
        let bytes = try Data(contentsOf: before.source); try bytes.write(to: before.source, options: .atomic)
        session.acknowledged = true; await store.acceptRefresh(session)
        XCTAssertEqual(session.phase, .exit); XCTAssertFalse(session.acknowledged)
        XCTAssertEqual(store.tree, before.working); XCTAssertEqual(store.profile?.base, before.base); XCTAssertEqual(store.undoStacks, undo)
    }
    @MainActor func testClosingRefreshReviewDoesNotCommitAndStaleWorkCannotBeAccepted() async throws {
        let store = store(), item = items(store)[0]
        await store.refreshProfile(); let session = try XCTUnwrap(store.review)
        let bytes = try Data(contentsOf: store.workspaceURL)
        store.review = nil; session.acknowledged = true; await store.acceptRefresh(session)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), bytes)
        await store.refreshProfile(); let fresh = try XCTUnwrap(store.review)
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "After review", url: item.url) })
        fresh.acknowledged = true; await store.acceptRefresh(fresh)
        XCTAssertEqual(store.tree?.nodes[item.id]?.name, "After review")
    }
    @MainActor func testRefreshPersistenceFailureKeepsBaseWorkAndUndo() async throws {
        let store = store(), item = items(store)[0]
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Local", url: item.url) })
        await store.refreshProfile(); let session = try XCTUnwrap(store.review), before = store.profile!, undo = store.undoStacks
        let saved = store.directory.appendingPathComponent("last-good.json")
        try FileManager.default.moveItem(at: store.workspaceURL, to: saved)
        try FileManager.default.createDirectory(at: store.workspaceURL, withIntermediateDirectories: false)
        session.acknowledged = true; await store.acceptRefresh(session)
        XCTAssertEqual(session.phase, .exit); XCTAssertEqual(store.profile?.base, before.base); XCTAssertEqual(store.tree, before.working)
        XCTAssertEqual(store.undoStacks, undo)
    }
    @MainActor func testMixedRefreshRetainsRestrictionAndDoesNotReadEncryptedPayload() async throws {
        let store = store(), source = store.profile!.source
        let encrypted = source.deletingLastPathComponent().appendingPathComponent("EncryptedBookmarks2")
        let marker = Data([0xff,0x00,0xfe]); try marker.write(to: encrypted)
        await store.refreshProfile(); let session = try XCTUnwrap(store.review)
        session.acknowledged = true; await store.acceptRefresh(session)
        XCTAssertEqual(session.phase, .complete); XCTAssertNotNil(store.profile?.sourceRestriction)
        XCTAssertEqual(try Data(contentsOf: encrypted), marker)
    }
    @MainActor func testUnparseableRefreshPreservesSavedWork() async throws {
        let store = store(), before = store.profile!
        let saved = try Data(contentsOf: store.workspaceURL)
        try Data("invalid synthetic file".utf8).write(to: before.source)
        await store.refreshProfile()
        XCTAssertNil(store.review); XCTAssertNotNil(store.error); XCTAssertEqual(store.tree, before.working)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), saved)
    }
    @MainActor func testSelectedRevertIsReviewedPersistedUndoableAndStaleGuarded() throws {
        let store = store(), ids = items(store)
        XCTAssertTrue(store.edit { try $0.edit(ids[0].id, name: "First", url: ids[0].url); try $0.edit(ids[1].id, name: "Keep", url: ids[1].url) })
        let before = store.tree, request = try XCTUnwrap(store.revertRequest(for: [ids[0].id]))
        XCTAssertTrue(store.resetWorkingCopy(request)); XCTAssertEqual(store.tree?.nodes[ids[0].id]?.name, ids[0].name)
        XCTAssertEqual(store.tree?.nodes[ids[1].id]?.name, "Keep")
        store.undo(); XCTAssertEqual(store.tree, before)
        XCTAssertTrue(store.edit { try $0.edit(ids[1].id, name: "Later", url: ids[1].url) })
        XCTAssertFalse(store.resetWorkingCopy(request)); XCTAssertEqual(store.tree?.nodes[ids[1].id]?.name, "Later")
    }
    @MainActor func testOpeningOnlyDispatchesExplicitValidHTTPURL() throws {
        let store = store(), item = items(store)[0]
        var opened = [URL]()
        store.openBookmark(item.id) { opened.append($0); return true }
        XCTAssertEqual(opened.map(\.absoluteString), [item.url!])
        store.openBookmark(SampleData.bar) { opened.append($0); return true }
        store.workspace.profiles[0].working.nodes[item.id]?.url = "javascript:alert(1)"
        store.openBookmark(item.id) { opened.append($0); return true }
        XCTAssertEqual(opened.count, 1); XCTAssertNotNil(store.error)
    }
}
