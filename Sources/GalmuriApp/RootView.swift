import SwiftUI
import UniformTypeIdentifiers
import GalmuriCore

struct EditorRequest: Identifiable {
    let id = UUID()
    var item: String?
    var folder: Bool = false
}

struct FolderRow: Identifiable {
    let id: String
    let name: String
    var children: [FolderRow]?
}

struct RootView: View {
    @Bindable var store: AppStore
    @State private var editor: EditorRequest?
    @State private var moving = false
    @State private var deletion: BookmarkDeletion?
    @State private var resetting: WorkingCopyReset?
    @State private var managingProfiles = false
    @State private var bookmarkDrag: BookmarkDrag?
    @State private var tableLocation: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if let notice = store.connectionNotice, notice.issue == .permissionDenied {
                ProfileAccessView(store: store, notice: notice)
            } else if store.profile == nil { ProfileWelcomeView(store: store) }
            else { workspaceView }
        }
        .frame(minWidth: 980, minHeight: 690)
        .preferredColorScheme(.dark)
        .tint(AppTheme.accent)
        .disabled(store.busy)
        .sheet(item: $editor) { request in BookmarkEditor(store: store, request: request) }
        .sheet(item: $store.pendingReview) { profile in PendingReviewView(profile: profile) }
        .sheet(item: $store.connectionDetails) { profile in ConnectionDetailsSheet(profile: profile, local: store.coordinator.canWrite(profile.source)) }
        .sheet(isPresented: $moving) { MoveSheet(store: store) }
        .sheet(item: $store.review) { session in ReviewView(store: store, session: session) }
        .sheet(item: $deletion) { request in BookmarkDeletionSheet(store: store, request: request) }
        .sheet(item: $resetting) { request in WorkingCopyResetSheet(store: store, request: request) }
        .sheet(isPresented: $managingProfiles) { ProfileManagementView(store: store) }
        .sheet(item: $store.connection) { request in ProfileSelectionSheet(store: store, request: request) }
        .onChange(of: store.navigation) { store.selection = []; bookmarkDrag = nil }
        .onChange(of: store.search) { store.selection = []; bookmarkDrag = nil }
        .onChange(of: store.selectedProfileID) { bookmarkDrag = nil }
        .onChange(of: store.tree) { bookmarkDrag = nil }
    }

    private var workspaceView: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            VStack(spacing: 0) {
                topbar
                Divider()
                if let notice = store.connectionNotice {
                    ProfileDiscoveryNoticeView(store: store, notice: notice).padding(.horizontal, 24).padding(.top, 12)
                } else if store.error != nil {
                    ScrollView { AppErrorNotice(store: store).padding(.horizontal, 24).padding(.top, 12) }
                        .frame(height: 90)
                }
                if store.navigation == "backups" { BackupsView(store: store) }
                else { editorContent }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }.navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) { Text(verbatim: "Galmuri").font(.title3.bold()); Text(L(Bundle.main.object(forInfoDictionaryKey: "GalmuriBuildConfiguration") as? String == "release" ? "app.localPreview" : "app.localDevelopment")).font(.caption2).foregroundStyle(.secondary) }
            }.padding(.horizontal, 18).padding(.top, 20)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("sidebar.profiles").font(.caption).foregroundStyle(.secondary); Spacer(); Menu { ForEach(BookmarkBrowser.allCases) { browser in Button(String(format: L("profile.connectBrowser"), browser.name)) { store.connect(browser) } } } label: { Image(systemName: "plus") }.buttonStyle(.borderless).help(L("profile.connect")).accessibilityLabel(L("profile.connect")) }
                Picker("sidebar.profiles", selection: Binding(get: { store.selectedProfileID }, set: { if let id = $0 { store.switchProfile(id) } })) {
                    ForEach(store.workspace.profiles) { profile in
                        let folder = profile.source.deletingLastPathComponent().lastPathComponent
                        Text(profile.name == folder ? profile.name : profile.name + " · " + folder).tag(Optional(profile.id))
                    }
                }.labelsHidden().pickerStyle(.menu).help(store.profile?.source.path ?? "")
                Button("profile.manage", systemImage: "slider.horizontal.3") { managingProfiles = true }
                    .buttonStyle(.borderless).font(.caption)
            }.padding(.horizontal, 18)
            List(selection: $store.navigation) {
                Label("sidebar.allBookmarks", systemImage: "square.grid.2x2").tag("all")
                Label("sidebar.changes", systemImage: "arrow.up.arrow.down").badge(store.pendingCount).tag("changes")
                Label("sidebar.sameURL", systemImage: "square.on.square").tag("duplicates")
                Section("sidebar.folders") {
                    ForEach(folderRoots) { root in
                        OutlineGroup(root, children: \.children) { folder in
                            Label(folder.name, systemImage: "folder").tag(folder.id)
                                .modifier(BookmarkFolderDropTarget { receiveDrop($0, to: folder.id) })
                        }
                    }
                }
                Section { Label("sidebar.backups", systemImage: "clock.arrow.circlepath").tag("backups") }
            }.listStyle(.sidebar).listItemTint(.fixed(.secondary)).layoutPriority(-1)
            VStack(alignment: .leading, spacing: 10) {
                SettingsLink { Label("settings.open", systemImage: "gearshape") }
                    .buttonStyle(.plain).help("⌘,").accessibilityIdentifier("open-settings")
                Divider()
                Label("status.savedLocally", systemImage: "circle.fill").font(.caption).foregroundStyle(.secondary)
                Text("status.notApplied").font(.caption2).foregroundStyle(.secondary)
            }.padding(18)
        }
    }

    private var folderRoots: [FolderRow] {
        guard let tree = store.tree else { return [] }
        func row(_ id: String) -> FolderRow {
            let n = tree.nodes[id]!
            let children = n.children.filter { tree.nodes[$0]?.isFolder == true }.map(row)
            return FolderRow(id: id, name: n.name, children: children.isEmpty ? nil : children)
        }
        return tree.orderedRoots.map(row)
    }

    private var topbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Button("navigation.back", systemImage: "chevron.left") { store.goBack() }
                    .disabled(!store.canGoBack).keyboardShortcut("[", modifiers: .command)
                    .help(L("navigation.back")).accessibilityIdentifier("navigate-back")
                Button("navigation.forward", systemImage: "chevron.right") { store.goForward() }
                    .disabled(!store.canGoForward).keyboardShortcut("]", modifiers: .command)
                    .help(L("navigation.forward")).accessibilityIdentifier("navigate-forward")
                Button("navigation.up", systemImage: "arrow.up") { store.goUp() }
                    .disabled(store.folder == nil).keyboardShortcut(.upArrow, modifiers: .command)
                    .help(L("navigation.up")).accessibilityIdentifier("navigate-up")
            }.labelStyle(.iconOnly).buttonStyle(.bordered)
            Text(verbatim: store.profile?.name ?? "Galmuri").font(.caption).foregroundStyle(.secondary).lineLimit(1).help(store.profile?.name ?? "Galmuri")
            Spacer()
            Label("status.savedLocally", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            if store.busy { ProgressView().controlSize(.small) }
            Button("refresh.action", systemImage: "arrow.clockwise") { Task { await store.refreshProfile() } }
                .disabled(store.profile == nil || store.review != nil).help(L("refresh.help"))
            Menu {
                Button("export.html") { store.exportHTML() }
                Button("export.workspaceJSON") { store.exportWorkspace() }
                Button("workspace.import") { store.importWorkspace() }
            } label: { Label("export.title", systemImage: "square.and.arrow.up") }
            .menuStyle(.borderlessButton).fixedSize()
            Button("review.title") { store.showPendingReview() }
            .buttonStyle(PrimaryActionStyle()).disabled(store.pendingCount == 0 || store.review != nil)
            .accessibilityIdentifier("review-changes")
        }.padding(.horizontal, 25).padding(.vertical, 14)
    }

    private var title: String {
        if let folder = store.folder { return store.tree?.nodes[folder]?.name ?? "" }
        return L(store.navigation == "changes" ? "sidebar.changes" : store.navigation == "duplicates" ? "sidebar.sameURL" : "sidebar.allBookmarks")
    }

    private var editorContent: some View {
        let rows = store.rows, changedIDs = store.profile?.changedIDs ?? []
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                if store.folder != nil { folderBreadcrumbs }
                HStack(spacing: 10) {
                    Image(systemName: store.folder == nil ? "bookmark" : "folder").foregroundStyle(.secondary)
                    Text(title).font(.title2.bold())
                    Spacer()
                }
                HStack(spacing: 18) {
                    Label { Text(localizedCount("editor.bookmarkCount", rows.filter { !$0.isFolder }.count)) } icon: { EmptyView() }
                    Text(localizedCount("editor.changeCount", changedIDs.count))
                }.font(.caption).foregroundStyle(.secondary)
            }
            if let p = store.profile {
                let local = store.coordinator.canWrite(p.source)
                HStack {
                    Label(L(local ? "editor.testWorkspace" : "editor.readOnlySource"), systemImage: local ? "flask" : "lock")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("connection.details") { store.showConnectionDetails() }
                        .font(.caption).buttonStyle(.borderless).accessibilityIdentifier("connection-details")
                }.padding(10).background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Label("editor.foldersFirst", systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("editor.newFolder", systemImage: "folder.badge.plus") { editor = EditorRequest(folder: true) }.disabled(store.tree == nil).keyboardShortcut("n", modifiers: [.command, .shift])
                Button("editor.addBookmark", systemImage: "plus") { editor = EditorRequest() }.accessibilityIdentifier("add-bookmark").disabled(store.tree == nil).keyboardShortcut("n", modifiers: .command)
            }.buttonStyle(.borderless)
            Divider()
            if store.navigation == "changes" {
                HStack {
                    Text("editor.discardScope").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("editor.revertSelected") { resetting = store.revertRequest(for: store.selection) }
                        .disabled(store.selection.isEmpty || !store.selection.isSubset(of: changedIDs))
                    Button("editor.discardAll", systemImage: "arrow.counterclockwise") { resetting = store.resetRequest() }
                        .disabled(changedIDs.isEmpty).accessibilityIdentifier("discard-all-changes")
                }
            }
            HStack {
                Button { searchFocused = true } label: {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help(L("editor.search")).accessibilityLabel(L("editor.search"))
                    .keyboardShortcut("f", modifiers: .command)
                TextField("editor.search", text: $store.search).textFieldStyle(.plain).accessibilityIdentifier("bookmark-search").focused($searchFocused)
                Text(localizedCount("editor.resultCount", rows.count)).font(.caption).foregroundStyle(.secondary)
            }
            selectionActions
            bookmarkTable(rows)
            HStack {
                Text(store.message ?? L("status.notApplied")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }.padding(28)
    }

    private var folderBreadcrumbs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                Button("sidebar.allBookmarks") { store.navigation = "all" }
                ForEach(store.folderPath) { node in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
                    if node.id == store.folder {
                        Text(verbatim: node.name).foregroundStyle(.secondary)
                    } else {
                        Button(node.name) { store.navigation = node.id }.help(store.tree?.path(to: node.id) ?? node.name)
                    }
                }
            }.font(.caption).buttonStyle(.borderless).fixedSize()
        }.scrollIndicators(.hidden).accessibilityLabel(Text("navigation.path"))
    }

    private func editTitle(_ id: String) -> String {
        L(store.tree?.nodes[id]?.isFolder == true ? "editor.editFolder" : "editor.editBookmark")
    }

    private var selectionActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.selection.isEmpty ? L("editor.selectHint") : localizedCount("editor.selectionCount", store.selection.count))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.selection.isEmpty {
                    Button("editor.clearSelection") { store.selection = [] }.buttonStyle(.borderless)
                }
                Button("editor.undo", systemImage: "arrow.uturn.backward") { store.undo() }
                    .disabled(!store.canUndo || searchFocused || editor != nil || moving || deletion != nil || resetting != nil || store.review != nil)
                    .keyboardShortcut("z", modifiers: .command)
                    .help(L("editor.undoLifetime"))
            }
            HStack(spacing: 10) {
                Button("editor.edit", systemImage: "pencil") {
                    if let id = store.selection.first { openEditor(id) }
                }.disabled(store.selection.count != 1 || !store.canMutateSelection)
                Button("editor.move", systemImage: "folder") { moving = true }
                    .disabled(!store.canMutateSelection).keyboardShortcut("m", modifiers: [.command, .shift])
                Button("editor.open", systemImage: "arrow.up.right.square") {
                    if let id = store.selection.first { store.openBookmark(id) }
                }.disabled(store.selection.count != 1 || store.selection.first.flatMap(store.bookmarkURL) == nil)
                Menu {
                    if let id = store.selection.first, store.selection.count == 1 {
                        Button("editor.moveUp", systemImage: "arrow.up") { store.reorder(id, direction: -1) }
                        Button("editor.moveDown", systemImage: "arrow.down") { store.reorder(id, direction: 1) }
                    }
                } label: { Label("editor.reorder", systemImage: "arrow.up.arrow.down") }
                    .disabled(store.selection.count != 1 || !store.canMutateSelection).fixedSize()
                Spacer()
                Button("editor.exclude", systemImage: "trash", role: .destructive) { requestDeletion(store.selection) }
                    .disabled(!store.canMutateSelection).accessibilityIdentifier("delete-selection")
            }
        }
        .buttonStyle(.bordered).controlSize(.regular)
    }

    private func openEditor(_ id: String) {
        guard store.canEditRow(id), let node = store.tree?.nodes[id] else { return }
        store.selection = [id]
        editor = EditorRequest(item: id, folder: node.isFolder)
    }

    private func requestDeletion(_ ids: Set<String>) {
        guard editor == nil, !moving, resetting == nil, store.review == nil, !store.busy,
              let request = store.deletionRequest(for: ids) else { return }
        if request.requiresConfirmation { deletion = request }
        else { store.delete(request) }
    }

    private var location: String { "\(store.selectedProfileID?.uuidString ?? "")/\(store.navigation)" }

    private func bookmarkTable(_ rows: [Bookmark]) -> some View {
        Table(of: Bookmark.self, selection: $store.selection) {
            TableColumn("editor.name") { node in
                HStack(spacing: 10) {
                    Image(systemName: store.isRemovedRow(node.id) ? "minus.circle" : node.isFolder ? "folder.fill" : "link").foregroundStyle(store.isRemovedRow(node.id) ? Color.secondary : node.isFolder ? Color.brown : Color.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.name).fontWeight(node.isFolder ? .semibold : .regular).strikethrough(store.isRemovedRow(node.id)).lineLimit(1).help(node.name)
                        if let url = node.url { Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(url) }
                    }
                }.padding(.vertical, 7).modifier(AppTableCell(selected: store.selection.contains(node.id)))
            }.width(min: 200, ideal: 360)
            TableColumn("editor.type") { node in
                Text(L(node.isFolder ? "editor.typeFolder" : "editor.typeBookmark")).font(.caption).foregroundStyle(.secondary).modifier(AppTableCell(selected: store.selection.contains(node.id)))
            }.width(85)
            TableColumn("editor.folder") { node in
                Text(store.rowFolderPath(node)).font(.caption).foregroundStyle(.secondary).modifier(AppTableCell(selected: store.selection.contains(node.id)))
            }.width(min: 130, ideal: 190, max: 240)
            TableColumn("sidebar.changes") { node in
                if store.isRemovedRow(node.id) { Text("change.pendingRemoval").font(.caption).foregroundStyle(.orange) }
                else if store.profile?.base.tree.nodes[node.id] == nil { Text("change.added").font(.caption).foregroundStyle(AppTheme.accent) }
                else if store.profile?.base.tree.nodes[node.id]?.parent != node.parent { Text("change.moved").font(.caption).foregroundStyle(.orange) }
                else if store.profile?.base.tree.nodes[node.id]?.children != node.children { Text("change.contents").font(.caption).foregroundStyle(AppTheme.accent) }
                else if store.profile?.base.tree.nodes[node.id] != node { Text("change.edited").font(.caption).foregroundStyle(.blue) }
                else { Text("—").foregroundStyle(.tertiary) }
            }.width(min: 110, ideal: 140)
            TableColumn("editor.edit") { node in
                if store.canEditRow(node.id) {
                    Button { openEditor(node.id) } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless).help(editTitle(node.id))
                        .accessibilityLabel(String(format: L("editor.editItem"), node.name))
                } else { Text("—").foregroundStyle(.tertiary) }
            }.width(55)
        } rows: {
            ForEach(tableLocation == location ? rows : []) { node in
                if node.isFolder {
                    TableRow(node)
                        .itemProvider { dragProvider(for: node.id) }
                        .dropDestination(for: BookmarkMoveData.self) { _ = receiveDrop($0, to: node.id) }
                } else {
                    TableRow(node).itemProvider { dragProvider(for: node.id) }
                }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        // AppKit re-enters its row-height cache when SwiftUI diffs one location's rows into another's; pass through an empty update instead.
        .task(id: location) { tableLocation = location }
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                if store.navigation == "changes" { Button("editor.revertSelected") { resetting = store.revertRequest(for: ids) } }
                if ids.count == 1, let id = ids.first {
                    Button(editTitle(id)) { openEditor(id) }.disabled(!store.canEditRow(id))
                    if store.bookmarkURL(id) != nil { Button("editor.open") { store.openBookmark(id) } }
                }
                Button("editor.move") { store.selection = ids; moving = true }.disabled(!ids.allSatisfy(store.canEditRow))
                Divider()
                Button("editor.exclude", role: .destructive) { requestDeletion(ids) }.disabled(!ids.allSatisfy(store.canEditRow))
            }
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first {
                if store.isRemovedRow(id) { resetting = store.revertRequest(for: ids); return }
                if store.tree?.nodes[id]?.isFolder == true { store.navigation = id }
                else { openEditor(id) }
            }
        }
        .onDeleteCommand { requestDeletion(store.selection) }
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard press.modifiers.isEmpty, store.selection.count == 1, let id = store.selection.first else { return .ignored }
            if store.isRemovedRow(id) { resetting = store.revertRequest(for: [id]) }
            else if store.tree?.nodes[id]?.isFolder == true { store.navigation = id }
            else { openEditor(id) }
            return .handled
        }
        .frame(minHeight: 0, maxHeight: .infinity)
        .layoutPriority(-1)
        .help(L("editor.dragMoveHelp"))
        .accessibilityHint(L("editor.dragMoveHelp"))
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label(store.navigation == "changes" ? "editor.emptyChanges" : "editor.emptyTitle", systemImage: "bookmark")
                } description: {
                    Text(L(store.search.isEmpty ? (store.navigation == "changes" ? "editor.emptyChangesHelp" : "editor.emptyHelp") : "editor.noResults"))
                }
            }
        }
    }

    private func dragProvider(for id: String) -> NSItemProvider? {
        guard !store.busy, store.review == nil, let profileID = store.selectedProfileID, let tree = store.tree else { return nil }
        let ids = store.selection.contains(id) ? store.selection : [id]
        if bookmarkDrag?.itemIDs != ids || bookmarkDrag?.isCurrent(profileID: profileID, tree: tree) != true {
            bookmarkDrag = try? BookmarkDrag(profileID: profileID, itemIDs: ids, tree: tree)
        }
        guard let data = bookmarkDrag?.data else { return nil }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.galmuriBookmarkMove.identifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    private func receiveDrop(_ items: [BookmarkMoveData], to destination: String) -> Bool {
        guard !store.busy, store.review == nil, let drag = bookmarkDrag,
              let profileID = store.selectedProfileID, let tree = store.tree,
              let moved = try? drag.movedTree(payloads: items.map(\.data), profileID: profileID, tree: tree, to: destination),
              moved != tree else { return false }
        let saved = store.edit { $0 = moved }
        bookmarkDrag = nil
        return saved
    }
}

