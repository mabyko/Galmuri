import AppKit
import XCTest
@testable import GalmuriApp

@MainActor
final class FolderConsentTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GalmuriFolderConsent-" + UUID().uuidString).resolvingSymlinksInPath()
        let target = root.appendingPathComponent("Chrome · Example", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return target
    }

    func testScopedPanelStartsInsideExactFolderWithoutBeingPresented() throws {
        let target = try fixture()
        let panel = BrowserFolderValidator.makePanel(directory: target, requiresExactFolder: true, title: "Synthetic connection")
        XCTAssertEqual(panel.directoryURL?.standardizedFileURL.path, target.path)
        XCTAssertEqual(panel.prompt, L("permission.confirmFolderAccess"))
        XCTAssertEqual(panel.title, "Synthetic connection")
        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertFalse(panel.canCreateDirectories)
        XCTAssertFalse(panel.isVisible)
    }

    func testCustomLocationPanelPreservesUnrestrictedBrowsingAndChooseLabel() throws {
        let target = try fixture()
        let panel = BrowserFolderValidator.makePanel(directory: target, requiresExactFolder: false, title: "Synthetic custom location")
        XCTAssertEqual(panel.directoryURL?.standardizedFileURL.path, target.deletingLastPathComponent().path)
        XCTAssertEqual(panel.prompt, L("permission.chooseFolder"))
        XCTAssertNil(panel.delegate)
        XCTAssertFalse(panel.isVisible)
    }

    func testUnknownDenialUsesSettingsOnlyAfterFolderWasConfirmed() {
        let target = URL(fileURLWithPath: "/Synthetic/Chrome")
        var notice = ProfileConnectionNotice(directory: target, issue: .permissionDenied)
        XCTAssertEqual(notice.guidance(onMacOSMajorVersion: 27), .folderSelection)
        notice.origin = .folderSelection
        XCTAssertEqual(notice.guidance(onMacOSMajorVersion: 27), .systemSettings)
        notice.browser = .egoLite
        XCTAssertEqual(notice.guidance(onMacOSMajorVersion: 27), .folderSelection)
    }
}
