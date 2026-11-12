import Foundation

public enum BookmarkRevert {
    public static func selected(_ ids: Set<String>, base: BookmarkTree, working: BookmarkTree) throws -> BookmarkTree {
        try base.validate(); try working.validate()
        guard base.roots == working.roots, !ids.isEmpty,
              ids.allSatisfy({ base.nodes[$0] != working.nodes[$0] }) else { throw GalmuriError.invalid("revert selection") }
        var affected = ids
        for id in ids where base.nodes[id]?.isFolder == true || working.nodes[id]?.isFolder == true {
            affected.formUnion(base.descendants(of: id)); affected.formUnion(working.descendants(of: id))
        }
        var result = working
        for id in affected {
            if let original = base.nodes[id] { result.nodes[id] = original }
            else { result.nodes[id] = nil }
        }
        // Restoring a deleted child may require its ancestors, but not unrelated deleted siblings.
        for id in Array(affected) where result.nodes[id] != nil {
            var parent = result.nodes[id]?.parent
            while let key = parent, result.nodes[key] == nil {
                guard let original = base.nodes[key], original.isFolder else { throw GalmuriError.invalid("revert parent") }
                result.nodes[key] = original; affected.insert(key); parent = original.parent
            }
        }
        let byParent = Dictionary(grouping: result.nodes.values.filter { $0.parent != nil }, by: { $0.parent! })
        for folder in result.nodes.values.filter(\.isFolder) {
            let children = Set((byParent[folder.id] ?? []).map(\.id))
            let baseline = base.nodes[folder.id]?.children ?? []
            var order = (affected.contains(folder.id) ? baseline : working.nodes[folder.id]?.children ?? []).filter { children.contains($0) }
            for id in baseline where children.contains(id) && !order.contains(id) {
                let later = baseline.drop(while: { $0 != id }).dropFirst()
                if let anchor = later.first(where: { order.contains($0) }), let index = order.firstIndex(of: anchor) { order.insert(id, at: index) }
                else { order.append(id) }
            }
            for id in working.nodes[folder.id]?.children ?? [] where children.contains(id) && !order.contains(id) { order.append(id) }
            guard Set(order) == children else { throw GalmuriError.invalid("revert child order") }
            result.nodes[folder.id]?.children = order
        }
        try result.validate()
        return result
    }
}
