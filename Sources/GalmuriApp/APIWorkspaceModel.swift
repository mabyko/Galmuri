import Foundation
import Observation
import GalmuriCore

@MainActor @Observable
final class APIAdoption: Identifiable {
    let id = UUID()
    let profile: APIWorkingCopy
    let envelope: APIEnvelope
    let tree: BookmarkTree
    let mapping: [String: String]
    let recoveryIDs: Set<String>
    init(profile: APIWorkingCopy, envelope: APIEnvelope) throws {
        self.profile = profile; self.envelope = envelope
        let nodes = try envelope.snapshot.nodes
        recoveryIDs = profile.recoveryIDs.filter { id in nodes.contains { $0.id == id && $0.parent == profile.scope && $0.url == nil } }
        var mapping = profile.mapping
        tree = try envelope.snapshot.tree(scope: profile.scope, mapping: &mapping, excluding: recoveryIDs)
        self.mapping = mapping
    }
}

@MainActor @Observable
final class APIReview: Identifiable {
    let id = UUID()
    let profile: APIWorkingCopy
    let envelope: APIEnvelope
    let theirs: BookmarkTree
    let ours: BookmarkTree
    let mergeBase: BookmarkTree
    let writable: Bool
    var mapping: [String: String]
    var resolutions: [String: MergeSide] = [:]
    var acknowledged = false
    var result: MergeResult
    struct Prepared: Sendable {
        let mapping: [String: String]
        let theirs: BookmarkTree
        let ours: BookmarkTree
        let base: BookmarkTree
        let result: MergeResult
    }
    nonisolated static func prepareData(profile: APIWorkingCopy, envelope: APIEnvelope, restore: Bool) throws -> Prepared {
        var mapping = profile.mapping
        let theirs = try envelope.snapshot.tree(scope: profile.scope, mapping: &mapping, excluding: profile.recoveryIDs)
        let base: BookmarkTree, ours: BookmarkTree
        if restore {
            guard let checkpoint = profile.history.last else { throw GalmuriError.invalid("API history empty") }
            base = checkpoint.after; ours = checkpoint.before
        } else { base = profile.base; ours = profile.working }
        return Prepared(mapping: mapping, theirs: theirs, ours: ours, base: base,
                        result: try MergeEngine.merge(base: base, ours: ours, theirs: theirs))
    }
    init(profile: APIWorkingCopy, envelope: APIEnvelope, restore: Bool = false, prepared: Prepared? = nil) throws {
        let data = try prepared ?? Self.prepareData(profile: profile, envelope: envelope, restore: restore)
        self.profile = profile; self.envelope = envelope
        writable = try envelope.writable && envelope.snapshot.writable(scope: profile.scope)
        mapping = data.mapping; theirs = data.theirs; ours = data.ours; mergeBase = data.base; result = data.result
    }

}

