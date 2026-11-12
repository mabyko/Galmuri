import SwiftUI
import GalmuriCore

struct ProfileWelcomeView: View {
    @Bindable var store: AppStore
    @State private var managingProfiles = false

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72).accessibilityHidden(true)
                .accessibilityHidden(true)
            Text("profile.welcomeTitle").font(.largeTitle.bold())
            Text("profile.welcomeDetail").font(.title3).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Picker("profile.browser", selection: Binding(get: { store.connectionBrowser }, set: { store.selectBrowser($0) })) {
                ForEach(BookmarkBrowser.allCases) { browser in Text(verbatim: browser.name).tag(browser) }
            }.pickerStyle(.segmented).frame(maxWidth: 330)
            if store.connectionBrowser == .egoLite {
                Text("profile.egoPreview").font(.caption).foregroundStyle(.orange)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if store.connectionNotice == nil {
                VStack(alignment: .leading, spacing: 16) {
                    Label("profile.findStep", systemImage: "magnifyingglass")
                    Label("profile.selectStep", systemImage: "person.crop.rectangle.stack")
                    Label("profile.originalsReadOnly", systemImage: "lock")
                }.font(.callout).padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
            if let notice = store.connectionNotice {
                ProfileDiscoveryNoticeView(store: store, notice: notice)
            } else {
                if store.error != nil { AppErrorNotice(store: store) }
                Button(String(format: L("profile.connectBrowser"), store.connectionBrowser.name), systemImage: "plus") { store.connect() }
                    .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("connect-chrome")
            }
            if store.connectionNotice?.issue != .missingLocation && store.connectionNotice?.issue != .unavailable {
                Button("profile.otherLocation") { store.chooseBrowserFolder() }.buttonStyle(.borderless)
            }
            if let saved = store.savedSampleProfiles.first {
                Button("profile.openSavedSample") { store.switchProfile(saved.id) }.buttonStyle(.borderless)
                Text("profile.savedSamplesPreserved").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Button("workspace.import") { store.importWorkspace() }.buttonStyle(.borderless)
                SettingsLink { Label("settings.open", systemImage: "gearshape") }.accessibilityIdentifier("open-settings")
            }
            if !store.workspace.profiles.isEmpty {
                Button("profile.manage") { managingProfiles = true }.buttonStyle(.borderless)
            }
        }.frame(maxWidth: 600).padding(48).frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $managingProfiles) { ProfileManagementView(store: store) }
    }
}

struct ProfileDiscoveryNoticeView: View {
    @Bindable var store: AppStore
    let notice: ProfileConnectionNotice