struct BookmarkEditor: View {
    @Bindable var store: AppStore
    let request: EditorRequest
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var parent = ""
    @State private var validation: String?
    @State private var editingProfileID: UUID?
    @State private var originalWorking: BookmarkTree?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L(request.item == nil ? (request.folder ? "editor.newFolder" : "editor.addBookmark") : (request.folder ? "editor.editFolder" : "editor.editBookmark"))).font(.title2.bold())
            Form {
                TextField("editor.name", text: $name).accessibilityIdentifier("bookmark-name").focused($nameFocused)
                if !request.folder { TextField("editor.url", text: $url).accessibilityIdentifier("bookmark-url") }
                if request.item == nil {
                    Picker("editor.folder", selection: $parent) { ForEach(store.folders) { n in Text(store.tree?.path(to: n.id) ?? n.name).tag(n.id) } }
                }
            }
            if store.error != nil { AppErrorNotice(store: store) }
            Text("editor.workingCopyHelp").font(.caption).foregroundStyle(.secondary)
            if let validation { Text(validation).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer(); Button("common.cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("editor.saveWorkingCopy") { save() }.keyboardShortcut(.defaultAction).buttonStyle(PrimaryActionStyle())
            }
        }.padding(25).frame(minWidth: 480, idealWidth: 560)
        .onAppear {
            guard originalWorking == nil else { return }
            editingProfileID = store.selectedProfileID; originalWorking = store.tree
            if let id = request.item, let n = store.tree?.nodes[id] { name = n.name; url = n.url ?? "" }
            parent = store.folderDestination ?? ""; nameFocused = true
        }
    }

    private func save() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        validation = nil
        do {
            guard !title.isEmpty else { throw GalmuriError.invalid("name") }
            // An unchanged URL may be non-web (javascript:, chrome://, file://); only a new or changed URL is validated.
            if !request.folder, request.item.flatMap({ originalWorking?.nodes[$0]?.url }) != address { try BookmarkTree.validateEditableURL(address) }
            guard let editingProfileID, let originalWorking else { return }
            let saved = store.edit(profileID: editingProfileID, expectedWorking: originalWorking) { tree in
                if let id = request.item { try Self.edit(&tree, id: id, name: title, url: request.folder ? nil : address) }
                else { _ = try tree.add(name: title, url: request.folder ? nil : address, to: parent) }
            }
            if saved { dismiss() }
        } catch { validation = localizedAppMessage(error.localizedDescription) }
    }

    /// Renames only when the URL is unchanged, so existing non-web URLs stay editable as in the API editor.
    static func edit(_ tree: inout BookmarkTree, id: String, name: String, url: String?) throws {
        guard let url, tree.nodes[id]?.url == url else { return try tree.edit(id, name: name, url: url) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GalmuriError.invalid("name") }
        guard !tree.roots.values.contains(id) else { throw GalmuriError.invalid("protected root") }
        tree.nodes[id]?.name = name
    }
}

