import AppKit
import SwiftUI

struct ProfileAccessView: View {
    @Bindable var store: AppStore
    let notice: ProfileConnectionNotice
    @State private var settingsOpenFailed = false

    private var guidance: ProfileAccessGuidance {
        notice.guidance(onMacOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
    private var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Galmuri" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Button("permission.back", systemImage: "chevron.left") { store.dismissConnectionNotice() }
                    .buttonStyle(.borderless).keyboardShortcut(.cancelAction)
                HStack(spacing: 16) {
                    Image(systemName: "lock.shield").font(.system(size: 42, weight: .light)).foregroundStyle(.brown)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(format: L("permission.title"), notice.browser.name)).font(.title.bold())
                            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        Text("permission.pending").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if guidance == .systemSettings {
                    Text("permission.settingsReason").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("permission.settingsStep", systemImage: "1.circle").font(.headline)
                            Text(String(format: L("permission.chromeSettingsPath"), appName)).fixedSize(horizontal: false, vertical: true)
                            Button("permission.openFilesFolders", action: openSettings)
                                .buttonStyle(.borderedProminent).controlSize(.large)
                            Text("permission.settingsNavigationHelp").font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Label(String(format: L("permission.chromeSwitchStep"), appName), systemImage: "2.circle").font(.headline)
                            Text(String(format: L("permission.chromeSwitchDetail"), appName)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Label("permission.returnStep", systemImage: "3.circle").font(.headline)
                            Text("permission.returnDetail").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                recheckButton.buttonStyle(.borderedProminent).controlSize(.large)
                                if store.busy { ProgressView().controlSize(.small).accessibilityLabel("permission.checking") }
                            }
                        }
                    }.padding(20).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                } else if guidance == .filePermissions {
                    Label("permission.fileTitle", systemImage: "folder.badge.questionmark").font(.headline)
                    Text("permission.fileDetail").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(format: L("permission.reason"), notice.browser.name))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 18) {
                        Label("permission.folderStep", systemImage: "1.circle").font(.headline)
                        Text(String(format: L("permission.folderStepDetail"), notice.directory.lastPathComponent))
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Label(notice.directory.lastPathComponent, systemImage: "folder.fill").font(.title3)
                        Label("permission.checkStep", systemImage: "2.circle").font(.headline)
                        Text("permission.checkStepDetail").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(20).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
                if guidance != .systemSettings {
                    HStack(spacing: 12) {
                        if guidance == .filePermissions {
                            recheckButton.buttonStyle(.borderedProminent).controlSize(.large)
                            Button("profile.otherLocation") { store.chooseBrowserFolder(browser: notice.browser) }
                        } else {
                            chooseFolderButton.buttonStyle(.borderedProminent).controlSize(.large)
                            recheckButton
                        }
                        if store.busy { ProgressView().controlSize(.small).accessibilityLabel("permission.checking") }
                    }
                }
                if settingsOpenFailed {
                    Text("permission.settingsUnavailable").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if guidance == .systemSettings {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("permission.noChromeSwitch").font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        chooseFolderButton
                    }
                    DisclosureGroup("permission.moreHelp") {
                        Text("permission.advancedDetail").font(.callout).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }.font(.callout)
                } else if guidance == .folderSelection && notice.origin == .folderSelection {
                    DisclosureGroup("permission.settingsTitle") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("permission.settingsDetail").fixedSize(horizontal: false, vertical: true)
                            Button("permission.openFilesFolders", action: openSettings)
                        }.padding(.top, 8)
                    }.font(.callout)
                }
                Text("profile.originalsReadOnly").font(.caption).foregroundStyle(.secondary)
                ProfileReadDetails(notice: notice)
            }.padding(36).frame(maxWidth: 660).frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recheckButton: some View {
        Button("permission.recheck") {
            Task { await store.findProfiles(in: notice.directory, browser: notice.browser, origin: notice.origin) }
        }
    }

    private var chooseFolderButton: some View {
        Button("permission.chooseFolderAction") {
            store.chooseBrowserFolder(requiredDirectory: notice.directory, browser: notice.browser)
        }
    }

    private func openSettings() {
        settingsOpenFailed = !ProfileSettingsNavigation.openFilesAndFolders(
            openURL: { NSWorkspace.shared.open($0) },
            settingsApplication: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences"))
    }
}

@MainActor
enum ProfileSettingsNavigation {
    // shortcut: Settings anchors depend on macOS; revise this route if Apple changes it, retaining manual navigation.
    static let filesAndFolders = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders")!

    static func openFilesAndFolders(openURL: (URL) -> Bool, settingsApplication: URL?) -> Bool {
        if openURL(filesAndFolders) { return true }
        guard let settingsApplication else { return false }
        return openURL(settingsApplication)
    }
}
