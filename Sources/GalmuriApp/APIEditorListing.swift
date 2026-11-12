import GalmuriCore

enum APIEditorListing {
    static func destinations(tree: BookmarkTree, itemIDs: Set<String>) -> [(node: Bookmark, path: String)] {
        let excluded = itemIDs.reduce(into: Set<String>()) { $0.formUnion(tree.descendants(of: $1)) }
        return tree.nodes.values.filter { $0.isFolder && !excluded.contains($0.id) }
            .map { (node: $0, path: tree.path(to: $0.id)) }.sorted { $0.path == $1.path ? $0.node.id < $1.node.id : $0.path < $1.path }
    }
    static func rows(tree: BookmarkTree, folder: String?, query: String) -> [Bookmark] {
        guard let root = folder ?? tree.orderedRoots.first else { return [] }
        var pending = Array((tree.nodes[root]?.children ?? []).reversed()), folders = [Bookmark](), links = [Bookmark]()
        while let id = pending.popLast(), let node = tree.nodes[id] {
            if query.isEmpty || (node.name + " " + (node.url ?? "")).localizedCaseInsensitiveContains(query) {
                if node.isFolder { folders.append(node) } else { links.append(node) }
            }
            if !query.isEmpty { pending.append(contentsOf: node.children.reversed()) }
        }
        return folders + links
    }
}