    private var titleKey: String {
        switch notice.issue {
        case .permissionDenied: "profile.accessTitle"
        case .missingLocation: "profile.missingTitle"
        case .unavailable: "profile.lookupFailedTitle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(format: L(titleKey), notice.browser.name), systemImage: notice.issue == .permissionDenied ? "lock" : "magnifyingglass")
                .font(.headline)
            Text(notice.issue == .permissionDenied ? String(format: L("profile.accessDetail"), notice.directory.lastPathComponent) : L("profile.locationDetail"))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if notice.issue == .permissionDenied {
                    Button("profile.allowAccess") { store.chooseBrowserFolder(requiredDirectory: notice.directory, browser: notice.browser) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("profile.otherLocation") { store.chooseBrowserFolder(browser: notice.browser) }.buttonStyle(.borderedProminent)
                }
                Button("profile.retryFind") { Task { await store.findProfiles(in: notice.directory, browser: notice.browser, origin: notice.origin) } }
                Spacer()
                Button("common.dismissError") { store.dismissConnectionNotice() }.buttonStyle(.borderless)
            }
            ProfileReadDetails(notice: notice)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ProfileSelectionSheet: View {
    @Bindable var store: AppStore
    let request: ProfileConnection
    @State private var selection = Set<String>()
    @Environment(\.dismiss) private var dismiss

    private func connected(_ profile: DiscoveredProfile) -> ConnectedProfile? {
        store.workspace.profiles.first { $0.source.standardizedFileURL == profile.file.standardizedFileURL }
    }

    private var available: Set<String> {
        Set(request.profiles.filter { $0.canImportPlaintext && connected($0) == nil }.map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(String(format: L("profile.selectBrowserTitle"), request.browser.name)).font(.title2.bold())
            Text("profile.selectDetail").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if request.browser == .egoLite {
                Text("profile.egoPreview").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            List(request.profiles) { profile in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Toggle(isOn: Binding(get: { selection.contains(profile.id) }, set: { selected in
                            if selected { selection.insert(profile.id) } else { selection.remove(profile.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name).font(.headline)
                                Text(profile.directory.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.checkbox).disabled(!available.contains(profile.id))
                        Spacer()
                        if let existing = connected(profile) {
                            Text("profile.alreadyConnected").font(.caption).foregroundStyle(.secondary)
                            Button("profile.openConnected") { store.switchProfile(existing.id); store.connection = nil }
                        } else if profile.canImportPlaintext {
                            Label("profile.plaintextAvailable", systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
                        } else if profile.hasPlaintext {
                            Label("profile.plaintextUnreadable", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        } else {
                            Label("profile.noPlaintext", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup {
                        ProfileSourceFilesView(files: profile.files)
                    } label: {
                        Text(String(format: L("profile.sourceFilesFor"), profile.name))
                    }.font(.caption)
                }.padding(.vertical, 6).help(profile.directory.path)
            }.frame(height: 320)
            HStack {
                Button("profile.selectAvailable") { selection = available }.disabled(available.isEmpty)
                Spacer()
                Text("profile.originalsReadOnly").font(.caption).foregroundStyle(.secondary)
            }
            if store.error != nil { AppErrorNotice(store: store) }
            HStack {
                if store.busy { ProgressView().controlSize(.small).accessibilityLabel(Text(String(format: L("profile.connectBrowser"), request.browser.name))) }
                Spacer()
                Button("common.cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    let ids = selection
                    Task { await store.finishConnection(request, profileIDs: ids) }
                } label: { Text(localizedCount("profile.connectCount", selection.count)) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty || store.busy)
            }
        }.padding(25).frame(width: 700)
            .disabled(store.busy)
            .interactiveDismissDisabled(store.busy)
            .onAppear { if available.count == 1 { selection = available } }
    }
}

struct ProfileSourceFilesView: View {
    let files: [BookmarkSourceFile]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(files) { file in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(verbatim: file.name).font(.caption.monospaced()).textSelection(.enabled)
                        Spacer(minLength: 12)
                        kindLabel(file.kind).font(.caption).foregroundStyle(.secondary)
                    }
                    if let date = file.modifiedAt {
                        HStack(spacing: 5) {
                            Text("profile.fileModified")
                            Text(date, style: .date)
                            Text(date, style: .time)
                        }.font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("profile.fileDateUnknown").font(.caption).foregroundStyle(.secondary)
                    }
                    if let problem = file.problem {
                        Text(localizedAppMessage(problem)).font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("profile.fileInfoScope").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.top, 6)
    }

    private func kindLabel(_ kind: BookmarkSourceFile.Kind) -> Text {
        switch kind {
        case .plaintext: Text("profile.filePlaintext")
        case .encrypted: Text("profile.fileEncrypted")
        case .account: Text("profile.fileAccount")
        case .ordering: Text("profile.fileOrdering")
        case .backup: Text("profile.fileBackup")
        case .other: Text("profile.fileOther")
        }
    }
}

struct ProfileReadDetails: View {
    let notice: ProfileConnectionNotice

    var body: some View {
        if notice.detail != nil || notice.diagnostic != nil {
            DisclosureGroup("profile.technicalDetails") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let detail = notice.detail {
                            Text(localizedAppMessage(detail)).fixedSize(horizontal: false, vertical: true)
                        }
                        if let diagnostic = notice.diagnostic {
                            Text("permission.errorCodes").fontWeight(.medium)
                            Text(verbatim: diagnostic.codes.joined(separator: " → ")).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(maxHeight: 120)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
