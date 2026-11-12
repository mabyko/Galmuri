import Foundation

/// A process-local move authorization. Only an opaque token leaves the working copy.
public struct BookmarkDrag: Sendable {
    public let data: Data
    public let itemIDs: Set<String>
    private let profileID: UUID
    private let snapshot: BookmarkTree

    public init(profileID: UUID, itemIDs: Set<String>, tree: BookmarkTree) throws {
        try tree.validate()
        guard !itemIDs.isEmpty,
              itemIDs.allSatisfy({ tree.nodes[$0] != nil && !tree.roots.values.contains($0) }) else {
            throw GalmuriError.invalid("protected root or missing item")
        }
        self.profileID = profileID
        self.itemIDs = itemIDs
        snapshot = tree
        data = Data(UUID().uuidString.utf8)
    }

    public func isCurrent(profileID: UUID, tree: BookmarkTree) -> Bool {
        self.profileID == profileID && snapshot == tree
    }

    public func movedTree(payloads: [Data], profileID: UUID, tree: BookmarkTree, to destination: String) throws -> BookmarkTree {
        guard isCurrent(profileID: profileID, tree: tree), !payloads.isEmpty,
              payloads.allSatisfy({ $0 == data }) else {
            throw GalmuriError.invalid("stale or foreign bookmark drag")
        }
        var result = tree
        try result.move(itemIDs, to: destination)
        return result
    }
}
