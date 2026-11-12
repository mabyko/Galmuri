public extension BookmarkTree {
    /// Moves an item one step among siblings of the same kind (folders with folders, links with links). Returns false when there is no such neighbour.
    @discardableResult mutating func reorderAmongPeers(_ id: String, direction: Int) throws -> Bool {
        guard direction == -1 || direction == 1, let node = nodes[id], let siblings = node.parent.flatMap({ nodes[$0]?.children }),
              let from = siblings.firstIndex(of: id) else { throw GalmuriError.invalid("order") }
        let peers = siblings.filter { nodes[$0]?.isFolder == node.isFolder }
        guard let index = peers.firstIndex(of: id), peers.indices.contains(index + direction),
              let to = siblings.firstIndex(of: peers[index + direction]) else { return false }
        try reorder(id, offset: to - from)
        return true
    }
}
