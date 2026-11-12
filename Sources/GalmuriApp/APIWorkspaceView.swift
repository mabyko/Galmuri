import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GalmuriCore

struct APIWorkspaceView: View {
    @State private var model: APIWorkspaceModel
    @State private var connection: UUID?
    @State private var exportMessage: String?
    @State private var scope = ""
    @State private var selection = Set<String>()
    @State private var back = [String?]()
    @State private var forward = [String?]()
    @State private var drag: BookmarkDrag?
    @State private var folder: String?
    @State private var search = ""
    @State private var editor: APIEditorRequest?
    @State private var move = false
    @State private var destination = ""
    @State private var deletion: APIEditorRequest?
    @State private var moveCapture: APIEditorRequest?
    @Environment(\.dismiss) private var dismiss
    init(directory: URL) { _model = State(initialValue: APIWorkspaceModel(directory: directory)) }
    init(model: APIWorkspaceModel) { _model = State(initialValue: model) }
    private var tree: BookmarkTree? { model.profile?.working }
    private var rows: [Bookmark] { tree.map { APIEditorListing.rows(tree: $0, folder: folder, query: search) } ?? [] }
    private var chosen: Bookmark? { selection.count == 1 ? selection.first.flatMap { tree?.nodes[$0] } : nil }
    private var editable: Bool { !model.busy && model.profile?.pendingJob == nil && model.review == nil }
    private func navigate(_ target: String?, record: Bool = true) {
        guard target != folder else { return }
        if record { back.append(folder); forward = [] }
        folder = target; selection = []; search = ""; drag = nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("api.title", systemImage: "bookmark.square.fill").font(.title2.bold()).foregroundStyle(AppTheme.accent); Spacer()
                Button("api.reload") { Task { await model.load() } }.disabled(model.busy)
                Button("common.close") { Task { await model.requestStop(); dismiss() } }
            }
            DisclosureGroup { Text("api.boundary").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } label: { Label("api.experimental", systemImage: "flask").font(.caption).foregroundStyle(.secondary) }
            if let error = model.error {
                DisclosureGroup("api.error") { Text(verbatim: error).textSelection(.enabled) }.foregroundStyle(.orange)
            }
            if let notice = model.notice { Text(L(notice)).foregroundStyle(.secondary) }
            // model.notice holds localization keys; the export count is already formatted.
            if let exportMessage { Text(verbatim: exportMessage).foregroundStyle(.secondary) }
            DisclosureGroup("api.connect") { connectionContent }
            if !model.workspace.profiles.isEmpty {
                Picker("api.scope", selection: $model.selected) {
                    ForEach(model.workspace.profiles) { profile in
                        Text(profile.name + " · " + (profile.base.nodes[profile.base.orderedRoots[0]]?.name ?? profile.scope)).tag(Optional(profile.id))
                    }
                }
                if let profile = model.profile {
                    HStack {
                        Button("export.html") {
                            let panel = NSSavePanel(); panel.nameFieldStringValue = "galmuri-api-bookmarks.html"
                            guard panel.runModal() == .OK, let url = panel.url else { return }
                            exportMessage = nil
                            do {
                                let export = try ProfileIO.exportHTMLSkippingUnsupported(profile.working, under: folder)
                                try export.data.write(to: url, options: .atomic)
                                if export.skipped > 0 { exportMessage = localizedCount("export.skippedUnsupportedCount", export.skipped) }
                            } catch { model.error = error.localizedDescription }
                        }.disabled(model.busy)
                        HStack(spacing: 6) {
                            Button { if let target = back.popLast() { forward.append(folder); navigate(target, record: false) } } label: { Label("navigation.back", systemImage: "chevron.left") }.disabled(back.isEmpty).keyboardShortcut("[", modifiers: .command)
                            Button { if let target = forward.popLast() { back.append(folder); navigate(target, record: false) } } label: { Label("navigation.forward", systemImage: "chevron.right") }.disabled(forward.isEmpty).keyboardShortcut("]", modifiers: .command)
                            Button { let parent = tree?.nodes[folder ?? ""]?.parent; navigate(parent == tree?.orderedRoots.first ? nil : parent) } label: { Label("navigation.up", systemImage: "arrow.up") }.disabled(folder == nil).keyboardShortcut(.upArrow, modifiers: .command)
                        }.labelStyle(.iconOnly)
                        Text(folder.flatMap { tree?.path(to: $0) } ?? (tree?.nodes[tree?.orderedRoots.first ?? ""]?.name ?? "")).lineLimit(2)
                        Spacer()
                        Text(localizedCount("editor.changeCount", Set(profile.base.nodes.keys).union(profile.working.nodes.keys).filter { profile.base.nodes[$0] != profile.working.nodes[$0] }.count))
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("editor.search", text: $search).textFieldStyle(.plain)
                        Text(localizedCount("editor.resultCount", rows.count)).font(.caption).foregroundStyle(.secondary)
                    }.padding(10).background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button("editor.addBookmark") { editor = APIEditorRequest(profile: profile, parent: folder ?? profile.working.orderedRoots[0], folder: false) }
                        Button("editor.newFolder") { editor = APIEditorRequest(profile: profile, parent: folder ?? profile.working.orderedRoots[0], folder: true) }
                        Button("editor.edit") { if let chosen { editor = APIEditorRequest(profile: profile, item: chosen) } }.disabled(chosen == nil)
                        Button("editor.move", systemImage: "folder") { moveCapture = APIEditorRequest(profile: profile, itemIDs: selection); destination = folder ?? profile.working.orderedRoots[0]; move = true }.disabled(selection.isEmpty).keyboardShortcut("m", modifiers: [.command, .shift])
                        Button("editor.exclude", systemImage: "trash", role: .destructive) { deletion = APIEditorRequest(profile: profile, itemIDs: selection) }.disabled(selection.isEmpty)
                        Spacer()
                        Text(localizedCount("editor.selectionCount", selection.count)).font(.caption).foregroundStyle(.secondary)
                        Button("editor.undo") { Task { await model.undoEdit() } }.disabled(model.undo[profile.id]?.isEmpty != false)
                    }.disabled(model.busy || profile.pendingJob != nil || model.review != nil)
                    Table(of: Bookmark.self, selection: $selection) {
                        TableColumn(L("editor.name")) { node in
                            HStack(spacing: 10) {
                                Image(systemName: node.isFolder ? "folder.fill" : "link").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(node.name).fontWeight(node.isFolder ? .medium : .regular).lineLimit(1).help(node.name)
                                    if let url = node.url { Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(url) }
                                }
                            }.padding(.vertical, 5).modifier(AppTableCell(selected: selection.contains(node.id)))
                        }.width(min: 260, ideal: 530)
                        TableColumn(L("editor.type")) { node in
                            Text(L(node.isFolder ? "editor.typeFolder" : "editor.typeBookmark")).font(.caption).foregroundStyle(.secondary)
                                .modifier(AppTableCell(selected: selection.contains(node.id)))
                        }.width(100)
                    } rows: {
                        ForEach(rows) { node in
                            if node.isFolder {
                                TableRow(node).itemProvider { dragProvider(node.id) }
                                    .dropDestination(for: BookmarkMoveData.self) { payloads in receiveDrop(payloads, to: node.id) }
                            } else { TableRow(node).itemProvider { dragProvider(node.id) } }
                        }
                    }.tableStyle(.inset(alternatesRowBackgrounds: false))
                    .contextMenu(forSelectionType: String.self) { ids in
                        if ids.count == 1, let id = ids.first {
                            Button("editor.edit") { if let item = tree?.nodes[id] { editor = APIEditorRequest(profile: profile, item: item) } }
                        }
                        if !ids.isEmpty {
                            Button("editor.move") { moveCapture = APIEditorRequest(profile: profile, itemIDs: ids); destination = folder ?? profile.working.orderedRoots[0]; move = true }
                            Button("editor.exclude", role: .destructive) { deletion = APIEditorRequest(profile: profile, itemIDs: ids) }
                        }
                    } primaryAction: { ids in
                        guard ids.count == 1, let id = ids.first, let item = tree?.nodes[id] else { return }
                        if item.isFolder { navigate(id) } else { editor = APIEditorRequest(profile: profile, item: item) }
                    }
                    .onDeleteCommand { if editable, !selection.isEmpty { deletion = APIEditorRequest(profile: profile, itemIDs: selection) } }
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        guard press.modifiers.isEmpty, let chosen, editable else { return .ignored }
                        if chosen.isFolder { navigate(chosen.id) } else { editor = APIEditorRequest(profile: profile, item: chosen) }
                        return .handled
                    }.disabled(model.busy)
                    HStack {
                        Button("api.earlier") { reorder(-1) }.disabled(chosen == nil || model.busy || profile.pendingJob != nil)
                        Button("api.later") { reorder(1) }.disabled(chosen == nil || model.busy || profile.pendingJob != nil)
                        Button("api.discard") { editor = APIEditorRequest(profile: profile, discard: true) }.disabled(profile.base == profile.working || model.busy || profile.pendingJob != nil)
                        Spacer()
                        if profile.pendingJob != nil {
                            Button("api.inspectInterrupted") { Task { await model.prepareAdoption() } }.disabled(model.busy)
                        } else {
                            Button("api.restore") { Task { await model.prepare(restore: true) } }.disabled(profile.history.isEmpty || profile.base != profile.working || model.busy)
                            Button("api.review") { Task { await model.prepare() } }.buttonStyle(PrimaryActionStyle()).disabled(model.busy)
                        }
                    }
                }
            } else { Spacer(); Text("api.empty").foregroundStyle(.secondary); Spacer() }
            if model.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L(model.stopping ? "api.stopping" : "api.working")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("api.stop", systemImage: "stop.circle") { Task { await model.requestStop() } }.disabled(model.stopping)
                }
            }
        }
        .padding(22).background(AppTheme.surface).tint(AppTheme.accent).preferredColorScheme(.dark)
        .frame(minWidth: 940, idealWidth: 1120, minHeight: 680, idealHeight: 780)
        .task { await model.load() }
        .onDisappear { Task { await model.requestStop() } }
        .onChange(of: model.selected) { selection = []; folder = nil; search = ""; back = []; forward = []; drag = nil; exportMessage = nil }
        .onChange(of: search) { selection = []; drag = nil }
        .onChange(of: model.profile?.working) { selection = []; drag = nil; if folder.flatMap({ tree?.nodes[$0] }) == nil { folder = nil }; back = back.filter { $0 == nil || tree?.nodes[$0!]?.isFolder == true }; forward = forward.filter { $0 == nil || tree?.nodes[$0!]?.isFolder == true } }
        .sheet(item: $editor) { request in APIEditorSheet(request: request, model: model) }
        .sheet(isPresented: $move) {
            VStack(alignment: .leading, spacing: 14) {
                Text("editor.move").font(.headline)
                if let tree {
                    Picker("editor.folder", selection: $destination) { ForEach(APIEditorListing.destinations(tree: tree, itemIDs: moveCapture?.itemIDs ?? []), id: \.node.id) { entry in Text(entry.path).tag(entry.node.id) } }
                }
                HStack { Button("common.cancel") { move = false }; Spacer(); Button("editor.move") {
                    let captured = moveCapture, target = destination
                    Task { await model.edit(expected: captured?.profile.id, working: captured?.profile.working) { tree in if let ids = captured?.itemIDs { try tree.move(ids, to: target) } }; if model.error == nil { move = false } }
                }.disabled(model.busy) }
            }.padding(22).frame(width: 540)
        }
        .sheet(item: $model.review) { review in APIReviewSheet(model: model, review: review) }
        .sheet(item: $model.adoption) { review in
            VStack(alignment: .leading, spacing: 14) {
                Text("api.adoptTitle").font(.title2.bold()); Text("api.adoptHelp")
                ScrollView { ChangeReviewList(before: review.profile.working, after: review.tree) }
                Toggle("api.ack", isOn: $model.adoptionAcknowledged)
                HStack { Button("common.cancel") { model.adoption = nil }; Spacer(); Button("api.adopt") { Task { await model.adopt() } }.disabled(!model.adoptionAcknowledged || model.busy) }
            }.padding(24).frame(width: 820, height: 680)
        }
        .sheet(item: $deletion) { captured in
            VStack(alignment: .leading, spacing: 14) {
                Text("api.deleteTitle").font(.title2.bold()); Text("api.deleteHelp")
                let removed = captured.itemIDs.reduce(into: Set<String>()) { $0.formUnion(captured.profile.working.descendants(of: $1)) }
                Text(localizedCount("editor.deletedCount", removed.count))
                ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(removed.sorted(), id: \.self) { id in BookmarkSnapshot(tree: captured.profile.working, id: id) } } }
                HStack { Button("common.cancel") { deletion = nil }; Spacer(); Button("editor.exclude", role: .destructive) {
                    Task { await model.edit(expected: captured.profile.id, working: captured.profile.working) { try $0.remove(captured.itemIDs) }; if model.error == nil { deletion = nil } }
                }.disabled(model.busy) }
            }.padding(24).frame(width: 700, height: 540)
        }
    }
    private var connectionContent: some View {
        VStack(alignment: .leading) {
            Text("api.connectHelp").font(.caption)
            if !model.sources.isEmpty {
                Picker("api.connection", selection: $connection) { ForEach(model.sources, id: \.session.id) { source in Text(source.session.name + " · " + source.session.installationID.uuidString.prefix(8)).tag(Optional(source.session.id)) } }
                if let source = model.sources.first(where: { $0.session.id == connection }), let snapshot = try? source.snapshot {
                    Picker("api.scope", selection: $scope) {
                        Text("api.chooseScope").tag("")
                        ForEach(snapshot.folders) { node in Text(node.title + " · " + node.id).tag(node.id) }
                    }
                    Button("api.connect") { let scope = scope; Task { await model.connect(source, scope: scope) } }.disabled(scope.isEmpty || model.busy)
                }
            }
        }
        // Selection follows the session, not its position, so a re-sorted reload cannot bind another browser.
        .onChange(of: model.sources.map(\.session.id), initial: true) { _, ids in
            if connection.map({ ids.contains($0) }) != true { connection = ids.first; scope = "" }
        }
        .onChange(of: connection) { scope = "" }
    }
    private func reorder(_ direction: Int) {
        let id = selection.count == 1 ? selection.first : nil, profileID = model.selected
        Task { await model.edit(expected: profileID) { tree in if let id { try tree.reorderAmongPeers(id, direction: direction) } } }
    }
    private func dragProvider(_ id: String) -> NSItemProvider? {
        guard editable, let profile = model.profile else { return nil }
        let ids = selection.contains(id) ? selection : [id]
        if drag?.itemIDs != ids || drag?.isCurrent(profileID: profile.id, tree: profile.working) != true {
            drag = try? BookmarkDrag(profileID: profile.id, itemIDs: ids, tree: profile.working)
        }
        guard let data = drag?.data else { return nil }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.galmuriBookmarkMove.identifier, visibility: .ownProcess) { completion in completion(data, nil); return nil }
        return provider
    }
    private func receiveDrop(_ payloads: [BookmarkMoveData], to target: String) {
        guard editable, let drag, let profile = model.profile,
              let changed = try? drag.movedTree(payloads: payloads.map(\.data), profileID: profile.id, tree: profile.working, to: target) else { return }
        Task { await model.edit(expected: profile.id, working: profile.working) { $0 = changed } }
    }

}

