import AppKit

@MainActor
final class BrowserFolderValidator: NSObject, NSOpenSavePanelDelegate {
    let requiredDirectory: URL

    init(requiredDirectory: URL) { self.requiredDirectory = requiredDirectory.standardizedFileURL }

    static func makePanel(directory: URL, requiresExactFolder: Bool, title: String) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = false
        panel.directoryURL = requiresExactFolder ? directory : directory.deletingLastPathComponent()
        panel.title = title
        panel.prompt = requiresExactFolder ? L("permission.confirmFolderAccess") : L("permission.chooseFolder")
        panel.message = requiresExactFolder ? String(format: L("profile.folderAccessPrompt"), directory.lastPathComponent) : L("profile.otherFolderHelp")
        return panel
    }

    func panel(_ sender: Any, validate url: URL) throws {
        guard url.isFileURL, url.host == nil || url.host == "localhost",
              url.query == nil, url.fragment == nil,
              url.standardizedFileURL.path == requiredDirectory.path else {
            throw NSError(domain: "Galmuri", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(format: L("profile.chooseNamedFolder"), requiredDirectory.lastPathComponent)])
        }
    }
}
