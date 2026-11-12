import Foundation

public enum MergeSide: String, Codable, Sendable { case ours, theirs }

public struct MergeConflict: Identifiable, Equatable, Sendable {
    public var id: String
    public var item: String
    public var field: String
    public var base: String
    public var ours: String
    public var theirs: String
}

public struct MergeResult: Sendable {
    public var tree: BookmarkTree
    public var conflicts: [MergeConflict]
    public var unresolved: [MergeConflict]
}

public enum MergeEngine {
    public static func merge(base: BookmarkTree, ours: BookmarkTree, theirs: BookmarkTree, resolutions: [String: MergeSide] = [:]) throws -> MergeResult {
        try base.validate(); try ours.validate(); try theirs.validate()
        guard base.roots == ours.roots, base.roots == theirs.roots else { throw GalmuriError.invalid("root identity changed") }
        let originalIDs = Dictionary(uniqueKeysWithValues: base.nodes.values.filter { $0.chromeID != "0" }.map { ($0.chromeID, $0.id) })
        for tree in [ours, theirs] {
            for node in tree.nodes.values {
                if node.chromeID != "0", let oldGUID = originalIDs[node.chromeID], oldGUID != node.id { throw GalmuriError.invalid("Chrome identity was regenerated; reconnect before applying") }
                if let old = base.nodes[node.id], old.chromeID != node.chromeID || old.isFolder != node.isFolder { throw GalmuriError.invalid("existing identity or type changed") }
            }
        }

        var result = [String: Bookmark](), conflicts = [MergeConflict](), covered = Set<String>()
        func describe(_ node: Bookmark?) -> String {
            guard let node else { return "Remove item" }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return (try? String(decoding: encoder.encode(node), as: UTF8.self)) ?? "Invalid item metadata"
        }
        struct SubtreeChoice { var id: String; var selected: BookmarkTree; var all: Set<String> }
        var subtreeChoices = [SubtreeChoice]()
        func subtreeChanged(_ id: String, in tree: BookmarkTree) -> Bool {
            let a = base.descendants(of: id), b = tree.descendants(of: id)
            return a != b || a.contains { base.nodes[$0] != tree.nodes[$0] }
        }
        // Base is validated (acyclic), so each depth is memoized from its nearest known ancestor.
        var depths = [String: Int]()
        for id in base.nodes.keys where depths[id] == nil {
            var chain = [String](), current: String? = id
            while let next = current, depths[next] == nil { chain.append(next); current = base.nodes[next]?.parent }
            var depth = current.flatMap { depths[$0] } ?? -1
            for next in chain.reversed() { depth += 1; depths[next] = depth }
        }
        for id in base.nodes.keys.sorted(by: { (depths[$0]!, $0) < (depths[$1]!, $1) }) where !covered.contains(id) && base.nodes[id]?.isFolder == true {
            let deletedOurs = ours.nodes[id] == nil, deletedTheirs = theirs.nodes[id] == nil
            if deletedOurs == deletedTheirs { continue }
            let surviving = deletedOurs ? theirs : ours
            guard subtreeChanged(id, in: surviving) else { continue }
            let key = id + ".subtree"
            let all = base.descendants(of: id).union(ours.descendants(of: id)).union(theirs.descendants(of: id))
            func show(_ tree: BookmarkTree) -> String { all.sorted().map { "[\($0)] \(tree.path(to: $0))\n\(describe(tree.nodes[$0]))" }.joined(separator: "\n\n") }
            conflicts.append(MergeConflict(id: key, item: base.path(to: id), field: "Folder deletion and descendant changes", base: show(base), ours: show(ours), theirs: show(theirs)))
            let selected = resolutions[key] == .ours ? ours : theirs
            covered.formUnion(all)
            subtreeChoices.append(SubtreeChoice(id: id, selected: selected, all: all))
        }

        func pick<T: Equatable>(_ b: T, _ o: T, _ t: T, key: String, item: @autoclosure () -> String, field: String, show: (T) -> String) -> T {
            if o == b { return t }
            if t == b || o == t { return o }
            conflicts.append(MergeConflict(id: key, item: item(), field: field, base: show(b), ours: show(o), theirs: show(t)))
            return resolutions[key] == .ours ? o : t
        }
        let allIDs = Set(base.nodes.keys).union(ours.nodes.keys).union(theirs.nodes.keys)
        for id in allIDs.sorted() where !covered.contains(id) {
            let b = base.nodes[id], o = ours.nodes[id], t = theirs.nodes[id]
            if b == nil || o == nil || t == nil {
                let chosen = pick(b, o, t, key: id + ".existence", item: (b ?? o ?? t)!.name, field: "Addition or deletion", show: describe)
                result[id] = chosen
                continue
            }
            var n = t!
            let item = { base.path(to: id) }
            n.name = pick(b!.name, o!.name, t!.name, key: id + ".name", item: item(), field: "Name", show: { $0 })
            n.url = pick(b!.url, o!.url, t!.url, key: id + ".url", item: item(), field: "URL", show: { $0 ?? "Folder" })
            n.parent = pick(b!.parent, o!.parent, t!.parent, key: id + ".parent", item: item(), field: "Folder", show: { value in value.map { ours.path(to: $0) } ?? "Root" })
            let metadataKeys = Set(b!.metadata.keys).union(o!.metadata.keys).union(t!.metadata.keys)
            n.metadata = [:]
            for field in metadataKeys.sorted() {
                n.metadata[field] = pick(b!.metadata[field], o!.metadata[field], t!.metadata[field], key: id + ".metadata." + field, item: item(), field: field, show: { $0?.display ?? "Not present" })
            }
            result[id] = n
        }
        for group in subtreeChoices {
            for id in group.all { result.removeValue(forKey: id) }
            for id in group.all { result[id] = group.selected.nodes[id] }
        }

        // A walk can stop at an already-walked node: every cycle is fully found by the first walk that reaches it.
        var cyclic = Set<String>(), walked = Set<String>()
        for id in result.keys {
            var chain = [String](), position = [String: Int](), current: String? = id
            while let next = current, !walked.contains(next), let node = result[next] {
                if let start = position[next] { cyclic.formUnion(chain[start...]); break }
                position[next] = chain.count; chain.append(next); current = node.parent
            }
            walked.formUnion(chain)
        }
        if !cyclic.isEmpty {
            // Include candidate ancestors so resolving one cycle cannot introduce another.
            var affected = cyclic, pending = Array(cyclic)
            while let id = pending.popLast() {
                for tree in [base, ours, theirs] {
                    if let parent = tree.nodes[id]?.parent, affected.insert(parent).inserted { pending.append(parent) }
                }
            }
            let key = "structure.moves"
            let parentKeys = Set(affected.map { $0 + ".parent" })
            conflicts.removeAll { parentKeys.contains($0.id) }
            func show(_ tree: BookmarkTree) -> String { affected.sorted().map { tree.nodes[$0] == nil ? "Removed: \($0)" : tree.path(to: $0) }.joined(separator: "\n") }
            conflicts.append(MergeConflict(id: key, item: cyclic.sorted().map { result[$0]!.name }.joined(separator: ", "), field: "Combined folder moves", base: show(base), ours: show(ours), theirs: show(theirs)))
            let selected = resolutions[key] == .ours ? ours : theirs
            for id in affected where result[id] != nil {
                guard let node = selected.nodes[id] else { throw GalmuriError.invalid("combined moves require an unavailable parent identity") }
                result[id]?.parent = node.parent
            }
        }

        var membersByParent = [String: Set<String>]()
        for node in result.values { if let parent = node.parent { membersByParent[parent, default: []].insert(node.id) } }
        var groupByFolder = [String: Int]()
        for (index, group) in subtreeChoices.enumerated() {
            for id in group.selected.descendants(of: group.id) where groupByFolder[id] == nil { groupByFolder[id] = index }
        }
        for id in result.keys.sorted() where result[id]!.isFolder {
            let members = membersByParent[id] ?? []
            let b = (base.nodes[id]?.children ?? []).filter { members.contains($0) }
            let o = (ours.nodes[id]?.children ?? []).filter { members.contains($0) }
            let t = (theirs.nodes[id]?.children ?? []).filter { members.contains($0) }
            if let index = groupByFolder[id] {
                let group = subtreeChoices[index]
                result[id]?.children = (group.selected.nodes[id]?.children ?? []).filter { members.contains($0) }
            } else if o == b {
                result[id]?.children = complete(t, with: o, members: members)
            } else if t == b || o == t {
                result[id]?.children = complete(o, with: t, members: members)
            } else if let order = mergeOrder(base: b, ours: o, theirs: t, members: members) {
                result[id]?.children = order
            } else {
                let key = id + ".order"
                let oo = complete(o, with: t, members: members), tt = complete(t, with: o, members: members)
                func show(_ order: [String]) -> String { order.map { result[$0]?.name ?? $0 }.joined(separator: " → ") }
                conflicts.append(MergeConflict(id: key, item: result[id]!.name, field: "Sibling order", base: show(b), ours: show(oo), theirs: show(tt)))
                result[id]?.children = resolutions[key] == .ours ? oo : tt
            }
        }
        let tree = BookmarkTree(roots: base.roots, nodes: result)
        try tree.validate()
        return MergeResult(tree: tree, conflicts: conflicts, unresolved: conflicts.filter { resolutions[$0.id] == nil })
    }

