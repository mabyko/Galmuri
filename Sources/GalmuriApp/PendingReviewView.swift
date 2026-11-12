import SwiftUI
import GalmuriCore

struct PendingReviewView: View {
    let profile: ConnectedProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("review.title").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("common.close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(verbatim: profile.name).font(.headline)
            Text(localizedCount("editor.changeCount", profile.changedIDs.count)).foregroundStyle(.secondary)
            Text("review.pendingHelp").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView { ChangeReviewList(before: profile.base.tree, after: profile.working) }
            Text("review.pendingApplyHelp").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(minWidth: 760, idealWidth: 820, minHeight: 600, idealHeight: 700).tint(AppTheme.accent)
    }
}
