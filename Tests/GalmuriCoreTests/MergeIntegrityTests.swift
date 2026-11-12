import XCTest
@testable import GalmuriCore

final class MergeIntegrityTests: XCTestCase {
    private func item(_ tree: BookmarkTree, named name: String) -> String { tree.nodes.values.first { $0.name == name }!.id }

    func testSubtreeChoicePreservesDescendantsMovedOutsideFolder() throws {
        let base = try SampleData.file().tree
        let folder = item(base, named: "Design references"), child = item(base, named: "Typography notes")
        var ours = base, theirs = base
        try ours.remove([folder])
        try theirs.move([child], to: SampleData.other)
        try theirs.edit(child, name: "Moved and edited", url: theirs.nodes[child]!.url)
        let pending = try MergeEngine.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(pending.unresolved.map(\.field), ["Folder deletion and descendant changes"])
        XCTAssertTrue(pending.conflicts[0].theirs.contains("Moved and edited"))
        XCTAssertTrue(pending.conflicts[0].theirs.contains(child))
        XCTAssertEqual(pending.tree.nodes[child], theirs.nodes[child])
        XCTAssertTrue(pending.tree.nodes[SampleData.other]!.children.contains(child))
        let removed = try MergeEngine.merge(base: base, ours: ours, theirs: theirs, resolutions: [pending.conflicts[0].id: .ours])
        XCTAssertNil(removed.tree.nodes[child])
        try removed.tree.validate()
    }

    func testSubtreeDeletionDoesNotDeleteItemMovedInFromOutside() throws {
        let base = try SampleData.file().tree
        let folder = item(base, named: "Design references"), child = item(base, named: "Component handbook")
        var ours = base, theirs = base
        try ours.remove([folder]); try theirs.move([child], to: folder)
        let pending = try MergeEngine.merge(base: base, ours: ours, theirs: theirs)
        let removed = try MergeEngine.merge(base: base, ours: ours, theirs: theirs, resolutions: [pending.conflicts[0].id: .ours])
        XCTAssertEqual(removed.tree.nodes[child], base.nodes[child])
        XCTAssertNil(removed.tree.nodes[folder])
        try removed.tree.validate()
    }

    func testCompetingMovesKeepIndependentRenameAndRequireChoice() throws {
        let base = try SampleData.file().tree, child = item(base, named: "Typography notes"), destination = item(base, named: "Development")
        var ours = base, theirs = base
        try ours.move([child], to: SampleData.other)
        try ours.edit(child, name: "Independent rename", url: ours.nodes[child]!.url)
        try theirs.move([child], to: destination)
        let pending = try MergeEngine.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(pending.unresolved.map(\.field), ["Folder"])
        for side in [MergeSide.ours, .theirs] {
            let resolved = try MergeEngine.merge(base: base, ours: ours, theirs: theirs, resolutions: [pending.conflicts[0].id: side])
            XCTAssertEqual(resolved.tree.nodes[child]?.name, "Independent rename")
            XCTAssertEqual(resolved.tree.nodes[child]?.parent, (side == .ours ? ours : theirs).nodes[child]?.parent)
            XCTAssertTrue(resolved.unresolved.isEmpty)
            try resolved.tree.validate()
        }
        XCTAssertEqual(try MergeEngine.merge(base: base, ours: base, theirs: theirs).tree, theirs)
        XCTAssertEqual(try MergeEngine.merge(base: base, ours: ours, theirs: base).tree, ours)
    }

    func testCombinedMoveChoiceIncludesAncestorsWithoutOverlappingParentChoices() throws {
        var base = try SampleData.file().tree
        let a = item(base, named: "Design references"), b = item(base, named: "Development")
        let c = try base.add(name: "Third folder", url: nil, to: SampleData.bar)
        var ours = base, theirs = base
        try ours.move([a], to: c); try ours.move([b], to: a)
        try theirs.move([a, c], to: b)
        try ours.edit(a, name: "Keep independent name", url: nil)
        let pending = try MergeEngine.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(pending.conflicts.map(\.field), ["Combined folder moves"])
        for side in [MergeSide.ours, .theirs] {
            let resolved = try MergeEngine.merge(base: base, ours: ours, theirs: theirs, resolutions: [pending.conflicts[0].id: side])
            for id in [a, b, c] { XCTAssertEqual(resolved.tree.nodes[id]?.parent, (side == .ours ? ours : theirs).nodes[id]?.parent) }
            XCTAssertEqual(resolved.tree.nodes[a]?.name, "Keep independent name")
            XCTAssertTrue(resolved.unresolved.isEmpty)
            try resolved.tree.validate()
        }
    }

