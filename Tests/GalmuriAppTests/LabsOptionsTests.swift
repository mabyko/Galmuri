import XCTest
import GalmuriCore
@testable import GalmuriApp

@MainActor final class LabsOptionsTests: XCTestCase {
    nonisolated private static func waitForInspection(_ signal: DispatchSemaphore) -> Bool { signal.wait(timeout: .now()+5) == .success }
    private let id = String(repeating: "a", count: 32)
    private func fixture() -> AppStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriLabOptions-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppStore(sampleData: true, directory: directory, browserState: { _ in false })
    }
    func testSwitchesDefaultOffPersistIndependentlyAndNeverResetWork() throws {
        let store = fixture(), item = try XCTUnwrap(store.tree?.nodes.values.first { $0.url != nil })
        XCTAssertFalse(store.labs.apiEnabled);XCTAssertFalse(store.labs.fileEnabled)
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Keep edit", url: item.url) })
        let before = try Data(contentsOf: store.workspaceURL)
        XCTAssertNil(store.fileApplyExperimentReview())
        XCTAssertTrue(store.setLabOptions(api: true));XCTAssertFalse(store.labs.fileEnabled)
        XCTAssertTrue(store.setLabOptions(file: true));XCTAssertNotNil(store.fileApplyExperimentReview())
        let reopened = AppStore(sampleData: true, directory: store.directory)
        XCTAssertTrue(reopened.labs.apiEnabled);XCTAssertTrue(reopened.labs.fileEnabled)
        XCTAssertTrue(reopened.setLabOptions(api: false));XCTAssertTrue(reopened.labs.fileEnabled)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
    }
    func testOffStopsPreparedFileApplyAndRestoreWithoutNewBackups() async throws {
        let store = fixture(), profile = try XCTUnwrap(store.profile), item = try XCTUnwrap(store.tree?.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.setLabOptions(file: true))
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Apply", url: item.url) })
        let review = try XCTUnwrap(store.fileApplyExperimentReview());await store.loadReview(review);review.acknowledged = true
        XCTAssertTrue(store.setLabOptions(file: false));await store.apply(review)
        XCTAssertFalse(review.acknowledged);XCTAssertTrue(store.backups.isEmpty)
        XCTAssertEqual(try Data(contentsOf: profile.source), profile.base.original)
        XCTAssertTrue(store.setLabOptions(file: true));review.acknowledged = true;await store.apply(review)
        let receipt = try XCTUnwrap(review.receipt), current = try Data(contentsOf: profile.source), count = store.backups.count
        XCTAssertTrue(store.setLabOptions(file: false));await store.restore(receipt, expectedHash: BookmarkFile.hash(current))
        XCTAssertEqual(try Data(contentsOf: profile.source), current);XCTAssertEqual(store.backups.count, count)
    }
    func testFailedOptionSaveAndMalformedOptionsStayOffWithoutDamagingWorkspace() throws {
        let store = fixture(), before = try Data(contentsOf: store.workspaceURL)
        try FileManager.default.createDirectory(at: store.labsURL, withIntermediateDirectories: true)
        XCTAssertFalse(store.setLabOptions(api: true));XCTAssertFalse(store.labs.apiEnabled)
        try FileManager.default.removeItem(at: store.labsURL)
        try Data("broken".utf8).write(to: store.labsURL)
        let reopened = AppStore(sampleData: true, directory: store.directory)
        XCTAssertFalse(reopened.labs.apiEnabled);XCTAssertFalse(reopened.labs.fileEnabled);XCTAssertNotNil(reopened.error)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
    }
    func testRegisteredProfileCheckRequiresOptInAndDoesNotChangeBrowserOrWorkspace() async throws {
        let store = fixture(), profile = try XCTUnwrap(store.profile), prefs = profile.source.deletingLastPathComponent().appendingPathComponent("Secure Preferences")
        try JSONSerialization.data(withJSONObject: ["extensions": ["settings": [id: ["path": "/synthetic/unpacked"]]]]).write(to: prefs)
        let before = try Data(contentsOf: store.workspaceURL), source = try Data(contentsOf: profile.source), originalPrefs = try Data(contentsOf: prefs)
        await store.checkRegisteredExtensions(extensionID: id);XCTAssertTrue(store.extensionChecks.isEmpty)
        XCTAssertTrue(store.setLabOptions(api: true));await store.checkRegisteredExtensions(extensionID: id)
        XCTAssertEqual(store.extensionChecks[profile.id]?.profileID, profile.id);XCTAssertEqual(store.extensionChecks[profile.id]?.presence, .recordFound)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertEqual(try Data(contentsOf: profile.source), source);XCTAssertEqual(try Data(contentsOf: prefs), originalPrefs)
        try Data("broken".utf8).write(to: prefs);await store.checkRegisteredExtensions(extensionID: id)
        XCTAssertEqual(store.extensionChecks[profile.id]?.presence, .unavailable)
    }
    func testLateExtensionCheckCannotSurviveTurningOff() async throws {
        let store = fixture();XCTAssertTrue(store.setLabOptions(api: true))
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let task = Task { await store.checkRegisteredExtensions(extensionID: id) { _, _ in
            entered.signal();_ = release.wait(timeout: .now()+5);return .recordFound
        } }
        let started = await Task.detached { Self.waitForInspection(entered) }.value
        XCTAssertTrue(started);XCTAssertTrue(store.setLabOptions(api: false));store.selectedProfileID = nil
        release.signal();await task.value
        XCTAssertTrue(store.extensionChecks.isEmpty);XCTAssertFalse(store.checkingExtension)
    }
    func testChangedSourceWithSameProfileIDRejectsLateResultAndUnblocksCheck() async throws {
        let store = fixture();XCTAssertTrue(store.setLabOptions(api: true))
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let task = Task { await store.checkRegisteredExtensions(extensionID: id) { _, _ in
            entered.signal();_ = release.wait(timeout: .now()+5);return .recordFound
        } }
        let started = await Task.detached { Self.waitForInspection(entered) }.value
        XCTAssertTrue(started)
        store.workspace.profiles[0].source = store.directory.appendingPathComponent("Changed/Bookmarks")
        release.signal();await task.value
        XCTAssertTrue(store.extensionChecks.isEmpty);XCTAssertFalse(store.checkingExtension)
    }
    func testPendingReviewShowsSavedBaseDeletionEvenWhenRefreshWouldMakeNoLocalChange() async throws {
        let store = fixture(), profile = try XCTUnwrap(store.profile), item = try XCTUnwrap(store.tree?.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.remove([item.id]) })
        let before = try Data(contentsOf: store.workspaceURL), source = try Data(contentsOf: profile.source)
        await store.refreshProfile()
        XCTAssertEqual(store.review?.workingAtReview, store.review?.result?.tree)
        XCTAssertEqual(store.pendingCount, 2)
        store.review = nil;store.showPendingReview()
        let preview = try XCTUnwrap(store.pendingReview)
        XCTAssertEqual(preview.changedIDs.count, 2)
        XCTAssertNotNil(preview.base.tree.nodes[item.id]);XCTAssertNil(preview.working.nodes[item.id])
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before);XCTAssertEqual(try Data(contentsOf: profile.source), source)
        store.workspace.profiles[0].permissionBookmark = Data("revoked".utf8)
        store.showPendingReview();XCTAssertNotNil(store.pendingReview)
    }
}
