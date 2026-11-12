import XCTest
import Darwin
@testable import GalmuriCore

final class IOVerificationTests: XCTestCase {
    private func fixture() throws -> (source: URL, profile: ConnectedProfile, coordinator: ApplyCoordinator) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("galmuri-io-" + UUID().uuidString)
        let directory = root.appendingPathComponent("test/Default")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = directory.appendingPathComponent("Bookmarks"), file = try SampleData.file()
        try file.original.write(to: source)
        var profile = ConnectedProfile(name: "Synthetic IO", source: source, base: file)
        let node = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        try profile.working.edit(node.id, name: "Reviewed IO edit", url: node.url)
        return (source, profile, ApplyCoordinator(testRoot: root.appendingPathComponent("test"), backupRoot: root.appendingPathComponent("backups")))
    }

    func testNonlocalURLsCannotBorrowAnOwnedFilesystemPath() throws {
        let f = try fixture()
        for scheme in ["https", "file"] {
            var components = URLComponents()
            components.scheme = scheme; components.host = "untrusted.invalid"; components.path = f.source.path
            let source = try XCTUnwrap(components.url)
            XCTAssertFalse(f.coordinator.canWrite(source))
            XCTAssertThrowsError(try f.coordinator.readForReview(source))
            XCTAssertThrowsError(try ProfileIO.read(source))
            XCTAssertThrowsError(try ProfileIO.discover(in: source.deletingLastPathComponent()))
        }
        XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
        XCTAssertTrue(try f.coordinator.receipts().isEmpty)
    }

    func testReadRejectsSymlinksDirectoriesFIFOsAndOversizedFiles() throws {
        let f = try fixture(), directory = f.source.deletingLastPathComponent()
        let leafAlias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: leafAlias, withDestinationURL: f.source)
        XCTAssertThrowsError(try ProfileIO.read(leafAlias))
        let ancestorAlias = directory.deletingLastPathComponent().appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: ancestorAlias, withDestinationURL: directory)
        XCTAssertThrowsError(try ProfileIO.read(ancestorAlias.appendingPathComponent("Bookmarks")))
        XCTAssertThrowsError(try ProfileIO.read(directory))
        let fifo = directory.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertThrowsError(try ProfileIO.read(fifo))
        let oversized = directory.appendingPathComponent("oversized")
        let fd = open(oversized.path, O_RDWR | O_CREAT | O_EXCL, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(ftruncate(fd, 50_000_000), 0)
        XCTAssertThrowsError(try ProfileIO.read(oversized))
        XCTAssertEqual(try ProfileIO.read(f.source).original, f.profile.base.original)
    }

    func testBackupCorruptionAtFinalCheckAbortsAndKeepsPreparedHistory() throws {
        let f = try fixture(), review = try f.coordinator.prepare(profile: f.profile)
        var calls = 0, callbackError: Error?
        var damaged = f.profile.base.original
        damaged.append(contentsOf: "\n".utf8)
        XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: review, browserRunning: {
            calls += 1
            if calls == 2 {
                do { try damaged.write(to: XCTUnwrap(f.coordinator.receipts().first).backup) }
                catch { callbackError = error }
            }
            return false
        })) { XCTAssertEqual($0 as? GalmuriError, .missingBackup) }
        XCTAssertNil(callbackError)
        XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
        let receipt = try XCTUnwrap(f.coordinator.receipts().first)
        XCTAssertEqual(receipt.state, "prepared")
        XCTAssertEqual(try Data(contentsOf: receipt.backup), damaged)
        XCTAssertThrowsError(try f.coordinator.restore(receipt, expectedCurrentHash: f.profile.base.fingerprint, browserRunning: { false }))
    }

    func testIdenticalTemporaryInodeSwapAndLateHardlinkAbortApply() throws {
        for swapTemporary in [false, true] {
            let f = try fixture(), review = try f.coordinator.prepare(profile: f.profile)
            var calls = 0, callbackError: Error?
            XCTAssertThrowsError(try f.coordinator.apply(profile: f.profile, review: review, browserRunning: {
                calls += 1
                if calls == 2 {
                    do {
                        if swapTemporary {
                            let temporary = try XCTUnwrap(f.coordinator.receipts().first?.temporary)
                            let replacement = temporary.appendingPathExtension("replacement")
                            try Data(contentsOf: temporary).write(to: replacement)
                            guard rename(replacement.path, temporary.path) == 0 else { throw POSIXError(.EIO) }
                        } else {
                            try FileManager.default.linkItem(at: f.source, to: f.source.appendingPathExtension("hardlink"))
                        }
                    } catch { callbackError = error }
                }
                return false
            })) { XCTAssertEqual($0 as? GalmuriError, .staleSource) }
            XCTAssertNil(callbackError)
            XCTAssertEqual(try Data(contentsOf: f.source), f.profile.base.original)
            XCTAssertEqual(try f.coordinator.receipts().first?.state, "prepared")
        }
    }

    func testUnsafeHistoryRecordsAreIsolatedAndOutsidePayloadsPreserved() throws {
        let f = try fixture()
        let receipt = try f.coordinator.apply(profile: f.profile, review: f.coordinator.prepare(profile: f.profile), browserRunning: { false })
        let external = f.coordinator.backupRoot.deletingLastPathComponent().appendingPathComponent("outside.bookmarks")
        try f.profile.base.original.write(to: external)
        var outsideReceipt = receipt; outsideReceipt.id = UUID(); outsideReceipt.backup = external
        try JSONEncoder().encode(outsideReceipt).write(to: f.coordinator.backupRoot.appendingPathComponent(outsideReceipt.id.uuidString + ".json"))
        let linkedReceipt = f.coordinator.backupRoot.appendingPathComponent(UUID().uuidString + ".json")
        try FileManager.default.createSymbolicLink(at: linkedReceipt, withDestinationURL: external)
        var nonlocal = receipt; nonlocal.id = UUID()
        nonlocal.backup = f.coordinator.backupRoot.appendingPathComponent(nonlocal.id.uuidString + ".bookmarks")
        nonlocal.source = URL(string: "https://untrusted.invalid/Bookmarks")!
        try JSONEncoder().encode(nonlocal).write(to: f.coordinator.backupRoot.appendingPathComponent(nonlocal.id.uuidString + ".json"))
        let history = try f.coordinator.receiptHistory()
        XCTAssertEqual(history.receipts.map(\.id), [receipt.id])
        XCTAssertEqual(history.unreadableCount, 3)
        XCTAssertThrowsError(try f.coordinator.restore(outsideReceipt, expectedCurrentHash: receipt.afterHash, browserRunning: { false }))
        XCTAssertEqual(try Data(contentsOf: external), f.profile.base.original)
        XCTAssertEqual(try ProfileIO.read(f.source).fingerprint, receipt.afterHash)
    }
}
