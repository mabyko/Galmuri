import XCTest
import GalmuriCore
@testable import GalmuriApp

@MainActor final class RegisteredExtensionTests: XCTestCase {
    private let extensionID = String(repeating: "a", count: 32)
    nonisolated private static func wait(_ signal: DispatchSemaphore) -> Bool { signal.wait(timeout: .now()+5) == .success }
    private func fixture() throws -> AppStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriRegistered-"+UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(sampleData: true, directory: root)
        for name in ["Second", "Third"] {
            let folder = store.testRoot.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = try SampleData.file(), source = folder.appendingPathComponent("Bookmarks")
            try file.original.write(to: source)
            store.workspace.profiles.append(ConnectedProfile(name: name, source: source, base: file))
        }
        XCTAssertTrue(store.setLabOptions(api: true))
        return store
    }
    func testBatchReadsAllRegisteredProfilesAndContinuesAfterOneInvalidProfile() async throws {
        let store = try fixture(), profiles = store.workspace.profiles
        let before = try Data(contentsOf: store.workspaceURL)
        try JSONSerialization.data(withJSONObject: ["extensions": ["settings": [extensionID: ["state": 1]]]])
            .write(to: profiles[0].source.deletingLastPathComponent().appendingPathComponent("Preferences"))
        try Data("broken".utf8).write(to: profiles[1].source.deletingLastPathComponent().appendingPathComponent("Preferences"))
        try Data("{}".utf8).write(to: profiles[2].source.deletingLastPathComponent().appendingPathComponent("Preferences"))
        let unregistered = store.testRoot.appendingPathComponent("Unregistered")
        try FileManager.default.createDirectory(at: unregistered, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: unregistered.appendingPathComponent("Preferences"))
        await store.checkRegisteredExtensions(extensionID: extensionID)
        XCTAssertEqual(Set(store.extensionChecks.keys), Set(profiles.map(\.id)))
        XCTAssertEqual(store.extensionChecks[profiles[0].id]?.presence, .recordFound)
        XCTAssertEqual(store.extensionChecks[profiles[1].id]?.presence, .unavailable)
        XCTAssertEqual(store.extensionChecks[profiles[2].id]?.presence, .notDetected)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
        let cached = store.extensionChecks
        store.switchProfile(profiles[2].id)
        XCTAssertEqual(store.extensionChecks, cached)
        try Data("{}".utf8).write(to: profiles[0].source.deletingLastPathComponent().appendingPathComponent("Preferences"))
        XCTAssertEqual(store.extensionChecks, cached)
        await store.checkRegisteredExtensions(extensionID: extensionID)
        XCTAssertEqual(store.extensionChecks[profiles[0].id]?.presence, .notDetected)
        XCTAssertEqual(try Data(contentsOf: store.workspaceURL), before)
    }
    func testSelectingAnotherProfileDuringBatchDoesNotCancelOrReassignResults() async throws {
        let store = try fixture(), profiles = store.workspace.profiles
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), first = profiles[0].source
        let task = Task { await store.checkRegisteredExtensions(extensionID: extensionID) { source, _ in
            if source == first { entered.signal();_ = release.wait(timeout: .now()+5) }
            return source == first ? .recordFound : .notDetected
        } }
        let started = await Task.detached { Self.wait(entered) }.value;XCTAssertTrue(started)
        store.switchProfile(profiles[2].id);release.signal();await task.value
        XCTAssertEqual(store.extensionChecks.count, 3)
        XCTAssertEqual(store.extensionChecks[profiles[0].id]?.source, first)
        XCTAssertEqual(store.extensionChecks[profiles[0].id]?.presence, .recordFound)
        XCTAssertEqual(store.selectedProfileID, profiles[2].id)
    }
    func testOffStopsBatchBeforeAnotherProfileIsRead() async throws {
        let store = try fixture(), first = store.workspace.profiles[0].source
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let task = Task { await store.checkRegisteredExtensions(extensionID: extensionID) { source, _ in
            if source != first { XCTFail("A later profile was read after off") }
            entered.signal();_ = release.wait(timeout: .now()+5);return .recordFound
        } }
        let started = await Task.detached { Self.wait(entered) }.value;XCTAssertTrue(started)
        XCTAssertTrue(store.setLabOptions(api: false));release.signal();await task.value
        XCTAssertTrue(store.extensionChecks.isEmpty);XCTAssertFalse(store.checkingExtension)
    }
    func testRemovedProfileCannotReappearInResultsWhileRemainingProfilesFinish() async throws {
        let store = try fixture(), first = store.workspace.profiles[0], entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let task = Task { await store.checkRegisteredExtensions(extensionID: extensionID) { source, _ in
            if source == first.source { entered.signal();_ = release.wait(timeout: .now()+5) }
            return .recordFound
        } }
        let started = await Task.detached { Self.wait(entered) }.value;XCTAssertTrue(started)
        store.workspace.profiles.removeFirst();release.signal();await task.value
        XCTAssertNil(store.extensionChecks[first.id]);XCTAssertEqual(store.extensionChecks.count, 2)
        XCTAssertFalse(store.checkingExtension)
    }
}
