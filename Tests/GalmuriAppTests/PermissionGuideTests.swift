import XCTest
import GalmuriCore
@testable import GalmuriApp

final class PermissionGuideTests: XCTestCase {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriPermissionGuide-" + UUID().uuidString).resolvingSymlinksInPath()
        let browser = root.appendingPathComponent("Chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: browser.appendingPathComponent("Default"), withIntermediateDirectories: true)
        try SampleData.file().original.write(to: browser.appendingPathComponent("Default/Bookmarks"))
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: browser.path)
            try? FileManager.default.removeItem(at: root)
        }
        return (root, browser)
    }

    @MainActor
    func testBackClearsOnlyConnectionNoticeAndKeepsPendingWork() async throws {
        let (root, browser) = try fixture()
        let store = AppStore(sampleData: true, directory: root.appendingPathComponent("App"))
        let item = try XCTUnwrap(store.tree?.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Preserve pending edit", url: item.url) })
        let before = try Data(contentsOf: store.workspaceURL), profile = try XCTUnwrap(store.profile)
        let source = try Data(contentsOf: profile.source)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: browser.path)
        await store.findProfiles(in: browser, browser: .chrome)
        XCTAssertEqual(store.connectionNotice?.issue, .permissionDenied)
        XCTAssertNil(store.connection)
        store.dismissConnectionNotice()
        XCTAssertNil(store.connectionNotice)
        XCTAssertNil(store.lastDiscoveryIssue)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.selectedProfileID, profile.id)
        XCTAssertEqual(store.profile?.base, profile.base)
        XCTAssertEqual(store.tree, profile.working)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertEqual(try Data(contentsOf: profile.source), source)
    }

    @MainActor
    func testBackWhileCheckingCannotDiscardThePendingNotice() async throws {
        let (root, browser) = try fixture()
        let store = AppStore(directory: root.appendingPathComponent("App"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: browser.path)
        await store.findProfiles(in: browser, browser: .egoLite)
        let notice = try XCTUnwrap(store.connectionNotice), error = store.error
        store.busy = true
        store.dismissConnectionNotice()
        XCTAssertEqual(store.connectionNotice?.directory, notice.directory)
        XCTAssertEqual(store.connectionNotice?.browser, .egoLite)
        XCTAssertEqual(store.connectionNotice?.issue, .permissionDenied)
        XCTAssertEqual(store.lastDiscoveryIssue, .permissionDenied)
        XCTAssertEqual(store.error, error)
        XCTAssertTrue(store.busy)
    }

    @MainActor
    func testRepeatedDenialKeepsGuideUntilAnActualReadSucceeds() async throws {
        for browserKind in BookmarkBrowser.allCases {
            let (root, browser) = try fixture()
            let store = AppStore(directory: root.appendingPathComponent("App"))
            let workspace = try Data(contentsOf: store.workspaceURL)
            let source = browser.appendingPathComponent("Default/Bookmarks"), original = try Data(contentsOf: source)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: browser.path)
            for _ in 0..<2 {
                await store.findProfiles(in: browser, browser: browserKind)
                XCTAssertEqual(store.connectionNotice?.issue, .permissionDenied)
                XCTAssertEqual(store.connectionNotice?.browser, browserKind)
                XCTAssertEqual(store.connectionNotice?.directory, browser)
                XCTAssertNil(store.connection)
                XCTAssertEqual(try Data(contentsOf: store.workspaceURL), workspace)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: browser.path)
            await store.findProfiles(in: browser, browser: browserKind)
            XCTAssertNil(store.connectionNotice)
            XCTAssertNil(store.lastDiscoveryIssue)
            XCTAssertNil(store.error)
            let request = try XCTUnwrap(store.connection)
            XCTAssertEqual(request.browser, browserKind)
            XCTAssertEqual(request.profiles.count, 1)
            XCTAssertTrue(store.workspace.profiles.isEmpty)
            XCTAssertEqual(try Data(contentsOf: store.workspaceURL), workspace)
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
    }
}
