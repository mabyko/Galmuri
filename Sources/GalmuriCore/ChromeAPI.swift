import Foundation
import CryptoKit
import Darwin

public struct ChromeAPINode: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var parent: String?
    public var title: String
    public var url: String?
    public var children: [String]
    public var folderType: String?
    public var syncing: Bool?
    public var managed: Bool
}

public struct ChromeAPISnapshot: Codable, Equatable, Sendable {
    public var nodes: [ChromeAPINode]
    public init(data: Data) throws {
        guard data.count < 8_000_000 else { throw GalmuriError.invalid("API snapshot size") }
        self = try JSONDecoder().decode(Self.self, from: data)
        try validate()
    }
    public func validate() throws {
        guard !nodes.isEmpty, nodes.count <= 20_000, Set(nodes.map(\.id)).count == nodes.count else { throw GalmuriError.invalid("API node identities") }
        let indexed = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let roots = nodes.filter { $0.parent == nil }
        guard roots.count == 1, roots[0].url == nil else { throw GalmuriError.invalid("API roots") }
        var visited = Set<String>()
        func visit(_ id: String, parent: String?, depth: Int) throws {
            guard depth <= 64, visited.insert(id).inserted, let n = indexed[id], n.parent == parent,
                  !id.isEmpty, id.utf8.count <= 128, n.title.utf8.count <= 16_384,
                  n.url == nil || n.children.isEmpty, Set(n.children).count == n.children.count else { throw GalmuriError.invalid("API hierarchy") }
            if let url = n.url { guard !url.isEmpty, url.utf8.count <= 32_768, !url.contains("\0") else { throw GalmuriError.invalid("API URL") } }
            for child in n.children { try visit(child, parent: id, depth: depth + 1) }
        }
        try visit(roots[0].id, parent: nil, depth: 0)
        guard visited.count == nodes.count else { throw GalmuriError.invalid("API orphan") }
    }
    public var folders: [ChromeAPINode] { nodes.filter { $0.url == nil && $0.parent != nil } }
    public func writable(scope: String) -> Bool {
        guard (try? validate()) != nil else { return false }
        let indexed = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        guard let root = indexed[scope], root.parent != nil, root.url == nil, root.folderType == nil || ["bookmarks-bar", "other", "mobile"].contains(root.folderType!) else { return false }
        func check(_ id: String) -> Bool {
            guard let node = indexed[id], !node.managed, node.syncing == false,
                  id == scope || node.folderType == nil else { return false }
            return node.children.allSatisfy(check)
        }
        return check(scope)
    }
    public func tree(scope: String, mapping: inout [String: String], excluding: Set<String>) throws -> BookmarkTree {
        try validate()
        let indexed = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        guard indexed[scope]?.url == nil, indexed[scope]?.parent != nil else { throw GalmuriError.invalid("API scope") }
        guard Set(mapping.values).count == mapping.count, mapping.values.allSatisfy({ UUID(uuidString: $0)?.uuidString.lowercased() == $0 }) else { throw GalmuriError.invalid("API identity map") }
        for id in excluding { guard indexed[id]?.parent == scope, indexed[id]?.url == nil else { throw GalmuriError.invalid("API recovery folder changed") } }
        var result = [String: Bookmark]()
        func visit(_ id: String, parent: String?) throws -> String {
            let n = indexed[id]!
            let key = mapping[id] ?? UUID().uuidString.lowercased(); mapping[id] = key
            let children = try n.children.filter { !excluding.contains($0) }.map { try visit($0, parent: key) }
            result[key] = Bookmark(id: key, name: n.title, url: n.url, parent: parent, children: children)
            return key
        }
        let root = try visit(scope, parent: nil)
        let tree = BookmarkTree(roots: ["api": root], nodes: result)
        try tree.validate(); return tree
    }
    public static func hash(_ raw: String) -> String { SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined() }
}

public struct APIEnvelope: Codable, Sendable {
    public let session: BridgeProof
    public let writable: Bool
    public let raw: String
    public init(session: BridgeProof, writable: Bool, raw: String) { self.session = session; self.writable = writable; self.raw = raw }
    public var snapshot: ChromeAPISnapshot { get throws { try ChromeAPISnapshot(data: Data(raw.utf8)) } }
}

