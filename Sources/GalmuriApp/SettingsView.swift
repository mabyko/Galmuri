import SwiftUI
import GalmuriCore

struct SettingsView: View {
    var directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "forked.galmuri.local")
    var store: AppStore?
    @State private var fallbackPage = "general"
    @State private var bridgeShowing = false
    @State private var installShowing = false
    @State private var fileReview: ReviewSession?

    private var page: Binding<String> {
        Binding(get: { store?.settingsNavigation ?? fallbackPage }, set: {
            if let store { store.settingsNavigation = $0 } else { fallbackPage = $0 }
        })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: page) {
                Label("settings.general", systemImage: "gearshape").tag("general")
                Label("settings.labs", systemImage: "flask").tag("labs")
            }.listStyle(.sidebar).navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 210)
        } detail: {
            if page.wrappedValue == "labs" { labsContent }
            else {
                Form {
                    Section {
                        LabeledContent("settings.version", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")")
                        LabeledContent("sidebar.profiles") { Text(store?.workspace.profiles.count ?? 0, format: .number) }
                        Text("settings.overviewHelp").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.formStyle(.grouped).navigationTitle(L("settings.title"))
            }
        }
        .navigationSplitViewStyle(.balanced).frame(width: 900, height: 680).tint(AppTheme.accent)
        .sheet(isPresented: $installShowing) { ExtensionInstallView() }
        .sheet(isPresented: $bridgeShowing) { BridgeProofView(directory: directory).frame(width: 580, height: 560) }
        .sheet(item: $fileReview) { session in if let store { ReviewView(store: store, session: session) } }
        .onChange(of: store?.labs.apiEnabled) {
            if store?.labs.apiEnabled == true { Task { await store?.checkRegisteredExtensions() } }
            else { bridgeShowing = false; installShowing = false }
        }
        .onChange(of: store?.labs.fileEnabled) { if store?.labs.fileEnabled != true { fileReview = nil } }
    }

    private var labsContent: some View {
        Form {
            Section {
                Toggle("labs.apiTitle", isOn: Binding(get: { store?.labs.apiEnabled == true }, set: { _ = store?.setLabOptions(api: $0) })).disabled(store == nil)
                Toggle("labs.fileTitle", isOn: Binding(get: { store?.labs.fileEnabled == true }, set: { _ = store?.setLabOptions(file: $0) })).disabled(store == nil)
            }
            if store?.labs.apiEnabled == true {
                Section {
                    Text("labs.apiDetail").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("labs.apiLimit").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    extensionStatus
                    HStack {
                        Button("labs.installGuide") { installShowing = true }
                        Button("labs.apiOpen") { bridgeShowing = true }
                    }
                }
            }
            if store?.labs.fileEnabled == true {
                Section {
                    Text("labs.fileDetail").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("labs.fileLimit").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("labs.fileReview") { fileReview = store?.fileApplyExperimentReview() }.disabled(store?.canReviewFileApplyExperiment != true)
                }
            }
            Section {
                Toggle("settings.encryptedBookmarks", isOn: .constant(false)).disabled(true)
                Text("settings.planned").font(.caption.bold()).foregroundStyle(.secondary)
                Text("settings.encryptedBookmarksDetail").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error = store?.error { Text(verbatim: error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }.formStyle(.grouped).navigationTitle(L("settings.labs"))
    }

    @ViewBuilder private var extensionStatus: some View {
        if let store, !store.workspace.profiles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("sidebar.profiles").font(.headline)
                    Spacer()
                    if store.checkingExtension { ProgressView().controlSize(.small).accessibilityLabel(Text("extension.checking")) }
                    Button("extension.checkAll") { Task { await store.checkRegisteredExtensions() } }.disabled(store.checkingExtension)
                }
                Table(store.workspace.profiles) {
                    TableColumn("sidebar.profiles") { profile in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: profile.name).lineLimit(1).help(profile.name)
                            Text(verbatim: profile.source.deletingLastPathComponent().lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }.width(min: 110, ideal: 170, max: 230)
                    TableColumn("extension.status") { profile in
                        let result = inspection(profile, in: store)
                        let key = result.map { $0.presence == .recordFound ? "extension.recordFound" : $0.presence == .notDetected ? "extension.notDetected" : "extension.unavailable" } ?? "extension.notChecked"
                        Text(L(key)).font(.caption).lineLimit(3).help(L(key))
                    }.width(min: 190, ideal: 280)
                    TableColumn("extension.lastChecked") { profile in
                        if let result = inspection(profile, in: store) {
                            Text(result.checkedAt.formatted(date: .omitted, time: .shortened)).font(.caption).help(result.checkedAt.formatted())
                        } else { Text("—").foregroundStyle(.secondary) }
                    }.width(80)
                }.frame(height: min(300, max(120, CGFloat(store.workspace.profiles.count) * 56 + 34)))
                Text("extension.batchHelp").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("extension.recordHelp").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else { Text("extension.noProfiles").foregroundStyle(.secondary) }
    }

    private func inspection(_ profile: ConnectedProfile, in store: AppStore) -> ExtensionInspection? {
        guard let record = store.extensionChecks[profile.id], record.source == profile.source else { return nil }
        return record
    }
}
