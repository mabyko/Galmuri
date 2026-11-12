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
    func testHTMLExportSkipsUnsupportedAddressesAndReportsCount() throws {
        let store = store(), item = try XCTUnwrap(store.tree?.nodes.values.first { $0.url != nil })
        store.workspace.profiles[0].working.nodes[item.id]?.url = "javascript:alert(1)"
        let url = store.directory.appendingPathComponent("export.html")
        store.exportHTML(to: url)
        XCTAssertNil(store.error)
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("javascript:"))
        XCTAssertEqual(store.message, localizedCount("export.skippedUnsupportedCount", 1))
    }

    @MainActor
    func testNoOpEditIsNotSavedAndUndoHistoryIsCapped() throws {
        let store = store(), id = try XCTUnwrap(store.selectedProfileID)
        let item = try XCTUnwrap(store.tree?.nodes.values.first { $0.url != nil })
        let saved = try Data(contentsOf: store.workspaceURL)
        store.message = nil
        XCTAssertTrue(store.edit { _ in })
        XCTAssertFalse(store.canUndo); XCTAssertNil(store.message)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), saved)
        for i in 0..<105 { XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Edit \(i)", url: item.url) }) }
        XCTAssertEqual(store.undoStacks[id]?.count, 100)
        XCTAssertEqual(store.undoStacks[id]?.first?.nodes[item.id]?.name, "Edit 4")
        XCTAssertEqual(store.undoStacks[id]?.last?.nodes[item.id]?.name, "Edit 103")
    }

    @MainActor
    func testArchivePruningKeepsTenNewestRefreshSnapshotsAndNeverDeletesRemovedWork() async throws {
        let store = store(), fm = FileManager.default
        func write(_ name: String, age: TimeInterval) throws -> URL {
            let url = store.directory.appendingPathComponent(name)
            try Data("{}".utf8).write(to: url)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: age)], ofItemAtPath: url.path)
            return url
        }
        let old = try (0..<12).map { try write("BeforeRefresh-" + UUID().uuidString + ".json", age: TimeInterval(1_000 + $0)) }
        let removedWork = try (0..<12).flatMap { i in
            try ["Disconnected-", "workspace-before-import-"].map { try write($0 + UUID().uuidString + ".json", age: TimeInterval(i)) }
        }
        let unrelated = try ["BeforeRefresh-not-a-uuid.json", "BeforeRefresh-" + UUID().uuidString.lowercased() + ".json"].map { try write($0, age: 0) }
        let folder = store.directory.appendingPathComponent("BeforeRefresh-" + UUID().uuidString + ".json")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let p = try XCTUnwrap(store.profile), item = try XCTUnwrap(p.base.tree.nodes.values.first { $0.url != nil })
        var tree = p.base.tree
        try tree.edit(item.id, name: "Browser edit", url: item.url)
        try p.base.serialize(tree).write(to: p.source, options: .atomic)
        await store.refreshProfile()
        let session = try XCTUnwrap(store.review)
        session.acknowledged = true; await store.acceptRefresh(session)
        let archive = try XCTUnwrap(session.localArchive)
        XCTAssertTrue(fm.fileExists(atPath: archive.path))
        XCTAssertEqual(old.filter { fm.fileExists(atPath: $0.path) }, Array(old.suffix(9)))
        store.review = nil
        let disconnected = try XCTUnwrap(store.removeProfile(ProfileRemoval(profile: XCTUnwrap(store.profile))))
        for url in unrelated + removedWork + [folder, disconnected] { XCTAssertTrue(fm.fileExists(atPath: url.path)) }
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
    func testFailedRereadClearsAllReviewApprovalAndRetainsWorkingCopy() async throws {
        let store = store(), profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Keep pending", url: item.url) })
        let working = store.tree, session = ReviewSession(profileID: profile.id)
        await store.loadReview(session)
        XCTAssertNotNil(session.result)
        session.acknowledged = true
        session.resolutions = ["obsolete-choice": .ours]
        try FileManager.default.removeItem(at: profile.source)
        await store.loadReview(session)
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
