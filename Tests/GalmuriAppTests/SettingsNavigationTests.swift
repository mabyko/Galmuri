import XCTest
@testable import GalmuriApp

@MainActor
final class SettingsNavigationTests: XCTestCase {
    private let settings = URL(fileURLWithPath: "/System/Applications/System Settings.app")

    func testTargetsFilesAndFoldersWithoutLaunchingGenericApp() {
        var opened: [URL] = []
        XCTAssertTrue(ProfileSettingsNavigation.openFilesAndFolders(openURL: { opened.append($0); return true }, settingsApplication: settings))
        XCTAssertEqual(opened.map(\.absoluteString), ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders"])
    }

    func testRejectedDestinationFallsBackToSettingsApplication() {
        var opened: [URL] = []
        XCTAssertTrue(ProfileSettingsNavigation.openFilesAndFolders(openURL: { opened.append($0); return $0 == self.settings }, settingsApplication: settings))
        XCTAssertEqual(opened, [ProfileSettingsNavigation.filesAndFolders, settings])
    }

    func testMissingOrUnlaunchableFallbackReportsFailure() {
        for fallback in [nil, settings] {
            var opened: [URL] = []
            XCTAssertFalse(ProfileSettingsNavigation.openFilesAndFolders(openURL: { opened.append($0); return false }, settingsApplication: fallback))
            XCTAssertEqual(opened, fallback.map { [ProfileSettingsNavigation.filesAndFolders, $0] } ?? [ProfileSettingsNavigation.filesAndFolders])
        }
    }
}