struct BookmarkDeletionSheet: View {
    @Bindable var store: AppStore
    let request: BookmarkDeletion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("editor.excludeConfirm").font(.title2.bold())
            Text(localizedCount("editor.removalCount", request.removedIDs.count)).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(request.items) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(item.name, systemImage: item.isFolder ? "folder" : "link")
                                .fixedSize(horizontal: false, vertical: true)
                            Text(request.working.path(to: item.id)).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(height: min(180, CGFloat(request.items.count) * 65))
            Text("editor.excludeHelp").font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.error != nil { AppErrorNotice(store: store) }
            HStack {
                Spacer()
                Button("common.cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("editor.exclude", role: .destructive) {
                    if store.delete(request) { dismiss() }
                }.keyboardShortcut(.defaultAction).accessibilityIdentifier("confirm-delete")
            }
        }.padding(25).frame(width: 540)
    }
}

struct MoveSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var destination = ""
    @State private var itemIDs = Set<String>()
    @State private var profileID: UUID?
    @State private var originalWorking: BookmarkTree?
    private var destinations: [Bookmark] {
        guard let originalWorking else { return [] }
        return APIEditorListing.destinations(tree: originalWorking, itemIDs: itemIDs).map(\.node)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("editor.move").font(.title2.bold())
            Picker("editor.folder", selection: $destination) { ForEach(destinations) { n in Text(originalWorking?.path(to: n.id) ?? n.name).tag(n.id) } }
            if store.error != nil { AppErrorNotice(store: store) }
            HStack {
                Spacer()
                Button("common.cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("editor.move") {
                    guard let profileID, let originalWorking else { return }
                    if store.edit(profileID: profileID, expectedWorking: originalWorking, { try $0.move(itemIDs, to: destination) }) { dismiss() }
                }.buttonStyle(PrimaryActionStyle()).keyboardShortcut(.defaultAction).disabled(destination.isEmpty)
            }
        }.padding(25).frame(minWidth: 490, idealWidth: 560)
        .onAppear {
            guard originalWorking == nil else { return }
            itemIDs = store.selection; profileID = store.selectedProfileID; originalWorking = store.tree
            let preferred = store.folderDestination
            destination = destinations.first { $0.id == preferred }?.id ?? destinations.first?.id ?? ""
        }
    }
}
