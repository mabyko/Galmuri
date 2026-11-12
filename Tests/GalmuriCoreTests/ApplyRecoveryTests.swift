import XCTest
import Darwin
@testable import GalmuriCore

final class ApplyRecoveryTests: XCTestCase {
    private func fixture(at base: URL = FileManager.default.temporaryDirectory) throws -> (root: URL, source: URL, profile: ConnectedProfile, coordinator: ApplyCoordinator) {
        let root = base.appendingPathComponent("galmuri-recovery-" + UUID().uuidString)
        let directory = root.appendingPathComponent("test/Default")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = directory.appendingPathComponent("Bookmarks"), file = try SampleData.file()
        try file.original.write(to: source)
        var profile = ConnectedProfile(name: "Synthetic", source: source, base: file)
        let node = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        try profile.working.edit(node.id, name: "Reviewed edit", url: node.url)
        return (root, source, profile, ApplyCoordinator(testRoot: root.appendingPathComponent("test"), backupRoot: root.appendingPathComponent("backups")))
    }

    private func replaceIdentically(_ source: URL) throws {
        let copy = source.deletingLastPathComponent().appendingPathComponent("replacement")
        try Data(contentsOf: source).write(to: copy)
        guard rename(copy.path, source.path) == 0 else { throw POSIXError(.EIO) }
    }

