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
    func testChangedURLsAreCanonicalAndSnapshotURLsStayByteIdentical() throws {
        let proof = try BridgeProof(installationID: UUID(), name: "QA", variant: "debug")
        var object = try JSONSerialization.jsonObject(with: Data(Self.snapshot().utf8)) as! [String: Any]
        var nodes = object["nodes"] as! [[String: Any]]
        nodes[3]["url"] = "HTTPS://Odd.Example"; object["nodes"] = nodes
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        var copy = try APIWorkingCopy(envelope: APIEnvelope(session: proof, writable: true, raw: raw), scope: "local")
        let root = copy.base.orderedRoots[0], odd = try XCTUnwrap(copy.mapping["opaque:a"])
        var added = ""
        try copy.edit { added = try $0.add(name: "New", url: "https://Example.com", to: root); $0.nodes[odd]?.name = "Renamed" }
        XCTAssertEqual(copy.working.nodes[added]?.url, "https://example.com/")
        XCTAssertEqual(copy.working.nodes[odd]?.url, "HTTPS://Odd.Example")
        XCTAssertEqual(try APIWorkingCopy.canonicalURL("HTTP://Example.COM:80?q=A#Frag"), "http://example.com/?q=A#Frag")
    }
    // Expected values are JavaScript `new URL(x).href` (Node 26).
    func testCanonicalURLMatchesJavaScriptHrefOrRejects() throws {
        let matches = [
            "https://한글.example": "https://xn--bj0bj06e.example/",
            "https://MÜNCHEN.de": "https://xn--mnchen-3ya.de/",
            "https://한글.example/경로?q=값#조각": "https://xn--bj0bj06e.example/%EA%B2%BD%EB%A1%9C?q=%EA%B0%92#%EC%A1%B0%EA%B0%81",
            "https://a.example/%7e%2F?q=%7e": "https://a.example/%7e%2F?q=%7e",
            "https://a.example./p": "https://a.example./p",
            "https://a.example:8080": "https://a.example:8080/",
            "https://a.example?x=1": "https://a.example/?x=1",
            "https://a.example#frag": "https://a.example/#frag",
            "https://a.example/a b/é?q=a b#f g": "https://a.example/a%20b/%C3%A9?q=a%20b#f%20g",
            "https://1.2.3.4/": "https://1.2.3.4/",
        ]
        for (input, href) in matches { XCTAssertEqual(try APIWorkingCopy.canonicalURL(input), href, input) }
        for href in matches.values { XCTAssertEqual(try APIWorkingCopy.canonicalURL(href), href, href) }
        for rejected in ["https://user:pass@a.example/", "https://[::1]/", "http://0x7f.1/", "https://01.2.3.4/", "https://1.2.3.4./",
                         "https:a.example", "https://a%2Eexample/", "https://a.example/./b/../c", "https://a.example/p\\x",
                         "https://a.example/?q=^", "https://a.example/%zz", "https://a.example/#a#b", "https://a.example/?q='",
                         "https://a.example/ x ", "https://a.example:65536/", "ftp://a.example/"] {
            XCTAssertThrowsError(try APIWorkingCopy.canonicalURL(rejected), rejected)
        }
    }
    func testCapabilityAndInstallationGuardBeforeCreatingJob() throws {
        let proof = try BridgeProof(installationID: UUID(), name: "QA", variant: "debug")
        let envelope = APIEnvelope(session: proof, writable: false, raw: try Self.snapshot())
        let copy = try APIWorkingCopy(envelope: envelope, scope: "local")
        XCTAssertThrowsError(try copy.job(envelope: envelope, target: copy.working))
        let other = try BridgeProof(installationID: UUID(), name: "QA", variant: "debug")
        XCTAssertThrowsError(try copy.job(envelope: APIEnvelope(session: other, writable: true, raw: Self.snapshot()), target: copy.working))
    }
    func testJobRejectsStoredNonCanonicalURLsButNotChromeURLs() throws {
        let proof = try BridgeProof(installationID: UUID(), name: "QA", variant: "debug")
        var object = try JSONSerialization.jsonObject(with: Data(Self.snapshot().utf8)) as! [String: Any]
        var nodes = object["nodes"] as! [[String: Any]]
        nodes[3]["url"] = "HTTPS://Odd.Example"; object["nodes"] = nodes
        let envelope = APIEnvelope(session: proof, writable: true, raw: String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
        var copy = try APIWorkingCopy(envelope: envelope, scope: "local")
        let odd = try XCTUnwrap(copy.mapping["opaque:a"]), other = try XCTUnwrap(copy.mapping["opaque:b"])
        copy.working.nodes[odd]?.name = "Renamed"
        XCTAssertNoThrow(try copy.job(envelope: envelope, target: copy.working))
        copy.working.nodes[other]?.url = "https://example.com" // saved before the canonical-URL rule
        XCTAssertThrowsError(try copy.job(envelope: envelope, target: copy.working)) { XCTAssertTrue($0.localizedDescription.contains("\"B\"")) }
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
