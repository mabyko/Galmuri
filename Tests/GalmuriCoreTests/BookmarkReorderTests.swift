import XCTest
@testable import GalmuriCore

final class BookmarkReorderTests: XCTestCase {
    func testReorderMovesAmongSameKindPeersOnly() throws {
        var tree = try SampleData.file().tree
        let parent = try tree.add(name: "Synthetic", url: nil, to: tree.orderedRoots[0])
        let a = try tree.add(name: "A", url: "https://example.test/a", to: parent)
        let f = try tree.add(name: "F", url: nil, to: parent)
        let b = try tree.add(name: "B", url: "https://example.test/b", to: parent)
        let moved = try tree.reorderAmongPeers(b, direction: -1)
        XCTAssertTrue(moved); XCTAssertEqual(tree.nodes[parent]?.children, [b, f, a])
        let folderMoved = try tree.reorderAmongPeers(f, direction: -1), firstMoved = try tree.reorderAmongPeers(b, direction: -1)
        XCTAssertFalse(folderMoved); XCTAssertFalse(firstMoved)
        XCTAssertEqual(tree.nodes[parent]?.children, [b, f, a])
        XCTAssertThrowsError(try tree.reorderAmongPeers(b, direction: 2))
    }
}
