import XCTest
@testable import GalmuriCore

final class BookmarkDragTests: XCTestCase {
    private func item(_ tree: BookmarkTree, named name: String) -> String {
        tree.nodes.values.first { $0.name == name }!.id
    }

    func testMultiSelectionKeepsTreeOrderAndDistinctSameURLIdentities() throws {
        let tree = try SampleData.file().tree
        let ids = Set(tree.nodes.values.filter { $0.url == "https://example.com/interface" }.map(\.id))
        XCTAssertEqual(ids.count, 2)
        let profileID = UUID(), drag = try BookmarkDrag(profileID: profileID, itemIDs: ids, tree: tree)
        let result = try drag.movedTree(payloads: [drag.data, drag.data], profileID: profileID, tree: tree, to: SampleData.other)
        var expected = tree
        try expected.move(ids, to: SampleData.other)
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.nodes.count, tree.nodes.count)
        for id in ids {
            XCTAssertEqual(result.nodes[id]?.parent, SampleData.other)
            XCTAssertEqual(result.nodes[id]?.url, tree.nodes[id]?.url)
            XCTAssertEqual(result.nodes[id]?.chromeID, tree.nodes[id]?.chromeID)
        }
        XCTAssertFalse(String(decoding: drag.data, as: UTF8.self).contains("https://"))
    }

    func testFolderAndSelectedDescendantMoveTogetherOnlyOnce() throws {
        let tree = try SampleData.file().tree
        let folder = item(tree, named: "Design references"), child = item(tree, named: "Typography notes")
        let profileID = UUID(), drag = try BookmarkDrag(profileID: profileID, itemIDs: [folder, child], tree: tree)
        let result = try drag.movedTree(payloads: [drag.data], profileID: profileID, tree: tree, to: SampleData.other)
        XCTAssertEqual(result.nodes[folder]?.parent, SampleData.other)
        XCTAssertEqual(result.nodes[child]?.parent, folder)
        XCTAssertEqual(result.nodes[folder]?.children, tree.nodes[folder]?.children)
        XCTAssertEqual(result.nodes[SampleData.other]?.children.filter { $0 == folder }.count, 1)
        try result.validate()
    }

    func testMoveAppendsInSourceOrderAndSameParentDoesNotReorder() throws {
        var tree = try SampleData.file().tree
        let a = try tree.add(name: "First", url: "https://example.com/a", to: SampleData.bar)
        let b = try tree.add(name: "Second", url: "https://example.com/b", to: SampleData.bar)
        let profileID = UUID(), drag = try BookmarkDrag(profileID: profileID, itemIDs: [b, a], tree: tree)
        let result = try drag.movedTree(payloads: [drag.data], profileID: profileID, tree: tree, to: SampleData.other)
        XCTAssertEqual(result.nodes[SampleData.other]?.children, tree.nodes[SampleData.other]!.children + [a, b])
        XCTAssertEqual(try drag.movedTree(payloads: [drag.data], profileID: profileID, tree: tree, to: SampleData.bar), tree)
    }

    func testRejectsForeignMalformedEmptyAndMixedPayloadsAtomically() throws {
        let tree = try SampleData.file().tree, profileID = UUID()
        let ids: Set<String> = [item(tree, named: "Typography notes")]
        let drag = try BookmarkDrag(profileID: profileID, itemIDs: ids, tree: tree)
        let otherDrag = try BookmarkDrag(profileID: profileID, itemIDs: ids, tree: tree)
        for payloads in [[], [Data()], [Data("https://example.com/".utf8)], [Data("{\"version\":999}".utf8)], [otherDrag.data], [drag.data, Data("invalid".utf8)]] {
            var working = tree
            XCTAssertThrowsError(working = try drag.movedTree(payloads: payloads, profileID: profileID, tree: working, to: SampleData.other))
            XCTAssertEqual(working, tree)
        }
        var working = tree
        XCTAssertThrowsError(working = try drag.movedTree(payloads: [drag.data], profileID: UUID(), tree: working, to: SampleData.other))
        XCTAssertEqual(working, tree)
    }

    func testRejectsStaleTreeAfterEditRemovalOrOrderChange() throws {
        let tree = try SampleData.file().tree, profileID = UUID(), id = item(tree, named: "Typography notes")
        let drag = try BookmarkDrag(profileID: profileID, itemIDs: [id], tree: tree)
        var edited = tree, removed = tree, reordered = tree
        try edited.edit(id, name: "Changed while dragging", url: tree.nodes[id]?.url)
        try removed.remove([id])
        try reordered.reorder(id, offset: 1)
        XCTAssertNotEqual(reordered, tree)
        for changed in [edited, removed, reordered] {
            var working = changed
            XCTAssertFalse(drag.isCurrent(profileID: profileID, tree: working))
            XCTAssertThrowsError(working = try drag.movedTree(payloads: [drag.data], profileID: profileID, tree: working, to: SampleData.other))
            XCTAssertEqual(working, changed)
        }
    }

    func testRejectsProtectedRootsMissingItemsAndURLIdentifiersAtDragStart() throws {
        let tree = try SampleData.file().tree
        for ids: Set<String> in [[], [SampleData.bar], [UUID().uuidString.lowercased()], ["https://example.com/interface"]] {
            XCTAssertThrowsError(try BookmarkDrag(profileID: UUID(), itemIDs: ids, tree: tree))
        }
    }

    func testRejectsCycleBookmarkAndMissingDestinationsWithoutPartialMove() throws {
        let tree = try SampleData.file().tree, profileID = UUID()
        let folder = item(tree, named: "Design references"), child = item(tree, named: "Typography notes")
        let other = item(tree, named: "Development")
        let drag = try BookmarkDrag(profileID: profileID, itemIDs: [folder, other], tree: tree)
        for destination in [folder, child, UUID().uuidString.lowercased()] {
            var working = tree
            XCTAssertThrowsError(working = try drag.movedTree(payloads: [drag.data], profileID: profileID, tree: working, to: destination))
            XCTAssertEqual(working, tree)
        }
    }
}
