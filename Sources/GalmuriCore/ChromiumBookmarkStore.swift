import Foundation

/// A local bookmark store whose observed copies agree; account and nonempty merged ordering remain unsupported.
public struct ChromiumBookmarkStore: Sendable {
    public let file: BookmarkFile
    public let originals: [String: Data]
    public static let plaintextName = "Bookmarks"
    public static let encryptedName = "EncryptedBookmarks2"
    public static let orderingName = "BookmarkMergedSurfaceOrdering"

    public init(files: [String: Data], cipher: ChromiumBookmarkCipher? = nil) throws {
        let known = Set([Self.plaintextName, Self.encryptedName, Self.orderingName])
        guard !files.isEmpty, Set(files.keys).isSubset(of: known), files.values.allSatisfy({ $0.count < 50_000_000 }) else {
            throw GalmuriError.unsupported("Unverified bookmark file set.")
        }
        if let order = files[Self.orderingName] {
            guard let object = try JSONDecoder().decode(JSONValue.self, from: order).object, object.isEmpty else {
                throw GalmuriError.unsupported("Nonempty merged bookmark ordering is unsupported.")
            }
        }
        let plain = try files[Self.plaintextName].map { try BookmarkFile(data: $0) }
        let encrypted: BookmarkFile?
        if let bytes = files[Self.encryptedName] {
            guard let cipher else { throw GalmuriError.unsupported("Bookmark encryption key is unavailable.") }
            encrypted = try BookmarkFile(data: cipher.decrypt(bytes))
        } else { encrypted = nil }
        if let plain, let encrypted {
            guard plain.original == encrypted.original else {
                throw GalmuriError.unsupported("Bookmark copies disagree; their authoritative source is unverified.")
            }
        }
        guard let canonical = encrypted ?? plain else { throw GalmuriError.unsupported("Unverified bookmark file set.") }
        file = canonical; originals = files
    }

    public func serialize(_ edited: BookmarkTree, cipher: ChromiumBookmarkCipher? = nil) throws -> [String: Data] {
        if edited == file.tree { return originals }
        let bytes = try file.serialize(edited)
        var output = originals
        if originals[Self.plaintextName] != nil { output[Self.plaintextName] = bytes }
        if originals[Self.encryptedName] != nil {
            guard let cipher else { throw GalmuriError.unsupported("Bookmark encryption key is unavailable.") }
            // Verify the supplied key against the captured copy before replacing its ciphertext.
            guard try cipher.decrypt(originals[Self.encryptedName]!) == file.original else {
                throw GalmuriError.invalid("Encrypted bookmark data could not be verified.")
            }
            output[Self.encryptedName] = try cipher.encrypt(bytes)
        }
        return output
    }
}
