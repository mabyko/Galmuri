import XCTest
import GalmuriCore
@testable import GalmuriApp

final class DirectConnectionTests: XCTestCase {
    private func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GalmuriDirectConnection-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func bookmark(in root: URL, profile: String = "Default", bytes: Data? = nil) throws -> URL {
        let directory = root.appendingPathComponent(profile)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("Bookmarks")
        try (bytes ?? SampleData.file().original).write(to: source)
        return source
    }

    @MainActor
    private func editedStore(in root: URL) throws -> AppStore {
        let store = AppStore(sampleData: true, directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let item = try XCTUnwrap(store.tree?.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Preserve pending work", url: item.url) })
        return store
    }

    @MainActor
    func testIsolatedStartupDoesNotStageDiscoveryOrGenerateProfiles() throws {
        let root = try scratch()
        let source = try bookmark(in: root.appendingPathComponent("Synthetic Chrome"))
        let original = try Data(contentsOf: source)
        let directory = root.appendingPathComponent("App")
        for _ in 0..<2 {
            let store = AppStore(directory: directory, browserState: { _ in false })
            XCTAssertNil(store.connection)
            XCTAssertNil(store.connectionNotice)
            XCTAssertNil(store.lastDiscoveryIssue)
            XCTAssertNil(store.error)
            XCTAssertFalse(store.busy)
            XCTAssertTrue(store.workspace.profiles.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.testRoot.path))
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    @MainActor
    func testDirectLookupStagesMetadataWithoutImportAndClearsPreviousNotice() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Synthetic Chrome")
        let payload = Data("not parsed during discovery".utf8)
        let source = try bookmark(in: chrome, bytes: payload)
        let metadata = Data(#"{"profile":{"info_cache":{"Default":{"name":"Synthetic Person"}}}}"#.utf8)
        try metadata.write(to: chrome.appendingPathComponent("Local State"))
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let workspace = try Data(contentsOf: store.workspaceURL)
        await store.findProfiles(in: root.appendingPathComponent("Missing"))
        XCTAssertNotNil(store.connectionNotice)
        await store.findProfiles(in: chrome)
        let request = try XCTUnwrap(store.connection)
        XCTAssertEqual(request.directory.standardizedFileURL, chrome.standardizedFileURL)
        XCTAssertEqual(request.profiles.map(\.name), ["Synthetic Person"])
        XCTAssertEqual(request.profiles.map { $0.file.standardizedFileURL }, [source.standardizedFileURL])
        XCTAssertNil(store.connectionNotice)
        XCTAssertNil(store.lastDiscoveryIssue)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.busy)
        XCTAssertTrue(store.workspace.profiles.isEmpty)
        XCTAssertNil(store.selectedProfileID)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), workspace)
        XCTAssertEqual(try Data(contentsOf: source), payload)
        XCTAssertEqual(try Data(contentsOf: chrome.appendingPathComponent("Local State")), metadata)
    }

