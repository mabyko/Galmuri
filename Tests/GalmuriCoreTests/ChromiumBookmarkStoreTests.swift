import XCTest
@testable import GalmuriCore

final class ChromiumBookmarkStoreTests: XCTestCase {
    private func cipher(_ password: String = "mock_password") throws -> ChromiumBookmarkCipher {
        try ChromiumBookmarkCipher(password: Data(password.utf8))
    }

    private func vector() -> Data {
        let hex = "763130729b92f8fe6ac21a408aa2c783801553adaa0af3b7ee474ee648bc3058ef1129a1fd8d74ef5a994bec2131e3c8b7dc8d"
        return Data(stride(from: 0, to: hex.count, by: 2).map { index in
            let start = hex.index(hex.startIndex, offsetBy: index)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        })
    }

    func testMacV10MatchesIndependentOpenSSLVector() throws {
        let cipher = try cipher(), plaintext = Data("Galmuri synthetic v10 interoperability: 1234".utf8)
        XCTAssertEqual(try cipher.encrypt(plaintext), vector())
        XCTAssertEqual(try cipher.decrypt(vector()), plaintext)
        XCTAssertEqual(try cipher.decrypt(cipher.encrypt(Data())), Data())
    }

    func testUnknownEnvelopesMissingKeysAndBadPaddingAreRejected() throws {
        XCTAssertThrowsError(try ChromiumBookmarkCipher(password: Data()))
        let cipher = try cipher()
        for bytes in [Data("v20".utf8) + Data(repeating: 0, count: 16), Data("v10short".utf8), Data("v10".utf8)] {
            XCTAssertThrowsError(try cipher.decrypt(bytes))
        }
        let wrong = try? self.cipher("wrong synthetic password").decrypt(vector())
        XCTAssertNotEqual(wrong, Data("Galmuri synthetic v10 interoperability: 1234".utf8))
        var damaged = vector(); damaged[damaged.count - 17] ^= 0xff
        XCTAssertThrowsError(try cipher.decrypt(damaged))
    }

    func testDualCopiesPreserveNoOpBytesAndEditedIdentityMetadataAndOrder() throws {
        let file = try SampleData.file(), cipher = try cipher()
        let files = ["Bookmarks": file.original, "EncryptedBookmarks2": try cipher.encrypt(file.original), "BookmarkMergedSurfaceOrdering": Data("{\n}\n".utf8)]
        let store = try ChromiumBookmarkStore(files: files, cipher: cipher)
        XCTAssertEqual(try store.serialize(store.file.tree), files)
        var edited = file.tree
        let parent = try XCTUnwrap(edited.roots["other"])
        _ = try edited.add(name: "갈무리 日本語 中文", url: "https://example.org/duplicate", to: parent)
        _ = try edited.add(name: "Same URL, distinct identity", url: "https://example.org/duplicate", to: parent)
        let output = try store.serialize(edited, cipher: cipher)
        XCTAssertEqual(Set(output.keys), Set(files.keys))
        XCTAssertEqual(output["BookmarkMergedSurfaceOrdering"], files["BookmarkMergedSurfaceOrdering"])
        let reloaded = try ChromiumBookmarkStore(files: output, cipher: cipher)
        XCTAssertEqual(reloaded.file.tree.nodes.count, edited.nodes.count)
        XCTAssertEqual(reloaded.file.tree.nodes.values.filter { $0.url == "https://example.org/duplicate" }.count, 2)
        XCTAssertEqual(reloaded.file.tree.nodes[parent]?.children, edited.nodes[parent]?.children)
        for var node in file.tree.nodes.values {
            if node.id == parent { node.children = edited.nodes[parent]!.children }
            XCTAssertEqual(reloaded.file.tree.nodes[node.id], node)
        }
        XCTAssertEqual(store.originals, files)
    }

    func testEncryptedOnlyStoreNeverIntroducesAPlaintextCopy() throws {
        let file = try SampleData.file(), cipher = try cipher()
        let store = try ChromiumBookmarkStore(files: ["EncryptedBookmarks2": cipher.encrypt(file.original)], cipher: cipher)
        var edited = file.tree
        let id = try XCTUnwrap(edited.nodes.values.first { $0.url != nil }).id
        try edited.edit(id, name: "Changed", url: edited.nodes[id]?.url)
        let output = try store.serialize(edited, cipher: cipher)
        XCTAssertEqual(Set(output.keys), ["EncryptedBookmarks2"])
        XCTAssertEqual(try ChromiumBookmarkStore(files: output, cipher: cipher).file.tree.nodes[id]?.name, "Changed")
        XCTAssertThrowsError(try store.serialize(edited))
        XCTAssertThrowsError(try store.serialize(edited, cipher: self.cipher("different synthetic password")))
    }

    func testConflictingCopiesUnknownFilesAndNonemptyOrderingFailClosed() throws {
        let file = try SampleData.file(), cipher = try cipher()
        var edited = file.tree
        let id = try XCTUnwrap(edited.nodes.values.first { $0.url != nil }).id
        try edited.edit(id, name: "Different browser copy", url: edited.nodes[id]?.url)
        XCTAssertThrowsError(try ChromiumBookmarkStore(files: ["Bookmarks": file.original, "EncryptedBookmarks2": cipher.encrypt(file.serialize(edited))], cipher: cipher))
        XCTAssertThrowsError(try ChromiumBookmarkStore(files: ["Bookmarks": file.original + Data("\n".utf8), "EncryptedBookmarks2": cipher.encrypt(file.original)], cipher: cipher))
        XCTAssertThrowsError(try ChromiumBookmarkStore(files: ["EncryptedBookmarks2": Data()], cipher: cipher))
        XCTAssertThrowsError(try ChromiumBookmarkStore(files: ["EncryptedBookmarks2": cipher.encrypt(file.original)]))
        XCTAssertThrowsError(try ChromiumBookmarkStore(files: ["Bookmarks": file.original, "AccountBookmarks": file.original]))
        XCTAssertThrowsError(try ChromiumBookmarkStore(files: ["Bookmarks": file.original, "BookmarkMergedSurfaceOrdering": Data("{\"unknown\": []}".utf8)]))
        XCTAssertThrowsError(try ChromiumBookmarkStore(files: ["BookmarkMergedSurfaceOrdering": Data("{}".utf8)]))
    }
}
