import XCTest
import GalmuriCore
@testable import GalmuriApp

final class APIEditorListingTests: XCTestCase {
    func testListingPreservesStoredOrderAndSeparatesFoldersFromLinks() throws {
        let tree = try SampleData.file().tree
        let root = tree.orderedRoots[0]
        let actual = APIEditorListing.rows(tree: tree, folder: root, query: "")
        let children = tree.nodes[root]!.children.compactMap { tree.nodes[$0] }
        XCTAssertEqual(actual.map(\.id), (children.filter(\.isFolder) + children.filter { !$0.isFolder }).map(\.id))
        for node in actual { XCTAssertEqual(node.parent, root) }
    }
    func testSearchIncludesDescendantsAndDestinationsExcludeWholeSelectionSubtrees() throws {
        var tree = try SampleData.file().tree
        let root = tree.orderedRoots[0]
        let folder = try tree.add(name: "Synthetic folder", url: nil, to: root)
        let nested = try tree.add(name: "Nested", url: nil, to: folder)
        let bookmark = try tree.add(name: "갈무리 unique needle", url: "https://example.test/search", to: nested)
        XCTAssertEqual(APIEditorListing.rows(tree: tree, folder: root, query: "unique needle").map(\.id), [bookmark])
        let destinations = Set(APIEditorListing.destinations(tree: tree, itemIDs: [folder]).map(\.node.id))
        XCTAssertTrue(destinations.contains(root)); XCTAssertFalse(destinations.contains(folder)); XCTAssertFalse(destinations.contains(nested))
    }
}
