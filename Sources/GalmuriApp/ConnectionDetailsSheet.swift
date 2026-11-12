import SwiftUI
import GalmuriCore

struct ConnectionDetailsSheet: View {
    let profile: ConnectedProfile
    let local: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("connection.details", systemImage: "info.circle").font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: profile.name).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L(local ? "profile.localTestHelp" : "profile.connectedReadOnly"))
                    if let restriction = profile.sourceRestriction ?? profile.base.writeRestriction, !restriction.isEmpty {
                        Text(localizedAppMessage(restriction))
                    }
                    Text(verbatim: profile.source.deletingLastPathComponent().path).font(.caption.monospaced()).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            HStack { Spacer(); Button("common.close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 580, height: 380).tint(AppTheme.accent)
    }
}
