import XCTest
@testable import GalmuriCore

final class BookmarkRevertTests: XCTestCase {
    func testIndependentEditAndDuplicateIdentityStayWhenRevertingOneItem() throws {
        let base = try SampleData.file().tree
        let items = base.nodes.values.filter { $0.url != nil }.sorted { $0.id < $1.id }
        var working = base
        try working.edit(items[0].id, name: "First changed", url: items[0].url)
        try working.edit(items[1].id, name: "Keep second", url: items[1].url)
        let result = try BookmarkRevert.selected([items[0].id], base: base, working: working)
        XCTAssertEqual(result.nodes[items[0].id], base.nodes[items[0].id])
        XCTAssertEqual(result.nodes[items[1].id], working.nodes[items[1].id])
        XCTAssertEqual(Set(result.nodes.keys), Set(base.nodes.keys))
    }

    func testMovedItemRestoresParentAndSiblingOrderWithoutChangingOthers() throws {
        let base = try SampleData.file().tree
        let folder = try XCTUnwrap(base.nodes.values.first { $0.children.count >= 3 && $0.parent != nil })
        let id = folder.children[1]
        var working = base
        try working.move([id], to: SampleData.other)
        let added = try working.add(name: "Keep new", url: "https://example.com/keep", to: folder.id)
        let result = try BookmarkRevert.selected([id], base: base, working: working)
        XCTAssertEqual(result.nodes[folder.id]?.children, folder.children + [added])
        XCTAssertEqual(result.nodes[id], base.nodes[id])
        XCTAssertEqual(result.nodes[added], working.nodes[added])
    }

    func testRestoreOneDeletedChildCreatesParentsButNotDeletedSiblings() throws {
        let base = try SampleData.file().tree
        let folder = try XCTUnwrap(base.nodes.values.first { $0.children.count >= 3 && $0.parent != nil })
        let id = folder.children[1]
        var working = base
        try working.remove([folder.id])
        let result = try BookmarkRevert.selected([id], base: base, working: working)
        XCTAssertEqual(result.nodes[id], base.nodes[id])
        XCTAssertEqual(result.nodes[folder.id]?.children, [id])
        XCTAssertNil(result.nodes[folder.children[0]])
        XCTAssertTrue(result.nodes[SampleData.bar]!.children.contains(folder.id))
    }

    func testFolderRevertIncludesMovedOutAndInDescendants() throws {
        let base = try SampleData.file().tree
        let folder = try XCTUnwrap(base.nodes.values.first { $0.children.count >= 3 && $0.parent != nil })
        let outside = try XCTUnwrap(base.nodes[SampleData.other]?.children.first)
        var working = base
        try working.move([folder.children[0]], to: SampleData.other)
        try working.move([outside], to: folder.id)
        _ = try working.add(name: "New in folder", url: "https://example.com/new", to: folder.id)
        let result = try BookmarkRevert.selected([folder.id], base: base, working: working)
        XCTAssertEqual(result, base)
    }

    func testRevertingNewFolderPreservesExistingItemsMovedInside() throws {
        let base = try SampleData.file().tree
        let existing = try XCTUnwrap(base.nodes[SampleData.other]?.children.first)
        var working = base
        let added = try working.add(name: "New parent", url: nil, to: SampleData.bar)
        try working.move([existing], to: added)
        _ = try working.add(name: "New child", url: "https://example.com/child", to: added)
        XCTAssertEqual(try BookmarkRevert.selected([added], base: base, working: working), base)
    }

    func testDeletedFolderRestoresExactOriginalSubtreeAndUnrelatedEditsRemain() throws {
        let base = try SampleData.file().tree
        let folder = try XCTUnwrap(base.nodes.values.first { $0.children.count >= 3 && $0.parent != nil })
        let unrelated = try XCTUnwrap(base.nodes[SampleData.other]?.children.first)
        var working = base
        try working.remove([folder.id]); try working.edit(unrelated, name: "Keep unrelated", url: working.nodes[unrelated]?.url)
        let result = try BookmarkRevert.selected([folder.id], base: base, working: working)
        for id in base.descendants(of: folder.id) { XCTAssertEqual(result.nodes[id], base.nodes[id]) }
        XCTAssertEqual(result.nodes[unrelated], working.nodes[unrelated])
    }

    func testEmptyUnknownAndUnchangedSelectionRejectWithoutMutation() throws {
        let base = try SampleData.file().tree
        for ids: Set<String> in [[], [UUID().uuidString.lowercased()], [SampleData.bar]] {
            XCTAssertThrowsError(try BookmarkRevert.selected(ids, base: base, working: base))
        }
    }
}
