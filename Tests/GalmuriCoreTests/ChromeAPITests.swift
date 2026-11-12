import XCTest
import Foundation
@testable import GalmuriCore

final class ChromeAPITests: XCTestCase {
    static func snapshot() throws -> String {
        let nodes: [[String: Any]] = [
            ["id":"root","title":"","children":["local","account"],"managed":false,"syncing":false],
            ["id":"local","parent":"root","title":"Local","children":["opaque:a","opaque:b"],"folderType":"bookmarks-bar","managed":false,"syncing":false],
            ["id":"account","parent":"root","title":"Account","children":[],"folderType":"bookmarks-bar","managed":false,"syncing":true],
            ["id":"opaque:a","parent":"local","title":"A","url":"https://example.test/same","children":[],"managed":false,"syncing":false],
            ["id":"opaque:b","parent":"local","title":"B","url":"https://example.test/same","children":[],"managed":false,"syncing":false]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["nodes": nodes], options: [.sortedKeys]), as: UTF8.self)
    }
    func testOpaqueIDsDuplicateURLsAndMultipleRootsKeepIndependentMappings() throws {
        let raw = try Self.snapshot(), snapshot = try ChromeAPISnapshot(data: Data(raw.utf8))
        XCTAssertEqual(snapshot.folders.count, 2)
        var mapping = [String: String]()
        let tree = try snapshot.tree(scope: "local", mapping: &mapping, excluding: [])
        XCTAssertNotEqual(mapping["opaque:a"], mapping["opaque:b"])
        XCTAssertEqual(tree.nodes.values.filter { $0.url != nil }.count, 2)
        let reopened = try snapshot.tree(scope: "local", mapping: &mapping, excluding: [])
        XCTAssertEqual(tree, reopened)
        XCTAssertThrowsError(try snapshot.tree(scope: "root", mapping: &mapping, excluding: []))
    }
    func testMalformedSnapshotsRejectDuplicatesOrphansCyclesAndInconsistentParents() throws {
        for kind in 0..<4 {
            var object = try JSONSerialization.jsonObject(with: Data(Self.snapshot().utf8)) as! [String: Any]
            var nodes = object["nodes"] as! [[String: Any]]
            if kind == 0 { nodes.append(nodes[3]) }
            if kind == 1 { nodes[3]["parent"] = "account" }
            if kind == 2 { nodes[0]["children"] = ["local"] }
            if kind == 3 { nodes[1]["children"] = ["local"] }
            object["nodes"] = nodes
            XCTAssertThrowsError(try ChromeAPISnapshot(data: JSONSerialization.data(withJSONObject: object)))
        }
    }
    func testWorkspacePersistenceAndRevisionGuardPreserveLegacyFileWorkspace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("workspace.json")
        let legacy = Workspace(profiles: [ConnectedProfile(name: "Synthetic", source: root.appendingPathComponent("Bookmarks"), base: try SampleData.file())])
        try legacy.save(to: file); let before = try Data(contentsOf: file)
        let store = BridgeAPIStore(workspace: root, variant: "debug")
        let proof = try BridgeProof(installationID: UUID(), name: "QA", variant: "debug")
        var api = APIWorkspace();api.profiles = [try APIWorkingCopy(envelope: APIEnvelope(session: proof, writable: true, raw: Self.snapshot()), scope: "local")];api.revision = UUID()
        try store.save(api, expectedRevision: nil)
        XCTAssertEqual(try store.loadWorkspace().profiles[0].mapping, api.profiles[0].mapping)
        var stale = api;stale.revision = UUID()
        XCTAssertThrowsError(try store.save(stale, expectedRevision: nil))
        XCTAssertEqual(try store.loadWorkspace().revision, api.revision)
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try Workspace.load(from: file).version, 1)
    }
    func testTamperedMappingAndRootAreRejected() throws {
        let proof = try BridgeProof(installationID: UUID(), name: "QA", variant: "debug")
        var workspace = APIWorkspace();workspace.profiles = [try APIWorkingCopy(envelope: APIEnvelope(session: proof, writable: true, raw: Self.snapshot()), scope: "local")]
        workspace.profiles[0].mapping.removeValue(forKey: "opaque:a")
        XCTAssertThrowsError(try workspace.validate())
    }
    func testSemanticProjectionIgnoresFileDatesAndPreservesAppEdits() throws {
        let proof = try BridgeProof(installationID: UUID(), name: "QA", variant: "debug")
        var copy = try APIWorkingCopy(envelope: APIEnvelope(session: proof, writable: true, raw: Self.snapshot()), scope: "local")
        let root = copy.base.orderedRoots[0]
        try copy.edit { _ = try $0.add(name: "New", url: "https://example.test/new", to: root) }
        XCTAssertTrue(copy.working.nodes.values.allSatisfy { $0.metadata.isEmpty && $0.chromeID == "0" })
        try copy.working.validate()
    }
    func testCapabilityAndInstallationGuardBeforeCreatingJob() throws {
        let proof = try BridgeProof(installationID: UUID(), name: "QA", variant: "debug")
        let envelope = APIEnvelope(session: proof, writable: false, raw: try Self.snapshot())
        let copy = try APIWorkingCopy(envelope: envelope, scope: "local")
        XCTAssertThrowsError(try copy.job(envelope: envelope, target: copy.working))
        let other = try BridgeProof(installationID: UUID(), name: "QA", variant: "debug")
        XCTAssertThrowsError(try copy.job(envelope: APIEnvelope(session: other, writable: true, raw: Self.snapshot()), target: copy.working))
    }
    func testStopMarkersRequireExactJobIdentityAndRejectSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BridgeAPIStore(workspace: root, variant: "debug")
        let proof = try BridgeProof(installationID: UUID(), name: "Synthetic stop", variant: "debug")
        let job = APIJob.refresh(proof)
        XCTAssertFalse(try store.stopRequested(job))
        try store.requestStop(job); XCTAssertTrue(try store.stopRequested(job))
        let other = APIJob.refresh(proof)
        XCTAssertFalse(try store.stopRequested(other))
        try store.put(APIStop(job: other), name: job.id.uuidString + ".stop")
        XCTAssertThrowsError(try store.stopRequested(job))
        let marker = store.directory.appendingPathComponent(job.id.uuidString + ".stop.json")
        try FileManager.default.removeItem(at: marker)
        try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: root.appendingPathComponent("absent"))
        XCTAssertThrowsError(try store.stopRequested(job))
    }
}
