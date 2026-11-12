import XCTest
import GalmuriCore
@testable import GalmuriApp

final class SettingsFirstTests: XCTestCase {
    private func fixture() throws -> (root: URL, browser: URL, source: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriSettingsFirst-" + UUID().uuidString).resolvingSymlinksInPath()
        let browser = root.appendingPathComponent("Chrome", isDirectory: true), source = browser.appendingPathComponent("Default/Bookmarks")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SampleData.file().original.write(to: source)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: browser.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
            try? FileManager.default.removeItem(at: root)
        }
        return (root, browser, source)
    }

    func testDiagnosticsPreserveCodesAndBoundUnderlyingTraversal() {
        for code in [POSIXErrorCode.EACCES, .EPERM] {
            let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
                                userInfo: [NSUnderlyingErrorKey: POSIXError(code)])
            let diagnostic = ProfileReadDiagnostic(error: error)
            XCTAssertEqual(diagnostic.posixCode, Int(code.rawValue))
            XCTAssertEqual(diagnostic.codes, ["NSCocoaErrorDomain (257)", "NSPOSIXErrorDomain (\(code.rawValue))"])
            XCTAssertEqual(ProfileDiscoveryIssue.classify(error), .permissionDenied)
        }
        var wrapped = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EPERM.rawValue))
        for _ in 0..<64 { wrapped = NSError(domain: "SyntheticWrapper", code: 2, userInfo: [NSUnderlyingErrorKey: wrapped]) }
        let bounded = ProfileReadDiagnostic(error: wrapped)
        XCTAssertEqual(bounded.codes.count, 4)
        XCTAssertNil(bounded.posixCode)
    }

    func testGuideRoutesBySelectionOriginVersionAndUnderlyingPermissions() {
        let url = URL(fileURLWithPath: "/Synthetic/Chrome")
        var notice = ProfileConnectionNotice(directory: url, issue: .permissionDenied)
        XCTAssertEqual(notice.guidance(onMacOSMajorVersion: 27), .folderSelection)
        XCTAssertEqual(notice.guidance(onMacOSMajorVersion: 26), .folderSelection)
        notice.browser = .egoLite
        XCTAssertEqual(notice.guidance(onMacOSMajorVersion: 27), .folderSelection)
        notice.browser = .chrome
        notice.diagnostic = ProfileReadDiagnostic(error: POSIXError(.EACCES))
        XCTAssertEqual(notice.guidance(onMacOSMajorVersion: 27), .filePermissions)
        notice.diagnostic = ProfileReadDiagnostic(error: POSIXError(.EPERM))
        XCTAssertEqual(notice.guidance(onMacOSMajorVersion: 27), .folderSelection)
        notice.origin = .folderSelection
        XCTAssertEqual(notice.guidance(onMacOSMajorVersion: 27), .systemSettings)
        XCTAssertEqual(notice.guidance(onMacOSMajorVersion: 26), .folderSelection)
    }

    @MainActor
    func testFreshFolderReferenceIsNeverReplacedByStoredGrant() throws {
        let f = try fixture(), store = AppStore(directory: f.root.appendingPathComponent("App"))
        let bookmark = try f.browser.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        store.workspace.profiles = [ConnectedProfile(name: "Synthetic", source: f.source, permissionBookmark: bookmark, base: try ProfileIO.read(f.source))]
        // A valid same-path spelling distinguishes the supplied URL from a re-resolved reference, without reading it.
        let selected = try XCTUnwrap(URL(string: f.browser.absoluteString + "./"))
        let cached = store.directoryForLookup(selected)
        XCTAssertNotEqual(cached.absoluteString, selected.absoluteString)
        XCTAssertEqual(cached.standardizedFileURL.path, selected.standardizedFileURL.path)
        XCTAssertEqual(store.directoryForLookup(selected, origin: .folderSelection).absoluteString, selected.absoluteString)
    }

    @MainActor
    func testSelectedFolderRetryKeepsOriginAndPreservesWorkUntilReadable() async throws {
        let f = try fixture(), store = AppStore(sampleData: true, directory: f.root.appendingPathComponent("App"))
        let before = try Data(contentsOf: store.workspaceURL), working = store.tree, original = try Data(contentsOf: f.source)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.browser.path)
        for _ in 0..<2 {
            await store.findProfiles(in: f.browser, browser: .chrome, origin: .folderSelection)
            let notice = try XCTUnwrap(store.connectionNotice)
            XCTAssertEqual(notice.origin, .folderSelection)
            XCTAssertEqual(notice.diagnostic?.posixCode, Int(POSIXErrorCode.EACCES.rawValue))
            XCTAssertEqual(notice.guidance(onMacOSMajorVersion: 27), .filePermissions)
            XCTAssertNil(store.connection)
            XCTAssertEqual(store.tree, working)
            XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.browser.path)
        await store.findProfiles(in: f.browser, browser: .chrome, origin: .folderSelection)
        XCTAssertEqual(store.connection?.origin, .folderSelection)
        XCTAssertNil(store.connectionNotice)
        XCTAssertNil(store.lastDiscoveryDiagnostic)
        XCTAssertEqual(store.tree, working)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertEqual(try Data(contentsOf: f.source), original)
    }

    @MainActor
    func testSelectedPayloadFailureRetainsDiagnosticAndSelectionOrigin() async throws {
        let f = try fixture(), store = AppStore(directory: f.root.appendingPathComponent("App"))
        await store.findProfiles(in: f.browser, browser: .chrome, origin: .folderSelection)
        let request = try XCTUnwrap(store.connection)
        let before = try Data(contentsOf: store.workspaceURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.source.path)
        let connected = await store.finishConnection(request, profileIDs: Set(request.profiles.map(\.id)))
        XCTAssertFalse(connected)
        XCTAssertNil(store.connection)
        XCTAssertEqual(store.connectionNotice?.origin, .folderSelection)
        XCTAssertEqual(store.connectionNotice?.diagnostic?.posixCode, Int(POSIXErrorCode.EACCES.rawValue))
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertTrue(store.workspace.profiles.isEmpty)
    }

    @MainActor
    func testBackAndBrowserChangeClearOnlyTransientDiagnostics() async throws {
        let f = try fixture(), store = AppStore(sampleData: true, directory: f.root.appendingPathComponent("App"))
        let before = try Data(contentsOf: store.workspaceURL), working = store.tree
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.browser.path)
        await store.findProfiles(in: f.browser)
        XCTAssertNotNil(store.lastDiscoveryDiagnostic)
        store.dismissConnectionNotice()
        XCTAssertNil(store.lastDiscoveryDiagnostic)
        await store.findProfiles(in: f.browser)
        XCTAssertNotNil(store.lastDiscoveryDiagnostic)
        store.selectBrowser(.egoLite)
        XCTAssertNil(store.lastDiscoveryDiagnostic)
        XCTAssertNil(store.connectionNotice)
        XCTAssertEqual(store.tree, working)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
    }
}
