import XCTest
import GalmuriCore
@testable import GalmuriApp

final class OnboardingTests: XCTestCase {
    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriOnboarding-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    @discardableResult
    private func profile(_ root: URL, _ name: String, bytes: Data? = nil) throws -> URL {
        let directory = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try (bytes ?? SampleData.file().original).write(to: directory.appendingPathComponent("Bookmarks"))
        return directory
    }

    @MainActor
    func testNormalStartupAndRelaunchPersistEmptySchemaOneWithoutSamples() throws {
        let directory = try scratch().appendingPathComponent("App")
        let store = AppStore(directory: directory, browserState: { _ in false })
        XCTAssertNil(store.error)
        XCTAssertTrue(store.workspace.profiles.isEmpty)
        XCTAssertNil(store.selectedProfileID)
        XCTAssertNil(store.profile)
        XCTAssertTrue(store.savedSampleProfiles.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.testRoot.path))
        let bytes = try Data(contentsOf: store.workspaceURL)
        XCTAssertEqual(try Workspace.load(from: store.workspaceURL).version, 1)
        for samples in [false, true] {
            let reopened = AppStore(sampleData: samples, directory: directory, browserState: { _ in false })
            XCTAssertNil(reopened.error)
            XCTAssertTrue(reopened.workspace.profiles.isEmpty)
            XCTAssertNil(reopened.selectedProfileID)
            XCTAssertEqual(try Data(contentsOf: reopened.workspaceURL), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.testRoot.path))
        }
    }

    @MainActor
    func testSavedEditedSampleSurvivesNormalWelcomeAndExplicitSampleRelaunchExactly() throws {
        let directory = try scratch().appendingPathComponent("App")
        let store = AppStore(sampleData: true, directory: directory, browserState: { _ in false })
        let initial = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(initial.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.isLocalTestProfile(initial))
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Keep my sample edit", url: item.url) })
        let working = store.tree
        let workspaceBytes = try Data(contentsOf: store.workspaceURL)
        let sourceBytes = try Data(contentsOf: initial.source)
        let normal = AppStore(directory: directory, browserState: { _ in false })
        XCTAssertNil(normal.error)
        XCTAssertNil(normal.selectedProfileID)
        XCTAssertNil(normal.tree)
        XCTAssertEqual(normal.savedSampleProfiles.map(\.id), [initial.id])
        let saved = try XCTUnwrap(normal.savedSampleProfiles.first)
        XCTAssertEqual(saved.base, initial.base)
        XCTAssertEqual(saved.working, working)
        XCTAssertTrue(saved.hasChanges)
        normal.switchProfile(saved.id)
        XCTAssertEqual(normal.tree, working)
        let explicit = AppStore(sampleData: true, directory: directory, browserState: { _ in false })
        XCTAssertEqual(explicit.selectedProfileID, initial.id)
        XCTAssertEqual(explicit.profile?.base, initial.base)
        XCTAssertEqual(explicit.tree, working)
        XCTAssertEqual(try Data(contentsOf: explicit.workspaceURL), workspaceBytes)
        XCTAssertEqual(try Data(contentsOf: initial.source), sourceBytes)
    }

    @MainActor
    func testExistingCorruptWorkspaceIsNeverReplacedOrSeeded() throws {
        let directory = try scratch()
        let file = directory.appendingPathComponent("workspace.json")
        let bytes = Data("existing invalid workspace, preserve for recovery".utf8)
        try bytes.write(to: file)
        for samples in [false, true] {
            let store = AppStore(sampleData: samples, directory: directory, browserState: { _ in false })
            XCTAssertNotNil(store.error)
            XCTAssertNil(store.selectedProfileID)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.testRoot.path))
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    @MainActor
    func testNormalReloadPrefersFirstExternalWhileSampleModeKeepsFirstSavedProfile() async throws {
        let root = try scratch()
        let first = try profile(root.appendingPathComponent("Chrome"), "Default")
        let second = try profile(root.appendingPathComponent("Chrome"), "Profile 1")
        let store = AppStore(sampleData: true, directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let sampleID = try XCTUnwrap(store.selectedProfileID)
        let connected = await store.connectDirectory(first)
        XCTAssertTrue(connected)
        let externalID = try XCTUnwrap(store.selectedProfileID)
        let connectedSecond = await store.connectDirectory(second)
        XCTAssertTrue(connectedSecond)
        XCTAssertNotEqual(store.selectedProfileID, externalID)
        let bytes = try Data(contentsOf: store.workspaceURL)
        let normal = AppStore(directory: store.directory, browserState: { _ in false })
        XCTAssertEqual(normal.selectedProfileID, externalID)
        XCTAssertFalse(normal.isLocalTestProfile(try XCTUnwrap(normal.profile)))
        XCTAssertEqual(normal.savedSampleProfiles.map(\.id), [sampleID])
        let explicit = AppStore(sampleData: true, directory: store.directory, browserState: { _ in false })
        XCTAssertEqual(explicit.selectedProfileID, sampleID)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), bytes)
    }

    @MainActor
    func testSampleClassificationRequiresAppOwnedPathBoundary() throws {
        let root = try scratch()
        let store = AppStore(sampleData: true, directory: root, browserState: { _ in false })
        var candidate = try XCTUnwrap(store.profile)
        XCTAssertTrue(store.isLocalTestProfile(candidate))
        for source in [root.appendingPathComponent("TestProfiles-other/Default/Bookmarks"),
                       root.appendingPathComponent("Elsewhere/TestProfiles/Default/Bookmarks"),
                       URL(string: "https://example.com/TestProfiles/Bookmarks")!] {
            candidate.source = source
            XCTAssertFalse(store.isLocalTestProfile(candidate))
        }
    }

    @MainActor
    func testDiscoveryStagesMetadataWithoutParsingBookmarksAndNilPreservesState() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Chrome")
        let malformed = Data("not a bookmark payload".utf8)
        let directory = try profile(chrome, "Default", bytes: malformed)
        let localState = Data(#"{"profile":{"info_cache":{"Default":{"name":"Synthetic Person"}}}}"#.utf8)
        try localState.write(to: chrome.appendingPathComponent("Local State"))
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let bytes = try Data(contentsOf: store.workspaceURL)
        await store.beginConnection(chrome)
        let request = try XCTUnwrap(store.connection)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.busy)
        XCTAssertEqual(request.directory, chrome)
        XCTAssertEqual(request.profiles.map { $0.directory.lastPathComponent }, ["Default"])
        XCTAssertEqual(request.profiles.map(\.id), request.profiles.map { $0.directory.path })
        XCTAssertEqual(request.profiles.map(\.name), ["Synthetic Person"])
        XCTAssertTrue(store.workspace.profiles.isEmpty)
        XCTAssertNil(store.selectedProfileID)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), bytes)
        await store.beginConnection(nil)
        let connected = await store.connectDirectory(nil)
        XCTAssertFalse(connected)
        XCTAssertEqual(store.connection?.id, request.id)
        XCTAssertTrue(store.workspace.profiles.isEmpty)
        XCTAssertFalse(store.busy)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("Bookmarks")), malformed)
        XCTAssertEqual(try Data(contentsOf: chrome.appendingPathComponent("Local State")), localState)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), bytes)
    }

    @MainActor
    func testExplicitSubsetImportsOnlyChosenPathDespiteEncryptedAndMalformedNeighbors() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Chrome")
        let chosen = try profile(chrome, "Default")
        let unchosen = try profile(chrome, "Profile 1")
        let malformed = try profile(chrome, "Profile 2", bytes: Data("invalid bookmark JSON".utf8))
        let unreadable = chrome.appendingPathComponent("Profile 4/Bookmarks")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        let encrypted = chrome.appendingPathComponent("Profile 3")
        try FileManager.default.createDirectory(at: encrypted, withIntermediateDirectories: true)
        let marker = Data("synthetic encrypted-only marker".utf8)
        try marker.write(to: encrypted.appendingPathComponent("EncryptedBookmarks2"))
        try Data(#"{"profile":{"info_cache":{"Default":{"name":"Same Name"},"Profile 1":{"name":"Same Name"}}}}"#.utf8)
            .write(to: chrome.appendingPathComponent("Local State"))
        let originals = try [chosen, unchosen, malformed].map { try Data(contentsOf: $0.appendingPathComponent("Bookmarks")) }
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        await store.beginConnection(chrome)
        let request = try XCTUnwrap(store.connection)
        XCTAssertEqual(request.profiles.count, 5)
        let connected = await store.finishConnection(request, profileIDs: [request.profiles[0].id])
        XCTAssertTrue(connected)
        XCTAssertNil(store.error)
        XCTAssertNil(store.connection)
        XCTAssertEqual(store.workspace.profiles.map(\.source), [request.profiles[0].file])
        XCTAssertEqual(store.profile?.name, "Same Name")
        XCTAssertTrue(store.savedSampleProfiles.isEmpty)
        XCTAssertEqual(try Workspace.load(from: store.workspaceURL).profiles.map(\.id), store.workspace.profiles.map(\.id))
        for (index, directory) in [chosen, unchosen, malformed].enumerated() {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("Bookmarks")), originals[index])
        }
        XCTAssertEqual(try Data(contentsOf: encrypted.appendingPathComponent("EncryptedBookmarks2")), marker)
        XCTAssertTrue(try unreadable.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
    }

    @MainActor
    func testEmptyAndMissingSelectionIDsRejectAtomicallyAndKeepStagedRequest() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Chrome")
        let chosen = try profile(chrome, "Default")
        let store = AppStore(sampleData: true, directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let selected = store.selectedProfileID, bytes = try Data(contentsOf: store.workspaceURL)
        await store.beginConnection(chrome)
        let request = try XCTUnwrap(store.connection)
        for ids: Set<String> in [[], ["missing"], [request.profiles[0].id, "missing"], ["Default"], [chosen.appendingPathComponent("Bookmarks").path]] {
            let connected = await store.finishConnection(request, profileIDs: ids)
            XCTAssertFalse(connected)
            XCTAssertNotNil(store.error)
            XCTAssertEqual(store.connection?.id, request.id)
            XCTAssertEqual(store.selectedProfileID, selected)
            XCTAssertFalse(store.busy)
            XCTAssertEqual(try Data(contentsOf: store.workspaceURL), bytes)
        }
    }

    @MainActor
    func testSelectedEncryptedOnlyProfileRejectsWholeSelection() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Chrome")
        try profile(chrome, "Default")
        let encrypted = chrome.appendingPathComponent("Profile 1")
        try FileManager.default.createDirectory(at: encrypted, withIntermediateDirectories: true)
        let marker = Data("synthetic encrypted-only marker".utf8)
        let source = encrypted.appendingPathComponent("EncryptedBookmarks2")
        try marker.write(to: source)
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let bytes = try Data(contentsOf: store.workspaceURL)
        await store.beginConnection(chrome)
        let request = try XCTUnwrap(store.connection)
        let connected = await store.finishConnection(request, profileIDs: Set(request.profiles.map(\.id)))
        XCTAssertFalse(connected)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.connection?.id, request.id)
        XCTAssertTrue(store.workspace.profiles.isEmpty)
        XCTAssertNil(store.selectedProfileID)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), bytes)
        XCTAssertEqual(try Data(contentsOf: source), marker)
    }

    @MainActor
    func testSelectedUnreadableProfileRejectsAtomicallyAfterReadableProfile() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Chrome")
        let readable = try profile(chrome, "Default")
        let unreadable = chrome.appendingPathComponent("Profile 1/Bookmarks")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        let store = AppStore(sampleData: true, directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let initial = try XCTUnwrap(store.profile)
        let item = try XCTUnwrap(initial.working.nodes.values.first { $0.url != nil })
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Keep pending sample work", url: item.url) })
        let selected = store.selectedProfileID, working = store.tree
        let sourceBytes = try Data(contentsOf: readable.appendingPathComponent("Bookmarks"))
        let bytes = try Data(contentsOf: store.workspaceURL)
        await store.beginConnection(chrome)
        let request = try XCTUnwrap(store.connection)
        await store.beginConnection(nil)
        XCTAssertEqual(store.connection?.id, request.id)
        XCTAssertEqual(store.selectedProfileID, selected)
        XCTAssertEqual(store.tree, working)
        let connected = await store.finishConnection(request, profileIDs: Set(request.profiles.map(\.id)))
        XCTAssertFalse(connected)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.busy)
        XCTAssertEqual(store.connection?.id, request.id)
        XCTAssertEqual(store.selectedProfileID, selected)
        XCTAssertEqual(store.tree, working)
        XCTAssertEqual(store.workspace.profiles.count, 1)
        XCTAssertEqual(store.profile?.base, initial.base)
        XCTAssertEqual(try Data(contentsOf: readable.appendingPathComponent("Bookmarks")), sourceBytes)
        XCTAssertTrue(try unreadable.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), bytes)
    }

    @MainActor
    func testLegacyConnectAllStillRejectsMalformedBatchAtomically() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Chrome")
        try profile(chrome, "Default")
        try profile(chrome, "Profile 1", bytes: Data("malformed unselected payload".utf8))
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        let bytes = try Data(contentsOf: store.workspaceURL)
        let connected = await store.connectDirectory(chrome)
        XCTAssertFalse(connected)
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.workspace.profiles.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), bytes)
    }

    @MainActor
    func testConfirmationRediscoveryRejectsProfileRemovedAfterStaging() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Chrome")
        let chosen = try profile(chrome, "Default")
        try profile(chrome, "Profile 1")
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        await store.beginConnection(chrome)
        let request = try XCTUnwrap(store.connection)
        let bytes = try Data(contentsOf: store.workspaceURL)
        try FileManager.default.removeItem(at: chosen)
        let connected = await store.finishConnection(request, profileIDs: [request.profiles[0].id])
        XCTAssertFalse(connected)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.connection?.id, request.id)
        XCTAssertTrue(store.workspace.profiles.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), bytes)
    }

    @MainActor
    func testConfirmationReadsCurrentPayloadAndConnectedWorkIsNeverReimported() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Chrome")
        let chosen = try profile(chrome, "Default", bytes: Data("not parsed during discovery".utf8))
        let source = chosen.appendingPathComponent("Bookmarks")
        let store = AppStore(directory: root.appendingPathComponent("App"), browserState: { _ in false })
        await store.beginConnection(chrome)
        let first = try XCTUnwrap(store.connection)
        let original = try SampleData.file()
        var latest = original.tree
        let item = try XCTUnwrap(latest.nodes.values.first { $0.url != nil })
        try latest.edit(item.id, name: "Latest at confirmation", url: item.url)
        let latestBytes = try original.serialize(latest)
        try latestBytes.write(to: source)
        let connected = await store.finishConnection(first, profileIDs: [first.profiles[0].id])
        XCTAssertTrue(connected)
        let imported = try XCTUnwrap(store.profile)
        XCTAssertEqual(imported.base.original, latestBytes)
        XCTAssertTrue(store.edit { try $0.edit(item.id, name: "Keep unapplied work", url: item.url) })
        let working = store.tree, bytes = try Data(contentsOf: store.workspaceURL)
        try original.original.write(to: source)
        await store.beginConnection(chrome)
        let second = try XCTUnwrap(store.connection)
        let reconnected = await store.finishConnection(second, profileIDs: [second.profiles[0].id])
        XCTAssertTrue(reconnected)
        XCTAssertNil(store.connection)
        XCTAssertEqual(store.workspace.profiles.count, 1)
        XCTAssertEqual(store.profile?.id, imported.id)
        XCTAssertEqual(store.profile?.base, imported.base)
        XCTAssertEqual(store.tree, working)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), bytes)
        XCTAssertEqual(try Data(contentsOf: source), original.original)
    }

    @MainActor
    func testStaleStagedRequestCannotImportOrDismissNewerRequest() async throws {
        let root = try scratch(), chrome = root.appendingPathComponent("Chrome")
        try profile(chrome, "Default")
        let store = AppStore(sampleData: true, directory: root.appendingPathComponent("App"), browserState: { _ in false })
        await store.beginConnection(chrome)
        let old = try XCTUnwrap(store.connection)
        await store.beginConnection(chrome)
        let current = try XCTUnwrap(store.connection)
        XCTAssertNotEqual(old.id, current.id)
        let bytes = try Data(contentsOf: store.workspaceURL), selected = store.selectedProfileID
        let connected = await store.finishConnection(old, profileIDs: [old.profiles[0].id])
        XCTAssertFalse(connected)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.connection?.id, current.id)
        XCTAssertEqual(store.selectedProfileID, selected)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), bytes)
        let currentConnected = await store.finishConnection(current, profileIDs: [current.profiles[0].id])
        XCTAssertTrue(currentConnected)
        XCTAssertNil(store.connection)
    }
}
