import XCTest
import GalmuriCore
@testable import GalmuriApp

final class AppStoreVerificationTests: XCTestCase {
    @MainActor
    private func store() -> AppStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriVerification-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppStore(sampleData: true, directory: directory, browserState: { _ in false })
    }

    @MainActor
    func testDuplicateSearchFolderExclusionAndUndoKeepOriginalUntouched() throws {
        let store = store(), profile = try XCTUnwrap(store.profile)
        store.navigation = "duplicates"
        let duplicates = store.rows
        XCTAssertEqual(duplicates.count, 2)
        XCTAssertEqual(Set(duplicates.map(\.id)).count, 2)
        XCTAssertEqual(Set(duplicates.compactMap(\.url)).count, 1)
        store.search = "INTERFACE"
        XCTAssertEqual(Set(store.rows.map(\.id)), Set(duplicates.map(\.id)))
        store.search = "not-in-the-fixture"
        XCTAssertTrue(store.rows.isEmpty)
        store.search = ""
        let item = duplicates[0], parent = try XCTUnwrap(item.parent)
        store.navigation = parent
        XCTAssertTrue(store.rows.contains { $0.id == item.id })
        store.selection = [item.id]
        XCTAssertTrue(store.edit { try $0.remove([item.id]) })
        XCTAssertTrue(store.selection.isEmpty)
        XCTAssertNil(store.tree?.nodes[item.id])
        let reopened = AppStore(sampleData: true, directory: store.directory, browserState: { _ in false })
        XCTAssertNil(reopened.tree?.nodes[item.id])
        store.undo()
        XCTAssertEqual(store.tree, profile.working)
        XCTAssertEqual(try Data(contentsOf: profile.source), profile.base.original)
    }

    @MainActor
    func testFailedPersistenceRollsBackEditAndKeepsUndoRetryable() throws {
        let store = store(), profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        let saved = store.directory.appendingPathComponent("last-good.json")
        try FileManager.default.moveItem(at: store.workspaceURL, to: saved)
        try FileManager.default.createDirectory(at: store.workspaceURL, withIntermediateDirectories: false)
        XCTAssertFalse(store.edit { try $0.edit(item.id, name: "Must roll back", url: item.url) })
        XCTAssertEqual(store.tree, profile.working)
        XCTAssertFalse(store.canUndo)
        try FileManager.default.removeItem(at: store.workspaceURL)
        try FileManager.default.moveItem(at: saved, to: store.workspaceURL)
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Persisted edit", url: item.url) })
        let edited = store.tree
        try FileManager.default.moveItem(at: store.workspaceURL, to: saved)
        try FileManager.default.createDirectory(at: store.workspaceURL, withIntermediateDirectories: false)
        store.undo()
        XCTAssertEqual(store.tree, edited)
        XCTAssertTrue(store.canUndo)
        try FileManager.default.removeItem(at: store.workspaceURL)
        try FileManager.default.moveItem(at: saved, to: store.workspaceURL)
        store.undo()
        XCTAssertEqual(store.tree, profile.working)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(try Data(contentsOf: profile.source), profile.base.original)
    }

    @MainActor
    func testFailedRereadClearsAllReviewApprovalAndRetainsWorkingCopy() throws {
        let store = store(), profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Keep pending", url: item.url) })
        let working = store.tree, session = ReviewSession(profileID: profile.id)
        store.loadReview(session)
        XCTAssertNotNil(session.result)
        session.acknowledged = true
        session.resolutions = ["obsolete-choice": .ours]
        try FileManager.default.removeItem(at: profile.source)
        store.loadReview(session)
        XCTAssertFalse(session.acknowledged)
        XCTAssertTrue(session.resolutions.isEmpty)
        XCTAssertNil(session.latest)
        XCTAssertNil(session.result)
        XCTAssertNil(session.sourceIdentity)
        XCTAssertNil(session.workingAtReview)
        XCTAssertEqual(store.tree, working)
        XCTAssertTrue(store.backups.isEmpty)
        let reopened = AppStore(sampleData: true, directory: store.directory, browserState: { _ in false })
        XCTAssertEqual(reopened.tree, working)
    }

    @MainActor
    func testSwitchingProfilesKeepsIndependentUndoAndResetsSelection() async throws {
        let store = store(), first = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(first.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Only first profile", url: item.url) })
        let working = store.tree
        let folder = store.directory.appendingPathComponent("ApprovedCopy/Default")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try SampleData.file().original.write(to: folder.appendingPathComponent("Bookmarks"))
        await store.connectDirectory(folder)
        let second = try XCTUnwrap(store.profile)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(store.canUndo)
        store.selection = [try XCTUnwrap(second.working.nodes.values.first { $0.url != nil }).id]
        store.search = "filter"; store.navigation = "duplicates"
        store.switchProfile(first.id)
        XCTAssertEqual(store.tree, working)
        XCTAssertTrue(store.canUndo)
        XCTAssertTrue(store.selection.isEmpty)
        XCTAssertTrue(store.search.isEmpty)
        XCTAssertEqual(store.navigation, "all")
        store.undo()
        XCTAssertEqual(store.tree, first.working)
        XCTAssertEqual(store.workspace.profiles.first { $0.id == second.id }?.working, second.working)
    }

    @MainActor
    func testConnectionPersistenceFailureKeepsExistingProfilesAndSelection() async throws {
        let store = store(), initial = store.workspace, selected = store.selectedProfileID
        let folder = store.directory.appendingPathComponent("ApprovedCopy/Default")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("Bookmarks"), bytes = try SampleData.file().original
        try bytes.write(to: source)
        let saved = store.directory.appendingPathComponent("last-good.json")
        try FileManager.default.moveItem(at: store.workspaceURL, to: saved)
        try FileManager.default.createDirectory(at: store.workspaceURL, withIntermediateDirectories: false)
        await store.connectDirectory(folder)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.busy)
        XCTAssertEqual(store.workspace.profiles.map(\.id), initial.profiles.map(\.id))
        XCTAssertEqual(store.selectedProfileID, selected)
        XCTAssertEqual(try Workspace.load(from: saved).profiles.first?.working, initial.profiles.first?.working)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    @MainActor
    func testUnsupportedEncryptedOnlyConnectionPreservesWorkspaceAndSources() async throws {
        let store = store(), selected = store.selectedProfileID
        let before = try Data(contentsOf: store.workspaceURL)
        let dataRoot = store.directory.appendingPathComponent("ApprovedCopy")
        let plain = dataRoot.appendingPathComponent("Default"), encrypted = dataRoot.appendingPathComponent("Profile 1")
        for directory in [plain, encrypted] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let bytes = try SampleData.file().original, marker = Data("synthetic encrypted-only marker".utf8)
        let source = plain.appendingPathComponent("Bookmarks"), companion = encrypted.appendingPathComponent("EncryptedBookmarks2")
        try bytes.write(to: source); try marker.write(to: companion)
        await store.connectDirectory(dataRoot)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.busy)
        XCTAssertEqual(store.selectedProfileID, selected)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: companion), marker)
    }
}