    func testIncompatibleRelativeOrdersAreExplicitAndDeterministic() throws {
        let base = try SampleData.file().tree, folder = item(base, named: "Design references")
        let children = base.nodes[folder]!.children
        var ours = base, theirs = base
        try ours.reorder(children[0], offset: 1); try theirs.reorder(children[1], offset: 1)
        let pending = try MergeEngine.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(pending.unresolved.map(\.field), ["Sibling order"])
        for side in [MergeSide.ours, .theirs] {
            let choices = [pending.conflicts[0].id: side]
            let resolved = try MergeEngine.merge(base: base, ours: ours, theirs: theirs, resolutions: choices)
            XCTAssertEqual(resolved.tree.nodes[folder]?.children, (side == .ours ? ours : theirs).nodes[folder]?.children)
            XCTAssertTrue(resolved.unresolved.isEmpty)
            XCTAssertEqual(try MergeEngine.merge(base: base, ours: ours, theirs: theirs, resolutions: choices).tree, resolved.tree)
        }
        XCTAssertEqual(ours.nodes[folder]?.children, [children[1], children[0]] + Array(children.dropFirst(2)))
        XCTAssertEqual(theirs.nodes[folder]?.children, [children[0], children[2], children[1]] + Array(children.dropFirst(3)))
    }

    func testIndependentDuplicateURLItemsAndUnknownMetadataMergeSeparately() throws {
        let base = try SampleData.file().tree
        let a = item(base, named: "Interface archive"), b = item(base, named: "Interface archive — reading copy")
        var ours = base, theirs = base
        try ours.remove([a])
        try theirs.edit(b, name: "Keep this duplicate", url: theirs.nodes[b]!.url)
        ours.nodes[b]?.metadata["ours_unknown"] = .object(["exact": .integer(Int64.max)])
        theirs.nodes[b]?.metadata["theirs_unknown"] = .string("keep")
        let merged = try MergeEngine.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertTrue(merged.conflicts.isEmpty)
        XCTAssertNil(merged.tree.nodes[a])
        XCTAssertEqual(merged.tree.nodes[b]?.name, "Keep this duplicate")
        XCTAssertEqual(merged.tree.nodes[b]?.metadata["ours_unknown"], ours.nodes[b]?.metadata["ours_unknown"])
        XCTAssertEqual(merged.tree.nodes[b]?.metadata["theirs_unknown"], .string("keep"))
        ours.nodes[b]?.metadata["theirs_unknown"] = .string("different")
        let pending = try MergeEngine.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(pending.unresolved.map(\.field), ["theirs_unknown"])
    }

    func testIdentityReassignmentAndTypeChangesAreRejected() throws {
        let base = try SampleData.file().tree, id = item(base, named: "Typography notes")
        var changed = base
        changed.nodes[id]?.chromeID = "9223372036854775807"
        XCTAssertThrowsError(try MergeEngine.merge(base: base, ours: base, theirs: changed))
        XCTAssertThrowsError(try MergeEngine.merge(base: base, ours: changed, theirs: base))
        changed = base; changed.nodes[id]?.url = nil
        XCTAssertThrowsError(try MergeEngine.merge(base: base, ours: base, theirs: changed))
        changed = base
        var node = changed.nodes.removeValue(forKey: id)!
        node.id = UUID().uuidString.lowercased()
        changed.nodes[node.id] = node
        let children = changed.nodes[node.parent!]!.children.map { $0 == id ? node.id : $0 }
        changed.nodes[node.parent!]?.children = children
        XCTAssertThrowsError(try MergeEngine.merge(base: base, ours: base, theirs: changed))
    }

    func testBatchMoveKeepsTreeOrderAndInvalidMoveLeavesInputUntouched() throws {
        var tree = try SampleData.file().tree
        let source = try tree.add(name: "Source", url: nil, to: SampleData.bar)
        let a = try tree.add(name: "A", url: nil, to: source), b = try tree.add(name: "B", url: nil, to: source)
        let expected = [a, b].sorted(by: >)
        tree.nodes[source]?.children = expected
        try tree.move([a, b], to: SampleData.other)
        XCTAssertEqual(Array(tree.nodes[SampleData.other]!.children.suffix(2)), expected)
        let before = tree
        XCTAssertThrowsError(try tree.move([a, "missing"], to: source))
        XCTAssertEqual(tree, before)
    }

    func testDescendantTraversalContinuesAfterRepeatedEdges() throws {
        var tree = try SampleData.file().tree
        let folder = item(tree, named: "Design references"), children = tree.nodes[folder]!.children
        tree.nodes[folder]?.children = [children[0], children[1], children[1]]
        XCTAssertEqual(tree.descendants(of: folder), Set([folder, children[0], children[1]]))
        tree.nodes[children[1]]?.children = [folder]
        XCTAssertEqual(tree.descendants(of: folder), Set([folder, children[0], children[1]]))
    }
}