struct APIEditorRequest: Identifiable {
    let id = UUID()
    let profile: APIWorkingCopy
    let item: Bookmark?
    let itemIDs: Set<String>
    let parent: String
    let folder: Bool
    let discard: Bool
    init(profile: APIWorkingCopy, parent: String = "", folder: Bool = false, item: Bookmark? = nil, discard: Bool = false, itemIDs: Set<String> = []) {
        self.profile = profile; self.item = item; self.parent = parent; self.folder = folder; self.discard = discard; self.itemIDs = item.map { [$0.id] } ?? itemIDs
    }
    init(profile: APIWorkingCopy, item: Bookmark) { self.init(profile: profile, folder: item.isFolder, item: item) }
}
struct APIEditorSheet: View {
    let request: APIEditorRequest
    @Bindable var model: APIWorkspaceModel
    @State private var name = ""
    @State private var url = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if request.discard {
                Text("api.discard").font(.headline)
                ScrollView { ChangeReviewList(before: request.profile.working, after: request.profile.base) }.frame(height: 300)
            } else {
                TextField("editor.name", text: $name)
                if !request.folder { TextField("editor.url", text: $url) }
            }
            if let error = model.error { Text(verbatim: error).font(.caption).foregroundStyle(.orange) }
            HStack { Button("common.cancel") { dismiss() }; Spacer(); Button("editor.saveWorkingCopy") {
                Task {
                    await model.edit(expected: request.profile.id, working: request.profile.working) { tree in
                        if request.discard { tree = request.profile.base }
                        else if let item = request.item {
                            if item.url == url || item.isFolder {
                                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GalmuriError.invalid("name") }; tree.nodes[item.id]?.name = name
                            } else { try tree.edit(item.id, name: name, url: url) }
                        } else { _ = try tree.add(name: name, url: request.folder ? nil : url, to: request.parent) }
                    }
                    if model.error == nil { dismiss() }
                }
            }.disabled(model.busy || (!request.discard && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }
        }.padding(24).frame(width: 620).onAppear { name = request.item?.name ?? ""; url = request.item?.url ?? "" }
    }
}
struct APIReviewSheet: View {
    @Bindable var model: APIWorkspaceModel
    @Bindable var review: APIReview
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("api.review").font(.title2.bold())
            Text("api.applyHelp").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(review.result.conflicts) { conflict in
                        GroupBox(conflict.item) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L(conflict.field)).font(.caption)
                                Text("refresh.base").font(.caption)
                                Text(verbatim: conflict.base).textSelection(.enabled)
                                Text(verbatim: conflict.ours).textSelection(.enabled)
                                Button("conflict.ours") { Task { await model.resolve(conflict.id, side: .ours) } }.disabled(model.busy)
                                    .accessibilityValue(L(review.resolutions[conflict.id] == .ours ? "conflict.selected" : "conflict.notSelected"))
                                Text(verbatim: conflict.theirs).textSelection(.enabled)
                                Button("conflict.theirs") { Task { await model.resolve(conflict.id, side: .theirs) } }.disabled(model.busy)
                                    .accessibilityValue(L(review.resolutions[conflict.id] == .theirs ? "conflict.selected" : "conflict.notSelected"))
                                if let side = review.resolutions[conflict.id] { Text(L(side == .ours ? "conflict.ours" : "conflict.theirs")).foregroundStyle(AppTheme.accent) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ChangeReviewList(before: review.theirs, after: review.result.tree)
                }
            }
            if model.busy { HStack { ProgressView().controlSize(.small); Text(L(model.stopping ? "api.stopping" : "api.working")).font(.caption).foregroundStyle(.secondary) } }
            Toggle("api.ack", isOn: $review.acknowledged).disabled(model.busy)
            HStack {
                Button(L(model.busy ? "api.stop" : "common.cancel")) { if model.busy { Task { await model.requestStop() } } else { model.review = nil } }.disabled(model.stopping)
                Spacer()
                Button("api.keepLocal") { Task { await model.accept(localOnly: true) } }.disabled(model.busy || !review.acknowledged || !review.result.unresolved.isEmpty)
                Button("api.apply") { Task { await model.accept() } }.buttonStyle(PrimaryActionStyle())
                    .disabled(model.busy || !review.acknowledged || !review.result.unresolved.isEmpty || !review.writable)
            }
        }.padding(24).frame(width: 880, height: 720)
    }
}
