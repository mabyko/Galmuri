import XCTest
import Foundation
import GalmuriCore
@testable import GalmuriApp

@MainActor final class APIWorkspaceModelTests: XCTestCase {
    private func raw() throws -> String {
        let nodes: [[String: Any]] = [
            ["id":"root","title":"","children":["scope"],"managed":false,"syncing":false],
            ["id":"scope","parent":"root","title":"Scope","children":["a"],"managed":false,"syncing":false],
            ["id":"a","parent":"scope","title":"A","url":"https://example.test/a","children":[],"managed":false,"syncing":false]]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["nodes":nodes]), as: UTF8.self)
    }
    private func fixture() async throws -> (URL, APIWorkspaceModel, APIEnvelope) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let model = APIWorkspaceModel(directory: root, variant: "debug")
        let session = try model.proof.create(installationID: UUID(), name: "QA")
        try model.proof.approve(session)
        let envelope = APIEnvelope(session: session, writable: true, raw: try raw())
        try model.store.put(envelope, name: session.id.uuidString + ".snapshot")
        await model.load()
        return (root, model, envelope)
    }
    func testLocalWorkingCopyPersistsAndUndoDoesNotTouchLegacyWorkspace() async throws {
        let (root, model, envelope) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("workspace.json")
        try Workspace().save(to: legacy); let before = try Data(contentsOf: legacy)
        await model.connect(envelope, scope: "scope")
        let profile = try XCTUnwrap(model.profile), id = try XCTUnwrap(profile.mapping["a"])
        await model.edit(expected: profile.id) { $0.nodes[id]?.name = "Edited" }
        XCTAssertNil(model.error)
        let reopened = APIWorkspaceModel(directory: root, variant: "debug"); await reopened.load()
        XCTAssertEqual(reopened.profile?.working.nodes[id]?.name, "Edited")
        await model.undoEdit(); XCTAssertEqual(model.profile?.working, profile.working)
        XCTAssertEqual(try Data(contentsOf: legacy), before)
    }
    func testNoOpEditsSkipSaveAndUndoStackIsCapped() async throws {
        let (root, model, envelope) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        await model.connect(envelope, scope: "scope")
        let profile = try XCTUnwrap(model.profile), id = try XCTUnwrap(profile.mapping["a"]), revision = model.workspace.revision
        await model.edit(expected: profile.id) { try $0.reorderAmongPeers(id, direction: -1) }
        XCTAssertNil(model.error); XCTAssertEqual(model.workspace.revision, revision); XCTAssertNil(model.undo[profile.id])
        for index in 0..<105 { await model.edit(expected: profile.id) { $0.nodes[id]?.name = "Edit \(index)" } }
        XCTAssertEqual(model.undo[profile.id]?.count, 100)
        model.undo[profile.id] = [try XCTUnwrap(model.profile).working]
        await model.undoEdit()
        XCTAssertNil(model.error); XCTAssertEqual(model.undo[profile.id], [])
    }
    func testStaleEditorAndConcurrentWindowCannotOverwriteNewWork() async throws {
        let (root, model, envelope) = try await fixture();defer { try? FileManager.default.removeItem(at: root) }
        await model.connect(envelope, scope: "scope")
        let profile = try XCTUnwrap(model.profile), id = try XCTUnwrap(profile.mapping["a"])
        let other = APIWorkspaceModel(directory: root, variant: "debug"); await other.load()
        await model.edit(expected: profile.id) { $0.nodes[id]?.name = "First" }
        await model.edit(expected: profile.id, working: profile.working) { $0.nodes[id]?.name = "Stale editor" }
        XCTAssertNotNil(model.error);XCTAssertEqual(model.profile?.working.nodes[id]?.name, "First")
        await other.edit(expected: profile.id) { $0.nodes[id]?.name = "Stale window" }
        XCTAssertNotNil(other.error)
        XCTAssertEqual(try model.store.loadWorkspace().profiles[0].working.nodes[id]?.name, "First")
    }
    func testSameInstallationAmbiguityBlocksConnection() async throws {
        let (root, model, envelope) = try await fixture();defer { try? FileManager.default.removeItem(at: root) }
        let second = try model.proof.create(installationID: envelope.session.installationID, name: "QA")
        try model.proof.approve(second)
        try model.store.put(APIEnvelope(session: second, writable: true, raw: raw()), name: second.id.uuidString + ".snapshot")
        await model.load(); await model.connect(envelope, scope: "scope")
        XCTAssertNotNil(model.error);XCTAssertTrue(model.workspace.profiles.isEmpty)
    }
    func testConflictsStartUnresolvedAndAcknowledgementIsResetByChoice() async throws {
        let (root, model, envelope) = try await fixture();defer { try? FileManager.default.removeItem(at: root) }
        await model.connect(envelope, scope: "scope")
        let profile = try XCTUnwrap(model.profile), id = try XCTUnwrap(profile.mapping["a"])
        await model.edit(expected: profile.id) { $0.nodes[id]?.name = "Ours" }
        let latest = APIEnvelope(session: envelope.session, writable: true, raw: try raw().replacingOccurrences(of: "\"A\"", with: "\"Theirs\""))
        let review = try APIReview(profile: XCTUnwrap(model.profile), envelope: latest)
        XCTAssertFalse(review.result.unresolved.isEmpty);XCTAssertFalse(review.acknowledged)
        model.review = review;review.acknowledged = true
        for conflict in review.result.conflicts { await model.resolve(conflict.id, side: .ours) }
        XCTAssertTrue(review.result.unresolved.isEmpty);XCTAssertFalse(review.acknowledged)
    }
    func testDetachedReviewRetainsNewBrowserNodeMapping() async throws {
        let (root, model, envelope) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        await model.connect(envelope, scope: "scope")
        let profile = try XCTUnwrap(model.profile)
        var object = try JSONSerialization.jsonObject(with: Data(envelope.raw.utf8)) as! [String: Any]
        var nodes = object["nodes"] as! [[String: Any]]
        nodes[1]["children"] = ["a", "browser-added"]
        nodes.append(["id":"browser-added", "parent":"scope", "title":"Independent", "url":"https://example.test/a", "children":[], "managed":false, "syncing":false])
        object["nodes"] = nodes
        let fresh = APIEnvelope(session: envelope.session, writable: true, raw: String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
        let prepared = try await Task.detached { try APIReview.prepareData(profile: profile, envelope: fresh, restore: false) }.value
        let review = try APIReview(profile: profile, envelope: fresh, prepared: prepared)
        let key = try XCTUnwrap(review.mapping["browser-added"])
        XCTAssertNotNil(review.theirs.nodes[key]); XCTAssertNotNil(review.result.tree.nodes[key])
        var staged = profile; staged.mapping = review.mapping
        let job = try staged.job(envelope: fresh, target: review.result.tree)
        XCTAssertEqual(job.desired.first(where: { $0.key == key })?.id, "browser-added")
    }

}
