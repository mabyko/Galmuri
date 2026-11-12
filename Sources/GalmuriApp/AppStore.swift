import AppKit
import Foundation
import Observation
import GalmuriCore

func L(_ key: String) -> String { NSLocalizedString(key, bundle: .main, comment: "") }

@MainActor @Observable
final class ReviewSession: Identifiable {
    enum Phase { case exit, conflicts, final, complete }
    enum Mode { case apply, refresh }
    let mode: Mode
    var baseAtReview: BookmarkFile?
    var sourceAtReview: URL?
    var restrictionAtReview: String?
    var localArchive: URL?
    let id = UUID()
    let profileID: UUID
    var phase: Phase = .exit
    var latest: BookmarkFile?
    var result: MergeResult?
    var resolutions: [String: MergeSide] = [:]
    var acknowledged = false
    var receipt: BackupReceipt?
    var workingAtReview: BookmarkTree?
    var sourceIdentity: ApplySourceIdentity?
    init(profileID: UUID, mode: Mode = .apply) { self.profileID = profileID; self.mode = mode }
}

struct ExtensionInspection: Equatable, Sendable {
    let profileID: UUID
    let source: URL
    let presence: ExtensionPresence
    let checkedAt: Date
}

@MainActor @Observable
final class AppStore {
    var workspace = Workspace()
    var selectedProfileID: UUID?
    var settingsNavigation = "general"
    private(set) var labs = LabOptions()
    private(set) var extensionChecks: [UUID: ExtensionInspection] = [:]
    private var extensionCheckToken: UUID?
    private(set) var checkingExtension = false
    var labsURL: URL { directory.appendingPathComponent("labs.json") }
    var navigation = "all" {
        didSet {
            guard navigation != oldValue else { return }
            if !restoringNavigation {
                if validLocation(oldValue) { backLocations.append((oldValue, search)) }
                forwardLocations.removeAll()
                search = ""
            }
            selection.removeAll()
        }
    }
    private var backLocations: [(route: String, search: String)] = []
    private var forwardLocations: [(route: String, search: String)] = []
    private var restoringNavigation = false
    var selection = Set<String>()
    var search = ""
    var error: String?
    var message: String?
    var busy = false
    var review: ReviewSession?
    var connection: ProfileConnection?
    var connectionDetails: ConnectedProfile?
    var pendingReview: ConnectedProfile?
    private(set) var connectionBrowser: BookmarkBrowser = .chrome
    var connectionNotice: ProfileConnectionNotice?
    private(set) var lastDiscoveryIssue: ProfileDiscoveryIssue?
    private(set) var lastDiscoveryDiagnostic: ProfileReadDiagnostic?
    var backups: [BackupReceipt] = []
    var unreadableBackupCount = 0
    var undoStacks: [UUID: [BookmarkTree]] = [:]
    var accessIssues = Set<UUID>()
    private var savingDisabled = false
    private let browserState: (@Sendable (URL) -> Bool)?

    let directory: URL
    var workspaceURL: URL { directory.appendingPathComponent("workspace.json") }
    var testRoot: URL { directory.appendingPathComponent("TestProfiles") }
    var coordinator: ApplyCoordinator { ApplyCoordinator(testRoot: testRoot, backupRoot: directory.appendingPathComponent("OriginalBackups")) }
    var profile: ConnectedProfile? { workspace.profiles.first { $0.id == selectedProfileID } }
    var tree: BookmarkTree? { profile?.working }
    var folder: String? { tree?.nodes[navigation]?.isFolder == true ? navigation : nil }
    var folderDestination: String? { folder ?? tree?.roots["bookmark_bar"] }
    var pendingCount: Int { profile?.changedIDs.count ?? 0 }
    var canUndo: Bool { selectedProfileID.flatMap { undoStacks[$0]?.isEmpty == false } ?? false }
    var needsReconnect: Bool { selectedProfileID.map { accessIssues.contains($0) } ?? false }
    @discardableResult
    func setLabOptions(api: Bool? = nil, file: Bool? = nil) -> Bool {
        var next = labs
        if let api { next.apiEnabled = api }
        if let file { next.fileEnabled = file }
        do {
            try next.save(to: labsURL)
            labs = next
            if error == L("labs.optionsFailure") { error = nil }
            if !next.apiEnabled { extensionChecks = [:]; extensionCheckToken = nil; checkingExtension = false }
            return true
        } catch { self.error = L("labs.optionsFailure"); return false }
    }

