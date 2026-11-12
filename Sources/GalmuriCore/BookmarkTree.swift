import Foundation

public struct Bookmark: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var chromeID: String
    public var name: String
    public var url: String?
    public var parent: String?
    public var children: [String]
    public var metadata: [String: JSONValue]
    public var isFolder: Bool { url == nil }

    public init(id: String = UUID().uuidString.lowercased(), chromeID: String = "0", name: String, url: String? = nil, parent: String? = nil, children: [String] = [], metadata: [String: JSONValue] = [:]) {
        self.id = id; self.chromeID = chromeID; self.name = name; self.url = url
        self.parent = parent; self.children = children; self.metadata = metadata
    }
}

public struct BookmarkTree: Codable, Equatable, Sendable {
    public var roots: [String: String]
    public var nodes: [String: Bookmark]
    public var orderedRoots: [String] {
        let known = ["bookmark_bar", "other", "synced"]
        return (known + roots.keys.filter { !known.contains($0) }.sorted()).compactMap { roots[$0] }
    }

    public init(roots: [String: String], nodes: [String: Bookmark]) { self.roots = roots; self.nodes = nodes }

    public func descendants(of id: String) -> Set<String> {
        var found = Set<String>(), pending = [id]
        while let next = pending.popLast() {
            guard found.insert(next).inserted else { continue }
            pending += nodes[next]?.children ?? []
        }
        return found
    }

    public func path(to id: String) -> String {
        var names = [String](), current: String? = id, visited = Set<String>()
        while let key = current, let node = nodes[key], visited.insert(key).inserted {
            names.append(node.name); current = node.parent
        }
        return names.reversed().joined(separator: " / ")
    }

    public func validate() throws {
        guard roots.count >= 1, Set(roots.values).count == roots.count else { throw GalmuriError.invalid("root identity") }
        let rootSet = Set(roots.values)
        var seen = Set<String>(), numericIDs = Set<String>()
        func visit(_ id: String, parent: String?) throws {
            guard seen.insert(id).inserted, let n = nodes[id], n.id == id, UUID(uuidString: id)?.uuidString.lowercased() == id,
                  n.parent == parent, n.isFolder || n.children.isEmpty, Set(n.children).count == n.children.count,
                  let numeric = Int64(n.chromeID), numeric >= 0, String(numeric) == n.chromeID,
                  Set(n.metadata.keys).isDisjoint(with: ["guid", "id", "name", "type", "url", "children"]),
                  numeric == 0 || numericIDs.insert(n.chromeID).inserted else { throw GalmuriError.invalid("cycle, identity, parent, or duplicate ID") }
            if let url = n.url {
                guard !url.isEmpty, !url.contains("\0") else { throw GalmuriError.invalid("empty URL") }
            }
            for child in n.children { try visit(child, parent: id) }
        }
        for id in orderedRoots {
            guard nodes[id]?.isFolder == true, nodes[id]?.parent == nil else { throw GalmuriError.invalid("protected root") }
            try visit(id, parent: nil)
        }
        guard seen == Set(nodes.keys), rootSet.isSubset(of: seen) else { throw GalmuriError.invalid("orphan nodes") }
    }

    public mutating func add(name: String, url: String?, to parent: String) throws -> String {
        guard let p = nodes[parent], p.isFolder, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GalmuriError.invalid("name or folder") }
        if let url { try Self.validateEditableURL(url) }
        let now = Self.chromeDate()
        let item = Bookmark(name: name, url: url, parent: parent, metadata: ["date_added": .string(now), "date_last_used": .string("0")] .merging(url == nil ? ["date_modified": .string(now)] : [:]) { _, new in new })
        nodes[item.id] = item; nodes[parent]?.children.append(item.id)
        return item.id
    }

    public mutating func edit(_ id: String, name: String, url: String?) throws {
        guard var n = nodes[id], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GalmuriError.invalid("name") }
        guard !roots.values.contains(id) else { throw GalmuriError.invalid("protected root") }
        if !n.isFolder { guard let url else { throw GalmuriError.invalid("URL") }; try Self.validateEditableURL(url); n.url = url }
        n.name = name; nodes[id] = n
    }

    public mutating func move(_ ids: Set<String>, to parent: String) throws {
        try validate()
        guard nodes[parent]?.isFolder == true else { throw GalmuriError.invalid("destination folder") }
        guard ids.allSatisfy({ nodes[$0] != nil }) else { throw GalmuriError.invalid("missing item") }
        let selected = ids.filter { id in !ids.contains { $0 != id && descendants(of: $0).contains(id) } }
        for id in selected {
            guard let n = nodes[id], !roots.values.contains(id), !descendants(of: id).contains(parent), let oldParent = n.parent else { throw GalmuriError.invalid("folder cycle or protected root") }
            if oldParent == parent { continue }
        }
        var order = [String]()
        func visit(_ id: String) {
            if selected.contains(id) { order.append(id) }
            for child in nodes[id]?.children ?? [] { visit(child) }
        }
        for id in orderedRoots { visit(id) }
        for id in order {
            let old = nodes[id]!.parent!
            if old == parent { continue }
            nodes[old]?.children.removeAll { $0 == id }; nodes[id]?.parent = parent; nodes[parent]?.children.append(id)
        }
        try validate()
    }

    public mutating func remove(_ ids: Set<String>) throws {
        guard ids.allSatisfy({ nodes[$0] != nil && !roots.values.contains($0) }) else { throw GalmuriError.invalid("protected root or missing item") }
        let removed = ids.reduce(into: Set<String>()) { $0.formUnion(descendants(of: $1)) }
        for id in removed { nodes.removeValue(forKey: id) }
        for id in nodes.keys { nodes[id]?.children.removeAll { removed.contains($0) } }
        try validate()
    }

    public mutating func reorder(_ id: String, offset: Int) throws {
        guard let parent = nodes[id]?.parent, var order = nodes[parent]?.children, let from = order.firstIndex(of: id) else { throw GalmuriError.invalid("order") }
        let (target, overflow) = from.addingReportingOverflow(offset)
        guard !overflow, order.indices.contains(target) else { return }
        order.swapAt(from, target); nodes[parent]?.children = order
    }

    public static func validateEditableURL(_ url: String) throws {
        guard let value = URL(string: url), ["https", "http"].contains(value.scheme?.lowercased() ?? ""), value.host?.isEmpty == false else { throw GalmuriError.invalid("enter an http or https URL") }
    }

    public static func chromeDate() -> String { String(Int64((Date().timeIntervalSince1970 + 11_644_473_600) * 1_000_000)) }
}