    @MainActor
    func testMissingLocationAndEmptyDirectoryHaveDistinctNotices() async throws {
        let root = try scratch()
        let missing = root.appendingPathComponent("Missing Chrome")
        let empty = root.appendingPathComponent("Empty Chrome")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let store = try editedStore(in: root)
        let before = try Data(contentsOf: store.workspaceURL), profile = try XCTUnwrap(store.profile)
        for (directory, issue) in [(missing, ProfileDiscoveryIssue.missingLocation), (empty, .unavailable)] {
            await store.findProfiles(in: directory)
            XCTAssertNil(store.connection)
            XCTAssertEqual(store.connectionNotice?.directory, directory)
            XCTAssertEqual(store.connectionNotice?.issue, issue)
            XCTAssertEqual(store.lastDiscoveryIssue, issue)
            XCTAssertFalse(store.busy)
            XCTAssertEqual(store.selectedProfileID, profile.id)
            XCTAssertEqual(store.profile?.base, profile.base)
            XCTAssertEqual(store.tree, profile.working)
            XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    @MainActor
    func testLookupWhileBusyOrAlreadyStagedPreservesCurrentState() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Synthetic Chrome")
        _ = try bookmark(in: chrome)
        let missing = root.appendingPathComponent("Missing")
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        await store.findProfiles(in: missing)
        store.busy = true
        await store.findProfiles(in: chrome)
        XCTAssertTrue(store.busy)
        XCTAssertNil(store.connection)
        XCTAssertEqual(store.connectionNotice?.directory, missing)
        XCTAssertEqual(store.lastDiscoveryIssue, .missingLocation)
        store.busy = false
        await store.findProfiles(in: chrome)
        let request = try XCTUnwrap(store.connection)
        await store.findProfiles(in: missing)
        XCTAssertEqual(store.connection?.id, request.id)
        XCTAssertNil(store.connectionNotice)
        XCTAssertNil(store.lastDiscoveryIssue)
        XCTAssertNil(store.error)
    }

    @MainActor
    func testNilCancellationPreservesNoticeIssueEditsAndWorkspace() async throws {
        let root = try scratch(), store = try editedStore(in: root)
        let missing = root.appendingPathComponent("Missing")
        await store.findProfiles(in: missing)
        let before = try Data(contentsOf: store.workspaceURL), profile = try XCTUnwrap(store.profile)
        let error = store.error
        let staged = await store.beginConnection(nil)
        let connected = await store.connectDirectory(nil)
        XCTAssertFalse(staged)
        XCTAssertFalse(connected)
        XCTAssertEqual(store.connectionNotice?.directory, missing)
        XCTAssertEqual(store.connectionNotice?.issue, .missingLocation)
        XCTAssertEqual(store.lastDiscoveryIssue, .missingLocation)
        XCTAssertEqual(store.error, error)
        XCTAssertEqual(store.selectedProfileID, profile.id)
        XCTAssertEqual(store.profile?.base, profile.base)
        XCTAssertEqual(store.tree, profile.working)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertFalse(store.busy)
    }

    @MainActor
    func testBeginConnectionReturnsResultAndFailedOrCanceledAttemptKeepsStagedRequest() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Synthetic Chrome")
        _ = try bookmark(in: chrome)
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let before = try Data(contentsOf: store.workspaceURL)
        let staged = await store.beginConnection(chrome)
        XCTAssertTrue(staged)
        let request = try XCTUnwrap(store.connection)
        let failed = await store.beginConnection(root.appendingPathComponent("Missing"))
        XCTAssertFalse(failed)
        XCTAssertEqual(store.lastDiscoveryIssue, .missingLocation)
        let canceled = await store.beginConnection(nil)
        XCTAssertFalse(canceled)
        XCTAssertEqual(store.lastDiscoveryIssue, .missingLocation)
        XCTAssertEqual(store.connection?.id, request.id)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertTrue(store.workspace.profiles.isEmpty)
    }