    func checkRegisteredExtensions() async {
        guard labs.apiEnabled else { return }
        guard let url = Bundle.main.url(forResource: "BridgeConfiguration", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let id = config["extensionID"] else {
            extensionCheckToken = nil; checkingExtension = false
            extensionChecks = Dictionary(uniqueKeysWithValues: workspace.profiles.map {
                ($0.id, ExtensionInspection(profileID: $0.id, source: $0.source, presence: .unavailable, checkedAt: Date()))
            })
            return
        }
        await checkRegisteredExtensions(extensionID: id)
    }

    func checkRegisteredExtensions(extensionID: String,
        inspector: @escaping @Sendable (URL, String) throws -> ExtensionPresence = ProfileExtensionInventory.inspect) async {
        guard labs.apiEnabled else { return }
        let profiles = workspace.profiles, token = UUID()
        let sources = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.source) })
        extensionChecks = extensionChecks.filter { sources[$0.key] == $0.value.source }
        extensionCheckToken = token; checkingExtension = true
        defer { if extensionCheckToken == token { checkingExtension = false } }
        for profile in profiles {
            guard extensionCheckToken == token, labs.apiEnabled, !Task.isCancelled else { return }
            let local = coordinator.canWrite(profile.source), presence: ExtensionPresence
            do {
                presence = try await Task.detached {
                    try Self.scopedRead(profile, localTest: local) { try inspector(profile.source, extensionID) }
                }.value
            } catch { presence = .unavailable }
            guard extensionCheckToken == token, labs.apiEnabled, !Task.isCancelled else { return }
            guard workspace.profiles.contains(where: { $0.id == profile.id && $0.source == profile.source }) else {
                extensionChecks[profile.id] = nil; continue
            }
            extensionChecks[profile.id] = ExtensionInspection(profileID: profile.id, source: profile.source, presence: presence, checkedAt: Date())
        }
    }

    func showConnectionDetails() { connectionDetails = profile }
    func showPendingReview() {
        guard !busy, review == nil, connection == nil else { return }
        pendingReview = profile?.hasChanges == true ? profile : nil
    }
    var savedSampleProfiles: [ConnectedProfile] { workspace.profiles.filter(isLocalTestProfile) }

    func isLocalTestProfile(_ profile: ConnectedProfile) -> Bool {
        profile.source.isFileURL && profile.source.standardizedFileURL.path.hasPrefix(testRoot.path + "/")
    }

    init(sampleData: Bool = false, directory: URL? = nil, browserState: (@Sendable (URL) -> Bool)? = nil) {
        self.browserState = browserState
        self.directory = (directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "forked.galmuri.local")).standardizedFileURL
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: workspaceURL.path) { workspace = try Workspace.load(from: workspaceURL) }
            else {
                if sampleData {
                    let folder = testRoot.appendingPathComponent("Default")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let source = folder.appendingPathComponent("Bookmarks")
                    if !FileManager.default.fileExists(atPath: source.path) { try SampleData.file().original.write(to: source, options: .withoutOverwriting) }
                    workspace = Workspace(profiles: [ConnectedProfile(name: L("profile.localTest"), source: source, base: try ProfileIO.read(source))])
                }
                try workspace.save(to: workspaceURL)
            }
            selectedProfileID = (sampleData ? workspace.profiles.first : workspace.profiles.first { !isLocalTestProfile($0) })?.id
            do { labs = try LabOptions.load(from: labsURL) }
            catch { self.error = L("labs.optionsFailure") }
            do { try refreshBackups(); if unreadableBackupCount > 0 { error = L("backup.unreadable") } }
            catch { self.error = error.localizedDescription }
        } catch { savingDisabled = true; self.error = error.localizedDescription }
    }

    func refreshBackups() throws {
        let history = try coordinator.receiptHistory()
        backups = history.receipts; unreadableBackupCount = history.unreadableCount
    }

    var rows: [Bookmark] {
        guard let p = profile else { return [] }
        if navigation == "changes" {
            let changed = p.changedIDs
            var seen = Set<String>(), changes = [Bookmark]()
            func visit(_ snapshot: BookmarkTree, _ id: String) {
                guard let node = snapshot.nodes[id] else { return }
                if seen.insert(id).inserted, changed.contains(id) { changes.append(p.working.nodes[id] ?? node) }
                for child in node.children { visit(snapshot, child) }
            }
            for root in p.working.orderedRoots { visit(p.working, root) }
            for root in p.base.tree.orderedRoots { visit(p.base.tree, root) }
            let matching = changes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || ($0.url?.localizedCaseInsensitiveContains(search) ?? false) }
            return matching.filter(\.isFolder) + matching.filter { !$0.isFolder }
        }
        var order = [Bookmark]()
        func visit(_ id: String) {
            guard let n = p.working.nodes[id] else { return }
            if !p.working.roots.values.contains(id) { order.append(n) }
            for child in n.children { visit(child) }
        }
        if let folder {
            for id in p.working.nodes[folder]?.children ?? [] {
                if search.isEmpty { if let node = p.working.nodes[id] { order.append(node) } }
                else { visit(id) }
            }
        }
        else { for id in p.working.orderedRoots { visit(id) } }
        let duplicates = navigation == "duplicates" ? Dictionary(grouping: p.working.nodes.values.filter { $0.url != nil }, by: { $0.url! }).filter { $0.value.count > 1 } : [:]
        let matching = order.filter { n in
            (navigation != "duplicates" || n.url.map { duplicates[$0] != nil } == true) &&
            (search.isEmpty || n.name.localizedCaseInsensitiveContains(search) || (n.url?.localizedCaseInsensitiveContains(search) ?? false))
        }
        return matching.filter(\.isFolder) + matching.filter { !$0.isFolder }
    }

    func isRemovedRow(_ id: String) -> Bool { profile?.base.tree.nodes[id] != nil && tree?.nodes[id] == nil }
    func canEditRow(_ id: String) -> Bool { tree?.nodes[id] != nil && tree?.roots.values.contains(id) == false }
    var canMutateSelection: Bool { !selection.isEmpty && selection.allSatisfy(canEditRow) }
    func rowFolderPath(_ node: Bookmark) -> String {
        guard let profile, let parent = node.parent else { return L("review.root") }
        let snapshot = profile.working.nodes[node.id] == nil ? profile.base.tree : profile.working
        return snapshot.path(to: parent)
    }

    var folders: [Bookmark] { (tree?.nodes.values.filter(\.isFolder) ?? []).sorted { (tree?.path(to: $0.id) ?? "") < (tree?.path(to: $1.id) ?? "") } }

    var folderPath: [Bookmark] {
        var path = [Bookmark](), current = folder, seen = Set<String>()
        while let id = current, let node = tree?.nodes[id], seen.insert(id).inserted {
            path.append(node); current = node.parent
        }
        return path.reversed()
    }

    private func validLocation(_ route: String) -> Bool {
        ["all", "changes", "duplicates", "backups"].contains(route) || tree?.nodes[route]?.isFolder == true
    }

    var canGoBack: Bool { backLocations.contains { validLocation($0.route) } }
    var canGoForward: Bool { forwardLocations.contains { validLocation($0.route) } }

    func goBack() {
        while let target = backLocations.popLast() {
            guard validLocation(target.route) else { continue }
            forwardLocations.append((navigation, search))
            restoringNavigation = true; navigation = target.route; search = target.search; restoringNavigation = false
            selection.removeAll(); return
        }
    }

    func goForward() {
        while let target = forwardLocations.popLast() {
            guard validLocation(target.route) else { continue }
            backLocations.append((navigation, search))
            restoringNavigation = true; navigation = target.route; search = target.search; restoringNavigation = false
            selection.removeAll(); return
        }
    }

    func goUp() {
        guard let folder else { return }
        navigation = tree?.nodes[folder]?.parent ?? "all"
    }

    private func resetNavigation() {
        restoringNavigation = true; navigation = "all"; restoringNavigation = false
        backLocations.removeAll(); forwardLocations.removeAll(); selection.removeAll(); search = ""
    }

    func switchProfile(_ id: UUID) { selectedProfileID = id; resetNavigation() }

    func removeProfile(_ request: ProfileRemoval) -> URL? {
        let expected = request.profile
        guard !busy, review == nil, connection == nil,
              let index = workspace.profiles.firstIndex(where: { $0.id == expected.id }),
              workspace.profiles[index].source == expected.source,
              workspace.profiles[index].base == expected.base,
              workspace.profiles[index].working == expected.working else {
            error = L("editor.staleAction"); return nil
        }
        do {
            let archive = directory.appendingPathComponent("Disconnected-" + UUID().uuidString + ".json")
            try workspace.save(to: archive)
            let before = workspace
            workspace.profiles.remove(at: index)
            do { try persist() } catch { workspace = before; throw error }
            undoStacks[expected.id] = nil; accessIssues.remove(expected.id)
            if selectedProfileID == expected.id {
                selectedProfileID = workspace.profiles.first { !isLocalTestProfile($0) }?.id
                resetNavigation()
            }
            error = nil
            return archive
        } catch { self.error = error.localizedDescription; return nil }
    }

    func reorder(_ id: String, direction: Int) {
        edit { _ = try $0.reorderAmongPeers(id, direction: direction) }
    }

    /// Keep the 10 newest `<prefix><UUID>.json` archives (only superseded `BeforeRefresh-` snapshots; other archives are the sole copy of removed work) in `directory`; deletion failures are ignored.
    private func pruneArchives(_ prefix: String, keeping written: URL) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let archives = entries.compactMap { url -> (url: URL, date: Date)? in
            let name = url.lastPathComponent
            guard name != written.lastPathComponent, name.hasPrefix(prefix), name.hasSuffix(".json") else { return nil }
            let id = String(name.dropFirst(prefix.count).dropLast(5))
            guard UUID(uuidString: id)?.uuidString == id,
                  let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.date > $1.date }
        for archive in archives.dropFirst(9) { try? FileManager.default.removeItem(at: archive.url) }
    }

    func bookmarkURL(_ id: String) -> URL? {
        guard let address = tree?.nodes[id]?.url, (try? BookmarkTree.validateEditableURL(address)) != nil else { return nil }
        return URL(string: address)
    }

    func openBookmark(_ id: String, opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        guard let url = bookmarkURL(id) else { error = L("editor.cannotOpen"); return }
        if !opener(url) { error = L("editor.cannotOpen") }
    }

    func persist() throws {
        if savingDisabled { throw GalmuriError.invalid("The workspace could not be loaded. Its original file is preserved; import a verified workspace into a new local workspace to recover.") }
        try workspace.save(to: workspaceURL)
    }

    @discardableResult
    func edit(profileID: UUID, expectedWorking: BookmarkTree, _ operation: (inout BookmarkTree) throws -> Void) -> Bool {
        guard selectedProfileID == profileID, tree == expectedWorking else {
            error = L("editor.staleAction")
            return false
        }
        return edit(operation)
    }

    func deletionRequest(for ids: Set<String>) -> BookmarkDeletion? {
        guard let profile, !ids.isEmpty,
              ids.allSatisfy({ profile.working.nodes[$0] != nil && !profile.working.roots.values.contains($0) }) else { return nil }
        return BookmarkDeletion(profileID: profile.id, working: profile.working, itemIDs: ids)
    }

    func resetRequest() -> WorkingCopyReset? {
        guard !busy, review == nil, let profile, profile.hasChanges else { return nil }
        return WorkingCopyReset(profile: profile)
    }

    func revertRequest(for ids: Set<String>) -> WorkingCopyReset? {
        guard !busy, review == nil, let profile else { return nil }
        do {
            let target = try BookmarkRevert.selected(ids, base: profile.base.tree, working: profile.working)
            return WorkingCopyReset(profile: profile, target: target, itemIDs: ids)
        } catch { self.error = error.localizedDescription; return nil }
    }

    @discardableResult
    func resetWorkingCopy(_ request: WorkingCopyReset) -> Bool {
        let expected = request.profile
        guard !busy, review == nil, let profile, profile.id == expected.id,
              profile.source == expected.source, profile.base == expected.base, expected.hasChanges else {
            error = L("editor.staleAction")
            return false
        }
        guard edit(profileID: expected.id, expectedWorking: expected.working, { $0 = request.target }) else { return false }
        selection.removeAll()
        message = L(request.itemIDs == nil ? "editor.discardedChanges" : "editor.revertedSelection")
        return true
    }

    @discardableResult
    func delete(_ request: BookmarkDeletion) -> Bool {
        guard edit(profileID: request.profileID, expectedWorking: request.working, { try $0.remove(request.itemIDs) }) else { return false }
        message = localizedCount("editor.deletedCount", request.removedIDs.count)
        return true
    }

    @discardableResult
    func edit(_ operation: (inout BookmarkTree) throws -> Void) -> Bool {
        guard let id = selectedProfileID, let index = workspace.profiles.firstIndex(where: { $0.id == id }) else { return false }
        let before = workspace.profiles[index].working
        do {
            var next = before; try operation(&next); try next.validate()
            if next == before { return true }
            workspace.profiles[index].working = next
            do { try persist() } catch { workspace.profiles[index].working = before; throw error }
            undoStacks[id] = Array((undoStacks[id] ?? []).suffix(99)) + [before]
            if !validLocation(navigation) { navigation = "all" }
            selection.formIntersection(rows.map(\.id))
            message = L("status.savedLocally")
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func undo() {
        guard let id = selectedProfileID, let index = workspace.profiles.firstIndex(where: { $0.id == id }), let old = undoStacks[id]?.last else { return }
        let current = workspace.profiles[index].working
        workspace.profiles[index].working = old
        do {
            try persist(); undoStacks[id]?.removeLast()
            if !validLocation(navigation) { navigation = "all" }
            let changed = Set(old.nodes.keys).union(current.nodes.keys).filter { old.nodes[$0] != current.nodes[$0] }
            let restored = Set(old.nodes.keys).subtracting(current.nodes.keys)
            let targets = restored.isEmpty ? changed : restored.filter { !restored.contains(old.nodes[$0]?.parent ?? "") }
            selection = Set(rows.map(\.id)).intersection(targets)
            message = L("editor.undone")
        }
        catch { workspace.profiles[index].working = current; self.error = error.localizedDescription }
    }

    func selectBrowser(_ browser: BookmarkBrowser) {
        guard !busy, connection == nil else { return }
        connectionBrowser = browser
        connectionNotice = nil; error = nil; lastDiscoveryIssue = nil; lastDiscoveryDiagnostic = nil
    }

    func connect(_ browser: BookmarkBrowser? = nil) {
        guard !busy, connection == nil else { return }
        let browser = browser ?? connectionBrowser
        selectBrowser(browser)
        Task { await findProfiles(in: browser.dataDirectory, browser: browser) }
    }

    func directoryForLookup(_ expected: URL, origin: ProfileDiscoveryOrigin = .knownLocation) -> URL {
        guard origin == .knownLocation else { return expected }
        guard expected.isFileURL, expected.host == nil || expected.host == "localhost" else { return expected }
        for profile in workspace.profiles where profile.source.isFileURL && profile.source.standardizedFileURL.path.hasPrefix(expected.standardizedFileURL.path + "/") {
            guard let bookmark = profile.permissionBookmark else { continue }
            var stale = false
            if let scoped = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
               !stale, scoped.isFileURL, scoped.host == nil || scoped.host == "localhost",
               scoped.standardizedFileURL.path == expected.standardizedFileURL.path { return scoped }
        }
        return expected
    }

    func findProfiles(in directory: URL, browser: BookmarkBrowser? = nil, origin: ProfileDiscoveryOrigin = .knownLocation) async {
        guard !busy, connection == nil else { return }
        let browser = browser ?? connectionBrowser
        connectionBrowser = browser
        let found = await beginConnection(directoryForLookup(directory, origin: origin), browser: browser, origin: origin)
        if !found, let issue = lastDiscoveryIssue {
            connectionNotice = ProfileConnectionNotice(directory: directory, issue: issue, detail: error, browser: browser, origin: origin, diagnostic: lastDiscoveryDiagnostic)
        }
    }

    func dismissConnectionNotice() {
        guard !busy else { return }
        connectionNotice = nil; error = nil; lastDiscoveryIssue = nil; lastDiscoveryDiagnostic = nil
    }

    func chooseBrowserFolder(requiredDirectory: URL? = nil, browser: BookmarkBrowser? = nil) {
        guard !busy, connection == nil else { return }
        let browser = browser ?? connectionBrowser
        let directory = requiredDirectory ?? browser.dataDirectory
        let panel = BrowserFolderValidator.makePanel(directory: directory, requiresExactFolder: requiredDirectory != nil,
            title: String(format: L("profile.connectBrowser"), browser.name))
        let validator = requiredDirectory.map { BrowserFolderValidator(requiredDirectory: $0) }
        panel.delegate = validator
        let result = withExtendedLifetime(validator) { panel.runModal() }
        guard result == .OK, let selected = panel.url else { return }
        Task { await findProfiles(in: selected, browser: browser, origin: .folderSelection) }
    }

    @discardableResult
    func beginConnection(_ selected: URL?, browser: BookmarkBrowser? = nil, origin: ProfileDiscoveryOrigin = .knownLocation) async -> Bool {
        guard let selected, !busy else { return false }
        busy = true
        lastDiscoveryIssue = nil
        lastDiscoveryDiagnostic = nil
        let access = selected.startAccessingSecurityScopedResource()
        defer { if access { selected.stopAccessingSecurityScopedResource() }; busy = false }
        do {
            let profiles = try await Task.detached { try ProfileIO.discover(in: selected) }.value
            guard !profiles.isEmpty else { throw GalmuriError.invalid("No plaintext Bookmarks files were found in the selected folder.") }
            connection = ProfileConnection(directory: selected, profiles: profiles, browser: browser ?? connectionBrowser, origin: origin)
            connectionNotice = nil
            error = nil
            return true
        } catch { self.error = error.localizedDescription; lastDiscoveryIssue = .classify(error); lastDiscoveryDiagnostic = ProfileReadDiagnostic(error: error); return false }
    }

    @discardableResult
    func finishConnection(_ request: ProfileConnection, profileIDs: Set<String>) async -> Bool {
        guard !busy else { return false }
        guard connection?.id == request.id else { error = L("profile.selectionChanged"); return false }
        let connected = await connectDirectory(request.directory, profileIDs: profileIDs, browser: request.browser)
        if connected { connection = nil }
        else if lastDiscoveryIssue == .permissionDenied {
            connection = nil
            connectionNotice = ProfileConnectionNotice(directory: request.directory, issue: .permissionDenied, detail: error, browser: request.browser, origin: request.origin, diagnostic: lastDiscoveryDiagnostic)
        }
        return connected
    }

    @discardableResult
    func connectDirectory(_ selected: URL?, profileIDs: Set<String>? = nil, browser: BookmarkBrowser = .chrome) async -> Bool {
        guard let selected, !busy else { return false }
        busy = true
        lastDiscoveryIssue = nil
        lastDiscoveryDiagnostic = nil
        let access = selected.startAccessingSecurityScopedResource()
        var readingSource = true
        defer { if access { selected.stopAccessingSecurityScopedResource() }; busy = false }
        do {
            let bookmark = try selected.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            var discovered = try await Task.detached { try ProfileIO.discover(in: selected) }.value
            guard !discovered.isEmpty else { throw GalmuriError.invalid("No plaintext Bookmarks files were found in the selected folder.") }
            if let profileIDs {
                guard !profileIDs.isEmpty, profileIDs.isSubset(of: Set(discovered.map(\.id))) else {
                    error = L("profile.selectionChanged")
                    return false
                }
                discovered = discovered.filter { profileIDs.contains($0.id) }
            }
            guard discovered.allSatisfy(\.hasPlaintext) else { throw GalmuriError.unsupported("Bookmark storage detected without a plaintext Bookmarks file; this profile is unsupported.") }
            var additions = [ConnectedProfile]()
            for found in discovered where !workspace.profiles.contains(where: { $0.source.standardizedFileURL == found.file.standardizedFileURL }) {
                let file = try await Task.detached { try ProfileIO.read(found.file) }.value
                additions.append(ConnectedProfile(name: found.name, source: found.file, permissionBookmark: bookmark, sourceRestriction: found.restriction ?? browser.storageWarning, base: file))
            }
            readingSource = false
            let old = workspace; workspace.profiles += additions
            do { try persist() } catch { workspace = old; throw error }
            if let first = additions.first { switchProfile(first.id) }
            message = L("profile.connectedReadOnly")
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            // The selected-store reader also uses .permission for nonregular/symlink inputs; an OS grant cannot fix them.
            let issue: ProfileDiscoveryIssue = error as? GalmuriError == .permission ? .unavailable : .classify(error)
            lastDiscoveryIssue = readingSource ? issue : .unavailable
            lastDiscoveryDiagnostic = ProfileReadDiagnostic(error: error)
            return false
        }
    }

    func reconnect() {
        guard let id = selectedProfileID else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        if let profile = workspace.profiles.first(where: { $0.id == id }) { panel.directoryURL = profile.source.deletingLastPathComponent() }
        panel.allowsMultipleSelection = false; panel.message = L("profile.chooseOriginalFolder")
        let selected = panel.runModal() == .OK ? panel.url : nil
        Task { await reconnectDirectory(selected, profileID: id) }
    }

    func reconnectDirectory(_ selected: URL?, profileID: UUID) async {
        guard let selected, !busy, let existing = workspace.profiles.first(where: { $0.id == profileID }) else { return }
        busy = true
        let access = selected.startAccessingSecurityScopedResource()
        defer { if access { selected.stopAccessingSecurityScopedResource() }; busy = false }
        do {
            let bookmark = try selected.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            let found = try await Task.detached { try ProfileIO.discover(in: selected) }.value
            guard let original = found.first(where: { $0.file.standardizedFileURL == existing.source.standardizedFileURL }) else {
                throw GalmuriError.invalid("Select the original profile folder. A different or moved source is not automatically remapped.")
            }
            guard original.hasPlaintext else { throw GalmuriError.unsupported("Bookmark storage detected without a plaintext Bookmarks file; this profile is unsupported.") }
            let latest = try await Task.detached { try ProfileIO.read(original.file) }.value
            guard latest.tree.roots == existing.base.tree.roots else { throw GalmuriError.invalid("Profile identity changed; the working copy is preserved.") }
            guard let index = workspace.profiles.firstIndex(where: { $0.id == profileID }), workspace.profiles[index].source == existing.source else { throw GalmuriError.staleSource }
            let before = workspace.profiles[index]
            workspace.profiles[index].permissionBookmark = bookmark
            workspace.profiles[index].sourceRestriction = original.restriction ?? (existing.sourceRestriction == BookmarkBrowser.egoLite.storageWarning ? existing.sourceRestriction : nil)
            do { try persist() } catch { workspace.profiles[index] = before; throw error }
            accessIssues.remove(profileID); error = nil; message = L("profile.reconnected")
        } catch { accessIssues.insert(profileID); self.error = error.localizedDescription }
    }

    func withAccess<T>(_ profile: ConnectedProfile, operation: () throws -> T) throws -> T {
        do {
            let value = try Self.scopedRead(profile, localTest: coordinator.canWrite(profile.source), operation: operation); accessIssues.remove(profile.id); return value
        } catch { noteAccessFailure(error, for: profile.id); throw error }
    }

    /// `withAccess` off the main actor: the scoped bookmark is started and stopped on the worker thread that reads.
    private func withDetachedAccess<T: Sendable>(_ profile: ConnectedProfile, operation: @escaping @Sendable (ApplyCoordinator) throws -> T) async throws -> T {
        let coordinator = coordinator, local = coordinator.canWrite(profile.source)
        do {
            let value = try await Task.detached { try Self.scopedRead(profile, localTest: local) { try operation(coordinator) } }.value
            accessIssues.remove(profile.id); return value
        } catch { noteAccessFailure(error, for: profile.id); throw error }
    }

    private func noteAccessFailure(_ error: Error, for id: UUID) {
        let nsError = error as NSError
        let posixAccessFailure = nsError.domain == NSPOSIXErrorDomain && [POSIXErrorCode.EACCES, .EPERM, .ENOENT, .ELOOP].contains { Int($0.rawValue) == nsError.code }
        if error as? GalmuriError == .permission || posixAccessFailure || nsError.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(nsError.code) { accessIssues.insert(id) }
    }

    /// True when the stored profile still has the source, base and working copy captured in `snapshot`.
    private func isCurrent(_ snapshot: ConnectedProfile) -> Bool {
        guard let current = workspace.profiles.first(where: { $0.id == snapshot.id }) else { return false }
        return current.source == snapshot.source && current.base == snapshot.base && current.working == snapshot.working
    }

    nonisolated private static func scopedRead<T>(_ profile: ConnectedProfile, localTest: Bool, operation: () throws -> T) throws -> T {
        guard let bookmark = profile.permissionBookmark else {
            guard localTest else { throw GalmuriError.permission }
            return try operation()
        }
        var stale = false
        let url: URL
        do { url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) }
        catch { throw GalmuriError.permission }
        guard !stale, profile.source.standardizedFileURL.path.hasPrefix(url.standardizedFileURL.path + "/"), url.startAccessingSecurityScopedResource() else { throw GalmuriError.permission }
        defer { url.stopAccessingSecurityScopedResource() }
        return try operation()
    }

    private func readRefreshSource(_ profile: ConnectedProfile) async throws -> (BookmarkFile, ApplySourceIdentity, String?) {
        let coordinator = coordinator, local = coordinator.canWrite(profile.source)
        return try await Task.detached {
            try Self.scopedRead(profile, localTest: local) {
                let candidates = try ProfileIO.discover(in: profile.source.deletingLastPathComponent())
                guard let found = candidates.first(where: { $0.file.standardizedFileURL == profile.source.standardizedFileURL }) else {
                    throw GalmuriError.unsupported("No plaintext Bookmarks files were found in the selected folder.")
                }
                guard found.canImportPlaintext else {
                    throw GalmuriError.unsupported(found.files.first(where: { $0.kind == .plaintext })?.problem ?? "No plaintext Bookmarks files were found in the selected folder.")
                }
                let snapshot = try coordinator.readForReview(profile.source)
                return (snapshot.file, snapshot.identity, found.restriction ?? profile.sourceRestriction)
            }
        }.value
    }

    func refreshProfile() async {
        guard !busy, review == nil, connection == nil, let profile else { return }
        busy = true; defer { busy = false }
        do {
            let (latest, identity, restriction) = try await readRefreshSource(profile)
            let result = try await Task.detached { try MergeEngine.merge(base: profile.base.tree, ours: profile.working, theirs: latest.tree) }.value
            guard self.profile?.id == profile.id, self.profile?.working == profile.working, self.profile?.base == profile.base, self.profile?.source == profile.source else { throw GalmuriError.staleSource }
            let session = ReviewSession(profileID: profile.id, mode: .refresh)
            session.baseAtReview = profile.base; session.sourceAtReview = profile.source
            session.latest = latest; session.sourceIdentity = identity; session.restrictionAtReview = restriction
            session.workingAtReview = profile.working; session.result = result; session.phase = .conflicts
            accessIssues.remove(profile.id); error = nil; review = session
        } catch {
            if error as? GalmuriError == .permission || ProfileDiscoveryIssue.classify(error) == .permissionDenied { accessIssues.insert(profile.id) }
            self.error = error.localizedDescription
        }
    }

    private func matchesRefresh(_ session: ReviewSession) -> Bool {
        session.mode == .refresh && selectedProfileID == session.profileID && profile?.source == session.sourceAtReview && profile?.base == session.baseAtReview && profile?.working == session.workingAtReview
    }

    func acceptRefresh(_ session: ReviewSession) async {
        guard !busy, review?.id == session.id, matchesRefresh(session), session.acknowledged,
              let profile, let latest = session.latest, let result = session.result, result.unresolved.isEmpty else {
            error = L("editor.staleAction"); return
        }
        busy = true; defer { busy = false }
        do {
            let (current, identity, restriction) = try await readRefreshSource(profile)
            guard !Task.isCancelled, review?.id == session.id, session.acknowledged, matchesRefresh(session), current.fingerprint == latest.fingerprint, identity == session.sourceIdentity,
                  restriction == session.restrictionAtReview,
                  let index = workspace.profiles.firstIndex(where: { $0.id == profile.id }) else { throw GalmuriError.staleSource }
            let before = workspace.profiles[index]
            let archive = directory.appendingPathComponent("BeforeRefresh-" + UUID().uuidString + ".json")
            try workspace.save(to: archive)
            pruneArchives("BeforeRefresh-", keeping: archive)
            workspace.profiles[index].base = latest; workspace.profiles[index].working = result.tree
            workspace.profiles[index].sourceRestriction = restriction
            do { try persist() } catch { workspace.profiles[index] = before; throw error }
            undoStacks[profile.id] = []; selection.removeAll()
            if !validLocation(navigation) { navigation = "all" }
            accessIssues.remove(profile.id)
            session.localArchive = archive; session.phase = .complete; message = L("refresh.complete"); error = nil
        } catch {
            if error as? GalmuriError == .permission || ProfileDiscoveryIssue.classify(error) == .permissionDenied { accessIssues.insert(profile.id) }
            session.acknowledged = false; session.phase = .exit; self.error = error.localizedDescription
        }
    }

    func browserRunning(for source: URL) -> Bool {
        if let browserState { return browserState(source) }
        return BrowserUsage.isRunning(for: source)
    }

    /// Browser check the coordinator can call from a worker thread during a commit.
    private var sendableBrowserCheck: @Sendable (URL) -> Bool {
        if let browserState { return browserState }
        return { source in
            // BrowserUsage reads NSWorkspace on the main actor; the caller is suspended in an await, so main is free.
            Thread.isMainThread ? MainActor.assumeIsolated { BrowserUsage.isRunning(for: source) }
                : DispatchQueue.main.sync { MainActor.assumeIsolated { BrowserUsage.isRunning(for: source) } }
        }
    }

    var canReviewFileApplyExperiment: Bool {
        guard !busy, review == nil, connection == nil, let profile else { return false }
        return labs.fileEnabled && profile.hasChanges && coordinator.canWrite(profile.source) &&
            profile.sourceRestriction == nil && profile.base.writeRestriction == nil
    }

    func fileApplyExperimentReview() -> ReviewSession? {
        guard canReviewFileApplyExperiment, let profile else { return nil }
        return ReviewSession(profileID: profile.id)
    }

    func loadReview(_ session: ReviewSession) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        await reloadReview(session)
    }

    /// Callers hold `busy`.
    private func reloadReview(_ session: ReviewSession) async {
        session.acknowledged = false; session.resolutions = [:]; session.result = nil
        session.latest = nil; session.workingAtReview = nil; session.sourceIdentity = nil; session.phase = .exit
        guard let p = workspace.profiles.first(where: { $0.id == session.profileID }) else { return }
        do {
            if coordinator.canWrite(p.source), browserRunning(for: p.source) { throw GalmuriError.browserRunning }
            let prepared = try await withDetachedAccess(p) { try $0.prepare(profile: p) }
            guard isCurrent(p) else { throw GalmuriError.staleSource }
            session.latest = prepared.latest; session.result = prepared.result; session.resolutions = [:]
            session.workingAtReview = p.working
            session.sourceIdentity = prepared.sourceIdentity
            session.acknowledged = false; session.phase = .conflicts
        } catch { self.error = error.localizedDescription }
    }

    func resolve(_ conflict: String, side: MergeSide, in session: ReviewSession) async {
        if session.mode == .refresh && !matchesRefresh(session) { error = L("editor.staleAction"); return }
        guard !busy, let p = workspace.profiles.first(where: { $0.id == session.profileID }), let latest = session.latest else { return }
        busy = true; defer { busy = false }
        let previous = session.resolutions
        var choices = previous; choices[conflict] = side
        do {
            let result = try await Task.detached { [choices] in try MergeEngine.merge(base: p.base.tree, ours: p.working, theirs: latest.tree, resolutions: choices) }.value
            // A result computed for older choices or an older snapshot must not replace a newer state.
            guard session.resolutions == previous, session.latest == latest, isCurrent(p),
                  session.mode != .refresh || matchesRefresh(session) else { error = L("editor.staleAction"); return }
            session.resolutions = choices; session.result = result; session.acknowledged = false
        } catch { self.error = error.localizedDescription }
    }

    func apply(_ session: ReviewSession) async {
        guard labs.fileEnabled else { session.acknowledged = false; error = L("labs.fileDisabled"); return }
        guard !busy, session.acknowledged, let index = workspace.profiles.firstIndex(where: { $0.id == session.profileID }), let latest = session.latest, let result = session.result else { return }
        busy = true; defer { busy = false }
        let p = workspace.profiles[index]
        guard p.working == session.workingAtReview else { await reloadReview(session); self.error = L("apply.sourceChanged"); return }
        let coordinator = coordinator, check = sendableBrowserCheck
        let review = ApplyReview(latest: latest, result: result, sourceIdentity: session.sourceIdentity)
        do {
            let receipt = try await Task.detached { try coordinator.apply(profile: p, review: review, browserRunning: { check(p.source) }) }.value
            session.receipt = receipt; session.phase = .complete
            do {
                let after = try await Task.detached { try ProfileIO.read(p.source) }.value
                // The file is written either way; only adopt it when the stored profile is still the one applied.
                guard isCurrent(p), let index = workspace.profiles.firstIndex(where: { $0.id == p.id }) else { try? refreshBackups(); throw GalmuriError.staleSource }
                workspace.profiles[index].base = after; workspace.profiles[index].working = after.tree; undoStacks[p.id] = []
                try refreshBackups(); try persist()
            } catch { self.error = L("result.fileVerified") + "\n" + error.localizedDescription }
        } catch GalmuriError.staleSource {
            await reloadReview(session); self.error = L("apply.sourceChanged")
        } catch {
            self.error = error.localizedDescription
            try? refreshBackups()
        }
    }

    /// Returns true only when the restore completed.
    @discardableResult
    func restore(_ receipt: BackupReceipt, expectedHash: String, expectedIdentity: ApplySourceIdentity? = nil) async -> Bool {
        guard labs.fileEnabled else { error = L("labs.fileDisabled"); return false }
        guard !busy else { return false }
        busy = true; defer { busy = false }
        let coordinator = coordinator, check = sendableBrowserCheck
        let tracked = workspace.profiles.contains { $0.source == receipt.source }
        do {
            let restored = try await Task.detached { () throws -> BookmarkFile? in
                _ = try coordinator.restore(receipt, expectedCurrentHash: expectedHash, expectedCurrentIdentity: expectedIdentity, browserRunning: { check(receipt.source) })
                return try tracked ? ProfileIO.read(receipt.source) : nil
            }.value
            if let restored, let index = workspace.profiles.firstIndex(where: { $0.source == receipt.source }) {
                workspace.profiles[index].base = restored
            }
            try refreshBackups(); try persist(); message = L("backup.restoredWorkingCopyKept")
            return true
        } catch { self.error = error.localizedDescription; try? refreshBackups(); return false }
    }

    func exportHTML() {
        guard tree != nil else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "galmuri-bookmarks.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportHTML(to: url)
    }

    func exportHTML(to url: URL) {
        guard let tree else { return }
        do {
            let export = try ProfileIO.exportHTMLSkippingUnsupported(tree, under: folder)
            try export.data.write(to: url, options: .atomic)
            if export.skipped > 0 { message = localizedCount("export.skippedUnsupportedCount", export.skipped) }
        } catch { self.error = error.localizedDescription }
    }

    func exportWorkspace() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "galmuri-workspace.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try workspace.save(to: url) } catch { self.error = error.localizedDescription }
    }

    func importWorkspace() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try Workspace.load(from: url)
            let backup = directory.appendingPathComponent("workspace-before-import-" + UUID().uuidString + ".json")
            try workspace.save(to: backup)
            let old = workspace; workspace = incoming
            do { try persist() } catch { workspace = old; throw error }
            selectedProfileID = workspace.profiles.first?.id; resetNavigation(); undoStacks = [:]
        } catch { self.error = error.localizedDescription }
    }
}
