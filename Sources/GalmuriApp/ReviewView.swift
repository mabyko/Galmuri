import SwiftUI
import GalmuriCore

struct ReviewView: View {
    @Bindable var store: AppStore
    @Bindable var session: ReviewSession
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var headingFocused: Bool
    private var profile: ConnectedProfile? { store.workspace.profiles.first { $0.id == session.profileID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L(session.mode == .refresh ? "refresh.title" : "review.title")).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: " / \(profile?.name ?? "")").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("common.close") { dismiss() }.buttonStyle(.borderless).keyboardShortcut(.cancelAction).disabled(store.busy)
            }
            if store.error != nil { AppErrorNotice(store: store) }
            switch session.phase {
            case .exit:
                if session.mode == .refresh {
                    Text("refresh.stale").fixedSize(horizontal: false, vertical: true)
                    Button("refresh.retry") { store.review = nil; Task { await store.refreshProfile() } }
                } else { exitContent }
            case .conflicts: conflictContent
            case .final: finalContent
            case .complete:
                if session.mode == .refresh {
                    Text("refresh.complete").font(.title2.bold())
                    Text("refresh.completeHelp").fixedSize(horizontal: false, vertical: true)
                    if let archive = session.localArchive { Text(verbatim: archive.path).font(.caption).textSelection(.enabled) }
                    Button("common.done") { dismiss() }.keyboardShortcut(.defaultAction)
                } else { completeContent }
            }
        }.padding(28).frame(minWidth: 780, idealWidth: 860, minHeight: 680, idealHeight: 740)
        .interactiveDismissDisabled(store.busy)
        .onAppear { headingFocused = true }
        .onChange(of: session.phase) { headingFocused = true }
    }

    private var exitContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "macwindow").font(.system(size: 38)).foregroundStyle(.secondary)
            Text("apply.quit.title").font(.title.bold()).accessibilityFocused($headingFocused)
            Text("apply.quit.help").foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(profile?.name ?? "")
                    if let profile { Text(profile.source.path).font(.caption).textSelection(.enabled) }
                    Text(localizedCount("editor.changeCount", profile?.changedIDs.count ?? 0))
                    if profile.map({ store.coordinator.canWrite($0.source) }) == true { Text("profile.localTestHelp").font(.callout).foregroundStyle(.secondary) }
                    else { Text("profile.connectedReadOnly").font(.callout).foregroundStyle(.orange) }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            HStack { Button("common.cancel", role: .cancel) { dismiss() }.disabled(store.busy); Spacer(); Button("apply.recheckExit") { Task { await store.loadReview(session) } }.buttonStyle(.borderedProminent).disabled(store.busy) }
        }
    }

    private var conflictContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("conflict.title").font(.title.bold()).accessibilityFocused($headingFocused)
            Text(L(session.mode == .refresh ? "refresh.conflictHelp" : "conflict.explanation")).foregroundStyle(.secondary)
            if let result = session.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if result.conflicts.isEmpty { Label("conflict.none", systemImage: "checkmark.circle").foregroundStyle(AppTheme.accent).padding(20) }
                        ForEach(result.conflicts) { conflict in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(conflict.item).font(.headline)
                                    Text(conflict.id.contains(".metadata.") ? conflict.field : L(conflict.field)).font(.caption).foregroundStyle(.orange)
                                    Text(L(session.mode == .refresh ? "refresh.base" : "conflict.base")).font(.caption).foregroundStyle(.secondary)
                                    if let tree = profile?.base.tree { conflictDetails(conflict, tree: tree, value: conflict.base, isOriginal: true) }
                                    HStack(alignment: .top, spacing: 12) {
                                        choice(conflict, side: .ours, title: "conflict.ours", tree: profile?.working)
                                        choice(conflict, side: .theirs, title: session.mode == .refresh ? "refresh.theirs" : "conflict.theirs", tree: session.latest?.tree)
                                    }
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                HStack {
                    // A refresh has no exit step; Back closes it instead of showing the stale-source notice.
                    Button("common.back") { if session.mode == .refresh { dismiss() } else { session.phase = .exit } }
                    Spacer()
                    if !result.unresolved.isEmpty { Text(localizedCount("conflict.remainingCount", result.unresolved.count)).foregroundStyle(.orange) }
                    Button("common.continue") { session.phase = .final; session.acknowledged = false }.buttonStyle(.borderedProminent).disabled(!result.unresolved.isEmpty)
                }
            }
        }
    }

    private func choice(_ conflict: MergeConflict, side: MergeSide, title: String, tree: BookmarkTree?) -> some View {
        let selected = session.resolutions[conflict.id] == side
        return VStack(alignment: .leading, spacing: 12) {
            Button { Task { await store.resolve(conflict.id, side: side, in: session) } } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle").accessibilityHidden(true)
                    Text(L(title)).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(store.busy).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(L(selected ? "conflict.selected" : "conflict.notSelected"))
            if conflict.id.hasSuffix(".order") {
                Text(verbatim: side == .ours ? conflict.ours : conflict.theirs)
                    .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if let tree { conflictDetails(conflict, tree: tree, value: side == .ours ? conflict.ours : conflict.theirs) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(selected ? Color.blue.opacity(0.13) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.blue : Color.secondary.opacity(0.3)))
    }

    @ViewBuilder
    private func conflictDetails(_ conflict: MergeConflict, tree: BookmarkTree, value: String, isOriginal: Bool = false) -> some View {
        let id = String(conflict.id.prefix { $0 != "." })
        if conflict.id == "structure.moves" {
            Text(localizedMovePaths(value, existingPaths: Set(tree.nodes.keys.map { tree.path(to: $0) }))).font(.caption).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else if tree.nodes[id] != nil {
            BookmarkSnapshot(tree: tree, id: id, includesDescendants: conflict.id.hasSuffix(".subtree") || conflict.id.hasSuffix(".existence"))
            if let keyRange = conflict.id.range(of: ".metadata.") {
                let key = String(conflict.id[keyRange.upperBound...])
                Text(verbatim: key + ": " + (tree.nodes[id]?.metadata[key]?.display ?? L("review.notPresent")))
                    .font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        } else if isOriginal {
            Text("review.notPresent").font(.caption).foregroundStyle(.secondary)
        } else {
            Label("conflict.removeItem", systemImage: "minus.circle").foregroundStyle(.orange)
            if let base = profile?.base.tree {
                let impacted = base.descendants(of: id)
                    .union(profile?.working.descendants(of: id) ?? [])
                    .union(session.latest?.tree.descendants(of: id) ?? [])
                Text(localizedCount("review.removalCount", impacted.count)).font(.caption)
                BookmarkSnapshot(tree: base, id: id, includesDescendants: true)
            }
        }
    }

    private var finalContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L(session.mode == .refresh ? "refresh.finalTitle" : "review.finalTitle")).font(.title.bold()).accessibilityFocused($headingFocused)
            ScrollView {
                if let latest = session.latest, let result = session.result {
                    if session.mode == .refresh, session.workingAtReview == result.tree {
                        Text("refresh.noWorkingChanges").foregroundStyle(.secondary)
                    } else {
                        ChangeReviewList(before: session.mode == .refresh ? (session.workingAtReview ?? latest.tree) : latest.tree, after: result.tree)
                    }
                }
            }
            Label(L(session.mode == .refresh ? "refresh.reviewHelp" : "review.backupExplanation"), systemImage: "shield.lefthalf.filled").font(.caption).foregroundStyle(.secondary)
            Toggle(L(session.mode == .refresh ? "refresh.acknowledge" : "review.acknowledge"), isOn: $session.acknowledged)
            if session.mode == .apply, profile.map({ !store.coordinator.canWrite($0.source) }) == true { Text("profile.connectedReadOnly").font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("common.back") { session.phase = .conflicts }; Spacer()
                if session.mode == .refresh {
                    Button("refresh.accept") { Task { await store.acceptRefresh(session) } }.buttonStyle(.borderedProminent)
                        .disabled(!session.acknowledged || session.result?.unresolved.isEmpty != true)
                } else {
                Button("apply.backupAndApply") { Task { await store.apply(session) } }.buttonStyle(.borderedProminent)
                    .disabled(store.busy || !store.labs.fileEnabled || !session.acknowledged || session.result?.unresolved.isEmpty != true || profile.map({ !store.coordinator.canWrite($0.source) || $0.sourceRestriction != nil || session.latest?.writeRestriction != nil }) != false)
                }
            }
        }
    }

    private var completeContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "checkmark.circle").font(.system(size: 42)).foregroundStyle(AppTheme.accent)
            Text("result.fileVerified").font(.title.bold()).accessibilityFocused($headingFocused)
            Text("result.localTestOnly").foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 15) {
                    Label("result.fileVerified", systemImage: "checkmark")
                    Label("result.restartPending", systemImage: "clock").foregroundStyle(.orange)
                    Label("result.syncPending", systemImage: "clock").foregroundStyle(.orange)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            if let receipt = session.receipt {
                Text(receipt.date.formatted()).font(.caption).foregroundStyle(.secondary)
                Text("backup.originalPath").font(.caption).foregroundStyle(.secondary)
                Text(receipt.backup.path).font(.caption).textSelection(.enabled)
            }
            Spacer()
            HStack { Button("sidebar.backups") { store.navigation = "backups"; dismiss() }; Spacer(); Button("common.done") { dismiss() }.buttonStyle(.borderedProminent) }
        }
    }
}

