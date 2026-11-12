import XCTest
import GalmuriCore
@testable import GalmuriApp

final class ReviewIdentityTests: XCTestCase {
    @MainActor
    func testInterruptedRestoreExposesItsPreparedBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriRestore-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var restarting = false, checks = 0
        let store = AppStore(sampleData: true, directory: directory, browserState: { _ in checks += 1; return restarting && checks >= 2 })
        XCTAssertTrue(store.setLabOptions(file: true))
        let profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Applied title", url: item.url) })
        let session = ReviewSession(profileID: profile.id)
        store.loadReview(session); session.acknowledged = true; store.apply(session)
        let receipt = try XCTUnwrap(session.receipt)
        let current = try store.coordinator.readForReview(profile.source)
        restarting = true; checks = 0
        store.restore(receipt, expectedHash: current.file.fingerprint, expectedIdentity: current.identity)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.backups.count, 2)
        XCTAssertTrue(store.backups.contains { $0.state == "prepared" })
        XCTAssertEqual(try Data(contentsOf: profile.source), current.file.original)
    }

    @MainActor
    func testByteIdenticalSourceReplacementInvalidatesNativeApproval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriIdentity-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(sampleData: true, directory: directory, browserState: { _ in false })
        XCTAssertTrue(store.setLabOptions(file: true))
        let profile = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Keep pending edit", url: item.url) })
        let session = ReviewSession(profileID: profile.id)
        store.loadReview(session)
        XCTAssertNotNil(session.sourceIdentity)
        let original = try Data(contentsOf: profile.source)
        try original.write(to: profile.source, options: .atomic)
        session.acknowledged = true
        store.apply(session)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(session.acknowledged)
        XCTAssertNil(session.receipt)
        XCTAssertTrue(store.backups.isEmpty)
        XCTAssertEqual(store.tree?.nodes[item.id]?.name, "Keep pending edit")
        XCTAssertEqual(try Data(contentsOf: profile.source), original)
    }
}
