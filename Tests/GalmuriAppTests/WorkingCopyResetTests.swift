import XCTest
import GalmuriCore
@testable import GalmuriApp

final class WorkingCopyResetTests: XCTestCase {
    @MainActor
    private func fixture() throws -> AppStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriReset-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory)
        let tree = try XCTUnwrap(store.tree)
        let folders = try XCTUnwrap(tree.nodes[SampleData.bar]?.children)
        let item = try XCTUnwrap(tree.nodes[folders[1]]?.children.first)
        XCTAssertTrue(store.edit { tree in
            try tree.edit(item, name: "Edited source item", url: "https://example.com/edited")
            try tree.move([item], to: SampleData.other)
            try tree.remove([folders[0]])
            let added = try tree.add(name: "Added folder", url: nil, to: SampleData.bar)
            _ = try tree.add(name: "Added bookmark", url: "https://example.com/new", to: added)
            try tree.reorder(added, offset: -1)
        })
        return store
    }

    @MainActor
    func testAfterRelaunchResetRestoresEntireBaseAndPersistsWithoutUndoHistory() throws {
        let original = try fixture(), before = try XCTUnwrap(original.profile)
        let source = try Data(contentsOf: before.source)
        let store = AppStore(sampleData: true, directory: original.directory)
        XCTAssertFalse(store.canUndo); XCTAssertGreaterThan(store.pendingCount, 0)
        store.navigation = "changes"; store.search = "no visible fixture match"; store.selection = []
        XCTAssertTrue(store.rows.isEmpty)
        let request = try XCTUnwrap(store.resetRequest())
        XCTAssertTrue(store.resetWorkingCopy(request))
        XCTAssertEqual(store.tree, before.base.tree); XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(store.profile?.base, before.base)
        XCTAssertEqual(store.profile?.source, before.source)
        XCTAssertEqual(try Data(contentsOf: before.source), source)
        let reopened = AppStore(sampleData: true, directory: store.directory)
        XCTAssertEqual(reopened.tree, before.base.tree); XCTAssertFalse(reopened.canUndo)
        XCTAssertNil(reopened.resetRequest())
    }

    @MainActor
    func testDiscardItselfCanBeUndoneAndPriorEditsReturnExactly() throws {
        let original = try fixture(), before = try XCTUnwrap(original.profile)
        let store = AppStore(sampleData: true, directory: original.directory)
        XCTAssertTrue(store.resetWorkingCopy(try XCTUnwrap(store.resetRequest())))
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertEqual(store.tree, before.working)
        XCTAssertEqual(store.profile?.changedIDs, before.changedIDs)
        XCTAssertEqual(try Workspace.load(from: store.workspaceURL).profiles[0].working, before.working)
        XCTAssertFalse(store.canUndo)
    }

    @MainActor
    func testInterveningEditAndRepeatedConfirmationAreRejected() throws {
        let store = try fixture(), request = try XCTUnwrap(store.resetRequest())
        XCTAssertTrue(store.edit { _ = try $0.add(name: "Later edit", url: "https://example.com/later", to: SampleData.other) })
        let before = store.tree, saved = try Data(contentsOf: store.workspaceURL)
        XCTAssertFalse(store.resetWorkingCopy(request))
        XCTAssertEqual(store.tree, before); XCTAssertEqual(try Data(contentsOf: store.workspaceURL), saved)
        let fresh = try XCTUnwrap(store.resetRequest())
        XCTAssertTrue(store.resetWorkingCopy(fresh))
        let clean = try Data(contentsOf: store.workspaceURL)
        XCTAssertFalse(store.resetWorkingCopy(fresh))
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), clean)
    }

    @MainActor
    func testChangedBaseOrSourceCannotReuseOldApproval() throws {
        let store = try fixture(), request = try XCTUnwrap(store.resetRequest())
        let profile = try XCTUnwrap(store.profile), working = store.tree
        var changedBase = profile.base.tree
        let item = try XCTUnwrap(changedBase.nodes.values.first { $0.url != nil })
        try changedBase.edit(item.id, name: "A later baseline", url: item.url)
        store.workspace.profiles[0].base = try BookmarkFile(data: profile.base.serialize(changedBase))
        XCTAssertFalse(store.resetWorkingCopy(request)); XCTAssertEqual(store.tree, working)
        store.workspace.profiles[0].base = profile.base
        store.workspace.profiles[0].source = store.directory.appendingPathComponent("Other source")
        XCTAssertFalse(store.resetWorkingCopy(request)); XCTAssertEqual(store.tree, working)
    }

    @MainActor
    func testOtherProfilesAndTheirUndoStacksRemainUnchanged() throws {
        let store = try fixture(), request = try XCTUnwrap(store.resetRequest())
        let first = try XCTUnwrap(store.profile)
        let second = ConnectedProfile(name: "Other synthetic profile", source: first.source, base: first.base)
        store.workspace.profiles.append(second); store.switchProfile(second.id)
        XCTAssertTrue(store.edit { _ = try $0.add(name: "Keep other work", url: "https://example.com/other", to: SampleData.other) })
        let otherWorking = store.tree, otherUndo = store.undoStacks[second.id]
        XCTAssertFalse(store.resetWorkingCopy(request)); XCTAssertEqual(store.tree, otherWorking)
        store.switchProfile(first.id)
        XCTAssertTrue(store.resetWorkingCopy(request))
        XCTAssertEqual(store.workspace.profiles.first { $0.id == second.id }?.working, otherWorking)
        XCTAssertEqual(store.undoStacks[second.id], otherUndo)
    }

    @MainActor
    func testPersistenceFailureRollsBackResetAndRetainsRetryableRequest() throws {
        let store = try fixture(), request = try XCTUnwrap(store.resetRequest())
        let before = store.tree, undo = store.undoStacks
        let saved = store.directory.appendingPathComponent("last-good.json")
        try FileManager.default.moveItem(at: store.workspaceURL, to: saved)
        try FileManager.default.createDirectory(at: store.workspaceURL, withIntermediateDirectories: false)
        XCTAssertFalse(store.resetWorkingCopy(request)); XCTAssertEqual(store.tree, before)
        XCTAssertEqual(store.undoStacks, undo)
        try FileManager.default.removeItem(at: store.workspaceURL)
        try FileManager.default.moveItem(at: saved, to: store.workspaceURL)
        XCTAssertTrue(store.resetWorkingCopy(request))
        XCTAssertEqual(store.tree, request.profile.base.tree)
    }

    @MainActor
    func testCleanBusyAndActiveReviewCannotCreateOrConfirmReset() throws {
        let store = try fixture(), request = try XCTUnwrap(store.resetRequest())
        let before = store.tree
        store.busy = true
        XCTAssertNil(store.resetRequest()); XCTAssertFalse(store.resetWorkingCopy(request))
        store.busy = false
        store.review = ReviewSession(profileID: request.profile.id)
        XCTAssertNil(store.resetRequest()); XCTAssertFalse(store.resetWorkingCopy(request))
        XCTAssertEqual(store.tree, before)
        store.review = nil
        XCTAssertTrue(store.resetWorkingCopy(request)); XCTAssertNil(store.resetRequest())
    }

    @MainActor
    func testResetUsesStoredBaseWhenOriginalIsChangedOrUnavailable() throws {
        let store = try fixture(), request = try XCTUnwrap(store.resetRequest())
        let source = request.profile.source, newer = Data("newer synthetic source; never read by reset".utf8)
        try newer.write(to: source)
        XCTAssertTrue(store.resetWorkingCopy(request))
        XCTAssertEqual(store.tree, request.profile.base.tree)
        XCTAssertEqual(try Data(contentsOf: source), newer)
        store.undo()
        let again = try XCTUnwrap(store.resetRequest())
        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(store.resetWorkingCopy(again))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(store.tree, request.profile.base.tree)
    }
}
