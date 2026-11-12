import XCTest
import GalmuriCore
@testable import GalmuriApp

final class PlaintextImportTests: XCTestCase {
    private func fixture() throws -> (root: URL, browser: URL, source: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriPlaintextImport-" + UUID().uuidString).resolvingSymlinksInPath()
        let browser = root.appendingPathComponent("Chrome"), source = browser.appendingPathComponent("Default/Bookmarks")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SampleData.file().original.write(to: source)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, browser, source)
    }

    @MainActor
    func testMixedStoreSelectionImportsOnlyPlaintextAndPreservesWriteRestriction() async throws {
        let f = try fixture(), store = AppStore(directory: f.root.appendingPathComponent("App"))
        let encrypted = f.source.deletingLastPathComponent().appendingPathComponent("EncryptedBookmarks2")
        let marker = Data([0xff, 0x00, 0xfe]), original = try Data(contentsOf: f.source)
        try marker.write(to: encrypted)
        await store.findProfiles(in: f.browser, browser: .chrome, origin: .folderSelection)
        let request = try XCTUnwrap(store.connection), found = try XCTUnwrap(request.profiles.first)
        XCTAssertTrue(found.canImportPlaintext)
        XCTAssertEqual(found.files.filter(\.canImport).map(\.name), ["Bookmarks"])
        let connected = await store.finishConnection(request, profileIDs: [found.id])
        XCTAssertTrue(connected)
        XCTAssertEqual(store.workspace.profiles.count, 1)
        XCTAssertEqual(store.profile?.source.resolvingSymlinksInPath(), f.source.resolvingSymlinksInPath())
        XCTAssertEqual(store.profile?.base.original, original)
        XCTAssertNotNil(store.profile?.sourceRestriction)
        XCTAssertFalse(store.coordinator.canWrite(f.source))
        XCTAssertEqual(try Data(contentsOf: f.source), original)
        XCTAssertEqual(try Data(contentsOf: encrypted), marker)
    }

    @MainActor
    func testForcedUnreadableSelectionStillFailsAtomically() async throws {
        let f = try fixture(), store = AppStore(directory: f.root.appendingPathComponent("App"))
        let second = f.browser.appendingPathComponent("Profile 1/Bookmarks")
        try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SampleData.file().original.write(to: second)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: second.path)
        let before = try Data(contentsOf: store.workspaceURL)
        await store.findProfiles(in: f.browser, browser: .chrome)
        let request = try XCTUnwrap(store.connection)
        XCTAssertEqual(request.profiles.filter(\.canImportPlaintext).count, 1)
        let connected = await store.finishConnection(request, profileIDs: Set(request.profiles.map(\.id)))
        XCTAssertFalse(connected)
        XCTAssertTrue(store.workspace.profiles.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertEqual(store.lastDiscoveryIssue, .permissionDenied)
    }
}
