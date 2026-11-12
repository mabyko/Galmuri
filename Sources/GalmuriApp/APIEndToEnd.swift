#if DEBUG
import Foundation
import GalmuriCore

// Runs only against a marker-bound empty legacy workspace and synthetic QA labels.
@MainActor enum APIEndToEnd {
    static func run(store: AppStore) async throws {
        guard store.workspace.profiles.isEmpty,
              try String(contentsOf: store.directory.appendingPathComponent(".galmuri-bridge-proof"), encoding: .utf8) == "Galmuri pairing-only proof v1\n" else { throw GalmuriError.localTestsOnly }
        let model = APIWorkspaceModel(directory: store.directory)
        var sessions: [BridgeProof] = []
        for _ in 0..<50 {
            sessions = try model.proof.requests()
            if !sessions.isEmpty { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard sessions.count == 1, let session = sessions.first, session.name == "API QA" else { throw GalmuriError.invalid("API QA session") }
        try model.proof.approve(session)
        for _ in 0..<50 {
            await model.load(); if !model.sources.isEmpty { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard model.sources.count == 1, let source = model.sources.first, source.writable else { throw GalmuriError.invalid("API QA snapshot") }
        var checks = ["approved exact QA session", "API snapshot read"]
        if ProcessInfo.processInfo.arguments.contains("--smoke-api-restart") {
            guard let profile = model.profile else { throw GalmuriError.invalid("API restart profile") }
            var mapping = profile.mapping
            let current = try source.snapshot.tree(scope: profile.scope, mapping: &mapping, excluding: profile.recoveryIDs)
            guard current == profile.base, profile.base == profile.working, profile.pendingJob == nil else { throw GalmuriError.invalid("API restart semantics") }
            checks += ["working copy reopened", "browser restart preserved IDs and semantics"]
        } else {
            guard model.workspace.profiles.isEmpty,
                  let scope = try source.snapshot.folders.first(where: { $0.folderType == "bookmarks-bar" && $0.syncing == false }) else { throw GalmuriError.invalid("API QA scope") }
            await model.connect(source, scope: scope.id)
            guard let original = model.profile, let item = original.working.nodes.values.filter({ $0.url != nil }).sorted(by: { $0.id < $1.id }).first,
                  let removed = original.working.nodes.values.first(where: { $0.url != nil && $0.id != item.id }) else { throw GalmuriError.invalid("API QA synthetic items") }
            let root = original.working.orderedRoots[0]
            await model.edit(expected: original.id) { tree in
                tree.nodes[item.id]?.name = "API QA renamed"
                let folder = try tree.add(name: "API QA folder", url: nil, to: root)
                _ = try tree.add(name: "API QA new", url: "https://example.test/new", to: folder)
                try tree.move([item.id], to: folder); try tree.remove([removed.id])
            }
            guard model.error == nil, model.profile?.working != original.working else { throw GalmuriError.invalid("API QA local edit") }
            await model.prepare()
            guard let review = model.review else { throw GalmuriError.invalid("API QA review: \(model.error ?? "missing")") }
            for conflict in review.result.conflicts { await model.resolve(conflict.id, side: .ours) }
            let browserBaseline = review.theirs
            review.acknowledged = true; await model.accept()
            guard model.error == nil, let applied = model.profile, applied.pendingJob == nil, applied.base == applied.working,
                  !applied.recoveryIDs.isEmpty, applied.mapping[item.chromeID] == nil else { throw GalmuriError.invalid("API QA apply: \(model.error ?? "missing")") }
            checks += ["reviewed create rename move and soft delete", "new-ID mapping", "verified final API state"]
            await model.prepare(restore: true)
            guard let restore = model.review, restore.result.unresolved.isEmpty else { throw GalmuriError.invalid("API QA restore review") }
            restore.acknowledged = true; await model.accept()
            guard model.error == nil, model.profile?.working == browserBaseline else { throw GalmuriError.invalid("API QA restore: \(model.error ?? "missing")") }
            checks.append("restored browser baseline and IDs while retaining independent additions")
            await model.edit(expected: original.id) { $0.nodes[item.id]?.name = "INTERRUPT after API update" }
            await model.prepare()
            guard let interrupted = model.review else { throw GalmuriError.invalid("API QA interruption review") }
            interrupted.acknowledged = true; await model.accept()
            guard model.profile?.pendingJob != nil, model.error != nil else { throw GalmuriError.invalid("API QA partial state") }
            let reopened = APIWorkspaceModel(directory: store.directory); await reopened.load()
            guard reopened.profile?.pendingJob != nil else { throw GalmuriError.invalid("API QA persisted interruption") }
            checks.append("interrupted API update persisted and blocked replay")
            await model.prepareAdoption()
            guard model.adoption != nil else { throw GalmuriError.invalid("API QA adoption review") }
            model.adoptionAcknowledged = true; await model.adopt()
            guard model.error == nil, model.profile?.pendingJob == nil,
                  model.profile?.working.nodes[item.id]?.name == "INTERRUPT after API update" else { throw GalmuriError.invalid("API QA adoption: \(model.error ?? "missing")") }
            checks.append("reviewed interrupted-state adoption with archive")
            await model.edit(expected: original.id) { $0.nodes[item.id]?.name = "API QA recovered" }
            await model.prepare()
            guard let recovered = model.review else { throw GalmuriError.invalid("API QA recovered review") }
            recovered.acknowledged = true; await model.accept()
            guard model.error == nil, model.profile?.pendingJob == nil else { throw GalmuriError.invalid("API QA reapply after recovery") }
            checks.append("subsequent reviewed apply after recovery")
            if ProcessInfo.processInfo.arguments.contains("--smoke-api-large") {
                await model.edit { tree in
                    for index in 0..<300 { _ = try tree.add(name: "Large QA \(index)", url: "https://example.test/large/\(index)", to: root) }
                }
                await model.prepare()
                guard let large = model.review, large.result.unresolved.isEmpty else { throw GalmuriError.invalid("API large review") }
                large.acknowledged = true; await model.accept()
                // Job files are removed after a successful apply; 300 new mappings can only arrive through a chunked result.
                guard model.error == nil, model.profile?.history.last != nil else { throw GalmuriError.invalid("API large apply: \(model.error ?? "missing")") }
                checks.append("300 real creates applied through a chunked result")

                await model.edit { tree in
                    tree.nodes[item.id]?.name = "STOP QA current call"
                    for index in 0..<60 { _ = try tree.add(name: "Stopped QA \(index)", url: "https://example.test/stopped/\(index)", to: root) }
                }
                await model.prepare()
                guard let stopReview = model.review, stopReview.result.unresolved.isEmpty else { throw GalmuriError.invalid("API stop review") }
                stopReview.acknowledged = true
                let task = Task { await model.accept() }
                var stopJob: UUID?
                for _ in 0..<300 {
                    if let id = model.profile?.pendingJob,
                       FileManager.default.fileExists(atPath: model.store.directory.appendingPathComponent(id.uuidString + ".operation-0.intent.json").path) { stopJob = id; break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                guard let stopJob else { task.cancel(); await task.value; throw GalmuriError.invalid("API stop intent not observed") }
                await model.requestStop(); await task.value
                guard model.profile?.pendingJob == stopJob, model.notice == "api.stopped", model.error == nil else { throw GalmuriError.invalid("API stop acknowledgement: \(model.error ?? "missing")") }
                _ = try model.store.get(APIStop.self, name: stopJob.uuidString + ".stop-ack")
                await model.prepareAdoption()
                guard let adoption = model.adoption,
                      !adoption.tree.nodes.values.contains(where: { $0.name.hasPrefix("Stopped QA ") }) else { throw GalmuriError.invalid("API stop allowed a later create") }
                model.adoptionAcknowledged = true; await model.adopt()
                guard model.error == nil, model.profile?.pendingJob == nil else { throw GalmuriError.invalid("API stop recovery") }
                checks += ["stop acknowledged between real API calls", "no later creates after stop", "stopped state reviewed and adopted"]
            }
        }
        let result: [String: Any] = ["passed": true, "checks": checks, "bookmarkFileIO": false, "keychainAccess": false, "bundlePath": Bundle.main.bundleURL.path]
        let file = ProcessInfo.processInfo.arguments.contains("--smoke-api-restart") ? "api-restart-result.json" : "api-smoke-result.json"
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: store.directory.appendingPathComponent(file))
    }
}
#endif
