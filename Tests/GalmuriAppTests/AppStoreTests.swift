import XCTest
import os
import GalmuriCore
@testable import GalmuriApp

final class AppStoreTests: XCTestCase {
    @MainActor
    func testInterruptedApplyExposesBackupAndDamagedReceiptKeepsEditingAvailable() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = OSAllocatedUnfairLock(initialState: (restarting: false, checks: 0))
        let store = AppStore(sampleData: true, directory: directory, browserState: { _ in state.withLock { $0.checks += 1; return $0.restarting && $0.checks >= 2 } })
        XCTAssertTrue(store.setLabOptions(file: true))
        let profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Keep my edit", url: item.url) })
        let session = ReviewSession(profileID: profile.id)
        await store.loadReview(session); session.acknowledged = true
        state.withLock { $0 = (restarting: true, checks: 0) }
        await store.apply(session)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.backups.count, 1)
        XCTAssertEqual(store.backups.first?.state, "prepared")
        XCTAssertEqual(try ProfileIO.read(profile.source).fingerprint, profile.base.fingerprint)
        let damagedReceipt = store.coordinator.backupRoot.appendingPathComponent("damaged.json")
        let damaged = Data("damaged receipt".utf8)
        try damaged.write(to: damagedReceipt)
        let relaunched = AppStore(sampleData: true, directory: directory, browserState: { _ in false })
        XCTAssertNotNil(relaunched.error)
        XCTAssertEqual(relaunched.tree?.nodes[item.id]?.name, "Keep my edit")
        XCTAssertTrue(relaunched.edit { try $0.edit(item.id, name: "Still editable", url: item.url) })
        XCTAssertEqual(try Data(contentsOf: damagedReceipt), damaged)
    }

    @MainActor
    func testApprovedCopyConnectionRetainsScopedAccessAfterRelaunch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceDirectory = directory.appendingPathComponent("ApprovedCopy/Default")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent("Bookmarks")
        let original = try SampleData.file().original
        try original.write(to: source)
        let store = AppStore(sampleData: true, directory: directory.appendingPathComponent("App"), browserState: { _ in false })
        XCTAssertTrue(store.setLabOptions(file: true))
        await store.connectDirectory(sourceDirectory)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.workspace.profiles.count, 2)
        let connected = try XCTUnwrap(store.profile)
        XCTAssertEqual(connected.source, source)
        XCTAssertNotNil(connected.permissionBookmark)
        XCTAssertFalse(store.coordinator.canWrite(source))
        let relaunched = AppStore(sampleData: true, directory: store.directory, browserState: { _ in false })
        let loaded = try XCTUnwrap(relaunched.workspace.profiles.first { $0.id == connected.id })
        XCTAssertEqual(try relaunched.withAccess(loaded) { try ProfileIO.read(loaded.source).original }, original)
        var invalidPermission = loaded
        invalidPermission.permissionBookmark = Data("invalid permission record".utf8)
        XCTAssertThrowsError(try relaunched.withAccess(invalidPermission) { true })
        var outsideScope = loaded
        outsideScope.source = directory.appendingPathComponent("Unapproved/Bookmarks")
        var readOutside = false
        XCTAssertThrowsError(try relaunched.withAccess(outsideScope) { readOutside = true })
        XCTAssertFalse(readOutside)
        XCTAssertEqual(try Data(contentsOf: source), original)
        await relaunched.connectDirectory(sourceDirectory)
        XCTAssertEqual(relaunched.workspace.profiles.count, 2)
    }

    @MainActor
    func testEditingPersistenceUndoAndRejectedChanges() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory, browserState: { _ in false })
        XCTAssertTrue(store.setLabOptions(file: true))
        let original = try XCTUnwrap(store.tree)
        let parent = try XCTUnwrap(original.roots["bookmark_bar"])
        var added = ""
        XCTAssertTrue(store.edit { added = try $0.add(name: "Local edit", url: "https://example.com/local", to: parent) })
        XCTAssertFalse(store.edit { try $0.edit(added, name: "Invalid", url: "javascript:alert(1)") })
        XCTAssertFalse(store.edit { try $0.edit(added, name: "Invalid", url: "javascript:alert(1)") })
        let relaunched = AppStore(sampleData: true, directory: directory, browserState: { _ in false })
        XCTAssertEqual(relaunched.tree?.nodes[added]?.name, "Local edit")
        XCTAssertEqual(try ProfileIO.read(store.profile!.source).tree, original)
        store.undo()
        XCTAssertEqual(store.tree, original)
        XCTAssertFalse(store.canUndo)
    }

    @MainActor
    func testRealMergeChoicesApplyAndRestoreThroughAppStore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory, browserState: { _ in false })
        XCTAssertTrue(store.setLabOptions(file: true))
        let profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "App title", url: item.url) })
        var theirs = profile.base.tree
        try theirs.edit(item.id, name: "Browser title", url: item.url)
        try profile.base.serialize(theirs).write(to: profile.source, options: .atomic)
        let beforeApply = try Data(contentsOf: profile.source)
        let session = ReviewSession(profileID: profile.id)
        await store.loadReview(session)
        let conflict = try XCTUnwrap(session.result?.unresolved.first)
        XCTAssertFalse(session.acknowledged)
        await store.resolve(conflict.id, side: .ours, in: session)
        XCTAssertTrue(try XCTUnwrap(session.result).unresolved.isEmpty)
        session.acknowledged = true
        await store.apply(session)
        XCTAssertNil(store.error)
        XCTAssertEqual(try ProfileIO.read(profile.source).tree.nodes[item.id]?.name, "App title")
        XCTAssertEqual(store.pendingCount, 0)
        let receipt = try XCTUnwrap(session.receipt)
        XCTAssertEqual(try Data(contentsOf: receipt.backup), beforeApply)
        let currentHash = try ProfileIO.read(profile.source).fingerprint
        store.busy = true
        let skipped = await store.restore(receipt, expectedHash: currentHash)
        XCTAssertFalse(skipped)
        store.busy = false
        let restored = await store.restore(receipt, expectedHash: currentHash)
        XCTAssertTrue(restored)
        XCTAssertNil(store.error)
        XCTAssertEqual(try Data(contentsOf: profile.source), beforeApply)
        XCTAssertEqual(store.tree?.nodes[item.id]?.name, "App title")
        XCTAssertEqual(store.backups.count, 2)
    }

    @MainActor
    func testApplyRefreshesBackupsWhenProfileChangesDuringWrite() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory, browserState: { _ in false })
        XCTAssertTrue(store.setLabOptions(file: true))
        let profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "App title", url: item.url) })
        let session = ReviewSession(profileID: profile.id)
        await store.loadReview(session)
        XCTAssertTrue(try XCTUnwrap(session.result).unresolved.isEmpty)
        session.acknowledged = true
        XCTAssertTrue(store.backups.isEmpty)
        let applying = Task { await store.apply(session) }
        while !store.busy { await Task.yield() }
        // apply is suspended in its write; change the stored profile before it resumes.
        store.workspace.profiles[0].working.nodes[item.id]?.name = "Changed during apply"
        await applying.value
        XCTAssertEqual(session.phase, .complete)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.backups.count, 1)
    }

    @MainActor
    func testReviewApprovalInvalidatedByWorkingCopyOrSourceChanges() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory, browserState: { _ in false })
        XCTAssertTrue(store.setLabOptions(file: true))
        let profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        let session = ReviewSession(profileID: profile.id)
        await store.loadReview(session)
        session.acknowledged = true
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Changed after review", url: item.url) })
        await store.apply(session)
        XCTAssertFalse(session.acknowledged)
        XCTAssertNil(session.receipt)
        XCTAssertEqual(try ProfileIO.read(profile.source).fingerprint, profile.base.fingerprint)
        store.error = nil
        session.acknowledged = true
        var external = profile.base.tree
        try external.edit(item.id, name: "Changed original", url: item.url)
        try profile.base.serialize(external).write(to: profile.source, options: .atomic)
        await store.apply(session)
        XCTAssertFalse(session.acknowledged)
        XCTAssertFalse(try XCTUnwrap(session.result).unresolved.isEmpty)
        XCTAssertTrue(store.backups.isEmpty)
    }

    @MainActor
    func testBrowserRestartAndCorruptWorkspacePreserveFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let running = OSAllocatedUnfairLock(initialState: false)
        let store = AppStore(sampleData: true, directory: directory, browserState: { _ in running.withLock { $0 } })
        XCTAssertTrue(store.setLabOptions(file: true))
        let profile = try XCTUnwrap(store.profile)
        let session = ReviewSession(profileID: profile.id)
        await store.loadReview(session)
        session.acknowledged = true
        running.withLock { $0 = true }
        await store.apply(session)
        XCTAssertNil(session.receipt)
        await store.loadReview(session)
        XCTAssertFalse(session.acknowledged)
        XCTAssertNil(session.result)
        XCTAssertEqual(try ProfileIO.read(profile.source).fingerprint, profile.base.fingerprint)
        let corrupt = Data("invalid workspace".utf8)
        try corrupt.write(to: store.workspaceURL)
        let recovered = AppStore(sampleData: true, directory: directory, browserState: { _ in false })
        XCTAssertNotNil(recovered.error)
        XCTAssertThrowsError(try recovered.persist())
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), corrupt)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriAppTests-" + UUID().uuidString, isDirectory: true)
    }
}
