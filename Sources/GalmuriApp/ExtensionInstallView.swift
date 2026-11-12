import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExtensionInstallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("labs.installGuide", systemImage: "puzzlepiece.extension").font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("labs.installDistribution")
                    Text("labs.installSteps")
                    Text(verbatim: "chrome://extensions").font(.body.monospaced()).textSelection(.enabled)
                    Text("labs.installHost").foregroundStyle(.secondary)
                    Text("labs.apiLimit").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("labs.saveExtension") { saveExtension() }
                Spacer()
                Button("common.close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 600, height: 500).tint(AppTheme.accent)
    }

    private func saveExtension() {
        guard let source = Bundle.main.url(forResource: "Galmuri-Chrome-Extension", withExtension: "zip") else {
            error = L("labs.extensionMissing"); return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Galmuri-Chrome-Extension.zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try Data(contentsOf: source).write(to: destination, options: .atomic); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