    @MainActor
    func testDeniedSelectedPayloadClosesChooserAndPreservesWorkspaceAtomically() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Synthetic Chrome")
        let readable = try bookmark(in: chrome)
        let denied = try bookmark(in: chrome, profile: "Profile 1")
        let readableOriginal = try Data(contentsOf: readable)
        let original = try Data(contentsOf: denied)
        let store = try editedStore(in: root)
        await store.findProfiles(in: chrome)
        let request = try XCTUnwrap(store.connection)
        let before = try Data(contentsOf: store.workspaceURL), profile = try XCTUnwrap(store.profile)
        let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: denied.path)[.posixPermissions])
        defer { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: denied.path) }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)
        guard (try? Data(contentsOf: denied)) == nil else {
            throw XCTSkip("This process can read a mode-000 owned fixture; permission denial cannot be exercised.")
        }
        let connected = await store.finishConnection(request, profileIDs: Set(request.profiles.map(\.id)))
        XCTAssertFalse(connected)
        XCTAssertNil(store.connection)
        XCTAssertEqual(store.connectionNotice?.directory, chrome)
        XCTAssertEqual(store.connectionNotice?.issue, .permissionDenied)
        XCTAssertEqual(store.lastDiscoveryIssue, .permissionDenied)
        XCTAssertEqual(store.selectedProfileID, profile.id)
        XCTAssertEqual(store.profile?.base, profile.base)
        XCTAssertEqual(store.tree, profile.working)
        XCTAssertEqual(store.workspace.profiles.count, 1)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertFalse(store.busy)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: denied.path)
        XCTAssertEqual(try Data(contentsOf: denied), original)
        XCTAssertEqual(try Data(contentsOf: readable), readableOriginal)
    }

    @MainActor
    func testWorkspacePermissionFailureDoesNotAskForChromeAccess() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Synthetic Chrome")
        let source = try bookmark(in: chrome)
        let original = try Data(contentsOf: source)
        let store = try editedStore(in: root)
        await store.findProfiles(in: chrome)
        let request = try XCTUnwrap(store.connection)
        let before = try Data(contentsOf: store.workspaceURL), working = store.tree
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: store.directory.path) }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: store.directory.path)
        let connected = await store.finishConnection(request, profileIDs: Set(request.profiles.map(\.id)))
        XCTAssertFalse(connected)
        XCTAssertEqual(store.connection?.id, request.id)
        XCTAssertNil(store.connectionNotice)
        XCTAssertEqual(store.lastDiscoveryIssue, .unavailable)
        XCTAssertEqual(store.tree, working)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    @MainActor
    func testMalformedSelectedPayloadKeepsChooserWithoutPermissionNotice() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Synthetic Chrome")
        let source = try bookmark(in: chrome, bytes: Data("malformed payload".utf8))
        let store = try editedStore(in: root)
        let before = try Data(contentsOf: store.workspaceURL), profile = try XCTUnwrap(store.profile)
        await store.findProfiles(in: chrome)
        let request = try XCTUnwrap(store.connection)
        let connected = await store.finishConnection(request, profileIDs: Set(request.profiles.map(\.id)))
        XCTAssertFalse(connected)
        XCTAssertEqual(store.connection?.id, request.id)
        XCTAssertNil(store.connectionNotice)
        XCTAssertEqual(store.lastDiscoveryIssue, .unavailable)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.selectedProfileID, profile.id)
        XCTAssertEqual(store.profile?.base, profile.base)
        XCTAssertEqual(store.tree, profile.working)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        XCTAssertEqual(try Data(contentsOf: source), Data("malformed payload".utf8))
        XCTAssertFalse(store.busy)
    }

    @MainActor
    func testConnectDirectoryClearsStaleIssueOnEntryAndSuccessfulRetry() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Synthetic Chrome")
        _ = try bookmark(in: chrome)
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let failed = await store.connectDirectory(root.appendingPathComponent("Missing"))
        XCTAssertFalse(failed)
        XCTAssertEqual(store.lastDiscoveryIssue, .missingLocation)
        let invalidSelection = await store.connectDirectory(chrome, profileIDs: [])
        XCTAssertFalse(invalidSelection)
        XCTAssertNil(store.lastDiscoveryIssue)
        let connected = await store.connectDirectory(chrome)
        XCTAssertTrue(connected)
        XCTAssertNil(store.lastDiscoveryIssue)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.workspace.profiles.count, 1)
    }

    func testDiscoveryIssueClassifiesPermissionMissingAndOtherErrors() {
        let cases: [(Error, ProfileDiscoveryIssue)] = [
            (GalmuriError.permission, .permissionDenied),
            (NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError), .permissionDenied),
            (POSIXError(.EACCES), .permissionDenied), (POSIXError(.EPERM), .permissionDenied),
            (NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError), .missingLocation),
            (NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError), .missingLocation),
            (POSIXError(.ENOENT), .missingLocation),
            (GalmuriError.invalid("No supported profiles"), .unavailable),
            (GalmuriError.unsupported("Encrypted only"), .unavailable),
            (POSIXError(.EIO), .unavailable),
            (NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError), .unavailable),
            (NSError(domain: "SyntheticOtherDomain", code: NSFileReadNoPermissionError), .unavailable)
        ]
        for (error, expected) in cases {
            XCTAssertEqual(ProfileDiscoveryIssue.classify(error), expected, String(describing: error))
            let wrapped = NSError(domain: "SyntheticWrapper", code: 1, userInfo: [NSUnderlyingErrorKey: error])
            XCTAssertEqual(ProfileDiscoveryIssue.classify(wrapped), expected, "Wrapped: \(error)")
        }
    }

    func testDiscoveryIssueBoundsUnderlyingErrorTraversalIncludingCycles() {
        let cycle = CyclicDiscoveryError(domain: "SyntheticCycle", code: 1, userInfo: nil)
        XCTAssertEqual(ProfileDiscoveryIssue.classify(cycle), .unavailable)
        var nested = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EACCES.rawValue))
        for _ in 0..<64 {
            nested = NSError(domain: "SyntheticWrapper", code: 1, userInfo: [NSUnderlyingErrorKey: nested])
        }
        XCTAssertEqual(ProfileDiscoveryIssue.classify(nested), .unavailable)
    }

    @MainActor
    func testExactCachedGrantReturnsAUsableScopedURLWithoutReadingPayloads() throws {
        let root = try scratch(), expected = root.appendingPathComponent("Synthetic Chrome")
        try FileManager.default.createDirectory(at: expected, withIntermediateDirectories: true)
        let data = try expected.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                             includingResourceValuesForKeys: nil, relativeTo: nil)
        var stale = false
        let resolved = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                               relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, resolved.startAccessingSecurityScopedResource() else {
            throw XCTSkip("The test runtime does not provide a usable security-scoped bookmark.")
        }
        resolved.stopAccessingSecurityScopedResource()
        let source = expected.appendingPathComponent("Default/Bookmarks")
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        store.workspace.profiles = [ConnectedProfile(name: "Synthetic", source: source, permissionBookmark: data, base: try SampleData.file())]
        let before = try Data(contentsOf: store.workspaceURL)
        let lookup = store.directoryForLookup(expected)
        XCTAssertEqual(lookup.standardizedFileURL, expected.standardizedFileURL)
        XCTAssertEqual(lookup.absoluteString, resolved.absoluteString)
        let accessing = lookup.startAccessingSecurityScopedResource()
        defer { if accessing { lookup.stopAccessingSecurityScopedResource() } }
        XCTAssertTrue(accessing, "The cached grant must retain its security scope, not just its path.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNil(store.connection)
        XCTAssertNil(store.lastDiscoveryIssue)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
    }

    @MainActor
    func testCachedLookupIgnoresBroaderChildUnrelatedMalformedAndOffScopeGrants() throws {
        let root = try scratch(), expected = root.appendingPathComponent("Synthetic Chrome").appendingPathComponent(".")
        let child = expected.appendingPathComponent("Default"), sibling = root.appendingPathComponent("Other Chrome")
        for directory in [child, sibling] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func grant(_ directory: URL) throws -> Data {
            try directory.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                       includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        let source = child.appendingPathComponent("Bookmarks"), base = try SampleData.file()
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let cases: [(String, URL, Data?)] = [
            ("broader", source, try grant(root)), ("child", source, try grant(child)),
            ("unrelated", source, try grant(sibling)), ("malformed", source, Data("invalid grant".utf8)),
            ("missing", source, nil),
            ("off-scope source", sibling.appendingPathComponent("Bookmarks"), try grant(expected)),
            ("path-prefix sibling", root.appendingPathComponent("Synthetic Chrome-other/Bookmarks"), try grant(expected))
        ]
        for (name, candidateSource, data) in cases {
            store.workspace.profiles = [ConnectedProfile(name: name, source: candidateSource, permissionBookmark: data, base: base)]
            let lookup = store.directoryForLookup(expected)
            XCTAssertEqual(lookup.standardizedFileURL, expected.standardizedFileURL, name)
            XCTAssertEqual(lookup.absoluteString, expected.absoluteString, "Ignored \(name) grant must return the original expected URL.")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNil(store.connection)
    }

    @MainActor
    func testFolderValidatorAcceptsOnlyExactStandardizedLocalTargetWithoutReadingIt() throws {
        let root = try scratch(), expected = root.appendingPathComponent("Missing Chrome")
        let validator = BrowserFolderValidator(requiredDirectory: expected)
        let sender = NSObject()
        XCTAssertNoThrow(try validator.panel(sender, validate: expected))
        XCTAssertNoThrow(try validator.panel(sender, validate: expected.appendingPathComponent(".")))
        var remote = try XCTUnwrap(URLComponents(url: expected, resolvingAgainstBaseURL: false))
        remote.host = "synthetic.invalid"
        for rejected in [root, expected.appendingPathComponent("Default"), root.appendingPathComponent("Sibling"),
                         try XCTUnwrap(remote.url), try XCTUnwrap(URL(string: "https://synthetic.invalid/Chrome"))] {
            XCTAssertThrowsError(try validator.panel(sender, validate: rejected)) { error in
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: expected.path))
    }
}

private final class CyclicDiscoveryError: NSError, @unchecked Sendable {
    override var userInfo: [String: Any] { [NSUnderlyingErrorKey: self] }
}
