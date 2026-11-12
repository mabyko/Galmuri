import Foundation
import CryptoKit

public struct BookmarkFile: Codable, Equatable, Sendable {
    public let original: Data
    public let payload: [String: JSONValue]
    public let tree: BookmarkTree
    public var fingerprint: String { Self.hash(original) }
    public var writeRestriction: String? {
        if JSONValue.object(payload).containsUnverifiedNumber { return "Unverified numeric metadata" }
        if let sync = payload["sync_metadata"], sync != .string(""), sync != .null { return "Synchronization metadata is not yet supported for direct writes" }
        if Set(tree.roots.keys) != Set(["bookmark_bar", "other", "synced"]) { return "Unrecognized root folders" }
        let bytes = Self.checksumBytes(for: tree)
        let md5 = Insecure.MD5.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        if payload["checksum"] != .string(md5) { return "Missing or unverified bookmark checksum" }
        if let sha256 = payload["checksum_sha256"], sha256 != .string(Self.hash(bytes)) { return "Unverified SHA256 bookmark checksum" }
        return nil
    }

    public init(data: Data) throws {
        guard data.count < 50_000_000 else { throw GalmuriError.invalid("file exceeds 50 MB") }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let payload = decoded.object, payload["version"] == .integer(1), let roots = payload["roots"]?.object else { throw GalmuriError.invalid("unsupported JSON version or roots") }
        var nodes = [String: Bookmark](), rootIDs = [String: String]()
        func read(_ value: JSONValue, parent: String?) throws -> String {
            guard let o = value.object, let id = o["guid"]?.string?.lowercased(), UUID(uuidString: id) != nil,
                  nodes[id] == nil, let numeric = o["id"]?.string, Int64(numeric).map({ $0 > 0 }) == true,
                  let name = o["name"]?.string, let type = o["type"]?.string, ["folder", "url"].contains(type) else { throw GalmuriError.invalid("bookmark identity or type") }
            guard type == "folder" ? o["url"] == nil : o["children"] == nil else { throw GalmuriError.invalid("inconsistent node type") }
            let url: String?
            if type == "url" { guard let u = o["url"]?.string else { throw GalmuriError.invalid("missing URL") }; url = u }
            else { url = nil }
            let metadata = o.filter { !["guid", "id", "name", "type", "url", "children"].contains($0.key) }
            nodes[id] = Bookmark(id: id, chromeID: numeric, name: name, url: url, parent: parent, metadata: metadata)
            if type == "folder" {
                guard let children = o["children"]?.array else { throw GalmuriError.invalid("folder children") }
                let childIDs = try children.map { try read($0, parent: id) }
                nodes[id]?.children = childIDs
            }
            return id
        }
        for (key, value) in roots { rootIDs[key] = try read(value, parent: nil) }
        let tree = BookmarkTree(roots: rootIDs, nodes: nodes)
        try tree.validate()
        self.original = data; self.payload = payload; self.tree = tree
    }

    public func serialize(_ edited: BookmarkTree) throws -> Data {
        try edited.validate()
        guard edited.roots == tree.roots else { throw GalmuriError.invalid("protected roots changed") }
        if edited == tree { return original }
        if let restriction = writeRestriction { throw GalmuriError.unsupported(restriction) }
        if edited.nodes.values.contains(where: { JSONValue.object($0.metadata).containsUnverifiedNumber }) {
            throw GalmuriError.unsupported("Unverified numeric metadata")
        }
        let originalIDs = Dictionary(uniqueKeysWithValues: tree.nodes.values.map { ($0.chromeID, $0.id) })
        for (id, node) in edited.nodes {
            if let oldGUID = originalIDs[node.chromeID], oldGUID != id { throw GalmuriError.invalid("existing numeric identity reused") }
            if let old = tree.nodes[id] {
                guard old.chromeID == node.chromeID, old.isFolder == node.isFolder else { throw GalmuriError.invalid("existing identity or type changed") }
            }
        }
        var originalGUIDs = [String: String]()
        func collectGUIDs(_ value: JSONValue) {
            if let guid = value.object?["guid"]?.string { originalGUIDs[guid.lowercased()] = guid }
            for child in value.object?["children"]?.array ?? [] { collectGUIDs(child) }
        }
        for value in payload["roots"]?.object?.values ?? [:].values { collectGUIDs(value) }
        var output = payload, checksumBytes = Data()
        var maxID = (Array(tree.nodes.values) + Array(edited.nodes.values)).compactMap { Int64($0.chromeID) }.max() ?? 0
        func encodeNode(_ id: String) throws -> JSONValue {
            guard let node = edited.nodes[id] else { throw GalmuriError.invalid("missing node") }
            var numeric = node.chromeID
            if numeric == "0" {
                guard maxID < Int64.max else { throw GalmuriError.invalid("ID overflow") }
                maxID += 1; numeric = String(maxID)
            }
            var o = node.metadata
            o["id"] = .string(numeric); o["guid"] = .string(originalGUIDs[id] ?? node.id); o["name"] = .string(node.name)
            let type = node.isFolder ? "folder" : "url"
            o["type"] = .string(type)
            checksumBytes.append(contentsOf: numeric.utf8)
            for unit in node.name.utf16 { checksumBytes.append(UInt8(unit & 255)); checksumBytes.append(UInt8(unit >> 8)) }
            checksumBytes.append(contentsOf: type.utf8)
            if let url = node.url { o["url"] = .string(url); checksumBytes.append(contentsOf: url.utf8) }
            else {
                o["children"] = .array(try node.children.map { try encodeNode($0) })
            }
            return .object(o)
        }
        var roots = [String: JSONValue]()
        for id in edited.orderedRoots {
            let key = edited.roots.first { $0.value == id }!.key
            roots[key] = try encodeNode(id)
        }
        output["roots"] = .object(roots)
        output["checksum"] = .string(Insecure.MD5.hash(data: checksumBytes).map { String(format: "%02x", $0) }.joined())
        if output["checksum_sha256"] != nil { output["checksum_sha256"] = .string(Self.hash(checksumBytes)) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(JSONValue.object(output))
    }

    public static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func checksumBytes(for tree: BookmarkTree) -> Data {
        var bytes = Data()
        func visit(_ id: String) {
            let node = tree.nodes[id]!
            bytes.append(contentsOf: node.chromeID.utf8)
            for unit in node.name.utf16 { bytes.append(UInt8(unit & 255)); bytes.append(UInt8(unit >> 8)) }
            bytes.append(contentsOf: (node.isFolder ? "folder" : "url").utf8)
            if let url = node.url { bytes.append(contentsOf: url.utf8) }
            for child in node.children { visit(child) }
        }
        for id in tree.orderedRoots { visit(id) }
        return bytes
    }
}
