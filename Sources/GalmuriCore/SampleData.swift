import Foundation
import CryptoKit

public enum SampleData {
    public static let bar = "00000000-0000-4000-a000-000000000001"
    public static let other = "00000000-0000-4000-a000-000000000002"
    public static let mobile = "00000000-0000-4000-a000-000000000003"

    public static func file() throws -> BookmarkFile {
        let rootIDs = ["bookmark_bar": bar, "other": other, "synced": mobile]
        var nodes = [String: Bookmark]()
        for (index, pair) in [("bookmark_bar", "Bookmarks bar"), ("other", "Other bookmarks"), ("synced", "Mobile bookmarks")].enumerated() {
            let id = rootIDs[pair.0]!
            nodes[id] = Bookmark(id: id, chromeID: String(index + 1), name: pair.1, metadata: ["date_added": .string("13300000000000000"), "date_modified": .string("13300000000000000")])
        }
        var tree = BookmarkTree(roots: rootIDs, nodes: nodes)
        let design = try tree.add(name: "Design references", url: nil, to: bar)
        let dev = try tree.add(name: "Development", url: nil, to: bar)
        for (title, url, parent) in [
            ("Interface archive", "https://example.com/interface", design),
            ("Typography notes", "https://example.com/type", design),
            ("Motion collection", "https://example.com/motion", design),
            ("Component handbook", "https://example.com/components", dev),
            ("Interface archive — reading copy", "https://example.com/interface", other),
            ("Color reference", "https://example.com/color", design),
            ("Design engineering", "https://example.com/engineering", dev)
        ] { _ = try tree.add(name: title, url: url, to: parent) }
        func encode(_ id: String, numeric: inout Int) -> JSONValue {
            let n = tree.nodes[id]!
            var result = n.metadata
            numeric += 1
            result["id"] = .string(String(numeric)); result["guid"] = .string(id); result["name"] = .string(n.name)
            result["type"] = .string(n.isFolder ? "folder" : "url")
            if let url = n.url { result["url"] = .string(url) }
            else { result["children"] = .array(n.children.map { encode($0, numeric: &numeric) }) }
            return .object(result)
        }
        var roots = [String: JSONValue](), numeric = 0
        for id in tree.orderedRoots { roots[rootIDs.first { $0.value == id }!.key] = encode(id, numeric: &numeric) }
        var payload: [String: JSONValue] = ["version": .integer(1), "roots": .object(roots), "meta_info": .object(["fixture": .string("synthetic-only")])]
        let parsed = try BookmarkFile(data: JSONEncoder().encode(JSONValue.object(payload)))
        let bytes = BookmarkFile.checksumBytes(for: parsed.tree)
        payload["checksum"] = .string(Insecure.MD5.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        return try BookmarkFile(data: JSONEncoder().encode(JSONValue.object(payload)))
    }
}
