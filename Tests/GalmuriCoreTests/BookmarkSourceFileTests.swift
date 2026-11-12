import XCTest
@testable import GalmuriCore

final class BookmarkSourceFileTests: XCTestCase {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriSourceFiles-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testMixedFilesExposeMetadataAndKeepPlaintextImportable() throws {
        let root = try root(), directory = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = try SampleData.file().original
        try original.write(to: directory.appendingPathComponent("Bookmarks"))
        for name in ["EncryptedBookmarks2", "AccountBookmarks", "BookmarkMergedSurfaceOrdering", "Bookmarks.bak"] {
            try Data([0xff, 0x00, 0xfe]).write(to: directory.appendingPathComponent(name))
        }
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: directory.appendingPathComponent("Bookmarks").path)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.appendingPathComponent("EncryptedBookmarks2").path)
        let profile = try XCTUnwrap(ProfileIO.discover(in: root).first)
        XCTAssertTrue(profile.hasPlaintext)
        XCTAssertTrue(profile.canImportPlaintext)
        XCTAssertNotNil(profile.restriction)
        XCTAssertEqual(profile.files.first?.name, "Bookmarks")
        XCTAssertEqual(profile.files.count, 5)
        XCTAssertEqual(try XCTUnwrap(profile.files.first?.modifiedAt).timeIntervalSince1970, modified.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(profile.files.first { $0.name == "EncryptedBookmarks2" }?.kind, .encrypted)
        XCTAssertEqual(profile.files.first { $0.name == "AccountBookmarks" }?.kind, .account)
        XCTAssertEqual(profile.files.first { $0.name == "BookmarkMergedSurfaceOrdering" }?.kind, .ordering)
        XCTAssertEqual(profile.files.first { $0.name == "Bookmarks.bak" }?.kind, .backup)
        XCTAssertEqual(profile.files.filter(\.canImport).map(\.name), ["Bookmarks"])
        XCTAssertEqual(try ProfileIO.read(profile.file).original, original)
    }

    func testEncryptedAndBackupOnlyRowsRemainVisibleWithoutImportablePlaintext() throws {
        let root = try root()
        for (name, file) in [("Encrypted", "EncryptedBookmarks2"), ("Backup", "Bookmarks.bak")] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([0xff]).write(to: directory.appendingPathComponent(file))
        }
        let profiles = try ProfileIO.discover(in: root)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertTrue(profiles.allSatisfy { !$0.hasPlaintext && !$0.canImportPlaintext && $0.files.count == 1 })
    }

    func testEmptyOrderingCompanionDoesNotDisablePlaintextOrClearWriteGate() throws {
        let root = try root()
        try SampleData.file().original.write(to: root.appendingPathComponent("Bookmarks"))
        try Data().write(to: root.appendingPathComponent("BookmarkMergedSurfaceOrdering"))
        let profile = try XCTUnwrap(ProfileIO.discover(in: root).first)
        XCTAssertTrue(profile.canImportPlaintext)
        XCTAssertNotNil(profile.restriction)
        XCTAssertEqual(profile.files.filter(\.canImport).map(\.name), ["Bookmarks"])
        XCTAssertEqual(profile.files.first { $0.kind == .ordering }?.name, "BookmarkMergedSurfaceOrdering")
    }

    func testUnreadablePlaintextKeepsPresenceDateAndSpecificProblem() throws {
        let root = try root(), file = root.appendingPathComponent("Bookmarks")
        try SampleData.file().original.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        let profile = try XCTUnwrap(ProfileIO.discover(in: root).first)
        XCTAssertTrue(profile.hasPlaintext)
        XCTAssertFalse(profile.canImportPlaintext)
        XCTAssertNotNil(profile.files.first?.modifiedAt)
        XCTAssertEqual(profile.files.first?.problem, "The plaintext bookmark file cannot be opened for reading.")
    }

    func testSymlinkAndDirectorySourcesAreListedWithoutFollowingOrImporting() throws {
        let root = try root(), target = root.appendingPathComponent("outside.json")
        let original = try SampleData.file().original
        try original.write(to: target)
        let linkProfile = root.appendingPathComponent("Link"), folderProfile = root.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: linkProfile, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkProfile.appendingPathComponent("Bookmarks"), withDestinationURL: target)
        try FileManager.default.createDirectory(at: folderProfile.appendingPathComponent("Bookmarks"), withIntermediateDirectories: true)
        let profiles = try ProfileIO.discover(in: root)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertTrue(profiles.allSatisfy { $0.hasPlaintext && !$0.canImportPlaintext && $0.files.first?.modifiedAt == nil })
        XCTAssertEqual(profiles.first { $0.directory.lastPathComponent == "Link" }?.files.first?.problem, "Symbolic links are not read.")
        XCTAssertEqual(profiles.first { $0.directory.lastPathComponent == "Folder" }?.files.first?.problem, "This is not a regular file.")
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testOversizedPlaintextIsListedWithoutLoadingPayload() throws {
        let root = try root(), file = root.appendingPathComponent("Bookmarks")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 50_000_000); try handle.close()
        let profile = try XCTUnwrap(ProfileIO.discover(in: root).first)
        XCTAssertTrue(profile.hasPlaintext)
        XCTAssertFalse(profile.canImportPlaintext)
        XCTAssertEqual(profile.files.first?.problem, "The plaintext bookmark file exceeds the read size limit.")
    }
}
