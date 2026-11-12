import XCTest
import Darwin
@testable import GalmuriCore

final class ChromiumStoreTransactionTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let profile: URL
        let coordinator: ChromiumStoreCoordinator
        let cipher: ChromiumBookmarkCipher
        let originals: [String: Data]
        func url(_ name: String) -> URL { profile.appendingPathComponent(name) }
    }

    private func fixture(encryptedOnly: Bool = false, sidecars: Bool = false) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("galmuri-group-" + UUID().uuidString)
        let profile = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let cipher = try ChromiumBookmarkCipher(password: Data("synthetic transaction password".utf8))
        let bytes = try SampleData.file().original
        var originals = ["EncryptedBookmarks2": try cipher.encrypt(bytes)]
        if !encryptedOnly {
            originals["Bookmarks"] = bytes
            originals["BookmarkMergedSurfaceOrdering"] = Data("{\n}\n".utf8)
        }
        if sidecars {
            originals["Bookmarks.bak"] = Data("old non-authoritative plain backup".utf8)
            originals["EncryptedBookmarks2.bak"] = Data("old non-authoritative encrypted backup".utf8)
        }
        for (name, data) in originals { try data.write(to: profile.appendingPathComponent(name)) }
        return Fixture(root: root, profile: profile,
                       coordinator: ChromiumStoreCoordinator(ownedRoot: root, backupRoot: root.appendingPathComponent("backups")),
                       cipher: cipher, originals: originals)
    }

    private func edit(_ review: ChromiumStoreCoordinator.Review) throws -> BookmarkTree {
        var tree = review.store.file.tree
        let node = try XCTUnwrap(tree.nodes.values.first { $0.url != nil })
        try tree.edit(node.id, name: "Reviewed synthetic change", url: node.url)
        return tree
    }

    private func apply(_ f: Fixture, browserRunning: () -> Bool = { false }) throws -> ChromiumStoreCoordinator.Receipt {
        let review = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
        let receipt = try f.coordinator.apply(review, edited: edit(review), cipher: f.cipher, browserRunning: browserRunning)
        return try XCTUnwrap(receipt)
    }

    private func assertOriginals(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) throws {
        for (name, bytes) in f.originals {
            XCTAssertEqual(try Data(contentsOf: f.url(name)), bytes, name, file: file, line: line)
        }
    }

    private func interrupted(_ operation: () throws -> ChromiumStoreCoordinator.Receipt?) throws -> ChromiumStoreCoordinator.Receipt {
        do { _ = try operation(); XCTFail("Expected a retained interrupted transaction"); throw GalmuriError.invalid("no interruption") }
        catch let error as ChromiumStoreInterruption { return error.receipt }
    }

    private func partial(_ f: Fixture) throws -> ChromiumStoreCoordinator.Receipt {
        var calls = 0
        return try interrupted { try apply(f, browserRunning: { calls += 1; return calls == 3 }) }
    }

    private func replaceIdentically(_ url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent("replacement")
        try Data(contentsOf: url).write(to: temporary)
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError(.EIO) }
    }

    private let quarantineName = "com.apple.quarantine"
    private let quarantineValue = Data("0081;12345678;SyntheticFixture;91BC6A9B-251B-470E-BDB9-B01DB3D537D2".utf8)

    private func setAttribute(_ name: String, value: Data, on url: URL) throws {
        guard value.withUnsafeBytes({ setxattr(url.path, name, $0.baseAddress, $0.count, 0, 0) }) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func attribute(_ name: String, on url: URL) throws -> Data {
        let length = getxattr(url.path, name, nil, 0, 0, 0)
        guard length >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var data = Data(count: length)
        guard data.withUnsafeMutableBytes({ getxattr(url.path, name, $0.baseAddress, $0.count, 0, 0) }) == length else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return data
    }

    func testQuarantineCopyApplyAndRestoreKeepExactRawAttributes() throws {
        let f = try fixture(sidecars: true)
        let otherName = "org.galmuri.transaction", otherValue = Data([0, 255, 1, 128])
        for name in f.originals.keys {
            try setAttribute(quarantineName, value: quarantineValue, on: f.url(name))
            try setAttribute(otherName, value: otherValue, on: f.url(name))
        }
        // Exercise the installed copyfile behavior independently of the coordinator's exact repair.
        let copy = f.root.appendingPathComponent("metadata-copy")
        try Data().write(to: copy)
        XCTAssertEqual(copyfile(f.url("Bookmarks").path, copy.path, nil, copyfile_flags_t(COPYFILE_METADATA)), 0)
        let copied = try attribute(quarantineName, on: copy)
        XCTAssertTrue(ChromiumStoreCoordinator.canRestoreCopiedQuarantine(quarantineValue, copied))
        let receipt = try apply(f)
        for name in f.originals.keys {
            for url in [f.url(name), receipt.journal.deletingLastPathComponent().appendingPathComponent(name)] {
                XCTAssertEqual(try attribute(quarantineName, on: url), quarantineValue)
                XCTAssertEqual(try attribute(otherName, on: url), otherValue)
            }
        }
        let newer = Data("0081;23456789;NewSyntheticAgent;91BC6A9B-251B-470E-BDB9-B01DB3D537D2".utf8)
        try setAttribute(quarantineName, value: newer, on: f.url("Bookmarks"))
        let review = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
        let restored = try XCTUnwrap(f.coordinator.restore(receipt, review: review, cipher: f.cipher, browserRunning: { false }))
        XCTAssertEqual(try attribute(quarantineName, on: restored.journal.deletingLastPathComponent().appendingPathComponent("Bookmarks")), newer)
        XCTAssertEqual(try attribute(quarantineName, on: f.url("Bookmarks")), quarantineValue)
        try assertOriginals(f)
    }

    func testEmptyEventQuarantineCopyApplyAndRestorePreserveAbsence() throws {
        let f = try fixture()
        let value = Data("0081;12345678;Google Chrome for Testing;".utf8)
        try setAttribute(quarantineName, value: value, on: f.url("Bookmarks"))
        let receipt = try apply(f)
        XCTAssertEqual(try attribute(quarantineName, on: f.url("Bookmarks")), value)
        XCTAssertEqual(try attribute(quarantineName, on: receipt.journal.deletingLastPathComponent().appendingPathComponent("Bookmarks")), value)
        let review = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
        _ = try f.coordinator.restore(receipt, review: review, cipher: f.cipher, browserRunning: { false })
        XCTAssertEqual(try attribute(quarantineName, on: f.url("Bookmarks")), value)
        try assertOriginals(f)
    }

    func testQuarantineRepairRejectsChangedProtectionAndUnknownEncodings() {
        let valid = "0081;6adcac90;;91BC6A9B-251B-470E-BDB9-B01DB3D537D2"
        XCTAssertTrue(ChromiumStoreCoordinator.canRestoreCopiedQuarantine(quarantineValue, Data(valid.utf8)))
        let emptyEvent = Data("0081;12345678;Google Chrome for Testing;".utf8)
        let copiedEmptyEvent = Data("0081;6adcac90;;".utf8)
        XCTAssertTrue(ChromiumStoreCoordinator.canRestoreCopiedQuarantine(emptyEvent, copiedEmptyEvent))
        XCTAssertFalse(ChromiumStoreCoordinator.canRestoreCopiedQuarantine(quarantineValue, copiedEmptyEvent))
        XCTAssertFalse(ChromiumStoreCoordinator.canRestoreCopiedQuarantine(emptyEvent, Data(valid.utf8)))
        for invalid in [
            valid.replacingOccurrences(of: "0081", with: "0085"),
            valid.replacingOccurrences(of: "0081", with: "0001"),
            valid.replacingOccurrences(of: "0081", with: "0181"),
            valid.replacingOccurrences(of: "91BC6A9B", with: "81BC6A9B"),
            valid.replacingOccurrences(of: "6adcac90", with: "not-hex!"),
            valid.replacingOccurrences(of: "6adcac90", with: "123456789"),
            valid.replacingOccurrences(of: ";;", with: ";bad\nagent;"),
            valid + ";extra", "0081;12345678;agent;not-a-uuid", "", "future encoding"
        ] {
            XCTAssertFalse(ChromiumStoreCoordinator.canRestoreCopiedQuarantine(quarantineValue, Data(invalid.utf8)), invalid)
            XCTAssertFalse(ChromiumStoreCoordinator.canRestoreCopiedQuarantine(Data(invalid.utf8), Data(valid.utf8)), invalid)
        }
        XCTAssertFalse(ChromiumStoreCoordinator.canRestoreCopiedQuarantine(quarantineValue, Data([0xff])))
    }

    func testRawQuarantineAndOtherAttributeMutationsStillBlockBeforeReplacement() throws {
        for target in ["source", "stage", "backup", "journal"] {
            for mutation in ["flags", "timestamp", "event", "other"] {
                let f = try fixture()
                try setAttribute(quarantineName, value: quarantineValue, on: f.url("Bookmarks"))
                let review = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
                var calls = 0, callbackError: Error?
                _ = try interrupted {
                    try f.coordinator.apply(review, edited: edit(review), cipher: f.cipher, browserRunning: {
                        calls += 1
                        if calls == 2 {
                            do {
                                let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: f.coordinator.backupRoot, includingPropertiesForKeys: nil).first)
                                let url: URL
                                switch target {
                                case "source": url = f.url("Bookmarks")
                                case "stage": url = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: f.profile, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".galmuri-") && $0.lastPathComponent.hasSuffix("-Bookmarks") })
                                case "backup": url = backup.appendingPathComponent("Bookmarks")
                                default: url = backup.appendingPathComponent("journal.json")
                                }
                                let text = String(decoding: self.quarantineValue, as: UTF8.self)
                                let value: Data
                                switch mutation {
                                case "flags": value = Data(text.replacingOccurrences(of: "0081", with: "0085").utf8)
                                case "timestamp": value = Data(text.replacingOccurrences(of: "12345678", with: "23456789").utf8)
                                case "event": value = Data(text.replacingOccurrences(of: "91BC6A9B", with: "81BC6A9B").utf8)
                                default: value = Data("changed arbitrary attribute".utf8)
                                }
                                try self.setAttribute(mutation == "other" ? "org.galmuri.transaction" : self.quarantineName, value: value, on: url)
                            } catch { callbackError = error }
                        }
                        return false
                    })
                }
                XCTAssertNil(callbackError, "\(target)/\(mutation)")
                try assertOriginals(f)
            }
        }
    }

    func testDualFileApplyRestorePreservesEveryOriginalAndBacksUpCurrentSet() throws {
        let f = try fixture(sidecars: true), receipt = try apply(f)
        let after = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
        XCTAssertNotEqual(after.store.file.original, f.originals["Bookmarks"])
        let restored = try XCTUnwrap(f.coordinator.restore(receipt, review: after, cipher: f.cipher, browserRunning: { false }))
        try assertOriginals(f)
        for name in f.originals.keys {
            let initialBackup = receipt.journal.deletingLastPathComponent().appendingPathComponent(name)
            XCTAssertEqual(try Data(contentsOf: initialBackup), f.originals[name])
            let currentBackup = restored.journal.deletingLastPathComponent().appendingPathComponent(name)
            XCTAssertEqual(try Data(contentsOf: currentBackup), after.store.originals[name] ?? f.originals[name])
        }
        let journal = try String(contentsOf: receipt.journal, encoding: .utf8)
        XCTAssertFalse(journal.contains("synthetic transaction password"))
        XCTAssertFalse(journal.contains("Reviewed synthetic change"))
    }

    func testPartialInterruptionRecoversRawDisagreeingPairAfterCoordinatorRestart() throws {
        let f = try fixture(), receipt = try partial(f)
        XCTAssertNotEqual(try Data(contentsOf: f.url("Bookmarks")), f.originals["Bookmarks"])
        XCTAssertEqual(try Data(contentsOf: f.url("EncryptedBookmarks2")), f.originals["EncryptedBookmarks2"])
        XCTAssertThrowsError(try f.coordinator.readForReview(f.profile, cipher: f.cipher))
        let restarted = ChromiumStoreCoordinator(ownedRoot: f.root, backupRoot: f.coordinator.backupRoot)
        let retained = try restarted.readReceipt(receipt.journal)
        XCTAssertEqual(retained.fingerprint, receipt.fingerprint)
        _ = try JSONDecoder().decode(ChromiumStoreCoordinator.Receipt.self, from: JSONEncoder().encode(retained))
        let recovery = try XCTUnwrap(restarted.recover(retained, cipher: f.cipher, browserRunning: { false }))
        try assertOriginals(f)
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.journal.path))
        XCTAssertNotEqual(try Data(contentsOf: recovery.journal.deletingLastPathComponent().appendingPathComponent("Bookmarks")), f.originals["Bookmarks"])
        XCTAssertThrowsError(try restarted.recover(retained, cipher: f.cipher, browserRunning: { false }))
    }

    func testRecoveryInterruptedAgainCanStillReachTheInitialOriginals() throws {
        let f = try fixture(), receipt = try apply(f)
        var calls = 0
        let interruptedRecovery = try interrupted {
            try f.coordinator.recover(receipt, cipher: f.cipher, browserRunning: { calls += 1; return calls == 4 })
        }
        // recover's entry check + commit entry + first rename check precede the second rename check.
        XCTAssertEqual(try Data(contentsOf: f.url("Bookmarks")), f.originals["Bookmarks"])
        XCTAssertNotEqual(try Data(contentsOf: f.url("EncryptedBookmarks2")), f.originals["EncryptedBookmarks2"])
        _ = try f.coordinator.recover(interruptedRecovery, cipher: f.cipher, browserRunning: { false })
        try assertOriginals(f)
    }

    func testNoOpPreservesBytesInodesAndAbsenceWithoutCreatingBackups() throws {
        for onlyEncrypted in [false, true] {
            let f = try fixture(encryptedOnly: onlyEncrypted)
            let review = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
            let before = try FileManager.default.attributesOfItem(atPath: f.url("EncryptedBookmarks2").path)[.systemFileNumber] as? NSNumber
            XCTAssertNil(try f.coordinator.apply(review, edited: review.store.file.tree, cipher: f.cipher, browserRunning: { false }))
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.coordinator.backupRoot.path))
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: f.url("EncryptedBookmarks2").path)[.systemFileNumber] as? NSNumber, before)
            let receipt = try apply(f), current = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
            _ = try f.coordinator.restore(receipt, review: current, cipher: f.cipher, browserRunning: { false })
            try assertOriginals(f)
            XCTAssertEqual(FileManager.default.fileExists(atPath: f.url("Bookmarks").path), !onlyEncrypted)
            XCTAssertEqual(FileManager.default.fileExists(atPath: f.url("BookmarkMergedSurfaceOrdering").path), !onlyEncrypted)
        }
    }

    func testStaleFileParentAndFullInventoryInvalidateApproval() throws {
        for change in ["inode", "parent", "inventory", "sidecar", "unsupported"] {
            let f = try fixture(sidecars: true), review = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
            switch change {
            case "inode": try replaceIdentically(f.url("EncryptedBookmarks2"))
            case "parent":
                let moved = f.root.appendingPathComponent("Old")
                try FileManager.default.moveItem(at: f.profile, to: moved)
                try FileManager.default.createDirectory(at: f.profile, withIntermediateDirectories: false)
                for name in f.originals.keys { try FileManager.default.moveItem(at: moved.appendingPathComponent(name), to: f.url(name)) }
            case "inventory": try Data().write(to: f.url("UnrelatedNewFile"))
            case "sidecar": try Data("new browser backup".utf8).write(to: f.url("Bookmarks.bak"))
            default: try Data().write(to: f.url("EncryptedAccountBookmarks2.bak"))
            }
            XCTAssertThrowsError(try f.coordinator.apply(review, edited: edit(review), cipher: f.cipher, browserRunning: { false }))
            XCTAssertEqual(try Data(contentsOf: f.url("Bookmarks")), f.originals["Bookmarks"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.coordinator.backupRoot.path))
        }
    }

    func testCorruptOrReplacedBackupAndJournalFailClosed() throws {
        for target in ["Bookmarks", "EncryptedBookmarks2", "journal.json", "identical-backup", "identical-journal"] {
            let f = try fixture(), receipt = try partial(f)
            let parent = receipt.journal.deletingLastPathComponent()
            if target == "identical-backup" { try replaceIdentically(parent.appendingPathComponent("Bookmarks")) }
            else if target == "identical-journal" { try replaceIdentically(receipt.journal) }
            else { try Data("tampered".utf8).write(to: parent.appendingPathComponent(target)) }
            let current = try Data(contentsOf: f.url("Bookmarks"))
            XCTAssertThrowsError(try f.coordinator.recover(receipt, cipher: f.cipher, browserRunning: { false }))
            XCTAssertEqual(try Data(contentsOf: f.url("Bookmarks")), current)
            XCTAssertEqual(try Data(contentsOf: f.url("EncryptedBookmarks2")), f.originals["EncryptedBookmarks2"])
        }
    }

    func testLateBrowserBlockRetainsPreparedArtifactsAndDoesNotAutoRollback() throws {
        for blockAt in [1, 2, 3, 4] {
            let f = try fixture()
            var calls = 0
            do { _ = try apply(f, browserRunning: { calls += 1; return calls == blockAt }); XCTFail("Expected browser block") }
            catch let interruption as ChromiumStoreInterruption {
                XCTAssertTrue(FileManager.default.fileExists(atPath: interruption.receipt.journal.path))
                let bytes = try Data(contentsOf: f.url("Bookmarks"))
                XCTAssertThrowsError(try f.coordinator.recover(interruption.receipt, cipher: f.cipher, browserRunning: { true }))
                XCTAssertEqual(try Data(contentsOf: f.url("Bookmarks")), bytes)
                _ = try f.coordinator.recover(interruption.receipt, cipher: f.cipher, browserRunning: { false })
                try assertOriginals(f)
            } catch { XCTAssertEqual(error as? GalmuriError, .browserRunning); try assertOriginals(f) }
        }
    }

    func testLateSourceStageBackupAndInventoryChangesBlockBeforeFirstRename() throws {
        for change in ["source", "stage", "backup", "inventory", "unknown-store"] {
            let f = try fixture(), review = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
            var calls = 0, callbackError: Error?
            let receipt = try interrupted {
                try f.coordinator.apply(review, edited: edit(review), cipher: f.cipher, browserRunning: {
                    calls += 1
                    if calls == 2 {
                        do {
                            let directory = try FileManager.default.contentsOfDirectory(at: f.coordinator.backupRoot, includingPropertiesForKeys: nil).first!
                            switch change {
                            case "source": try self.replaceIdentically(f.url("EncryptedBookmarks2"))
                            case "stage":
                                let stage = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: f.profile, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".galmuri-") })
                                try Data("damaged stage".utf8).write(to: stage)
                            case "backup": try Data("damaged backup".utf8).write(to: directory.appendingPathComponent("Bookmarks"))
                            case "inventory": try Data().write(to: f.url("new-file"))
                            default: try Data().write(to: f.url("EncryptedBookmarks99"))
                            }
                        } catch { callbackError = error }
                    }
                    return false
                })
            }
            XCTAssertNil(callbackError)
            try assertOriginals(f)
            XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.journal.path))
        }
    }

    func testRecoveryRejectsNewerWriterAndRestoreNeedsFreshReview() throws {
        let f = try fixture(), receipt = try apply(f)
        let stale = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
        var newer = stale.store.file.tree
        let node = try XCTUnwrap(newer.nodes.values.first { $0.url != nil })
        try newer.edit(node.id, name: "Newer writer", url: node.url)
        for (name, bytes) in try stale.store.serialize(newer, cipher: f.cipher) { try bytes.write(to: f.url(name)) }
        let newerBytes = try Data(contentsOf: f.url("Bookmarks"))
        XCTAssertThrowsError(try f.coordinator.recover(receipt, cipher: f.cipher, browserRunning: { false }))
        XCTAssertThrowsError(try f.coordinator.restore(receipt, review: stale, cipher: f.cipher, browserRunning: { false }))
        XCTAssertEqual(try Data(contentsOf: f.url("Bookmarks")), newerBytes)
        let fresh = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
        let restore = try XCTUnwrap(f.coordinator.restore(receipt, review: fresh, cipher: f.cipher, browserRunning: { false }))
        XCTAssertEqual(try Data(contentsOf: restore.journal.deletingLastPathComponent().appendingPathComponent("Bookmarks")), newerBytes)
        try assertOriginals(f)
    }

    func testBrowserSidecarsAddedAfterApplyAreBackedUpAndPreservedOnReviewedRestore() throws {
        let f = try fixture(), receipt = try apply(f)
        let bytes = Data("new browser-owned backup bytes".utf8)
        for name in ["Bookmarks.bak", "EncryptedBookmarks2.bak"] { try bytes.write(to: f.url(name)) }
        let current = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
        let restored = try XCTUnwrap(f.coordinator.restore(receipt, review: current, cipher: f.cipher, browserRunning: { false }))
        for name in ["Bookmarks.bak", "EncryptedBookmarks2.bak"] {
            XCTAssertEqual(try Data(contentsOf: f.url(name)), bytes)
            XCTAssertEqual(try Data(contentsOf: restored.journal.deletingLastPathComponent().appendingPathComponent(name)), bytes)
        }
        try assertOriginals(f)
    }

    func testModeOwnershipXattrsAndACLSurviveAndRestoreOriginalMetadata() throws {
        let f = try fixture(), name = "org.galmuri.transaction", value = Data("synthetic attributes".utf8)
        let source = f.url("Bookmarks")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)
        XCTAssertEqual(value.withUnsafeBytes { setxattr(source.path, name, $0.baseAddress, $0.count, 0, 0) }, 0)
        let command = Process(); command.executableURL = URL(fileURLWithPath: "/bin/chmod")
        command.arguments = ["+a", "everyone allow readattr,readextattr", source.path]
        try command.run(); command.waitUntilExit(); XCTAssertEqual(command.terminationStatus, 0)
        func aclText(_ url: URL) throws -> String {
            let acl = try XCTUnwrap(acl_get_file(url.path, ACL_TYPE_EXTENDED)); defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var size = 0
            let text = try XCTUnwrap(acl_to_text(acl, &size)); defer { acl_free(text) }
            return String(cString: text)
        }
        let originalACL = try aclText(source)
        var before = stat(); XCTAssertEqual(lstat(source.path, &before), 0)
        let receipt = try apply(f)
        XCTAssertEqual(try aclText(source), originalACL)
        var after = stat(); XCTAssertEqual(lstat(source.path, &after), 0)
        XCTAssertEqual(after.st_mode, before.st_mode); XCTAssertEqual(after.st_uid, before.st_uid); XCTAssertEqual(after.st_gid, before.st_gid)
        // A subsequent reviewed state has different attributes; restore must use the original backup's metadata.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
        XCTAssertEqual(removexattr(source.path, name, 0), 0)
        let current = try f.coordinator.readForReview(f.profile, cipher: f.cipher)
        _ = try f.coordinator.restore(receipt, review: current, cipher: f.cipher, browserRunning: { false })
        XCTAssertEqual(lstat(source.path, &after), 0); XCTAssertEqual(after.st_mode, before.st_mode)
        XCTAssertEqual(try aclText(source), originalACL)
        var actual = Data(count: value.count)
        XCTAssertEqual(actual.withUnsafeMutableBytes { getxattr(source.path, name, $0.baseAddress, $0.count, 0, 0) }, value.count)
        XCTAssertEqual(actual, value)
        try assertOriginals(f)
    }

    func testOnlyExplicitLocalOwnedPathsAndRegularUnlinkedStoresAreAccepted() throws {
        for protection in ["symlink", "hardlink", "fifo", "outside", "host", "ancestor", "backups"] {
            let f = try fixture()
            switch protection {
            case "symlink":
                let original = f.root.appendingPathComponent("original")
                try FileManager.default.moveItem(at: f.url("Bookmarks"), to: original)
                try FileManager.default.createSymbolicLink(at: f.url("Bookmarks"), withDestinationURL: original)
            case "hardlink": try FileManager.default.linkItem(at: f.url("Bookmarks"), to: f.root.appendingPathComponent("alias"))
            case "fifo":
                try FileManager.default.removeItem(at: f.url("Bookmarks")); XCTAssertEqual(mkfifo(f.url("Bookmarks").path, 0o600), 0)
            case "outside":
                let other = ChromiumStoreCoordinator(ownedRoot: f.root.appendingPathComponent("Elsewhere"), backupRoot: f.coordinator.backupRoot)
                XCTAssertThrowsError(try other.readForReview(f.profile, cipher: f.cipher)); continue
            case "host":
                XCTAssertThrowsError(try f.coordinator.readForReview(URL(string: "file://remote" + f.profile.path)!, cipher: f.cipher)); continue
            case "ancestor":
                let link = f.root.appendingPathComponent("linked")
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.profile)
                XCTAssertThrowsError(try f.coordinator.readForReview(link, cipher: f.cipher)); continue
            default:
                try FileManager.default.createSymbolicLink(at: f.coordinator.backupRoot, withDestinationURL: f.profile)
                XCTAssertThrowsError(try apply(f)); try assertOriginals(f); continue
            }
            XCTAssertThrowsError(try f.coordinator.readForReview(f.profile, cipher: f.cipher))
        }
    }
}
