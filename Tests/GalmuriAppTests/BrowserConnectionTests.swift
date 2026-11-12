import XCTest
import GalmuriCore
@testable import GalmuriApp

final class BrowserConnectionTests: XCTestCase {
    private func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriBrowserConnection-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func fixture(_ root: URL, encryptedOnly: Bool = false) throws -> URL {
        let profile = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let file = profile.appendingPathComponent(encryptedOnly ? "EncryptedBookmarks2" : "Bookmarks")
        try (encryptedOnly ? Data("unsupported synthetic ciphertext".utf8) : SampleData.file().original).write(to: file)
        try Data(#"{"profile":{"info_cache":{"Default":{"name":"Ego · Example"}}}}"#.utf8).write(to: root.appendingPathComponent("Local State"))
        return file
    }

    func testKnownLocationsAreDistinctWithoutReadingUserData() {
        let home = URL(fileURLWithPath: "/Synthetic Home", isDirectory: true)
        XCTAssertEqual(BookmarkBrowser.chrome.dataDirectory(home: home).path, "/Synthetic Home/Library/Application Support/Google/Chrome")
        XCTAssertEqual(BookmarkBrowser.egoLite.dataDirectory(home: home).path, "/Synthetic Home/Library/Application Support/Citro Labs/ego lite")
        XCTAssertNil(BookmarkBrowser.chrome.storageWarning)
        XCTAssertNotNil(BookmarkBrowser.egoLite.storageWarning)
    }

    @MainActor
    func testSelectingBrowserDoesNotDiscoverImportOrChangeWorkspace() async throws {
        let root = try scratch(), store = AppStore(sampleData: true, directory: root.appendingPathComponent("App"))
        let before = try Data(contentsOf: store.workspaceURL), tree = store.tree
        await store.findProfiles(in: root.appendingPathComponent("Missing"))
        XCTAssertNotNil(store.connectionNotice)
        store.selectBrowser(.egoLite)
        XCTAssertEqual(store.connectionBrowser, .egoLite)
        XCTAssertNil(store.connectionNotice)
        XCTAssertNil(store.connection)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.tree, tree)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        store.busy = true
        store.selectBrowser(.chrome)
        XCTAssertEqual(store.connectionBrowser, .egoLite)
    }

    @MainActor
    func testEgoFailureAndStagedRequestKeepTheirBrowser() async throws {
        let root = try scratch(), store = AppStore(directory: root.appendingPathComponent("App"))
        let missing = root.appendingPathComponent("Missing Ego")
        await store.findProfiles(in: missing, browser: .egoLite)
        XCTAssertEqual(store.connectionNotice?.browser, .egoLite)
        XCTAssertEqual(store.connectionNotice?.directory, missing)
        XCTAssertEqual(store.connectionBrowser, .egoLite)
        let data = root.appendingPathComponent("Synthetic Ego")
        _ = try fixture(data)
        await store.findProfiles(in: data, browser: .egoLite)
        let request = try XCTUnwrap(store.connection)
        XCTAssertEqual(request.browser, .egoLite)
        XCTAssertNil(store.connectionNotice)
        store.selectBrowser(.chrome)
        XCTAssertEqual(store.connectionBrowser, .egoLite)
        XCTAssertEqual(store.connection?.id, request.id)
        let canceled = await store.beginConnection(nil, browser: .chrome)
        XCTAssertFalse(canceled)
        XCTAssertEqual(store.connection?.browser, .egoLite)
    }

    @MainActor
    func testEgoPlaintextSelectionPersistsWarningAndNeverChangesOriginal() async throws {
        let root = try scratch(), data = root.appendingPathComponent("Synthetic Ego")
        let source = try fixture(data), original = try Data(contentsOf: source)
        let app = root.appendingPathComponent("App"), store = AppStore(directory: app)
        await store.findProfiles(in: data, browser: .egoLite)
        let request = try XCTUnwrap(store.connection)
        XCTAssertTrue(store.workspace.profiles.isEmpty)
        XCTAssertEqual(request.profiles.first?.name, "Ego · Example")
        XCTAssertEqual(request.profiles.first?.file.standardizedFileURL, source.standardizedFileURL)
        let connected = await store.finishConnection(request, profileIDs: Set(request.profiles.map(\.id)))
        XCTAssertTrue(connected, store.error ?? "No diagnostic")
        let profile = try XCTUnwrap(store.profile)
        XCTAssertEqual(profile.sourceRestriction, BookmarkBrowser.egoLite.storageWarning)
        XCTAssertFalse(store.coordinator.canWrite(profile.source))
        let item = try XCTUnwrap(profile.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Working copy only", url: item.url) })
        XCTAssertEqual(try Data(contentsOf: source), original)
        let restored = AppStore(directory: app)
        XCTAssertEqual(restored.profile?.sourceRestriction, BookmarkBrowser.egoLite.storageWarning)
        XCTAssertEqual(restored.tree, store.tree)
        XCTAssertEqual(restored.workspace.version, 1)
        await restored.reconnectDirectory(data, profileID: profile.id)
        XCTAssertNil(restored.error)
        XCTAssertEqual(restored.profile?.sourceRestriction, BookmarkBrowser.egoLite.storageWarning)
        XCTAssertEqual(restored.tree, store.tree)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    @MainActor
    func testEgoEncryptedOnlyAndMalformedPayloadsRemainUnsupported() async throws {
        let root = try scratch(), app = root.appendingPathComponent("App")
        for encrypted in [true, false] {
            let data = root.appendingPathComponent(encrypted ? "Encrypted Ego" : "Malformed Ego")
            let source = try fixture(data, encryptedOnly: encrypted)
            if !encrypted { try Data("not bookmarks".utf8).write(to: source) }
            let original = try Data(contentsOf: source)
            let store = AppStore(directory: app)
            await store.findProfiles(in: data, browser: .egoLite)
            let request = try XCTUnwrap(store.connection), before = try Data(contentsOf: store.workspaceURL)
            XCTAssertEqual(request.profiles.first?.hasPlaintext, !encrypted)
            let connected = await store.finishConnection(request, profileIDs: Set(request.profiles.map(\.id)))
            XCTAssertFalse(connected)
            XCTAssertEqual(store.connection?.id, request.id)
            XCTAssertTrue(store.workspace.profiles.isEmpty)
            XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
    }

    @MainActor
    func testChromeConnectionDoesNotAcquireEgoWarning() async throws {
        let root = try scratch(), data = root.appendingPathComponent("Synthetic Chrome")
        _ = try fixture(data)
        let store = AppStore(directory: root.appendingPathComponent("App"))
        await store.findProfiles(in: data, browser: .chrome)
        let request = try XCTUnwrap(store.connection)
        let connected = await store.finishConnection(request, profileIDs: Set(request.profiles.map(\.id)))
        XCTAssertTrue(connected, store.error ?? "No diagnostic")
        XCTAssertNil(store.profile?.sourceRestriction)
        XCTAssertFalse(store.coordinator.canWrite(try XCTUnwrap(store.profile).source))
    }
}
