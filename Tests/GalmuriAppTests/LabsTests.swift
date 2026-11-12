import XCTest
import GalmuriCore
@testable import GalmuriApp

@MainActor final class LabsTests: XCTestCase {
    private func fixture() -> AppStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriLabs-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory, browserState: { _ in true })
        XCTAssertTrue(store.setLabOptions(file: true))
        return store
    }

    func testFileExperimentRequiresPendingOwnedSupportedSourceAndPreservesWork() async throws {
        let store = fixture()
        XCTAssertNil(store.fileApplyExperimentReview())
        let item = try XCTUnwrap(store.tree?.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Labs edit", url: item.url) })
        let before = try Data(contentsOf: store.workspaceURL), source = try XCTUnwrap(store.profile?.source)
        let original = try Data(contentsOf: source)
        let session = try XCTUnwrap(store.fileApplyExperimentReview())
        XCTAssertEqual(session.mode, .apply); XCTAssertEqual(session.profileID, store.selectedProfileID)
        XCTAssertNil(store.review)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertEqual(try Data(contentsOf: source), original)
        await store.loadReview(session)
        XCTAssertEqual(session.phase, .exit); XCTAssertNil(session.latest)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testLabsEntryDoesNotUnlockExternalRestrictedBusyOrActiveReview() throws {
        let store = fixture(), item = try XCTUnwrap(store.tree?.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Labs edit", url: item.url) })
        XCTAssertTrue(store.canReviewFileApplyExperiment)
        store.busy = true; XCTAssertNil(store.fileApplyExperimentReview()); store.busy = false
        store.review = ReviewSession(profileID: store.profile!.id)
        XCTAssertNil(store.fileApplyExperimentReview()); store.review = nil
        store.workspace.profiles[0].sourceRestriction = "Unsupported companion"
        XCTAssertNil(store.fileApplyExperimentReview()); store.workspace.profiles[0].sourceRestriction = nil
        store.workspace.profiles[0].source = store.directory.appendingPathComponent("OutsideOwnedRoot/Bookmarks")
        XCTAssertNil(store.fileApplyExperimentReview())
    }
}
