import Foundation
import GalmuriCore

struct WorkingCopyReset: Identifiable {
    let id = UUID()
    let profile: ConnectedProfile
    let target: BookmarkTree
    let itemIDs: Set<String>?
    init(profile: ConnectedProfile, target: BookmarkTree? = nil, itemIDs: Set<String>? = nil) {
        self.profile = profile; self.target = target ?? profile.base.tree; self.itemIDs = itemIDs
    }
}
