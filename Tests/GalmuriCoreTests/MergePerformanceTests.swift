import XCTest
@testable import GalmuriCore

/// Equivalence and timing checks for `MergeEngine` against a frozen copy of the pre-optimization engine (2026-10-29).
/// Benchmark: `GALMURI_MERGE_BENCH=1 swift test --filter MergePerformanceTests`.
final class MergePerformanceTests: XCTestCase {
    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
    }

    private static func id(_ n: Int) -> String { "00000000-0000-4000-a000-" + String(format: "%012x", n) }

    /// Roots plus `folders` folders (nested to `depth` levels) and `items` bookmarks spread across them.
    private static func tree(folders: Int, items: Int, depth: Int, rng: inout Generator) -> BookmarkTree {
        var nodes = [String: Bookmark](), next = 100
        let roots = ["bookmark_bar": SampleData.bar, "other": SampleData.other, "synced": SampleData.mobile]
        for (i, root) in [SampleData.bar, SampleData.other, SampleData.mobile].enumerated() { nodes[root] = Bookmark(id: root, chromeID: String(i + 1), name: "Root \(i)") }
        var folderIDs = [SampleData.bar, SampleData.other]
        func add(_ node: Bookmark) { nodes[node.id] = node; nodes[node.parent!]!.children.append(node.id) }
        for f in 0..<folders {
            let parent = depth > 1 && f % depth != 0 ? folderIDs.last! : folderIDs[Int(rng.next() % UInt64(min(folderIDs.count, 2)))]
            let node = Bookmark(id: id(next), name: "Folder \(f)", parent: parent, metadata: ["date_added": .string("1")]); next += 1
            add(node); folderIDs.append(node.id)
        }
        for i in 0..<items {
            let parent = folderIDs[Int(rng.next() % UInt64(folderIDs.count))]
            add(Bookmark(id: id(next), name: "Item \(i)", url: "https://example.com/\(i)", parent: parent, metadata: ["date_added": .string("1")])); next += 1
        }
        return BookmarkTree(roots: roots, nodes: nodes)
    }

    /// Applies `count` random edits through the public tree API; invalid edits are skipped.
    private static func mutate(_ tree: BookmarkTree, count: Int, firstNewID: Int, rng: inout Generator) -> BookmarkTree {
        var tree = tree, newID = firstNewID
        for _ in 0..<count {
            let movable = tree.nodes.keys.filter { !tree.roots.values.contains($0) }.sorted()
            guard !movable.isEmpty else { break }
            let target = movable[Int(rng.next() % UInt64(movable.count))]
            let folders = tree.nodes.values.filter(\.isFolder).map(\.id).sorted()
            switch rng.next() % 7 {
            case 0: try? tree.edit(target, name: "Renamed \(rng.next() % 3)", url: tree.nodes[target]!.url.map { $0 + "?v" })
            case 1: try? tree.move([target], to: folders[Int(rng.next() % UInt64(folders.count))])
            case 2: try? tree.remove([target])
            case 3: try? tree.reorder(target, offset: Int(rng.next() % 5) - 2)
            case 4: tree.nodes[target]!.metadata["date_modified"] = .string(String(rng.next() % 3))
            case 5:
                let parent = folders[Int(rng.next() % UInt64(folders.count))]
                let node = Bookmark(id: id(newID), name: "New \(newID)", url: rng.next() % 2 == 0 ? nil : "https://example.com/new", parent: parent); newID += 1
                tree.nodes[node.id] = node; tree.nodes[parent]!.children.insert(node.id, at: Int(rng.next() % UInt64(tree.nodes[parent]!.children.count + 1)))
            default:
                if let parent = tree.nodes[target]?.parent { tree.nodes[parent]!.children.shuffle(using: &rng) }
            }
        }
        return tree
    }

    private static func outcome(_ run: () throws -> MergeResult) -> String {
        do {
            let r = try run()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let tree = String(decoding: try! encoder.encode(r.tree), as: UTF8.self)
            return tree + "\n" + r.conflicts.map { [$0.id, $0.item, $0.field, $0.base, $0.ours, $0.theirs].joined(separator: "|") }.joined(separator: "\n") + "\n" + r.unresolved.map(\.id).joined(separator: ",")
        } catch { return "error: \(error)" }
    }

    func testOptimizedMergeMatchesLegacyOnRandomEdits() {
        var rng = Generator(state: 20261029), conflicts = 0, orders = 0, cycles = 0, subtrees = 0, errors = 0
        for round in 0..<400 {
            let base = Self.tree(folders: 3 + round % 9, items: 6 + round % 25, depth: 1 + round % 4, rng: &rng)
            var ours = Self.mutate(base, count: 1 + round % 8, firstNewID: 10_000, rng: &rng)
            var theirs = Self.mutate(base, count: 1 + (round / 3) % 8, firstNewID: 20_000, rng: &rng)
            if round % 4 == 0 {
                // Crossed folder moves produce a combined-move cycle choice.
                let folders = base.nodes.values.filter { $0.isFolder && !base.roots.values.contains($0.id) }.map(\.id).sorted()
                if let a = folders.first, let b = folders.last(where: { !base.descendants(of: a).contains($0) && !base.descendants(of: $0).contains(a) }) {
                    try? ours.move([a], to: b); try? theirs.move([b], to: a)
                }
            }
            let pending = (try? MergeEngine.merge(base: base, ours: ours, theirs: theirs))?.conflicts ?? []
            var resolutions = [String: MergeSide]()
            for conflict in pending where rng.next() % 3 != 0 { resolutions[conflict.id] = rng.next() % 2 == 0 ? .ours : .theirs }
            for choice in [[:], resolutions] {
                let expected = Self.outcome { try LegacyMergeEngine.merge(base: base, ours: ours, theirs: theirs, resolutions: choice) }
                XCTAssertEqual(Self.outcome { try MergeEngine.merge(base: base, ours: ours, theirs: theirs, resolutions: choice) }, expected, "round \(round)")
            }
            conflicts += pending.count; orders += pending.filter { $0.field == "Sibling order" }.count
            cycles += pending.filter { $0.id == "structure.moves" }.count; subtrees += pending.filter { $0.id.hasSuffix(".subtree") }.count
            if (try? MergeEngine.merge(base: base, ours: ours, theirs: theirs)) == nil { errors += 1 }
        }
        // Guard against a fuzz that never reaches the interesting branches.
        XCTAssertGreaterThan(orders, 10); XCTAssertGreaterThan(conflicts, 100); XCTAssertGreaterThan(cycles, 5); XCTAssertGreaterThan(subtrees, 5)
        print("merge fuzz coverage: conflicts=\(conflicts) order=\(orders) cycles=\(cycles) subtrees=\(subtrees) errors=\(errors)")
    }

    func testMergeBenchmark() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GALMURI_MERGE_BENCH"] == "1", "set GALMURI_MERGE_BENCH=1 to run")
        func time(_ run: () throws -> MergeResult) rethrows -> Double {
            let start = ContinuousClock.now; _ = try run(); let d = ContinuousClock.now - start
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        func order(_ count: Int, rng: inout Generator) -> (BookmarkTree, BookmarkTree, BookmarkTree) {
            var base = Self.tree(folders: 0, items: count, depth: 1, rng: &rng)
            base.nodes[SampleData.bar]!.children += base.nodes[SampleData.other]!.children
            for id in base.nodes[SampleData.other]!.children { base.nodes[id]!.parent = SampleData.bar }
            base.nodes[SampleData.other]!.children = []
            var ours = base, theirs = base
            let c = base.nodes[SampleData.bar]!.children
            // Non-overlapping moves on each side so the 3-way order merge (not a conflict) is exercised.
            ours.nodes[SampleData.bar]!.children = Array(c[1..<(c.count / 2)]) + [c[0]] + Array(c[(c.count / 2)...])
            theirs.nodes[SampleData.bar]!.children = Array(c[..<(c.count / 2)]) + [c[c.count - 1]] + Array(c[(c.count / 2)..<(c.count - 1)])
            return (base, ours, theirs)
        }
        var rng = Generator(state: 7)
        var cases = [(String, BookmarkTree, BookmarkTree, BookmarkTree)]()
        let broad = Self.tree(folders: 300, items: 5_000, depth: 1, rng: &rng)
        cases.append(("broad 300 folders/5000 items, sparse edits", broad, Self.mutate(broad, count: 40, firstNewID: 100_000, rng: &rng), Self.mutate(broad, count: 40, firstNewID: 200_000, rng: &rng)))
        let deep = Self.tree(folders: 300, items: 300, depth: 300, rng: &rng)
        cases.append(("deep 300-level chain/300 items, sparse edits", deep, Self.mutate(deep, count: 20, firstNewID: 100_000, rng: &rng), Self.mutate(deep, count: 20, firstNewID: 200_000, rng: &rng)))
        for count in [50, 400] { let (b, o, t) = order(count, rng: &rng); cases.append(("order merge, \(count) siblings", b, o, t)) }
        var report = ["| case | legacy s | optimized s |", "|---|---:|---:|"]
        for (name, base, ours, theirs) in cases {
            XCTAssertEqual(Self.outcome { try MergeEngine.merge(base: base, ours: ours, theirs: theirs) }, Self.outcome { try LegacyMergeEngine.merge(base: base, ours: ours, theirs: theirs) }, name)
            let legacy = try (0..<3).map { _ in try time { try LegacyMergeEngine.merge(base: base, ours: ours, theirs: theirs) } }.min()!
            let optimized = try (0..<3).map { _ in try time { try MergeEngine.merge(base: base, ours: ours, theirs: theirs) } }.min()!
            report.append("| \(name) | \(String(format: "%.4f", legacy)) | \(String(format: "%.4f", optimized)) |")
        }
        print(report.joined(separator: "\n"))
    }
}