public struct APIJob: Codable, Identifiable, Sendable {
    public var owner: APIOwner?
    public let id: UUID
    public let sessionID: UUID
    public let installationID: UUID
    public let command: String
    public let scope: String
    public let expected: String
    public let desired: [APIDesiredNode]
    public let recoveryIDs: [String]
    public static func refresh(_ session: BridgeProof) -> APIJob {
        APIJob(id: UUID(), sessionID: session.id, installationID: session.installationID, command: "snapshot", scope: "", expected: "", desired: [], recoveryIDs: [])
    }
    public static func adopt(_ envelope: APIEnvelope) -> APIJob {
        APIJob(id: UUID(), sessionID: envelope.session.id, installationID: envelope.session.installationID, command: "adopt", scope: "", expected: ChromeAPISnapshot.hash(envelope.raw), desired: [], recoveryIDs: [])
    }
}
public struct APIOwner: Codable, Equatable, Sendable {
    public let pid: Int32
    public let executable: String
    public let seconds: UInt64
    public let microseconds: UInt64
    public static func read(_ pid: Int32 = getpid()) throws -> APIOwner {
        var info = proc_bsdinfo(), path = [CChar](repeating: 0, count: 4096)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == geteuid(), proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { throw GalmuriError.invalid("API app process identity unavailable") }
        let end = path.firstIndex(of: 0) ?? path.endIndex
        let executable = String(decoding: path[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return APIOwner(pid: pid, executable: executable, seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
    }
}
public struct APIDesiredNode: Codable, Sendable {
    public let key: String
    public let id: String?
    public let title: String
    public let url: String?
    public let parent: String?
    public let children: [String]
}
public struct APIJobResult: Codable, Sendable {
    public var jobID: UUID
    public var state: String
    public var mapping: [String: String]?
    public var recovery: String?
    public var detail: String?
    public var sequence: Int?
}
public struct APIStop: Codable, Sendable, Equatable {
    public let jobID: UUID
    public let sessionID: UUID
    public let installationID: UUID
    public init(job: APIJob) { jobID = job.id; sessionID = job.sessionID; installationID = job.installationID }
}
public struct APICheckpoint: Codable, Identifiable, Sendable {
    public let id: UUID
    public let before: BookmarkTree
    public let after: BookmarkTree
    public init(id: UUID, before: BookmarkTree, after: BookmarkTree) { self.id = id; self.before = before; self.after = after }
}
public struct APIWorkingCopy: Codable, Identifiable, Sendable {
    public var id: UUID
    public var installationID: UUID
    public var name: String
    public var scope: String
    public var mapping: [String: String]
    public var recoveryIDs: Set<String>
    public var base: BookmarkTree
    public var working: BookmarkTree
    public var pendingJob: UUID?
    public var history: [APICheckpoint]
    public init(envelope: APIEnvelope, scope: String) throws {
        id = UUID(); installationID = envelope.session.installationID; name = envelope.session.name
        self.scope = scope; mapping = [:]; recoveryIDs = []; pendingJob = nil; history = []
        base = try envelope.snapshot.tree(scope: scope, mapping: &mapping, excluding: [])
        working = base
    }
    public mutating func edit(_ mutation: (inout BookmarkTree) throws -> Void) throws {
        var next = working; try mutation(&next)
        next = Self.semantic(next); try Self.validateTree(next)
        guard next.roots == base.roots else { throw GalmuriError.invalid("API protected root") }
        working = next
    }
    public static func semantic(_ tree: BookmarkTree) -> BookmarkTree {
        var result = tree
        for id in result.nodes.keys { result.nodes[id]?.metadata = [:]; result.nodes[id]?.chromeID = "0" }
        return result
    }
    public static func validateTree(_ tree: BookmarkTree) throws {
        guard tree.nodes.count <= 20_000 else { throw GalmuriError.invalid("API tree size") }
        var pending = tree.orderedRoots.map { ($0, 0) }, seen = Set<String>()
        while let (id, depth) = pending.popLast() {
            guard depth <= 64, seen.insert(id).inserted, let node = tree.nodes[id] else { throw GalmuriError.invalid("API tree depth or structure") }
            pending += node.children.map { ($0, depth + 1) }
        }
        try tree.validate()
    }
    public func job(envelope: APIEnvelope, target: BookmarkTree) throws -> APIJob {
        guard envelope.writable, envelope.session.installationID == installationID, pendingJob == nil,
              try envelope.snapshot.writable(scope: scope),
              target.nodes.count <= 10_000, target.roots == base.roots, target == Self.semantic(target) else { throw GalmuriError.invalid("API review identity, size or write capability") }
        try Self.validateTree(target)
        let inverse = Dictionary(uniqueKeysWithValues: mapping.map { ($0.value, $0.key) })
        for node in target.nodes.values {
            guard node.name.utf16.count <= 4096, (node.url?.utf8.count ?? 0) <= 32768 else { throw GalmuriError.invalid("API edited text size") }
        }
        let job = APIJob(id: UUID(), sessionID: envelope.session.id, installationID: installationID, command: "apply", scope: scope,
                      expected: ChromeAPISnapshot.hash(envelope.raw), desired: target.nodes.values.sorted { $0.id < $1.id }.map {
            APIDesiredNode(key: $0.id, id: inverse[$0.id], title: $0.name, url: $0.url, parent: $0.parent, children: $0.children)
        }, recoveryIDs: recoveryIDs.sorted())
        guard try JSONEncoder().encode(job).count < 7_900_000 else { throw GalmuriError.invalid("API job size") }
        return job
    }
}

public struct APIWorkspace: Codable, Sendable {
    public var version = 1
    public var revision: UUID?
    public var profiles: [APIWorkingCopy] = []
    public init() {}
    public func validate() throws {
        guard version == 1, profiles.count <= 100, Set(profiles.map(\.id)).count == profiles.count else { throw GalmuriError.invalid("API workspace version or profiles") }
        for p in profiles {
            try APIWorkingCopy.validateTree(p.base); try APIWorkingCopy.validateTree(p.working)
            guard p.base.roots == p.working.roots, p.base == APIWorkingCopy.semantic(p.base), p.working == APIWorkingCopy.semantic(p.working),
                  Set(p.mapping.values).count == p.mapping.count, p.mapping.count <= 100_000,
                  Set(p.base.nodes.keys).isSubset(of: Set(p.mapping.values)), p.mapping[p.scope] == p.base.roots["api"],
                  p.mapping.values.allSatisfy({ UUID(uuidString: $0)?.uuidString.lowercased() == $0 }), p.history.count <= 100 else { throw GalmuriError.invalid("API working copy") }
            for h in p.history {
                try APIWorkingCopy.validateTree(h.before); try APIWorkingCopy.validateTree(h.after)
                guard h.before.roots == p.base.roots, h.after.roots == p.base.roots,
                      Set(h.before.nodes.keys).union(h.after.nodes.keys).isSubset(of: Set(p.mapping.values)) else { throw GalmuriError.invalid("API history mapping") }
            }
        }
    }
}

public struct BridgeAPIStore: Sendable {
    public let directory: URL
    let files: BridgeProofStore
    public init(workspace: URL, variant: String) {
        directory = workspace.appendingPathComponent("BridgeAPI")
        files = BridgeProofStore(directory: directory, variant: variant)
    }
    func name(_ text: String) -> URL { directory.appendingPathComponent(text + ".json") }
    public func loadWorkspace() throws -> APIWorkspace {
        guard FileManager.default.fileExists(atPath: name("workspace").path) else { return APIWorkspace() }
        try files.checkDirectory(create: false)
        let value = try JSONDecoder().decode(APIWorkspace.self, from: files.readData(name("workspace"), limit: 20_000_000))
        try value.validate(); return value
    }
    public func save(_ value: APIWorkspace, expectedRevision: UUID?) throws {
        try value.validate(); try files.checkDirectory(create: true)
        let fd = open(directory.appendingPathComponent("workspace.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw GalmuriError.invalid("API workspace lock") }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_nlink == 1,
              info.st_mode & 0o077 == 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw GalmuriError.staleSource }
        guard value.revision != nil, try loadWorkspace().revision == expectedRevision else { throw GalmuriError.staleSource }
        try files.replaceData(JSONEncoder().encode(value), target: name("workspace"))
    }
    public func put<T: Encodable>(_ value: T, name: String) throws {
        guard UUID(uuidString: name.split(separator: ".").first.map(String.init) ?? "") != nil else { throw GalmuriError.invalid("API file identity") }
        try files.replaceData(JSONEncoder().encode(value), target: self.name(name))
    }
    public func get<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        guard UUID(uuidString: name.split(separator: ".").first.map(String.init) ?? "") != nil else { throw GalmuriError.invalid("API file identity") }
        try files.checkDirectory(create: false)
        return try JSONDecoder().decode(type, from: files.readData(self.name(name), limit: 20_000_000))
    }
    public func envelope(_ session: BridgeProof) throws -> APIEnvelope {
        let value = try get(APIEnvelope.self, name: session.id.uuidString + ".snapshot")
        guard value.session == session else { throw GalmuriError.staleSource }
        _ = try value.snapshot; return value
    }
    public func queue(_ job: APIJob) throws {
        try put(job, name: job.id.uuidString + ".job")
        try put(job, name: job.sessionID.uuidString + ".outbox")
    }
    public func requestStop(_ job: APIJob) throws { try put(APIStop(job: job), name: job.id.uuidString + ".stop") }
    public func stopRequested(_ job: APIJob) throws -> Bool {
        let file = name(job.id.uuidString + ".stop")
        var info = stat()
        if lstat(file.path, &info) != 0 { guard errno == ENOENT else { throw GalmuriError.staleSource }; return false }
        guard try get(APIStop.self, name: job.id.uuidString + ".stop") == APIStop(job: job) else { throw GalmuriError.staleSource }
        return true
    }
}
