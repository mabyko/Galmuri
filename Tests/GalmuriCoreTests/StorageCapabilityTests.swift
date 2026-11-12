import XCTest
@testable import GalmuriCore

final class StorageCapabilityTests: XCTestCase {
    private func fixture() throws -> (source: URL, profile: ConnectedProfile, coordinator: ApplyCoordinator) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("galmuri-capability-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("Bookmarks"), base = try SampleData.file()
        try base.original.write(to: source)
        var profile = ConnectedProfile(name: "Synthetic", source: source, base: base)
        let node = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        try profile.working.edit(node.id, name: "Reviewed edit", url: node.url)
        return (source, profile, ApplyCoordinator(testRoot: root, backupRoot: root.appendingPathComponent("Backups")))
    }

    func testCompanionStoresBlockApplyEvenInsideAnOwnedTestRoot() throws {
        for companion in ["EncryptedBookmarks2", "AccountBookmarks", "EncryptedAccountBookmarks2", "BookmarkMergedSurfaceOrdering"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("galmuri-capability-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let directory = root.appendingPathComponent("Default")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = directory.appendingPathComponent("Bookmarks"), base = try SampleData.file()
            try base.original.write(to: source)
            XCTAssertNil(try ProfileIO.discover(in: root).first?.restriction)
            let marker = Data("Unsupported synthetic companion".utf8)
            let companionURL = directory.appendingPathComponent(companion)
            try marker.write(to: companionURL)
            let discovered = try XCTUnwrap(ProfileIO.discover(in: root).first)
            XCTAssertNotNil(discovered.restriction, companion)
            var profile = ConnectedProfile(name: "Synthetic", source: source, sourceRestriction: discovered.restriction, base: base)
            let node = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
            try profile.working.edit(node.id, name: "Must not be applied", url: node.url)
            let coordinator = ApplyCoordinator(testRoot: root, backupRoot: root.appendingPathComponent("Backups"))
            let review = try coordinator.prepare(profile: profile)
            XCTAssertThrowsError(try coordinator.apply(profile: profile, review: review, browserRunning: { false })) {
                guard case GalmuriError.unsupported = $0 else { return XCTFail("Expected unsupported storage: \($0)") }
            }
            XCTAssertEqual(try Data(contentsOf: source), base.original)
            XCTAssertEqual(try Data(contentsOf: companionURL), marker)
            XCTAssertTrue(try coordinator.receipts().isEmpty)
        }
    }

    func testNewCompanionInvalidatesApplyBeforeBackupAndAtFinalCheck() throws {
        for companionName in ["EncryptedBookmarks2", "BookmarkMergedSurfaceOrdering"] {
        for atFinalCheck in [false, true] {
            let f = try fixture()
            XCTAssertNil(f.profile.sourceRestriction)
            let review = try f.coordinator.prepare(profile: f.profile)
            let companion = f.source.deletingLastPathComponent().appendingPathComponent(companionName)
            if !atFinalCheck { try Data("synthetic".utf8).write(to: companion) }
            var calls = 0, callbackError: Error?
            XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: review, browserRunning: {
                calls += 1
                if atFinalCheck && calls == 2 {
                    do { try Data("synthetic".utf8).write(to: companion) } catch { callbackError = error }
                }
                return false
            })) {
                guard case GalmuriError.unsupported = $0 else { return XCTFail("Expected unsupported storage: \($0)") }
            }
            XCTAssertNil(callbackError)
            XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
            let receipts = try f.coordinator.receipts()
            XCTAssertEqual(receipts.count, atFinalCheck ? 1 : 0)
            if atFinalCheck { XCTAssertEqual(receipts.first?.state, "prepared") }
        }
        }
    }

    func testRestoreRechecksCompanionsInsteadOfTrustingOldReceipt() throws {
        for companionName in ["AccountBookmarks", "BookmarkMergedSurfaceOrdering"] {
        let f = try fixture()
        let review = try f.coordinator.prepare(profile: f.profile)
        let receipt = try f.coordinator.apply(profile: f.profile, review: review, browserRunning: { false })
        let applied = try f.coordinator.readForReview(f.source)
        try Data("synthetic".utf8).write(to: f.source.deletingLastPathComponent().appendingPathComponent(companionName))
        XCTAssertThrowsError(try f.coordinator.restore(receipt, expectedCurrentHash: applied.file.fingerprint, expectedCurrentIdentity: applied.identity, browserRunning: { false })) {
            guard case GalmuriError.unsupported = $0 else { return XCTFail("Expected unsupported storage: \($0)") }
        }
        XCTAssertEqual(try Data(contentsOf: f.source), applied.file.original)
        XCTAssertEqual(try f.coordinator.receipts().count, 1)
        XCTAssertEqual(try Data(contentsOf: receipt.backup), f.profile.base.original)
        }
    }

    func testEncryptedOnlyDiscoveryReportsUnsupportedWithoutReadingPayload() throws {
        let f = try fixture(), directory = f.source.deletingLastPathComponent()
        let encryptedOnly = directory.deletingLastPathComponent().appendingPathComponent("EncryptedOnly")
        try FileManager.default.createDirectory(at: encryptedOnly, withIntermediateDirectories: true)
        let marker = Data([0xff, 0xfe, 0x00]), encrypted = encryptedOnly.appendingPathComponent("EncryptedBookmarks2")
        try marker.write(to: encrypted)
        let discovered = try ProfileIO.discover(in: directory.deletingLastPathComponent())
        XCTAssertEqual(discovered.count, 2)
        XCTAssertTrue(try XCTUnwrap(discovered.first { $0.directory.lastPathComponent == directory.lastPathComponent }).hasPlaintext)
        let unsupported = try XCTUnwrap(discovered.first { $0.directory.lastPathComponent == encryptedOnly.lastPathComponent })
        XCTAssertFalse(unsupported.hasPlaintext)
        XCTAssertNotNil(unsupported.restriction)
        XCTAssertEqual(unsupported.file, unsupported.directory.appendingPathComponent("Bookmarks"))
        let selected = try XCTUnwrap(ProfileIO.discover(in: encryptedOnly).first)
        XCTAssertFalse(selected.hasPlaintext)
        XCTAssertEqual(selected.directory.path, encryptedOnly.path)
        XCTAssertEqual(try Data(contentsOf: encrypted), marker)
    }
}