/// Frozen copy of `MergeEngine` before the 2026-10-29 performance changes. Do not edit; it is the equivalence oracle.
enum LegacyMergeEngine {
    static func merge(base: BookmarkTree, ours: BookmarkTree, theirs: BookmarkTree, resolutions: [String: MergeSide] = [:]) throws -> MergeResult {
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
        func depth(_ id: String) -> Int {
            var depth = 0, parent = base.nodes[id]?.parent
            while let id = parent { depth += 1; parent = base.nodes[id]?.parent }
            return depth
        }
        for id in base.nodes.keys.sorted(by: { depth($0) == depth($1) ? $0 < $1 : depth($0) < depth($1) }) where !covered.contains(id) && base.nodes[id]?.isFolder == true {
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

        func pick<T: Equatable>(_ b: T, _ o: T, _ t: T, key: String, item: String, field: String, show: (T) -> String) -> T {
            if o == b { return t }
            if t == b || o == t { return o }
            conflicts.append(MergeConflict(id: key, item: item, field: field, base: show(b), ours: show(o), theirs: show(t)))
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
            let item = base.path(to: id)
            n.name = pick(b!.name, o!.name, t!.name, key: id + ".name", item: item, field: "Name", show: { $0 })
            n.url = pick(b!.url, o!.url, t!.url, key: id + ".url", item: item, field: "URL", show: { $0 ?? "Folder" })
            n.parent = pick(b!.parent, o!.parent, t!.parent, key: id + ".parent", item: item, field: "Folder", show: { value in value.map { ours.path(to: $0) } ?? "Root" })
            let metadataKeys = Set(b!.metadata.keys).union(o!.metadata.keys).union(t!.metadata.keys)
            n.metadata = [:]
            for field in metadataKeys.sorted() {
                n.metadata[field] = pick(b!.metadata[field], o!.metadata[field], t!.metadata[field], key: id + ".metadata." + field, item: item, field: field, show: { $0?.display ?? "Not present" })
            }
            result[id] = n
        }
        for group in subtreeChoices {
            for id in group.all { result.removeValue(forKey: id) }
            for id in group.all { result[id] = group.selected.nodes[id] }
        }

        var cyclic = Set<String>()
        for id in result.keys.sorted() {
            var chain = [String](), current: String? = id
            while let next = current, let node = result[next] {
                if let start = chain.firstIndex(of: next) { cyclic.formUnion(chain[start...]); break }
                chain.append(next); current = node.parent
            }
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

        for id in result.keys.sorted() where result[id]!.isFolder {
            let members = Set(result.values.filter { $0.parent == id }.map(\.id))
            let b = (base.nodes[id]?.children ?? []).filter { members.contains($0) }
            let o = (ours.nodes[id]?.children ?? []).filter { members.contains($0) }
            let t = (theirs.nodes[id]?.children ?? []).filter { members.contains($0) }
            if let group = subtreeChoices.first(where: { $0.selected.descendants(of: $0.id).contains(id) }) {
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
        var order = preferred.filter { members.contains($0) }
        for (index, id) in other.enumerated() where members.contains(id) && !order.contains(id) {
            if let next = other.dropFirst(index + 1).first(where: { order.contains($0) }), let destination = order.firstIndex(of: next) { order.insert(id, at: destination) }
            else { order.append(id) }
        }
        order += members.subtracting(order).sorted()
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
        var result = [String](), remaining = members
        while !remaining.isEmpty {
            let ready = remaining.filter { id in !remaining.contains { edges[$0]!.contains(id) } }
            guard ready.count == 1, let next = ready.first else { return nil }
            result.append(next); remaining.remove(next)
        }
        return result
    }
}
