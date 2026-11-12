import XCTest
import GalmuriCore
@testable import GalmuriApp

final class PermissionTests: XCTestCase {
    @MainActor
    func testMissingSourceOffersReconnectWithoutLosingOfflineEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriMissing-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Approved/Default")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("Bookmarks"), original = try SampleData.file().original
        try original.write(to: source)
        let store = AppStore(sampleData: true, directory: root.appendingPathComponent("App"), browserState: { _ in false })
        await store.connectDirectory(folder)
        let profile = try XCTUnwrap(store.profile)
        try FileManager.default.removeItem(at: source)
        await store.loadReview(ReviewSession(profileID: profile.id))
        XCTAssertTrue(store.needsReconnect)
        XCTAssertEqual(store.profile?.base, profile.base)
        let parent = try XCTUnwrap(profile.working.roots["other"])
        XCTAssertTrue(store.edit { _ = try $0.add(name: "Offline", url: "https://example.com/offline", to: parent) })
        let working = store.tree
        try original.write(to: source)
        await store.reconnectDirectory(folder, profileID: profile.id)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.needsReconnect)
        XCTAssertEqual(store.tree, working)
    }

    @MainActor
    func testCancelAndDeniedScopePreserveWorkAndReconnectKeepsBase() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriPermissions-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Approved/Default")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("Bookmarks")
        try SampleData.file().original.write(to: source)
        let store = AppStore(sampleData: true, directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let initialWorkspace = try Data(contentsOf: store.workspaceURL)
        await store.connectDirectory(nil)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), initialWorkspace)
        XCTAssertFalse(store.busy)
        await store.connectDirectory(directory)
        let profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Unapplied title", url: item.url) })
        var working = try XCTUnwrap(store.tree)
        let saved = try Data(contentsOf: store.workspaceURL)
        store.workspace.profiles[1].permissionBookmark = Data("revoked or damaged scope".utf8)
        XCTAssertThrowsError(try store.withAccess(store.workspace.profiles[1]) { try ProfileIO.read(source) })
        XCTAssertTrue(store.needsReconnect)
        await store.reconnectDirectory(nil, profileID: profile.id)
        XCTAssertTrue(store.needsReconnect)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), saved)
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Unapplied title", url: "https://example.com/offline-edit") })
        working = try XCTUnwrap(store.tree)
        var theirs = profile.base.tree
        let rootID = try XCTUnwrap(theirs.roots["other"])
        _ = try theirs.add(name: "New browser bookmark", url: "https://example.org/new", to: rootID)
        try profile.base.serialize(theirs).write(to: source, options: .atomic)
        let latestBytes = try Data(contentsOf: source)
        await store.reconnectDirectory(directory, profileID: profile.id)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.needsReconnect)
        XCTAssertEqual(store.profile?.id, profile.id)
        XCTAssertEqual(store.profile?.base, profile.base)
        XCTAssertEqual(store.tree, working)
        let review = ReviewSession(profileID: profile.id)
        await store.loadReview(review)
        XCTAssertEqual(review.result?.tree.nodes[item.id]?.name, "Unapplied title")
        XCTAssertTrue(review.result?.tree.nodes.values.contains { $0.name == "New browser bookmark" } == true)
        XCTAssertEqual(try Data(contentsOf: source), latestBytes)
        let reopened = AppStore(sampleData: true, directory: store.directory, browserState: { _ in false })
        let restored = try XCTUnwrap(reopened.workspace.profiles.first { $0.id == profile.id })
        XCTAssertEqual(try reopened.withAccess(restored) { try ProfileIO.read(source).original }, latestBytes)
        XCTAssertEqual(restored.working, working)
    }

    @MainActor
    func testDifferentFolderAndMissingPermissionNeverReadOrRebindSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriScope-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let approved = root.appendingPathComponent("Approved/Default"), other = root.appendingPathComponent("Other/Default")
        for folder in [approved, other] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try SampleData.file().original.write(to: folder.appendingPathComponent("Bookmarks"))
        }
        let store = AppStore(sampleData: true, directory: root.appendingPathComponent("App"), browserState: { _ in false })
        await store.connectDirectory(approved)
        let profile = try XCTUnwrap(store.profile), before = try Data(contentsOf: store.workspaceURL)
        await store.reconnectDirectory(other, profileID: profile.id)
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.needsReconnect)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertEqual(store.profile?.source, profile.source)
        var imported = profile; imported.permissionBookmark = nil
        var read = false
        XCTAssertThrowsError(try store.withAccess(imported) { read = true })
        XCTAssertFalse(read)
    }
}