struct RestoreRequest: Identifiable {
    let id = UUID()
    let receipt: BackupReceipt
    let currentHash: String
    let currentIdentity: ApplySourceIdentity
    let current: BookmarkTree
    let backup: BookmarkTree
}

struct BackupsView: View {
    @Bindable var store: AppStore
    @State private var restore: RestoreRequest?
    @State private var preparing: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("sidebar.backups").font(.largeTitle.bold())
            Text("backup.explanation").foregroundStyle(.secondary)
            if store.unreadableBackupCount > 0 { Text("backup.unreadable").font(.callout).foregroundStyle(.orange) }
            List(store.backups) { receipt in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(receipt.profileName).font(.headline)
                        Text(receipt.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        Text(receipt.source.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(L(receipt.state == "fileVerified" ? "result.fileVerified" : "backup.prepared")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("backup.reviewRestore") { prepare(receipt) }.disabled(!store.labs.fileEnabled)
                }.padding(.vertical, 8)
            }.overlay { if store.backups.isEmpty { ContentUnavailableView(L("backup.empty"), systemImage: "clock") } }
            if let message = store.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.padding(28)
        .sheet(item: $restore) { request in
            VStack(alignment: .leading, spacing: 18) {
                Text("backup.reviewRestore").font(.title2.bold())
                Text("backup.restoreWarning").foregroundStyle(.orange)
                Text(request.receipt.profileName).font(.headline)
                Text(request.receipt.source.path).font(.caption).textSelection(.enabled)
                if store.error != nil { AppErrorNotice(store: store) }
                ScrollView { ChangeReviewList(before: request.current, after: request.backup) }
                Text("backup.currentPreserved").font(.caption).foregroundStyle(.secondary)
                HStack { Button("common.cancel", role: .cancel) { restore = nil }.keyboardShortcut(.cancelAction).disabled(store.busy); Spacer(); Button("backup.backupCurrentAndRestore") { Task { store.error = nil; if await store.restore(request.receipt, expectedHash: request.currentHash, expectedIdentity: request.currentIdentity) { restore = nil } } }.buttonStyle(.borderedProminent).disabled(store.busy) }
            }.padding(25).frame(minWidth: 700, idealWidth: 780, minHeight: 580, idealHeight: 680)
            .interactiveDismissDisabled(store.busy)
        }
    }

    private func prepare(_ receipt: BackupReceipt) {
        let token = UUID(), coordinator = store.coordinator
        preparing = token
        Task {
            do {
                let request = try await Task.detached { () throws -> RestoreRequest in
                    let reviewed = try coordinator.readForReview(receipt.source)
                    let current = reviewed.file
                    let backup = try BookmarkFile(data: Data(contentsOf: receipt.backup))
                    guard BookmarkFile.hash(backup.original) == receipt.beforeHash else { throw GalmuriError.missingBackup }
                    return RestoreRequest(receipt: receipt, currentHash: current.fingerprint, currentIdentity: reviewed.identity, current: current.tree, backup: backup.tree)
                }.value
                guard preparing == token else { return }
                restore = request
            } catch {
                guard preparing == token else { return }
                store.error = error.localizedDescription
            }
        }
    }
}
