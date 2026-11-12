import Foundation

public struct ConnectedProfile: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var source: URL
    public var permissionBookmark: Data?
    public var sourceRestriction: String?
    public var base: BookmarkFile
    public var working: BookmarkTree
    public var hasChanges: Bool { base.tree != working }
    public var changedIDs: Set<String> {
        Set(base.tree.nodes.keys).union(working.nodes.keys).filter { base.tree.nodes[$0] != working.nodes[$0] }
    }

    public init(name: String, source: URL, permissionBookmark: Data? = nil, sourceRestriction: String? = nil, base: BookmarkFile) {
        self.id = UUID(); self.name = name; self.source = source; self.permissionBookmark = permissionBookmark
        self.sourceRestriction = sourceRestriction; self.base = base; self.working = base.tree
    }
}

public struct Workspace: Codable, Sendable {
    public var version: Int = 1
    public var profiles: [ConnectedProfile]
    public init(profiles: [ConnectedProfile] = []) { self.profiles = profiles }

    public func validate() throws { try validate(reparsingBase: true) }

    /// Bases are immutable and only built by `BookmarkFile(data:)` or a validated `load`, so `save` skips the re-parse.
    func validate(reparsingBase: Bool) throws {
        guard version == 1, Set(profiles.map(\.id)).count == profiles.count else { throw GalmuriError.invalid("workspace version or profile identity") }
        for profile in profiles {
            try profile.working.validate()
            guard try !reparsingBase || BookmarkFile(data: profile.base.original) == profile.base,
                  profile.working.roots == profile.base.tree.roots else { throw GalmuriError.invalid("workspace snapshot") }
        }
    }

    public static func load(from url: URL) throws -> Workspace {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 100_000_000 else { throw GalmuriError.invalid("workspace exceeds 100 MB") }
        let result = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: url))
        try result.validate(); return result
    }

    public func save(to url: URL) throws {
        try validate(reparsingBase: false)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count < 100_000_000 else { throw GalmuriError.invalid("workspace exceeds 100 MB") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
