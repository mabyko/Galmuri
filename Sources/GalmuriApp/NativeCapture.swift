#if DEBUG
import AppKit
import SwiftUI
import GalmuriCore

// Captures only this app's synthetic windows, never the desktop or another app.
@MainActor
enum NativeCapture {
    static func run(store: AppStore, output: URL) async throws {
        guard store.workspace.profiles.count == 1, let profile = store.profile,
              store.coordinator.canWrite(profile.source), !profile.hasChanges,
              store.backups.isEmpty else { throw GalmuriError.localTestsOnly }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await settle()
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
            throw GalmuriError.invalid("native window did not appear")
        }
        window.appearance = NSAppearance(named: .darkAqua)
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let width = min(1180, visible.width), height = min(820, visible.height)
            window.setFrame(NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height), display: true)
        }
        try await settle()
        try capture(window, to: output.appendingPathComponent("editor.png"))

        guard let openedFolder = profile.working.nodes.values.first(where: { $0.isFolder && $0.parent != nil }),
              let navigationTable = table(in: window.contentView), window.makeFirstResponder(navigationTable) else {
            throw GalmuriError.invalid("synthetic folder navigation unavailable")
        }
        store.selection = [openedFolder.id]
        try await settle()
        try key("\r", code: 36, in: window)
        try await settle()
        guard store.navigation == openedFolder.id, window.attachedSheet == nil,
              store.rows.allSatisfy({ $0.parent == openedFolder.id }),
              store.folderPath.last?.id == openedFolder.id else {
            throw GalmuriError.invalid("Return did not open the direct folder contents")
        }
        try capture(window, to: output.appendingPathComponent("folder-navigation.png"))
        try key(String(UnicodeScalar(NSUpArrowFunctionKey)!), code: 126, modifiers: .command, in: window)
        try await settle()
        guard store.navigation == openedFolder.parent else { throw GalmuriError.invalid("Enclosing Folder shortcut failed") }
        try capture(window, to: output.appendingPathComponent("folder-parent.png"))
        try key("[", code: 33, modifiers: .command, in: window)
        try await settle()
        guard store.navigation == openedFolder.id else { throw GalmuriError.invalid("Back shortcut failed") }
        try key("]", code: 30, modifiers: .command, in: window)
        try await settle()
        guard store.navigation == openedFolder.parent, store.tree == profile.working,
              try Data(contentsOf: profile.source) == profile.base.original else {
            throw GalmuriError.invalid("Forward changed folder data or failed")
        }
        store.navigation = "all"
        window.makeFirstResponder(nil)
        try await settle()

        let onboarding = AppStore(directory: output.appendingPathComponent("EmptyWorkspace"))
        guard onboarding.workspace.profiles.isEmpty, onboarding.profile == nil else { throw GalmuriError.invalid("new workspace did not start empty") }
        let onboardingWindow = NSWindow(contentViewController: NSHostingController(rootView: RootView(store: onboarding)))
        onboardingWindow.isReleasedWhenClosed = false
        onboardingWindow.setContentSize(NSSize(width: 1000, height: 720))
        onboardingWindow.center(); onboardingWindow.makeKeyAndOrderFront(nil)
        try await settle()
        try capture(onboardingWindow, to: output.appendingPathComponent("welcome.png"))
        await onboarding.findProfiles(in: output.appendingPathComponent("MissingChromeFixture"))
        guard onboarding.connectionNotice?.issue == .missingLocation else { throw GalmuriError.invalid("missing Chrome notice not shown") }
        try await settle()
        try capture(onboardingWindow, to: output.appendingPathComponent("missing-location.png"))
        let deniedChrome = output.appendingPathComponent("PermissionFixtures/Chrome")
        try FileManager.default.createDirectory(at: deniedChrome, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: deniedChrome.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: deniedChrome.path) }
        await onboarding.findProfiles(in: deniedChrome)
        guard onboarding.connectionNotice?.issue == .permissionDenied else { throw GalmuriError.invalid("permission notice not shown") }
        guard let fileNotice = onboarding.connectionNotice,
              fileNotice.diagnostic?.posixCode == Int(POSIXErrorCode.EACCES.rawValue),
              fileNotice.guidance(onMacOSMajorVersion: 27) == .filePermissions else {
            throw GalmuriError.invalid("file-permission guidance did not retain EACCES")
        }
        try await settle()
        try capture(onboardingWindow, to: output.appendingPathComponent("file-permission-needed.png"))
        // Render a synthetic restricted-access state without touching TCC or a real browser folder.
        var settingsNotice = fileNotice
        settingsNotice.diagnostic = ProfileReadDiagnostic(error: POSIXError(.EPERM))
        settingsNotice.detail = POSIXError(.EPERM).localizedDescription
        guard settingsNotice.guidance(onMacOSMajorVersion: 27) == .folderSelection else {
            throw GalmuriError.invalid("initial Chrome denial must show folder consent")
        }
        onboarding.connectionNotice = settingsNotice
        try await settle()
        try capture(onboardingWindow, to: output.appendingPathComponent("access-needed.png"))
        settingsNotice.origin = .folderSelection
        guard settingsNotice.guidance(onMacOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) == .systemSettings else {
            throw GalmuriError.invalid("selected-folder Settings fallback capture requires macOS 27 or later")
        }
        onboarding.connectionNotice = settingsNotice
        try await settle()
        try capture(onboardingWindow, to: output.appendingPathComponent("settings-access-needed.png"))
        settingsNotice.origin = .knownLocation
        settingsNotice.browser = .egoLite
        guard settingsNotice.guidance(onMacOSMajorVersion: 27) == .folderSelection else { throw GalmuriError.invalid("Ego fallback route changed") }
        onboarding.connectionNotice = settingsNotice
        try await settle()
        try capture(onboardingWindow, to: output.appendingPathComponent("folder-access-needed.png"))
        onboarding.connectionNotice = fileNotice
        await onboarding.findProfiles(in: deniedChrome)
        guard onboarding.connectionNotice?.issue == .permissionDenied else { throw GalmuriError.invalid("denied retry advanced without access") }
        onboarding.dismissConnectionNotice()
        guard onboarding.connectionNotice == nil, onboarding.workspace.profiles.isEmpty else { throw GalmuriError.invalid("permission back changed workspace") }
        await onboarding.findProfiles(in: deniedChrome)
        guard onboarding.connectionNotice?.issue == .permissionDenied else { throw GalmuriError.invalid("permission guide not restored") }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: deniedChrome.path)
        let chromeFixture = deniedChrome
        for name in ["Default", "Profile 1"] {
            let directory = chromeFixture.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try SampleData.file().original.write(to: directory.appendingPathComponent("Bookmarks"), options: .withoutOverwriting)
        }
        let excluded = Data([0xff, 0x00, 0xfe])
        let encryptedCompanion = chromeFixture.appendingPathComponent("Default/EncryptedBookmarks2")
        for name in ["EncryptedBookmarks2", "AccountBookmarks", "BookmarkMergedSurfaceOrdering", "Bookmarks.bak"] {
            try excluded.write(to: chromeFixture.appendingPathComponent("Default/" + name))
        }
        let unreadable = chromeFixture.appendingPathComponent("Profile 3")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try SampleData.file().original.write(to: unreadable.appendingPathComponent("Bookmarks"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.appendingPathComponent("Bookmarks").path)
        let unavailable = chromeFixture.appendingPathComponent("Profile 2")
        try FileManager.default.createDirectory(at: unavailable, withIntermediateDirectories: true)
        try Data("synthetic unsupported storage".utf8).write(to: unavailable.appendingPathComponent("EncryptedBookmarks2"))
        try Data(#"{"profile":{"info_cache":{"Default":{"name":"Mixed files · Example"},"Profile 1":{"name":"Plaintext · Example"},"Profile 2":{"name":"Encrypted only · Example"},"Profile 3":{"name":"Unreadable · Example"}}}}"#.utf8)
            .write(to: chromeFixture.appendingPathComponent("Local State"))
        await onboarding.findProfiles(in: chromeFixture)
        try await settle()
        guard let request = onboarding.connection, request.profiles.count == 4,
              let chooser = onboardingWindow.attachedSheet else { throw GalmuriError.invalid("native profile chooser did not appear") }
        try capture(chooser, to: output.appendingPathComponent("profile-chooser.png"))
        guard let mixed = request.profiles.first(where: { $0.directory.lastPathComponent == "Default" }),
              mixed.canImportPlaintext, mixed.files.count == 5,
              request.profiles.filter(\.canImportPlaintext).count == 2 else { throw GalmuriError.invalid("plaintext file availability mismatch") }
        let fileWindow = NSWindow(contentViewController: NSHostingController(rootView: ProfileSourceFilesView(files: mixed.files).padding(20)))
        fileWindow.isReleasedWhenClosed = false
        fileWindow.setContentSize(NSSize(width: 660, height: 400))
        fileWindow.center(); fileWindow.makeKeyAndOrderFront(nil)
        try await settle()
        try capture(fileWindow, to: output.appendingPathComponent("profile-files.png"))
        fileWindow.close(); chooser.makeKeyAndOrderFront(nil)
        let selected = chromeFixture.appendingPathComponent("Default").path
        guard await onboarding.finishConnection(request, profileIDs: [selected]), onboarding.workspace.profiles.count == 1,
              onboarding.profile?.source == chromeFixture.appendingPathComponent("Default/Bookmarks"),
              try Data(contentsOf: encryptedCompanion) == excluded,
              onboarding.profile?.sourceRestriction != nil,
              !onboarding.coordinator.canWrite(onboarding.profile!.source) else {
            throw GalmuriError.invalid("explicit read-only profile selection failed")
        }
        try await settle()
        try capture(onboardingWindow, to: output.appendingPathComponent("connected-profile.png"))
        let connectedTree = onboarding.tree, connectedBytes = try Data(contentsOf: onboarding.profile!.source)
        onboarding.showConnectionDetails()
        try await settle()
        guard let detailsSheet = onboardingWindow.attachedSheet, detailsSheet.contentView != nil else { throw GalmuriError.invalid("connection details sheet unavailable") }
        try capture(detailsSheet, to: output.appendingPathComponent("connection-details.png"))
        try key("\u{1b}", code: 53, in: detailsSheet)
        try await settle()
        guard onboardingWindow.attachedSheet == nil, onboarding.tree == connectedTree,
              try Data(contentsOf: onboarding.profile!.source) == connectedBytes else { throw GalmuriError.invalid("connection details dismissal changed work") }

        onboarding.selectedProfileID = nil
        onboarding.selectBrowser(.egoLite)
        try await settle()
        try capture(onboardingWindow, to: output.appendingPathComponent("ego-welcome.png"))
        let egoFixture = output.appendingPathComponent("ApprovedEgoFixture")
        let egoProfile = egoFixture.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: egoProfile, withIntermediateDirectories: true)
        let egoSource = egoProfile.appendingPathComponent("Bookmarks")
        let egoOriginal = try SampleData.file().original
        try egoOriginal.write(to: egoSource, options: .withoutOverwriting)
        try Data(#"{"profile":{"info_cache":{"Default":{"name":"Ego · Example"}}}}"#.utf8).write(to: egoFixture.appendingPathComponent("Local State"))
        await onboarding.findProfiles(in: egoFixture, browser: .egoLite)
        try await settle()
        guard let egoRequest = onboarding.connection, egoRequest.browser == .egoLite,
              let egoChooser = onboardingWindow.attachedSheet else { throw GalmuriError.invalid("Ego fixture chooser did not appear") }
        try capture(egoChooser, to: output.appendingPathComponent("ego-profile-chooser.png"))
        guard await onboarding.finishConnection(egoRequest, profileIDs: Set(egoRequest.profiles.map(\.id))),
              onboarding.workspace.profiles.count == 2,
              onboarding.profile?.sourceRestriction == BookmarkBrowser.egoLite.storageWarning,
              !onboarding.coordinator.canWrite(egoSource), try Data(contentsOf: egoSource) == egoOriginal else {
            throw GalmuriError.invalid("Ego fixture read-only warning or source preservation")
        }
        try await settle()
        try capture(onboardingWindow, to: output.appendingPathComponent("ego-connected-profile.png"))
        onboardingWindow.close(); window.makeKeyAndOrderFront(nil)

        guard let settingsItem = NSApp.mainMenu?.items.first?.submenu?.items.first(where: {
            $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command)
        }), let action = settingsItem.action,
              NSApp.sendAction(action, to: settingsItem.target, from: settingsItem) else {
            throw GalmuriError.invalid("native Settings command unavailable")
        }
        try await settle()
        guard let settings = NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.contentView != nil }) else {
            throw GalmuriError.invalid("native Settings window did not appear")
        }
        try capture(settings, to: output.appendingPathComponent("settings.png"))
        store.settingsNavigation = "labs"
        try await settle()
        try capture(settings, to: output.appendingPathComponent("settings-labs.png"))
        let preferenceFile = store.profile!.source.deletingLastPathComponent().appendingPathComponent("Preferences")
        let configuration = try JSONSerialization.jsonObject(with: Data(contentsOf: Bundle.main.url(forResource: "BridgeConfiguration", withExtension: "json")!)) as! [String: String]
        let extensionID = configuration["extensionID"]!
        try JSONSerialization.data(withJSONObject: ["extensions": ["settings": [extensionID: ["state": 1, "path": "/synthetic/Galmuri-extension"]]]]).write(to: preferenceFile, options: .withoutOverwriting)
        guard store.setLabOptions(api: true, file: true) else { throw GalmuriError.invalid("Labs options save") }
        try await settle()
        guard store.extensionChecks[store.profile!.id]?.presence == .recordFound else { throw GalmuriError.invalid("selected profile extension record") }
        try capture(settings, to: output.appendingPathComponent("labs-enabled.png"))
        try JSONSerialization.data(withJSONObject: ["extensions": ["settings": [String: String]()]]).write(to: preferenceFile, options: .atomic)
        await store.checkRegisteredExtensions()
        guard store.extensionChecks[store.profile!.id]?.presence == .notDetected else { throw GalmuriError.invalid("missing extension record") }
        try capture(settings, to: output.appendingPathComponent("extension-not-detected.png"))
        guard store.setLabOptions(api: false, file: false) else { throw GalmuriError.invalid("Labs options disable") }
        settings.close()
        let registered = AppStore(sampleData: true, directory: output.appendingPathComponent("RegisteredProfilesWorkspace"))
        registered.workspace.profiles[0].name = "Example A"
        for name in ["Example B", "Example C"] {
            let folder = registered.testRoot.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = try SampleData.file(), source = folder.appendingPathComponent("Bookmarks")
            try file.original.write(to: source)
            registered.workspace.profiles.append(ConnectedProfile(name: name, source: source, base: file))
        }
        try JSONSerialization.data(withJSONObject: ["extensions": ["settings": [extensionID: ["state": 1]]]])
            .write(to: registered.workspace.profiles[0].source.deletingLastPathComponent().appendingPathComponent("Preferences"))
        try Data("{}".utf8).write(to: registered.workspace.profiles[1].source.deletingLastPathComponent().appendingPathComponent("Preferences"))
        guard registered.setLabOptions(api: true) else { throw GalmuriError.invalid("registered profiles opt-in") }
        registered.settingsNavigation = "labs"
        let registeredWindow = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(directory: registered.directory, store: registered)))
        registeredWindow.isReleasedWhenClosed = false; registeredWindow.center(); registeredWindow.makeKeyAndOrderFront(nil)
        try await settle()
        guard registered.extensionChecks.isEmpty else { throw GalmuriError.invalid("Settings appearance automatically rescanned") }
        await registered.checkRegisteredExtensions()
        guard registered.extensionChecks.count == 3,
              registered.extensionChecks[registered.workspace.profiles[0].id]?.presence == .recordFound,
              registered.extensionChecks[registered.workspace.profiles[1].id]?.presence == .notDetected,
              registered.extensionChecks[registered.workspace.profiles[2].id]?.presence == .unavailable else { throw GalmuriError.invalid("registered profiles evidence table") }
        try await settle()
        try capture(registeredWindow, to: output.appendingPathComponent("registered-extensions.png"))
        registeredWindow.close()
        guard Bundle.main.url(forResource: "Galmuri-Chrome-Extension", withExtension: "zip") != nil else {
            throw GalmuriError.invalid("packaged extension ZIP missing")
        }
        let installWindow = NSWindow(contentViewController: NSHostingController(rootView: ExtensionInstallView()))
        installWindow.isReleasedWhenClosed = false
        installWindow.setContentSize(NSSize(width: 600, height: 500))
        installWindow.center(); installWindow.makeKeyAndOrderFront(nil)
        try await settle()
        try capture(installWindow, to: output.appendingPathComponent("extension-install.png"))
        installWindow.close()
        let proofStore = BridgeProofStore(workspace: store.directory, variant: "debug")
        let proof = try proofStore.create(installationID: UUID(), name: "Synthetic QA profile")
        let proofWindow = NSWindow(contentViewController: NSHostingController(rootView: BridgeProofView(directory: store.directory, requests: [proof]).frame(width: 580, height: 460)))
        proofWindow.isReleasedWhenClosed = false
        proofWindow.setContentSize(NSSize(width: 580, height: 460))
        proofWindow.center(); proofWindow.makeKeyAndOrderFront(nil)
        try await settle()
        try capture(proofWindow, to: output.appendingPathComponent("bridge-proof.png"))
        proofWindow.close()
        try proofStore.approve(proof)
        guard try proofStore.approved(proof) else { throw GalmuriError.invalid("bridge proof approval") }
        try proofStore.close(proof)
        let apiDirectory = output.appendingPathComponent("APIUIFixture")
        let apiModel = APIWorkspaceModel(directory: apiDirectory, variant: "debug")
        let apiSession = try apiModel.proof.create(installationID: UUID(), name: "Synthetic API profile")
        try apiModel.proof.approve(apiSession)
        let synthetic = try SampleData.file().tree
        var apiNodes: [[String: Any]] = [["id": "root", "title": "", "children": synthetic.orderedRoots.map { synthetic.nodes[$0]!.chromeID }, "managed": false, "syncing": false]]
        for n in synthetic.nodes.values {
            var value: [String: Any] = ["id": n.chromeID, "title": n.name, "parent": n.parent.map { synthetic.nodes[$0]!.chromeID } ?? "root", "children": n.children.map { synthetic.nodes[$0]!.chromeID }, "managed": false, "syncing": false]
            if let url = n.url { value["url"] = url }
            apiNodes.append(value)
        }
        let apiRaw = String(decoding: try JSONSerialization.data(withJSONObject: ["nodes": apiNodes]), as: UTF8.self)
        let apiSource = APIEnvelope(session: apiSession, writable: true, raw: apiRaw)
        try apiModel.store.put(apiSource, name: apiSession.id.uuidString + ".snapshot")
        await apiModel.load()
        let apiScope = synthetic.nodes[synthetic.roots["bookmark_bar"]!]!.chromeID
        await apiModel.connect(apiSource, scope: apiScope)
        let apiView = NSWindow(contentViewController: NSHostingController(rootView: APIWorkspaceView(model: apiModel).frame(width: 1100, height: 760)))
        apiView.isReleasedWhenClosed = false; apiView.center(); apiView.makeKeyAndOrderFront(nil)
        try await settle(); try capture(apiView, to: output.appendingPathComponent("api-workspace.png"))
        guard let apiTable = table(in: apiView.contentView, minimumColumns: 2), apiTable.numberOfRows >= 2 else { throw GalmuriError.invalid("API native table unavailable") }
        apiTable.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        _ = apiView.makeFirstResponder(apiTable)
        try await settle()
        guard apiTable.selectedRowIndexes.count == 2, apiTable.selectionHighlightStyle == .none else { throw GalmuriError.invalid("API multi-selection theme unavailable") }
        try capture(apiView, to: output.appendingPathComponent("api-selection.png"))
        guard let apiProfile = apiModel.profile, let apiItem = apiProfile.working.nodes.values.first(where: { $0.url != nil }) else { throw GalmuriError.invalid("API capture fixture") }
        await apiModel.edit(expected: apiProfile.id) { $0.nodes[apiItem.id]?.name = "Ours · 갈무리" }
        let apiReview = try APIReview(profile: apiModel.profile!, envelope: apiSource)
        let apiReviewWindow = NSWindow(contentViewController: NSHostingController(rootView: APIReviewSheet(model: apiModel, review: apiReview).frame(width: 880, height: 720)))
        apiReviewWindow.isReleasedWhenClosed = false; apiReviewWindow.center(); apiReviewWindow.makeKeyAndOrderFront(nil)
        try await settle(); try capture(apiReviewWindow, to: output.appendingPathComponent("api-review.png"))
        apiReviewWindow.close(); apiView.close(); try apiModel.proof.close(apiSession)
        window.makeKeyAndOrderFront(nil)

        guard let editable = profile.working.nodes.values.sorted(by: { $0.id < $1.id }).first(where: { $0.url != nil }) else {
            throw GalmuriError.invalid("synthetic editable bookmark missing")
        }
        store.selection = [editable.id]
        try await settle()
        try capture(window, to: output.appendingPathComponent("selection.png"))
        guard let table = table(in: window.contentView) else { throw GalmuriError.invalid("bookmark table not found") }
        guard window.makeFirstResponder(table) else { throw GalmuriError.invalid("bookmark table could not receive focus") }
        try key("\r", code: 36, in: window)
        try await settle()
        guard let editingSheet = window.attachedSheet else { throw GalmuriError.invalid("Return did not open the editor") }
        try capture(editingSheet, to: output.appendingPathComponent("edit.png"))
        guard let fieldEditor = editingSheet.firstResponder as? NSTextView else { throw GalmuriError.invalid("name field is not focused") }
        fieldEditor.selectAll(nil)
        try key("\u{7f}", code: 51, in: editingSheet)
        guard fieldEditor.string.isEmpty, store.tree == profile.working else {
            throw GalmuriError.invalid("text Delete changed bookmarks or did not edit the name")
        }
        try key("\u{1b}", code: 53, in: editingSheet)
        try await settle()
        guard window.attachedSheet == nil, store.tree == profile.working else { throw GalmuriError.invalid("Cancel changed the working copy") }
        guard let singleDeletion = store.deletionRequest(for: [editable.id]), store.delete(singleDeletion) else {
            throw GalmuriError.invalid("synthetic single deletion failed")
        }
        try await settle()
        try capture(window, to: output.appendingPathComponent("after-delete.png"))
        try key("z", code: 6, modifiers: .command, in: window)
        try await settle()
        guard store.tree == profile.working else { throw GalmuriError.invalid("Undo shortcut did not restore the deleted bookmark") }

        guard store.edit({ try $0.edit(editable.id, name: "Search undo fixture", url: editable.url) }) else {
            throw GalmuriError.invalid("synthetic search fixture failed")
        }
        let beforeSearch = store.tree
        try key("f", code: 3, modifiers: .command, in: window)
        try await settle()
        try key("x", code: 7, in: window)
        try await settle()
        guard store.search == "x" else { throw GalmuriError.invalid("search is not focused") }
        try key("z", code: 6, modifiers: .command, in: window)
        try await settle()
        guard store.tree == beforeSearch else { throw GalmuriError.invalid("search Undo changed bookmarks") }
        // Synthetic routing verifies bookmark isolation; physical text-editing undo needs native acceptance.
        store.search = ""
        window.makeFirstResponder(nil)
        store.undo()
        guard store.tree == profile.working else { throw GalmuriError.invalid("search fixture was not restored") }
        store.selection = []

        guard let folder = profile.working.nodes.values.first(where: { $0.isFolder && $0.parent != nil }),
              let deletion = store.deletionRequest(for: [folder.id]) else { throw GalmuriError.invalid("synthetic folder missing") }
        let deletionWindow = NSWindow(contentViewController: NSHostingController(rootView: BookmarkDeletionSheet(store: store, request: deletion)))
        deletionWindow.isReleasedWhenClosed = false
        window.beginSheet(deletionWindow, completionHandler: { _ in })
        try await settle()
        try capture(deletionWindow, to: output.appendingPathComponent("delete-preview.png"))
        try key("\r", code: 36, in: deletionWindow)
        try await settle()
        guard deletion.removedIDs.isDisjoint(with: Set(store.tree?.nodes.keys.map { $0 } ?? [])) else {
            throw GalmuriError.invalid("Return did not confirm the reviewed deletion")
        }
        store.undo()
        guard store.tree == profile.working else { throw GalmuriError.invalid("folder deletion undo failed") }
        window.endSheet(deletionWindow); deletionWindow.close(); window.makeKeyAndOrderFront(nil)

        store.workspace.profiles[0].permissionBookmark = Data("unusable synthetic permission record".utf8)
        do { try store.withAccess(store.workspace.profiles[0]) {} }
        catch { store.error = error.localizedDescription }
        guard store.needsReconnect else { throw GalmuriError.invalid("expected reconnect action") }
        try await settle()
        try capture(window, to: output.appendingPathComponent("reconnect.png"))
        store.workspace.profiles[0].permissionBookmark = nil
        store.accessIssues.remove(profile.id); store.error = nil

        let resetItems = profile.working.nodes.values.filter { $0.url != nil }.sorted { $0.id < $1.id }
        guard resetItems.count >= 2, store.edit({ tree in
            try tree.edit(resetItems[0].id, name: "Pending edit · 갈무리", url: resetItems[0].url)
            try tree.remove([resetItems[1].id])
            _ = try tree.add(name: "Added locally · 日本語 · 中文", url: "https://example.com/discard-fixture", to: SampleData.other)
        }) else { throw GalmuriError.invalid("pending reset fixture failed") }
        let pendingTree = store.tree
        let reopened = AppStore(sampleData: true, directory: store.directory)
        guard !reopened.canUndo, reopened.pendingCount > 0, let reset = reopened.resetRequest() else {
            throw GalmuriError.invalid("persisted pending changes unavailable without undo")
        }
        reopened.navigation = "changes"
        let pendingWindow = NSWindow(contentViewController: NSHostingController(rootView: RootView(store: reopened)))
        pendingWindow.isReleasedWhenClosed = false
        pendingWindow.setContentSize(NSSize(width: 1180, height: 780))
        pendingWindow.center(); pendingWindow.makeKeyAndOrderFront(nil)
        try await settle()
        try capture(pendingWindow, to: output.appendingPathComponent("pending-changes.png"))
        let resetWindow = NSWindow(contentViewController: NSHostingController(rootView: WorkingCopyResetSheet(store: reopened, request: reset)))
        resetWindow.isReleasedWhenClosed = false
        pendingWindow.beginSheet(resetWindow, completionHandler: { _ in })
        try await settle()
        try capture(resetWindow, to: output.appendingPathComponent("discard-preview.png"))
        try key("\r", code: 36, in: resetWindow)
        try await settle()
        guard reopened.tree == profile.base.tree, reopened.pendingCount == 0 else {
            throw GalmuriError.invalid("native discard confirmation failed")
        }
        reopened.undo()
        guard reopened.tree == pendingTree, try Data(contentsOf: profile.source) == profile.base.original else {
            throw GalmuriError.invalid("discard undo or original preservation failed")
        }
        pendingWindow.endSheet(resetWindow); resetWindow.close(); pendingWindow.close()
        guard let cleanupReset = store.resetRequest(), store.resetWorkingCopy(cleanupReset), store.tree == profile.working else {
            throw GalmuriError.invalid("reset capture fixture could not be restored")
        }
        window.makeKeyAndOrderFront(nil)
        try await settle()

        let pendingList = AppStore(sampleData: true, directory: output.appendingPathComponent("PendingListWorkspace"))
        let pendingProfile = pendingList.profile!
        let deletedID = pendingProfile.working.nodes.values.first { $0.url != nil }!.id
        var initial = pendingProfile.working
        try initial.move([deletedID], to: SampleData.bar)
        let directBase = try BookmarkFile(data: pendingProfile.base.serialize(initial))
        try directBase.original.write(to: pendingProfile.source)
        pendingList.workspace.profiles[0].base = directBase; pendingList.workspace.profiles[0].working = directBase.tree
        pendingList.navigation = "changes"
        guard pendingList.edit({ try $0.remove([deletedID]) }), pendingList.pendingCount == 2,
              Set(pendingList.rows.map(\.id)) == [SampleData.bar, deletedID] else { throw GalmuriError.invalid("pending deletion rows do not match count") }
        let pendingListWindow = NSWindow(contentViewController: NSHostingController(rootView: RootView(store: pendingList)))
        pendingListWindow.isReleasedWhenClosed = false; pendingListWindow.setContentSize(NSSize(width: 1180, height: 780))
        pendingListWindow.center(); pendingListWindow.makeKeyAndOrderFront(nil)
        pendingList.selection = [deletedID]
        try await settle()
        try capture(pendingListWindow, to: output.appendingPathComponent("pending-deletion.png"))
        pendingList.showPendingReview()
        try await settle()
        guard let pendingPreview = pendingListWindow.attachedSheet,
              pendingList.pendingReview?.changedIDs.count == 2,
              pendingList.pendingReview?.base.tree.nodes[deletedID] != nil,
              pendingList.pendingReview?.working.nodes[deletedID] == nil else { throw GalmuriError.invalid("pending review omits deletion") }
        try capture(pendingPreview, to: output.appendingPathComponent("pending-review.png"))
        try key("\u{1b}", code: 53, in: pendingPreview)
        try await settle()
        guard pendingListWindow.attachedSheet == nil, pendingList.pendingCount == 2 else { throw GalmuriError.invalid("pending review dismissal changed work") }
        guard let pendingTable = Self.table(in: pendingListWindow.contentView), pendingTable.numberOfRows == 2,
              !pendingList.canMutateSelection, !pendingList.canEditRow(SampleData.bar),
              pendingListWindow.makeFirstResponder(pendingTable) else { throw GalmuriError.invalid("pending deletion native table unavailable") }
        try key("\r", code: 36, in: pendingListWindow)
        try await settle()
        guard let restorePreview = pendingListWindow.attachedSheet else { throw GalmuriError.invalid("deleted item did not open restore preview") }
        try capture(restorePreview, to: output.appendingPathComponent("pending-restore.png"))
        try key("\r", code: 36, in: restorePreview)
        try await settle()
        guard pendingList.pendingCount == 0, pendingList.rows.isEmpty,
              pendingList.tree == directBase.tree, try Data(contentsOf: pendingProfile.source) == directBase.original else { throw GalmuriError.invalid("pending deleted item restore failed") }
        pendingListWindow.close()

        let feature = AppStore(sampleData: true, directory: output.appendingPathComponent("PreUseWorkspace"))
        let fp = feature.profile!
        let links = fp.working.nodes.values.filter { $0.url != nil }.sorted { $0.id < $1.id }
        guard feature.edit({ try $0.edit(links[0].id, name: "App edit · 갈무리", url: links[0].url) }) else { throw GalmuriError.invalid("pre-use fixture") }
        let featureWindow = NSWindow(contentViewController: NSHostingController(rootView: RootView(store: feature)))
        featureWindow.isReleasedWhenClosed = false; featureWindow.setContentSize(NSSize(width: 1180, height: 780))
        featureWindow.center(); featureWindow.makeKeyAndOrderFront(nil)
        let management = NSWindow(contentViewController: NSHostingController(rootView: ProfileManagementView(store: feature)))
        management.isReleasedWhenClosed = false; management.center(); management.makeKeyAndOrderFront(nil)
        try await settle()
        try capture(management, to: output.appendingPathComponent("profile-management.png"))
        management.close(); featureWindow.makeKeyAndOrderFront(nil)
        var theirs = fp.base.tree
        try theirs.edit(links[0].id, name: "File edit · 日本語", url: links[0].url)
        try theirs.edit(links[1].id, name: "Independent file edit · 中文", url: links[1].url)
        try fp.base.serialize(theirs).write(to: fp.source, options: .atomic)
        let sourceBytes = try Data(contentsOf: fp.source)
        await feature.refreshProfile()
        guard let refresh = feature.review, refresh.mode == .refresh, refresh.result?.unresolved.isEmpty == false else { throw GalmuriError.invalid("refresh conflict missing") }
        try await settle()
        try capture(featureWindow.attachedSheet ?? featureWindow, to: output.appendingPathComponent("refresh-conflicts.png"))
        for c in refresh.result!.conflicts { feature.resolve(c.id, side: .ours, in: refresh) }
        refresh.phase = .final
        try await settle()
        try capture(featureWindow.attachedSheet ?? featureWindow, to: output.appendingPathComponent("refresh-review.png"))
        refresh.acknowledged = true; await feature.acceptRefresh(refresh)
        guard refresh.phase == .complete, feature.tree?.nodes[links[0].id]?.name == "App edit · 갈무리",
              feature.tree?.nodes[links[1].id]?.name == "Independent file edit · 中文", refresh.localArchive != nil else { throw GalmuriError.invalid("refresh acceptance failed") }
        try await settle()
        try capture(featureWindow.attachedSheet ?? featureWindow, to: output.appendingPathComponent("refresh-complete.png"))
        feature.review = nil; feature.navigation = "changes"; feature.selection = [links[0].id]
        try await settle()
        featureWindow.setContentSize(NSSize(width: 980, height: 690))
        try await settle()
        try capture(featureWindow, to: output.appendingPathComponent("editor-minimum.png"))
        guard let selective = feature.revertRequest(for: [links[0].id]) else { throw GalmuriError.invalid("selective revert request failed") }
        let selectionBefore = feature.tree
        let selectiveWindow = NSWindow(contentViewController: NSHostingController(rootView: WorkingCopyResetSheet(store: feature, request: selective)))
        selectiveWindow.isReleasedWhenClosed = false; featureWindow.beginSheet(selectiveWindow, completionHandler: { _ in })
        try await settle()
        try capture(selectiveWindow, to: output.appendingPathComponent("selected-revert.png"))
        try key("\r", code: 36, in: selectiveWindow)
        try await settle()
        guard feature.tree == feature.profile?.base.tree else { throw GalmuriError.invalid("selective native revert failed") }
        feature.undo(); guard feature.tree == selectionBefore else { throw GalmuriError.invalid("selective undo failed") }
        featureWindow.endSheet(selectiveWindow); selectiveWindow.close()
        var dispatched = false
        feature.openBookmark(links[0].id) { _ in dispatched = true; return true }
        guard dispatched, let removedArchive = feature.removeProfile(ProfileRemoval(profile: feature.profile!)),
              try Workspace.load(from: removedArchive).profiles.count == 1,
              feature.workspace.profiles.isEmpty, try Data(contentsOf: fp.source) == sourceBytes else { throw GalmuriError.invalid("profile archival/source preservation failed") }
        featureWindow.close(); window.makeKeyAndOrderFront(nil)
        try await settle()

        guard let item = profile.working.nodes.values.sorted(by: { $0.id < $1.id }).first(where: { $0.url != nil }) else {
            throw GalmuriError.invalid("synthetic bookmark missing")
        }
        guard store.edit({ try $0.edit(item.id, name: "App title · 갈무리", url: item.url) }) else {
            throw GalmuriError.invalid("synthetic edit failed")
        }
        var changed = profile.base.tree
        try changed.edit(item.id, name: "Browser title · 日本語 · 中文", url: item.url)
        try profile.base.serialize(changed).write(to: profile.source, options: .atomic)
        let prepared = try store.coordinator.prepare(profile: store.profile!)
        guard !prepared.result.unresolved.isEmpty else { throw GalmuriError.invalid("expected native conflict") }
        let session = ReviewSession(profileID: profile.id)
        session.latest = prepared.latest; session.result = prepared.result
        session.sourceIdentity = prepared.sourceIdentity
        session.workingAtReview = store.profile?.working; session.phase = .conflicts
        store.review = session
        try await settle()
        try capture(window.attachedSheet ?? window, to: output.appendingPathComponent("conflicts.png"))
        for conflict in prepared.result.conflicts { store.resolve(conflict.id, side: .ours, in: session) }
        guard session.result?.unresolved.isEmpty == true else { throw GalmuriError.unresolved }
        session.phase = .final
        try await settle()
        try capture(window.attachedSheet ?? window, to: output.appendingPathComponent("review.png"))
        let evidence: [String: Any] = [
            "preferredLocalizations": Bundle.main.preferredLocalizations,
            "connectLabel": L("profile.connect"),
            "conflictCount": prepared.result.conflicts.count,
            "screenshots": ["registered-extensions.png", "settings-labs.png", "pending-review.png", "labs-enabled.png", "extension-not-detected.png", "extension-install.png", "connection-details.png", "pending-deletion.png", "pending-restore.png", "api-workspace.png", "api-selection.png", "api-review.png", "bridge-proof.png", "profile-management.png", "refresh-conflicts.png", "refresh-review.png", "refresh-complete.png", "editor-minimum.png", "selected-revert.png","pending-changes.png", "discard-preview.png", "editor.png", "folder-navigation.png", "folder-parent.png", "welcome.png", "missing-location.png", "file-permission-needed.png", "access-needed.png", "settings-access-needed.png", "folder-access-needed.png", "profile-chooser.png", "profile-files.png", "connected-profile.png", "ego-welcome.png", "ego-profile-chooser.png", "ego-connected-profile.png", "settings.png", "selection.png", "edit.png", "after-delete.png", "delete-preview.png", "reconnect.png", "conflicts.png", "review.png"],
            "connectionChecks": ["empty welcome", "missing location guidance", "EACCES file-permission guide", "initial EPERM Chrome folder-consent guide", "selected-folder EPERM Chrome Settings fallback", "synthetic EPERM Ego folder guide", "denied retry cannot advance", "permission Back preserves workspace", "normal read stages named profiles without a picker", "only explicitly selected profile connected read-only", "mixed-store plaintext import excludes companion contents and keeps write restriction", "Ego selection without discovery", "Ego chooser retains browser identity", "Ego fixture imports read-only with persisted warning and unchanged source"],
            "preUseChecks": ["profile management archives work and preserves original", "refresh requires explicit conflict choices", "accepted refresh preserves independent edits with recovery archive", "selective revert and undo", "explicit validated URL dispatched only to injected opener", "minimum window captured"],
            "resetChecks": ["persisted changes reload without session undo", "review compares entire working copy to saved Base", "Return confirms discard to saved source", "session undo restores discarded working copy", "discard and undo leave synthetic original unchanged"],
            "navigationChecks": ["Return opens a folder without an editor sheet", "folder view contains direct children and ancestor path", "Command-Up opens enclosing folder", "Command-[ and Command-] traverse folder history", "navigation leaves working copy and synthetic original unchanged"],
            "editingChecks": ["Return opens the selected bookmark editor", "Delete edits focused name text without deleting bookmarks", "Escape cancels without a working-copy change", "Command-Z restores a deleted bookmark", "search Command-Z preserves bookmark edits", "Return confirms a captured folder deletion in a native sheet", "folder deletion undo restores all items"],
            "scope": "Own native windows, synthetic in-process key routing and conflict review; no physical gestures, OS permission changes, VoiceOver or browser adoption."
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("capture.json"))
        store.review = nil
        try await settle()
    }

    private static func settle() async throws { try await Task.sleep(for: .milliseconds(800)) }

    private static func table(in view: NSView?, minimumColumns: Int = 4) -> NSTableView? {
        guard let view else { return nil }
        if let table = view as? NSTableView, table.numberOfColumns >= minimumColumns { return table }
        return view.subviews.lazy.compactMap { table(in: $0, minimumColumns: minimumColumns) }.first
    }

    private static func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) throws {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                          context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                          isARepeat: false, keyCode: code) else { throw GalmuriError.invalid("synthetic key unavailable") }
        if window.performKeyEquivalent(with: event) { return }
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return }
        window.sendEvent(event)
    }

    private static func capture(_ window: NSWindow, to output: URL) throws {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.path]
        let errors = Pipe(); capture.standardError = errors
        try capture.run(); capture.waitUntilExit()
        guard capture.terminationStatus == 0 else {
            throw GalmuriError.invalid("native window capture unavailable; no screen permission was changed")
        }
    }
}
#endif