    private static func complete(_ preferred: [String], with other: [String], members: Set<String>) -> [String] {
        var order = preferred.filter { members.contains($0) }, placed = Set(order)
        for (index, id) in other.enumerated() where members.contains(id) && !placed.contains(id) {
            if let next = other.dropFirst(index + 1).first(where: { placed.contains($0) }), let destination = order.firstIndex(of: next) { order.insert(id, at: destination) }
            else { order.append(id) }
            placed.insert(id)
        }
        order += members.subtracting(placed).sorted()
        return order
    }

    private static func mergeOrder(base: [String], ours: [String], theirs: [String], members: Set<String>) -> [String]? {
        let b = Dictionary(uniqueKeysWithValues: base.enumerated().map { ($1, $0) })
        let o = Dictionary(uniqueKeysWithValues: ours.enumerated().map { ($1, $0) })
        let t = Dictionary(uniqueKeysWithValues: theirs.enumerated().map { ($1, $0) })
        let ids = members.sorted()
        var edges = Dictionary(uniqueKeysWithValues: ids.map { ($0, Set<String>()) })
        for i in ids.indices {
            for j in ids.indices where j > i {
                let a = ids[i], c = ids[j]
                let bb = b[a].flatMap { ai in b[c].map { ai < $0 } }
                let oo = o[a].flatMap { ai in o[c].map { ai < $0 } }
                let tt = t[a].flatMap { ai in t[c].map { ai < $0 } }
                var directions = Set<Bool>()
                if let bb {
                    if let oo, oo != bb { directions.insert(oo) }
                    if let tt, tt != bb { directions.insert(tt) }
                    if directions.isEmpty { directions.insert(bb) }
                } else {
                    if let oo { directions.insert(oo) }
                    if let tt { directions.insert(tt) }
                }
                for forward in directions { edges[forward ? a : c]?.insert(forward ? c : a) }
            }
        }
        // Kahn's algorithm; the order is accepted only when exactly one item is ready at every step.
        var incoming = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        for targets in edges.values { for id in targets { incoming[id]! += 1 } }
        var result = [String](), ready = ids.filter { incoming[$0] == 0 }
        while result.count < ids.count {
            guard ready.count == 1, let next = ready.popLast() else { return nil }
            result.append(next)
            for id in edges[next]! { incoming[id]! -= 1; if incoming[id] == 0 { ready.append(id) } }
        }
        return result
    }
}
