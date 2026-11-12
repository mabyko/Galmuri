import XCTest
@testable import GalmuriCore

final class ExtensionInventoryTests: XCTestCase {
    private let id = String(repeating: "a", count: 32)
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriExtensions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func preferences(_ root: URL, name: String = "Preferences", id: String) throws {
        try JSONSerialization.data(withJSONObject: ["extensions": ["settings": [id: ["state": 1, "path": "/synthetic/unpacked"]]]]).write(to: root.appendingPathComponent(name))
    }
    func testOnlySelectedProfileAndExactExtensionRecordAreUsedIncludingUnpacked() throws {
        let root = try fixture(), other = try fixture()
        try preferences(other, id: id)
        let source = root.appendingPathComponent("Bookmarks")
        XCTAssertEqual(try ProfileExtensionInventory.inspect(source: source, extensionID: id), .unavailable)
        try preferences(root, id: String(repeating: "b", count: 32))
        XCTAssertEqual(try ProfileExtensionInventory.inspect(source: source, extensionID: id), .notDetected)
        try preferences(root, name: "Secure Preferences", id: id)
        let before = try Data(contentsOf: root.appendingPathComponent("Secure Preferences"))
        XCTAssertEqual(try ProfileExtensionInventory.inspect(source: source, extensionID: id), .recordFound)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Secure Preferences")), before)
    }
    func testMalformedSymlinkAndUnknownMetadataFailWithoutClaimingAbsence() throws {
        let root = try fixture(), source = root.appendingPathComponent("Bookmarks"), prefs = root.appendingPathComponent("Preferences")
        try Data("not JSON".utf8).write(to: prefs)
        XCTAssertThrowsError(try ProfileExtensionInventory.inspect(source: source, extensionID: id))
        try FileManager.default.removeItem(at: prefs)
        let other = try fixture();try preferences(other, id: id)
        try FileManager.default.createSymbolicLink(at: prefs, withDestinationURL: other.appendingPathComponent("Preferences"))
        XCTAssertThrowsError(try ProfileExtensionInventory.inspect(source: source, extensionID: id))
        XCTAssertThrowsError(try ProfileExtensionInventory.inspect(source: source, extensionID: "../escape"))
    }
    func testOptionsDefaultOffRoundTripAndMalformedVersion() throws {
        let url = try fixture().appendingPathComponent("labs.json")
        XCTAssertEqual(try LabOptions.load(from: url), LabOptions())
        var options = LabOptions();options.apiEnabled = true;options.fileEnabled = true
        try options.save(to: url);XCTAssertEqual(try LabOptions.load(from: url), options)
        options.version = 2
        XCTAssertThrowsError(try options.save(to: url))
        XCTAssertTrue(try LabOptions.load(from: url).apiEnabled)
        try Data("{\"version\":2,\"apiEnabled\":true,\"fileEnabled\":true}".utf8).write(to: url)
        XCTAssertThrowsError(try LabOptions.load(from: url))
    }
}