    func testSystemTemporaryAliasesWorkAndCustomAncestorSymlinksAreRejected() throws {
        for base in [FileManager.default.temporaryDirectory, URL(fileURLWithPath: "/tmp", isDirectory: true)] {
            let f = try fixture(at: base)
            XCTAssertTrue(f.coordinator.canWrite(f.source))
            let review = try f.coordinator.prepare(profile: f.profile)
            _ = try f.coordinator.apply(profile: f.profile, review: review, browserRunning: { false })
            let link = f.root.appendingPathComponent("test/Linked")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.source.deletingLastPathComponent())
            let linkedSource = link.appendingPathComponent("Bookmarks")
            XCTAssertFalse(f.coordinator.canWrite(linkedSource))
            XCTAssertThrowsError(try f.coordinator.readForReview(linkedSource))
        }
    }

    func testApprovalRejectsChangedParentEvenWhenFileInodeAndBytesSurvive() throws {
        let f = try fixture(), review = try f.coordinator.prepare(profile: f.profile)
        let parent = f.source.deletingLastPathComponent(), moved = f.root.appendingPathComponent("test/Moved")
        try FileManager.default.moveItem(at: parent, to: moved)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        try FileManager.default.moveItem(at: moved.appendingPathComponent("Bookmarks"), to: f.source)
        XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: review, browserRunning: { false })) {
            XCTAssertEqual($0 as? GalmuriError, .staleSource)
        }
        XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
    }

    func testApprovalRejectsIdenticalBytesAtDifferentInode() throws {
        let f = try fixture(), review = try f.coordinator.prepare(profile: f.profile)
        try replaceIdentically(f.source)
        XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: review, browserRunning: { false })) {
            XCTAssertEqual($0 as? GalmuriError, .staleSource)
        }
        XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
        XCTAssertTrue(try f.coordinator.receipts().isEmpty)
    }

    func testApprovalCannotBeTransferredToAnotherSourceOrLoseIdentity() throws {
        let f = try fixture(), review = try f.coordinator.prepare(profile: f.profile)
        let other = f.root.appendingPathComponent("test/Other/Bookmarks")
        try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try f.profile.base.original.write(to: other)
        var moved = f.profile; moved.source = other
        XCTAssertThrowsError(try f.coordinator.apply(profile: moved, review: review, browserRunning: { false }))
        let unbound = ApplyReview(latest: review.latest, result: review.result)
        XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: unbound, browserRunning: { false }))
        XCTAssertEqual(try Data(contentsOf: other), f.profile.base.original)
    }

    func testFinalBrowserCallbackCannotSwapSourceWithIdenticalBytes() throws {
        let f = try fixture(), review = try f.coordinator.prepare(profile: f.profile)
        var calls = 0, callbackError: Error?
        XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: review, browserRunning: {
            calls += 1
            if calls == 2 { do { try self.replaceIdentically(f.source) } catch { callbackError = error } }
            return false
        })) { XCTAssertEqual($0 as? GalmuriError, .staleSource) }
        XCTAssertNil(callbackError)
        XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
        let receipt = try XCTUnwrap(f.coordinator.receipts().first)
        XCTAssertEqual(receipt.state, "prepared")
        XCTAssertEqual(try Data(contentsOf: receipt.backup), f.profile.base.original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(receipt.temporary).path))
    }

    func testFinalBrowserCallbackCannotChangeSourceBytesOrAttributes() throws {
        for changeAttributes in [false, true] {
            let f = try fixture(), review = try f.coordinator.prepare(profile: f.profile)
            var calls = 0, callbackError: Error?
            var changed = f.profile.base.original; changed.append(contentsOf: "\n".utf8)
            XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: review, browserRunning: {
                calls += 1
                if calls == 2 {
                    do {
                        if changeAttributes { try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: f.source.path) }
                        else { try changed.write(to: f.source) }
                    } catch { callbackError = error }
                }
                return false
            }))
            XCTAssertNil(callbackError)
            XCTAssertEqual(try Data(contentsOf: f.source), changeAttributes ? f.profile.base.original : changed)
            XCTAssertEqual(try f.coordinator.receipts().first?.state, "prepared")
        }
    }

    func testTamperedTemporaryIsNotApplied() throws {
        let f = try fixture(), review = try f.coordinator.prepare(profile: f.profile)
        var calls = 0, callbackError: Error?
        XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: review, browserRunning: {
            calls += 1
            if calls == 2 {
                do {
                    let receipt = try XCTUnwrap(f.coordinator.receipts().first)
                    try f.profile.base.original.write(to: XCTUnwrap(receipt.temporary))
                } catch { callbackError = error }
            }
            return false
        }))
        XCTAssertNil(callbackError)
        XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
        XCTAssertEqual(try f.coordinator.receipts().first?.state, "prepared")
    }

    func testModeOwnershipAndExtendedAttributesSurviveApplyAndRestore() throws {
        let f = try fixture(), attribute = "org.galmuri.synthetic", value = Data("synthetic metadata".utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: f.source.path)
        let setResult = value.withUnsafeBytes { setxattr(f.source.path, attribute, $0.baseAddress, $0.count, 0, 0) }
        XCTAssertEqual(setResult, 0)
        var before = stat(); XCTAssertEqual(lstat(f.source.path, &before), 0)
        let receipt = try f.coordinator.apply(profile: f.profile, review: f.coordinator.prepare(profile: f.profile), browserRunning: { false })
        func checkAttributes(_ source: URL) throws {
            var after = stat(); XCTAssertEqual(lstat(source.path, &after), 0)
            XCTAssertEqual(after.st_mode, before.st_mode)
            XCTAssertEqual(after.st_uid, before.st_uid); XCTAssertEqual(after.st_gid, before.st_gid)
            var bytes = Data(count: value.count)
            let count = bytes.withUnsafeMutableBytes { getxattr(source.path, attribute, $0.baseAddress, $0.count, 0, 0) }
            XCTAssertEqual(count, value.count); XCTAssertEqual(bytes, value)
        }
        try checkAttributes(f.source)
        var backupStatus = stat(); XCTAssertEqual(lstat(receipt.backup.path, &backupStatus), 0)
        XCTAssertEqual(backupStatus.st_mode & 0o777, 0o600)
        XCTAssertEqual(receipt.sourceMode, 0o640)
        let current = try f.coordinator.readForReview(f.source)
        _ = try f.coordinator.restore(receipt, expectedCurrentHash: current.file.fingerprint, expectedCurrentIdentity: current.identity, browserRunning: { false })
        try checkAttributes(f.source)
        XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
    }

    func testExtendedACLSurvivesApplyAndRestore() throws {
        let f = try fixture()
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+a", "everyone allow readattr,readextattr", f.source.path]
        try chmod.run(); chmod.waitUntilExit()
        XCTAssertEqual(chmod.terminationStatus, 0)
        func aclText(_ source: URL) throws -> String {
            let acl = try XCTUnwrap(acl_get_file(source.path, ACL_TYPE_EXTENDED))
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var length = 0
            let text = try XCTUnwrap(acl_to_text(acl, &length))
            defer { acl_free(text) }
            return String(cString: text)
        }
        let originalACL = try aclText(f.source)
        XCTAssertTrue(originalACL.contains("allow"))
        let receipt = try f.coordinator.apply(profile: f.profile, review: f.coordinator.prepare(profile: f.profile), browserRunning: { false })
        XCTAssertEqual(try aclText(f.source), originalACL)
        _ = try f.coordinator.restore(receipt, expectedCurrentHash: receipt.afterHash, browserRunning: { false })
        XCTAssertEqual(try aclText(f.source), originalACL)
    }

    func testRestoreApprovalRejectsIdenticalByteReplacementAndTamperedBackup() throws {
        let f = try fixture()
        let receipt = try f.coordinator.apply(profile: f.profile, review: f.coordinator.prepare(profile: f.profile), browserRunning: { false })
        let current = try f.coordinator.readForReview(f.source)
        try replaceIdentically(f.source)
        XCTAssertThrowsError(try f.coordinator.restore(receipt, expectedCurrentHash: current.file.fingerprint, expectedCurrentIdentity: current.identity, browserRunning: { false })) {
            XCTAssertEqual($0 as? GalmuriError, .staleSource)
        }
        try Data("damaged".utf8).write(to: receipt.backup)
        XCTAssertThrowsError(try f.coordinator.restore(receipt, expectedCurrentHash: current.file.fingerprint, browserRunning: { false }))
        XCTAssertEqual(try Data(contentsOf: f.source), current.file.original)
        XCTAssertEqual(try f.coordinator.receipts().count, 1)
    }

    func testDamagedReceiptDoesNotHideValidHistoryAndLegacyReceiptDecodes() throws {
        let f = try fixture()
        let receipt = try f.coordinator.apply(profile: f.profile, review: f.coordinator.prepare(profile: f.profile), browserRunning: { false })
        _ = try f.coordinator.restore(receipt, expectedCurrentHash: receipt.afterHash, browserRunning: { false })
        let damaged = f.coordinator.backupRoot.appendingPathComponent("damaged.json"), bytes = Data("broken".utf8)
        try bytes.write(to: damaged)
        let receiptURL = f.coordinator.backupRoot.appendingPathComponent(receipt.id.uuidString + ".json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as? [String: Any])
        for key in ["sourceIdentity", "temporary", "sourceMode"] { json.removeValue(forKey: key) }
        try JSONSerialization.data(withJSONObject: json).write(to: receiptURL)
        let history = try f.coordinator.receiptHistory()
        XCTAssertEqual(history.receipts.count, 2); XCTAssertEqual(history.unreadableCount, 1)
        XCTAssertEqual(try Data(contentsOf: damaged), bytes)
        XCTAssertTrue(history.receipts.contains { $0.id == receipt.id && $0.sourceIdentity == nil })
    }

    func testReceiptFinalizationFailureRetainsOriginalAndPreparedJournal() throws {
        let f = try fixture(), review = try f.coordinator.prepare(profile: f.profile)
        var calls = 0, callbackError: Error?
        XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: review, browserRunning: {
            calls += 1
            if calls == 2 {
                do {
                    let receipt = try XCTUnwrap(f.coordinator.receipts().first)
                    let collision = f.coordinator.backupRoot.appendingPathComponent("." + receipt.id.uuidString + "-receipt.tmp")
                    try Data("synthetic collision".utf8).write(to: collision)
                } catch { callbackError = error }
            }
            return false
        })) { XCTAssertTrue($0.localizedDescription.contains("replacement may have completed")) }
        XCTAssertNil(callbackError)
        let prepared = try XCTUnwrap(f.coordinator.receipts().first)
        XCTAssertEqual(prepared.state, "prepared")
        XCTAssertEqual(try ProfileIO.read(f.source).fingerprint, prepared.afterHash)
        XCTAssertEqual(try Data(contentsOf: prepared.backup), f.profile.base.original)
        // A fresh coordinator can discover and restore the prepared backup after the failed finalization.
        let relaunched = ApplyCoordinator(testRoot: f.coordinator.testRoot, backupRoot: f.coordinator.backupRoot)
        _ = try relaunched.restore(prepared, expectedCurrentHash: prepared.afterHash, browserRunning: { false })
        XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
    }

    func testBackupDirectoryFailureAndHardlinksLeaveOriginalUntouched() throws {
        let f = try fixture(), review = try f.coordinator.prepare(profile: f.profile)
        try Data("not a directory".utf8).write(to: f.coordinator.backupRoot)
        XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: review, browserRunning: { false }))
        XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
        try FileManager.default.removeItem(at: f.coordinator.backupRoot)
        try FileManager.default.linkItem(at: f.source, to: f.root.appendingPathComponent("alias"))
        XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: review, browserRunning: { false }))
        XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
    }

    func testSymlinkedBackupRootAndExternalRestoreAreRejected() throws {
        let f = try fixture(), other = f.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: f.coordinator.backupRoot, withDestinationURL: other)
        XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: f.coordinator.prepare(profile: f.profile), browserRunning: { false }))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: other.path).isEmpty)
        try FileManager.default.removeItem(at: f.coordinator.backupRoot)
        var receipt = try f.coordinator.apply(profile: f.profile, review: f.coordinator.prepare(profile: f.profile), browserRunning: { false })
        receipt.source = other.appendingPathComponent("Bookmarks")
        try f.profile.base.original.write(to: receipt.source)
        XCTAssertThrowsError(try f.coordinator.restore(receipt, expectedCurrentHash: f.profile.base.fingerprint, browserRunning: { false })) {
            XCTAssertEqual($0 as? GalmuriError, .localTestsOnly)
        }
        XCTAssertEqual(try Data(contentsOf: receipt.source), f.profile.base.original)
    }
}
