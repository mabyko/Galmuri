import AppKit
import UniformTypeIdentifiers
import GalmuriCore

@MainActor
enum LocalSmokeTest {
    static func run(store: AppStore) async throws {
        if AppArguments.apiSmoke { try await APIEndToEnd.run(store: store); return }
        if AppArguments.onboardingSmoke {
            try await Task.sleep(for: .milliseconds(700))
            guard store.workspace.profiles.isEmpty, store.selectedProfileID == nil,
                  !FileManager.default.fileExists(atPath: store.testRoot.path),
                  try Workspace.load(from: store.workspaceURL).profiles.isEmpty,
                  NSApp.windows.contains(where: { $0.isVisible && $0.contentView != nil }),
                  L("profile.welcomeTitle") != "profile.welcomeTitle" else {
                throw GalmuriError.invalid("empty onboarding or native resources")
            }
            let evidence: [String: Any] = ["passed": true, "bundlePath": Bundle.main.bundleURL.path,
                "checks": ["visible native welcome", "localized welcome", "empty workspace v1", "no synthetic profiles generated"]]
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
                .write(to: store.directory.appendingPathComponent("smoke-result.json"))
            return
        }
        guard store.workspace.profiles.count == 1, let profile = store.profile,
              store.coordinator.canWrite(profile.source), !profile.hasChanges,
              store.backups.isEmpty, store.error == nil else { throw GalmuriError.localTestsOnly }
        try await Task.sleep(for: .milliseconds(700))
        guard NSApp.windows.contains(where: { $0.isVisible && $0.contentView != nil }),
              UTType.galmuriBookmarkMove.conforms(to: .data),
              L("profile.connect") != "profile.connect",
              Bundle.main.url(forResource: "Galmuri-Chrome-Extension", withExtension: "zip") != nil,
              let icon = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
              Bundle.main.url(forResource: icon, withExtension: nil) != nil || Bundle.main.url(forResource: icon, withExtension: "icns") != nil,
              let parent = profile.working.roots["bookmark_bar"] else { throw GalmuriError.invalid("native resources or window") }
        let before = try Data(contentsOf: profile.source)
        guard !store.labs.apiEnabled, !store.labs.fileEnabled,
              store.setLabOptions(api: true, file: true),
              try LabOptions.load(from: store.labsURL).apiEnabled,
              try LabOptions.load(from: store.labsURL).fileEnabled,
              store.setLabOptions(api: false, file: false) else { throw GalmuriError.invalid("persistent default-off Labs options") }
        var added = ""
        guard store.edit({ added = try $0.add(name: "Release smoke · 갈무리", url: "https://example.com/release-smoke", to: parent) }),
              try Workspace.load(from: store.workspaceURL).profiles.first?.working.nodes[added] != nil else {
            throw GalmuriError.invalid("native working-copy persistence")
        }
        store.undo()
        guard store.tree == profile.working, try Data(contentsOf: profile.source) == before else {
            throw GalmuriError.invalid("native undo or source preservation")
        }
        guard let item = profile.working.nodes.values.first(where: { $0.url != nil }),
              let deletion = store.deletionRequest(for: [item.id]), !deletion.requiresConfirmation,
              store.delete(deletion), store.tree?.nodes[item.id] == nil,
              try Workspace.load(from: store.workspaceURL).profiles.first?.working.nodes[item.id] == nil else {
            throw GalmuriError.invalid("native deletion persistence")
        }
        store.navigation = "changes"
        store.selection = [item.id]
        guard store.rows.count == store.pendingCount,
              store.rows.contains(where: { $0.id == item.id }), !store.canMutateSelection else {
            throw GalmuriError.invalid("pending removal visibility")
        }
        let deletedTree = store.tree
        store.showPendingReview()
        try await Task.sleep(for: .milliseconds(350))
        guard store.pendingReview?.base.tree.nodes[item.id] != nil,
              store.pendingReview?.working.nodes[item.id] == nil,
              store.pendingReview?.changedIDs.count == store.pendingCount,
              NSApp.windows.contains(where: { $0.attachedSheet != nil }) else { throw GalmuriError.invalid("pending review native presentation") }
        store.pendingReview = nil
        try await Task.sleep(for: .milliseconds(350))
        guard store.tree == deletedTree else { throw GalmuriError.invalid("pending preview mutated work") }
        store.showConnectionDetails()
        try await Task.sleep(for: .milliseconds(350))
        guard store.connectionDetails?.id == profile.id,
              NSApp.windows.contains(where: { $0.attachedSheet != nil }) else {
            throw GalmuriError.invalid("native connection details presentation")
        }
        store.connectionDetails = nil
        try await Task.sleep(for: .milliseconds(350))
        guard !NSApp.windows.contains(where: { $0.attachedSheet != nil }),
              store.tree == deletedTree, try Data(contentsOf: profile.source) == before else {
            throw GalmuriError.invalid("native connection details dismissal or source preservation")
        }
        store.navigation = "all"
        store.undo()
        guard store.tree == profile.working, try Data(contentsOf: profile.source) == before else {
            throw GalmuriError.invalid("native deletion undo or source preservation")
        }
        guard store.edit({ try $0.edit(item.id, name: "Pending after reopen", url: item.url) }) else {
            throw GalmuriError.invalid("pending reset smoke fixture")
        }
        let pendingTree = store.tree
        let reopened = AppStore(sampleData: true, directory: store.directory)
        guard !reopened.canUndo, reopened.pendingCount > 0, let reset = reopened.resetRequest(),
              reopened.resetWorkingCopy(reset), reopened.tree == profile.base.tree,
              try Workspace.load(from: store.workspaceURL).profiles.first?.working == profile.base.tree else {
            throw GalmuriError.invalid("reopened working-copy reset")
        }
        reopened.undo()
        guard reopened.tree == pendingTree, let cleanupReset = store.resetRequest(),
              store.resetWorkingCopy(cleanupReset), store.tree == profile.working,
              try Data(contentsOf: profile.source) == before else {
            throw GalmuriError.invalid("discard undo or source preservation")
        }
        let feature = AppStore(sampleData: true, directory: store.directory.appendingPathComponent("FeatureSmoke"))
        guard feature.workspace.profiles.count == 1, let fp = feature.profile,
              feature.coordinator.canWrite(fp.source), !fp.hasChanges else { throw GalmuriError.localTestsOnly }
        let link = fp.working.nodes.values.first { $0.url != nil }!
        guard feature.edit({ try $0.edit(link.id, name: "Local smoke edit", url: link.url) }) else { throw GalmuriError.invalid("feature smoke edit") }
        var theirs = fp.base.tree
        try theirs.edit(link.id, name: "Source smoke edit", url: link.url)
        try fp.base.serialize(theirs).write(to: fp.source, options: .atomic)
        let originalSource = try Data(contentsOf: fp.source)
        await feature.refreshProfile()
        guard let refresh = feature.review, refresh.result?.unresolved.isEmpty == false else { throw GalmuriError.invalid("refresh smoke conflict") }
        for conflict in refresh.result!.conflicts { feature.resolve(conflict.id, side: .ours, in: refresh) }
        refresh.acknowledged = true; await feature.acceptRefresh(refresh)
        guard refresh.phase == .complete, refresh.localArchive != nil,
              feature.tree?.nodes[link.id]?.name == "Local smoke edit" else { throw GalmuriError.invalid("refresh smoke acceptance") }
        feature.review = nil
        guard let selective = feature.revertRequest(for: [link.id]), feature.resetWorkingCopy(selective),
              feature.tree?.nodes[link.id]?.name == "Source smoke edit" else { throw GalmuriError.invalid("selective revert smoke") }
        feature.undo()
        var opened = false
        feature.openBookmark(link.id) { _ in opened = true; return true }
        guard opened, let archive = feature.removeProfile(ProfileRemoval(profile: feature.profile!)),
              try Workspace.load(from: archive).profiles.count == 1, feature.workspace.profiles.isEmpty,
              try Data(contentsOf: fp.source) == originalSource else { throw GalmuriError.invalid("profile management smoke") }
        let evidence: [String: Any] = ["passed": true, "bundlePath": Bundle.main.bundleURL.path,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "", "configuration": Bundle.main.object(forInfoDictionaryKey: "GalmuriBuildConfiguration") ?? "",
            "checks": ["visible native window", "localized resource", "app icon", "matched extension archive", "persistent default-off Labs options", "pending deletion review", "persistent edit", "undo", "persistent deletion", "pending removal visibility", "native connection details presentation and dismissal", "deletion undo", "reopened pending changes", "discard to saved source", "discard undo", "refresh merge and archive", "selected revert", "profile removal and archive", "injected bookmark opening", "original unchanged"]]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: store.directory.appendingPathComponent("smoke-result.json"))
    }
}
