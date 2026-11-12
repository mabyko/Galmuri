import AppKit
import SwiftUI

@main
struct GalmuriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore(sampleData: AppArguments.sampleData, directory: AppArguments.workspace)
    var body: some Scene {
        WindowGroup(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Galmuri") {
            RootView(store: store)
                .tint(AppTheme.accent)
                .accentColor(AppTheme.accent)
                .onAppear {
                    if AppArguments.smokeTest, AppArguments.workspace != nil { delegate.smokeOnce(store: store) }
                    #if DEBUG
                    if let output = AppArguments.captureDirectory, AppArguments.workspace != nil {
                        delegate.captureOnce(store: store, output: output)
                    }
                    #endif
                }
        }.defaultSize(width: 1180, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(format: L("profile.connectBrowser"), BookmarkBrowser.chrome.name)) { store.connect(.chrome) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(store.busy || store.connection != nil)
                Button(String(format: L("profile.connectBrowser"), BookmarkBrowser.egoLite.name)) { store.connect(.egoLite) }
                    .disabled(store.busy || store.connection != nil)
            }
        }
        Settings {
            SettingsView(store: store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var checking = false
    func smokeOnce(store: AppStore) {
        guard !checking else { return }
        checking = true
        Task {
            do { try await LocalSmokeTest.run(store: store); NSApp.terminate(nil) }
            catch { FileHandle.standardError.write(Data("Local smoke check failed: \(error)\n".utf8)); exit(1) }
        }
    }
    #if DEBUG
    private var capturing = false
    func captureOnce(store: AppStore, output: URL) {
        guard !capturing else { return }
        capturing = true
        Task {
            do { try await NativeCapture.run(store: store, output: output); NSApp.terminate(nil) }
            catch { fputs("Native capture failed: \(error)\n", stderr); exit(1) }
        }
    }
    #endif
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum AppArguments {
    /// The API QA harness approves a pairing without a click, so it exists only in Debug builds.
    static var apiSmoke: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--smoke-api") || ProcessInfo.processInfo.arguments.contains("--smoke-api-restart")
        #else
        return false
        #endif
    }
    static var onboardingSmoke: Bool { ProcessInfo.processInfo.arguments.contains("--smoke-onboarding") }
    static var smokeTest: Bool { apiSmoke || onboardingSmoke || ProcessInfo.processInfo.arguments.contains("--smoke-test") }
    static var sampleData: Bool {
        guard workspace != nil else { return false }
        if onboardingSmoke || apiSmoke { return false }
        if smokeTest || ProcessInfo.processInfo.arguments.contains("--sample-data") { return true }
        #if DEBUG
        return captureDirectory != nil
        #else
        return false
        #endif
    }
    static var workspace: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--workspace"), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }
    #if DEBUG
    static var captureDirectory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--capture-ui"), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }
    #endif
}
