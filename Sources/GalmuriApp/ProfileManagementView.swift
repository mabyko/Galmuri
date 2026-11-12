import SwiftUI
import GalmuriCore

struct ProfileRemoval: Identifiable {
    let id = UUID()
    let profile: ConnectedProfile
}

struct ProfileManagementView: View {
    @Bindable var store: AppStore
    @State private var removal: ProfileRemoval?
    @State private var archive: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("profile.manage").font(.title2.bold())
            Text("profile.manageHelp").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(store.workspace.profiles) { profile in
                HStack {
                    VStack(alignment: .leading) {
                        Text(verbatim: profile.name).font(.headline).lineLimit(2).help(profile.name)
                        Text(verbatim: profile.source.deletingLastPathComponent().lastPathComponent).foregroundStyle(.secondary)
                        if profile.hasChanges { Text(localizedCount("editor.changeCount", profile.changedIDs.count)).font(.caption).foregroundStyle(.orange) }
                    }
                    Spacer()
                    Button("profile.remove", role: .destructive) { removal = ProfileRemoval(profile: profile) }
                        .accessibilityLabel(String(format: L("profile.removeNamed"), profile.name))
                }.padding(.vertical, 5)
            }.frame(height: 240)
            if let archive {
                Text("profile.archived").foregroundStyle(.secondary)
                Text(verbatim: archive.path).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if store.error != nil { AppErrorNotice(store: store) }
            HStack { Spacer(); Button("common.done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(25).frame(width: 580)
            .sheet(item: $removal) { request in
                VStack(alignment: .leading, spacing: 18) {
                    Text("profile.removeTitle").font(.title2.bold())
                    Text(verbatim: request.profile.name).font(.headline)
                    Text(localizedCount("editor.changeCount", request.profile.changedIDs.count))
                    Text("profile.removeHelp").fixedSize(horizontal: false, vertical: true)
                    if store.error != nil { AppErrorNotice(store: store) }
                    HStack {
                        Spacer()
                        Button("common.cancel", role: .cancel) { removal = nil }.keyboardShortcut(.cancelAction)
                        Button("profile.remove", role: .destructive) {
                            if let saved = store.removeProfile(request) { archive = saved; removal = nil }
                        }
                    }
                }.padding(25).frame(width: 480)
            }
            .disabled(store.busy)
    }
}
