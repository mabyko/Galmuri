import Foundation
import GalmuriCore

struct BookmarkDeletion: Identifiable {
    let id = UUID()
    let profileID: UUID
    let working: BookmarkTree
    let itemIDs: Set<String>

    var removedIDs: Set<String> {
        itemIDs.reduce(into: Set<String>()) { $0.formUnion(working.descendants(of: $1)) }
    }

    var requiresConfirmation: Bool {
        itemIDs.count > 1 || itemIDs.contains { working.nodes[$0]?.isFolder == true }
    }

    var items: [Bookmark] {
        itemIDs.compactMap { working.nodes[$0] }.sorted { $0.id < $1.id }
    }
}