@MainActor @Observable
final class APIWorkspaceModel {
    var workspace = APIWorkspace()
    var selected: UUID?
    var sources: [APIEnvelope] = []
    var review: APIReview?
    var adoption: APIAdoption?
    var adoptionAcknowledged = false
    var busy = false
    var stopping = false
    @ObservationIgnored private var activeJob: APIJob?
    var error: String?
    var notice: String?
    var undo: [UUID: [BookmarkTree]] = [:]
    let store: BridgeAPIStore
    let proof: BridgeProofStore
    var profile: APIWorkingCopy? { workspace.profiles.first { $0.id == selected } }
    init(directory: URL, variant: String? = nil) {
        let variant = variant ?? (Bundle.main.object(forInfoDictionaryKey: "GalmuriBuildConfiguration") as? String ?? "debug")
        store = BridgeAPIStore(workspace: directory, variant: variant)
        proof = BridgeProofStore(workspace: directory, variant: variant)
    }
    func load() async {
        guard !busy else { return }; busy = true; defer { finish() }
        do {
            let source = store, approvals = proof
            let loaded = try await Task.detached { () -> (APIWorkspace, [APIEnvelope]) in
                let workspace = try source.loadWorkspace(), sessions = try approvals.requests()
                let values = try sessions.filter { try approvals.approved($0) }.compactMap { try? source.envelope($0) }
                return (workspace, values)
            }.value
            if workspace.revision != loaded.0.revision { undo = [:] }
            workspace = loaded.0; sources = loaded.1
            if !workspace.profiles.contains(where: { $0.id == selected }) { selected = workspace.profiles.first?.id }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    // Stop has no effect on most operations, so a leftover "stopping" notice must not outlive the operation.
    private func finish() {
        busy = false; stopping = false
        if notice == "api.stopping" { notice = nil }
    }
    private func commit(_ candidate: APIWorkspace) async throws {
        let expected = workspace.revision, store = store
        var value = candidate; value.revision = UUID()
        let saved = value
        try await Task.detached { try store.save(saved, expectedRevision: expected) }.value
        workspace = value
    }
    private func change(_ profile: APIWorkingCopy) async throws {
        var next = workspace
        guard let index = next.profiles.firstIndex(where: { $0.id == profile.id }) else { throw GalmuriError.staleSource }
        next.profiles[index] = profile; try await commit(next)
    }
    func connect(_ source: APIEnvelope, scope: String) async {
        guard !busy else { return }; busy = true; defer { finish() }
        do {
            guard sources.filter({ $0.session.installationID == source.session.installationID }).count == 1 else { throw GalmuriError.invalid("ambiguous API installation") }
            if let existing = workspace.profiles.first(where: { $0.installationID == source.session.installationID && $0.scope == scope }) { selected = existing.id; return }
            let profile = try APIWorkingCopy(envelope: source, scope: scope)
            var next = workspace; next.profiles.append(profile); try await commit(next); selected = profile.id
        } catch { self.error = error.localizedDescription }
    }
    func edit(expected: UUID? = nil, working: BookmarkTree? = nil, _ action: (inout BookmarkTree) throws -> Void) async {
        guard !busy, var profile, profile.pendingJob == nil, review == nil,
              expected == nil || expected == profile.id, working == nil || working == profile.working else { error = GalmuriError.staleSource.localizedDescription; return }
        busy = true; defer { finish() }
        error = nil; notice = nil
        do {
            let before = profile.working
            try profile.edit(action)
            guard profile.working != before else { return }
            try await change(profile)
            undo[profile.id, default: []].append(before)
            undo[profile.id] = undo[profile.id].map { Array($0.suffix(100)) }
        } catch { self.error = error.localizedDescription }
    }
    func undoEdit() async {
        guard let profile, let previous = undo[profile.id]?.last else { return }
        // edit skips identical trees without pushing, so removeLast(2) below would underflow.
        if previous == profile.working { undo[profile.id]?.removeLast(); return }
        await edit(expected: profile.id) { $0 = previous }; if error == nil { undo[profile.id]?.removeLast(2) }
    }
    private func endpoint(_ profile: APIWorkingCopy) throws -> APIEnvelope {
        let matches = sources.filter { $0.session.installationID == profile.installationID }
        guard matches.count == 1, let value = matches.first, try proof.approved(value.session) else { throw GalmuriError.invalid("API connection missing or ambiguous") }
        return value
    }
    func requestStop() async {
        guard busy else { return }
        stopping = true; notice = "api.stopping"
        guard let job = activeJob, job.command == "apply" else { return }
        do { let store = store; try await Task.detached { try store.requestStop(job) }.value }
        catch { self.error = error.localizedDescription }
    }
    private func perform(_ job: APIJob) async throws -> (APIJobResult, APIEnvelope) {
        let store = store, session = try selfProof(job)
        activeJob = job; defer { activeJob = nil }
        do {
            if stopping { throw CancellationError() }
            try await Task.detached { try store.queue(job) }.value
            for _ in 0..<120 {
                try Task.checkCancellation()
                if stopping && job.command != "apply" { throw CancellationError() }
                if let result = try? await Task.detached(operation: { try store.get(APIJobResult.self, name: job.id.uuidString + ".result") }).value {
                    // Snapshot/adopt files are not recovery state; apply files stay until the apply is settled.
                    if job.command != "apply" { await removeJobFiles(job.id) }
                    guard result.jobID == job.id else { throw GalmuriError.staleSource }
                    let envelope = try await Task.detached { try store.envelope(session) }.value
                    return (result, envelope)
                }
                try await Task.sleep(for: .milliseconds(500))
            }
            throw GalmuriError.invalid("API response timed out; inspect interrupted operation")
        } catch {
            if job.command == "apply" { try await Task.detached { try store.requestStop(job) }.value }
            else { await removeJobFiles(job.id) }
            throw error
        }
    }
    // The envelope must remain bound to the full approved session, not a guessed profile label.
    private func selfProof(_ job: APIJob) throws -> BridgeProof {
        guard let session = sources.first(where: { $0.session.id == job.sessionID })?.session else { throw GalmuriError.staleSource }
        return session
    }
    func prepare(restore: Bool = false) async {
        guard !busy, let profile, profile.pendingJob == nil else { return }
        busy = true; stopping = false; error = nil; notice = nil; defer { finish() }
        do {
            let endpoint = try endpoint(profile)
            let (result, fresh) = try await perform(.refresh(endpoint.session))
            guard result.state == "succeeded" else { throw GalmuriError.staleSource }
            let prepared = try await Task.detached { try APIReview.prepareData(profile: profile, envelope: fresh, restore: restore) }.value
            try Task.checkCancellation()
            if stopping { throw CancellationError() }
            review = try APIReview(profile: profile, envelope: fresh, restore: restore, prepared: prepared)
        } catch is CancellationError { notice = "api.stopped" }
        catch { self.error = error.localizedDescription }
    }
    func resolve(_ id: String, side: MergeSide) async {
        guard !busy, let review else { return }
        busy = true; defer { finish() }
        do {
            review.resolutions[id] = side; review.acknowledged = false
            let base = review.mergeBase, ours = review.ours, theirs = review.theirs, choices = review.resolutions
            let result = try await Task.detached { try MergeEngine.merge(base: base, ours: ours, theirs: theirs, resolutions: choices) }.value
            guard self.review === review else { throw GalmuriError.staleSource }
            review.result = result
        } catch { self.error = error.localizedDescription }
    }
    func accept(localOnly: Bool = false) async {
        guard !busy, let review, review.acknowledged, review.result.unresolved.isEmpty,
              var profile, profile.id == review.profile.id, profile.base == review.profile.base,
              profile.working == review.profile.working, profile.pendingJob == nil else { return }
        busy = true; stopping = false; error = nil; notice = nil; defer { finish() }
        do {
            let endpoint = try endpoint(profile)
            guard endpoint.session == review.envelope.session else { throw GalmuriError.staleSource }
            if localOnly || review.result.tree == review.theirs {
                let (result, fresh) = try await perform(.refresh(endpoint.session))
                guard result.state == "succeeded", fresh.raw == review.envelope.raw else { throw GalmuriError.staleSource }
                try store.put(profile, name: UUID().uuidString + ".archive")
                profile.base = review.theirs; profile.working = review.result.tree; profile.mapping = review.mapping
                try await change(profile); self.review = nil; undo[profile.id] = []; return
            }
            // The host withholds apply jobs with under 90 s left; refuse before recovery files or pendingJob exist.
            guard endpoint.session.expires.timeIntervalSinceNow >= 120 else { throw GalmuriError.invalid("API connection expires soon; reconnect in Chrome and review again") }
            var staged = profile; staged.mapping = review.mapping
            var job = try staged.job(envelope: review.envelope, target: review.result.tree)
            job.owner = try APIOwner.read()
            let archives = store, before = profile, source = review.envelope, jobID = job.id
            try await Task.detached {
                try archives.put(before, name: jobID.uuidString + ".before")
                try archives.put(source, name: jobID.uuidString + ".source")
            }.value
            guard self.review === review, review.acknowledged else { throw GalmuriError.staleSource }
            try Task.checkCancellation()
            if stopping { throw CancellationError() }
            staged.pendingJob = job.id; try await change(staged)
            let (result, fresh) = try await perform(job)
            if result.state == "stopped" { notice = "api.stopped"; self.review = nil; return }
            guard result.state == "succeeded", let mapping = result.mapping else { throw GalmuriError.invalid("API partially applied or uncertain; adopt Chrome state before retry") }
            var inverse = Dictionary(uniqueKeysWithValues: staged.mapping.map { ($0.value, $0.key) })
            for (key, apiID) in mapping {
                guard review.result.tree.nodes[key] != nil, (inverse[key] == nil || inverse[key] == apiID), staged.mapping[apiID] == nil || staged.mapping[apiID] == key else { throw GalmuriError.invalid("API returned identity map") }
                staged.mapping[apiID] = key; inverse[key] = apiID
            }
            if let recovery = result.recovery { staged.recoveryIDs.insert(recovery) }
            let after = try fresh.snapshot.tree(scope: staged.scope, mapping: &staged.mapping, excluding: staged.recoveryIDs)
            guard after == review.result.tree else { throw GalmuriError.invalid("API final snapshot mismatch") }
            staged.history.append(APICheckpoint(id: job.id, before: review.theirs, after: after))
            staged.history = Array(staged.history.suffix(1)); staged.base = after; staged.working = after; staged.pendingJob = nil
            try await change(staged); self.review = nil; undo[staged.id] = []; notice = "api.applied"
            await removeJobFiles(job.id)
        } catch is CancellationError { notice = "api.stopped"; self.review = nil }
        catch { self.error = error.localizedDescription; self.review = nil }
    }
    // Best effort once the job is cleared; .archive/.interrupted copies carry their own UUIDs and are kept.
    private func removeJobFiles(_ job: UUID) async {
        let store = store, prefix = job.uuidString + "."
        await Task.detached {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []
            for name in names where name.hasPrefix(prefix) && name.hasSuffix(".json") { try? store.remove(name: String(name.dropLast(5))) }
        }.value
    }
    func prepareAdoption() async {
        guard !busy, let profile, profile.pendingJob != nil else { return }
        busy = true; stopping = false; error = nil; defer { finish() }
        do {
            let endpoint = try endpoint(profile)
            let (result, fresh) = try await perform(.refresh(endpoint.session))
            guard result.state == "succeeded" else { throw GalmuriError.staleSource }
            adoption = try APIAdoption(profile: profile, envelope: fresh); adoptionAcknowledged = false
        } catch { self.error = error.localizedDescription }
    }
    func adopt() async {
        guard !busy, var profile, let adoption, adoptionAcknowledged, profile.id == adoption.profile.id,
              profile.pendingJob == adoption.profile.pendingJob, profile.working == adoption.profile.working, profile.base == adoption.profile.base else { return }
        busy = true; stopping = false; error = nil; defer { finish() }
        do {
            let endpoint = try endpoint(profile)
            guard endpoint.session == adoption.envelope.session else { throw GalmuriError.staleSource }
            let fresh = adoption.envelope
            try store.put(profile, name: UUID().uuidString + ".interrupted")
            let job = APIJob.adopt(fresh), stale = profile.pendingJob
            let (result, confirmed) = try await perform(job)
            guard result.state == "succeeded", confirmed.raw == fresh.raw else { throw GalmuriError.staleSource }
            profile.recoveryIDs = adoption.recoveryIDs; profile.mapping = adoption.mapping
            profile.base = adoption.tree
            profile.working = profile.base; profile.pendingJob = nil; try await change(profile)
            undo[profile.id] = []; notice = "api.adopted"; self.adoption = nil
            if let stale { await removeJobFiles(stale) }
        } catch { self.error = error.localizedDescription }
    }
}
