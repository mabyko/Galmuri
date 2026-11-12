import XCTest
import Foundation
import GalmuriCore
@testable import GalmuriApp

@MainActor final class APIWorkspaceRecoveryTests: XCTestCase {
    private func fixture() async throws -> (URL, APIWorkspaceModel, APIEnvelope) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let model = APIWorkspaceModel(directory: root, variant: "debug")
        let session = try model.proof.create(installationID: UUID(), name: "Synthetic recovery")
        try model.proof.approve(session)
        let nodes: [[String: Any]] = [
            ["id":"0", "title":"", "children":["scope"], "managed":false, "syncing":false],
            ["id":"scope", "parent":"0", "title":"Scope", "children":["a"], "managed":false, "syncing":false],
            ["id":"a", "parent":"scope", "title":"A", "url":"https://example.test/a", "children":[], "managed":false, "syncing":false]
        ]
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: ["nodes":nodes]), as: UTF8.self)
        let envelope = APIEnvelope(session: session, writable: true, raw: raw)
        try model.store.put(envelope, name: session.id.uuidString + ".snapshot")
        await model.load(); await model.connect(envelope, scope: "scope")
        let id = try XCTUnwrap(model.profile?.mapping["a"])
        await model.edit { $0.nodes[id]?.name = "Local work" }
        XCTAssertNil(model.error)
        return (root, model, envelope)
    }
    private func queued(_ model: APIWorkspaceModel, session: BridgeProof) async throws -> APIJob {
        for _ in 0..<200 {
            if let job = try? model.store.get(APIJob.self, name: session.id.uuidString + ".outbox") { return job }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw GalmuriError.invalid("Synthetic test job was not queued")
    }
    private func pending(_ model: APIWorkspaceModel) async throws -> APIWorkingCopy {
        var value = model.workspace
        value.profiles[0].pendingJob = UUID(); value.revision = UUID()
        try model.store.save(value, expectedRevision: model.workspace.revision)
        await model.load()
        return try XCTUnwrap(model.profile)
    }
    func testCancelledRefreshPreservesBaseAndLocalWork() async throws {
        let (root, model, envelope) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try XCTUnwrap(model.profile)
        let task = Task { await model.prepare() }; defer { task.cancel() }
        let job = try await queued(model, session: envelope.session)
        XCTAssertEqual(job.command, "snapshot")
        task.cancel(); await task.value
        XCTAssertFalse(model.busy); XCTAssertNil(model.review)
        XCTAssertEqual(model.profile?.base, before.base); XCTAssertEqual(model.profile?.working, before.working)
        XCTAssertNil(model.profile?.pendingJob)
        XCTAssertEqual(try model.store.loadWorkspace().profiles[0].working, before.working)
    }
    func testCancelledApplyPersistsPendingBeforeDispatchAndBlocksReopenedEditing() async throws {
        let (root, model, envelope) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try XCTUnwrap(model.profile)
        let review = try APIReview(profile: before, envelope: envelope); review.acknowledged = true; model.review = review
        let task = Task { await model.accept() }; defer { task.cancel() }
        let job = try await queued(model, session: envelope.session)
        XCTAssertEqual(job.command, "apply")
        XCTAssertEqual(try model.store.loadWorkspace().profiles[0].pendingJob, job.id)
        task.cancel(); await task.value
        XCTAssertFalse(model.busy); XCTAssertNil(model.review); XCTAssertEqual(model.profile?.pendingJob, job.id)
        XCTAssertTrue(try model.store.stopRequested(job))
        let saved = try model.store.get(APIWorkingCopy.self, name: job.id.uuidString + ".before")
        XCTAssertEqual(saved.working, before.working)
        let reopened = APIWorkspaceModel(directory: root, variant: "debug"); await reopened.load()
        XCTAssertEqual(reopened.profile?.pendingJob, job.id); XCTAssertTrue(reopened.undo.isEmpty)
        await reopened.edit { $0 = before.base }
        XCTAssertNotNil(reopened.error); XCTAssertEqual(reopened.profile?.working, before.working)
        await reopened.prepare()
        XCTAssertEqual(try reopened.store.get(APIJob.self, name: envelope.session.id.uuidString + ".outbox").id, job.id)
    }
    func testDisconnectedSessionDoesNotQueueOrDiscardSavedWork() async throws {
        let (root, model, envelope) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try XCTUnwrap(model.profile)
        try model.proof.close(envelope.session)
        await model.prepare()
        XCTAssertNotNil(model.error); XCTAssertNil(model.review)
        XCTAssertEqual(model.profile?.working, before.working); XCTAssertEqual(model.profile?.base, before.base)
        XCTAssertThrowsError(try model.store.get(APIJob.self, name: envelope.session.id.uuidString + ".outbox"))
    }
    func testUserStopIsBoundToActiveJobAndRetainsPendingAfterAcknowledgement() async throws {
        let (root, model, envelope) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try XCTUnwrap(model.profile)
        let review = try APIReview(profile: before, envelope: envelope); review.acknowledged = true; model.review = review
        let task = Task { await model.accept() }; defer { task.cancel() }
        let job = try await queued(model, session: envelope.session)
        await model.requestStop()
        XCTAssertTrue(model.stopping); XCTAssertTrue(try model.store.stopRequested(job))
        let result = "{\"jobID\":\"\(job.id.uuidString)\",\"state\":\"stopped\"}"
        try model.store.put(JSONDecoder().decode(APIJobResult.self, from: Data(result.utf8)), name: job.id.uuidString + ".result")
        await task.value
        XCTAssertFalse(model.busy); XCTAssertFalse(model.stopping); XCTAssertNil(model.error)
        XCTAssertEqual(model.notice, "api.stopped"); XCTAssertEqual(model.profile?.pendingJob, job.id)
        XCTAssertEqual(model.profile?.working, before.working)
    }
    func testInterruptedAdoptionNeedsAcknowledgementBeforeQueue() async throws {
        let (root, model, envelope) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try await pending(model)
        model.adoption = try APIAdoption(profile: before, envelope: envelope)
        model.adoptionAcknowledged = false
        await model.adopt()
        XCTAssertEqual(model.profile?.pendingJob, before.pendingJob)
        XCTAssertEqual(model.profile?.working, before.working)
        XCTAssertThrowsError(try model.store.get(APIJob.self, name: envelope.session.id.uuidString + ".outbox"))
    }
    func testChangedAdoptionResponseRetainsPendingAndArchivesPreviousWork() async throws {
        let (root, model, envelope) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try await pending(model)
        model.adoption = try APIAdoption(profile: before, envelope: envelope); model.adoptionAcknowledged = true
        let task = Task { await model.adopt() }; defer { task.cancel() }
        let job = try await queued(model, session: envelope.session)
        XCTAssertEqual(job.command, "adopt")
        let changed = APIEnvelope(session: envelope.session, writable: true, raw: envelope.raw.replacingOccurrences(of: "\"A\"", with: "\"Concurrent\""))
        try model.store.put(changed, name: envelope.session.id.uuidString + ".snapshot")
        let result = "{\"jobID\":\"\(job.id.uuidString)\",\"state\":\"succeeded\"}"
        try model.store.put(JSONDecoder().decode(APIJobResult.self, from: Data(result.utf8)), name: job.id.uuidString + ".result")
        await task.value
        XCTAssertNotNil(model.error); XCTAssertEqual(model.profile?.pendingJob, before.pendingJob)
        XCTAssertEqual(model.profile?.working, before.working)
        let archives = try FileManager.default.contentsOfDirectory(at: model.store.directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasSuffix(".interrupted.json") }
        XCTAssertEqual(archives.count, 1)
        let archived = try model.store.get(APIWorkingCopy.self, name: archives[0].deletingPathExtension().lastPathComponent)
        XCTAssertEqual(archived.working, before.working)
    }
}
