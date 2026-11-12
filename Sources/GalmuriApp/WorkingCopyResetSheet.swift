import SwiftUI
import GalmuriCore

struct WorkingCopyResetSheet: View {
    @Bindable var store: AppStore
    let request: WorkingCopyReset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L(request.itemIDs == nil ? "editor.discardTitle" : "editor.revertTitle")).font(.title2.bold())
            Text(verbatim: request.profile.name).font(.headline)
            Text(L(request.itemIDs == nil ? "editor.discardDetail" : "editor.revertDetail")).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                ChangeReviewList(before: request.profile.working, after: request.target)
            }.frame(height: 300)
            Text("editor.discardUndoHelp").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.error != nil { AppErrorNotice(store: store) }
            HStack {
                Spacer()
                Button("common.cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L(request.itemIDs == nil ? "editor.confirmDiscard" : "editor.confirmRevert"), role: .destructive) {
                    if store.resetWorkingCopy(request) { dismiss() }
                }.keyboardShortcut(.defaultAction).accessibilityIdentifier("confirm-discard-changes")
            }
        }.padding(25).frame(width: 620)
            .interactiveDismissDisabled(store.busy)
            .disabled(store.busy)
    }
}
