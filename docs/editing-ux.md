# Bookmark editing UX

2026-10-25 · Native editing improvements for task 5.13. These actions change Galmuri working copies; they do not enable real-profile writes or encrypted-bookmark support.

## Product boundary

The Release 8 checkpoint created a synthetic profile automatically. Task 1.7 subsequently replaced normal startup with [guided Chrome connection](profile-connection.md), separating sample data into explicit development/demo/QA entry points. Existing profiles, working copies and backups must be preserved. No automatic data deletion or migration is part of this UX change.

## Problems and changes

| Previous behavior | Current behavior |
| --- | --- |
| Edit/remove controls appeared only after selecting a row | Edit, Move and Delete remain visible, with selection-dependent enabled states and a short selection hint |
| “Exclude from working copy” required understanding an internal distinction | Use Delete; explain that changes stay in Galmuri until a supported review/apply |
| Editing was hidden behind selection or a name-cell context menu | Each row has a labeled pencil button; Return, double-click and native table context actions remain available |
| Context actions were attached only to the name cell | Use SwiftUI’s selection-aware table menu and the IDs provided by that menu; empty-area menus do not reuse an unrelated selection |
| Every removal opened the same generic confirmation | Single-bookmark deletion is immediate and undoable; folder/multi-item deletion lists the selected names/paths and unique total including descendants |
| Undo was a small footer action and left an outdated status message | Undo is visible next to selection controls; deletion and undo produce explicit status text |
| Confirmation used the current selection at the moment of deletion | Capture target IDs, profile and working tree; reject stale working copies or profile switches instead of retargeting |
| A large decorative header reduced table space | Use a compact title/count header while retaining the existing sidebar/table design |

After the user deliberately requests folder/batch deletion, Return confirms the captured preview and Escape cancels it. Return on a selected bookmark opens Edit; Return on a folder opens its contents (Release22); the editor keeps native name focus, Save/Return and Cancel/Escape. The standard `⌘E` Find command is not repurposed. Its save is bound to the profile and tree loaded when it opened. Existing persistence validation, rollback and per-profile undo are reused; URL identity is never used for deletion.

## References and interpretation

- [Apple HIG: Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) recommends avoiding alerts for common actions people can undo. Galmuri applies this to a single bookmark; retaining a folder/batch preview is our product choice because hidden descendants increase the impact.
- [Apple HIG: Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo) informs the visible undo control and explicit feedback after reversal. Action-specific multi-level undo labels and redo are not added in this bounded pass.
- [Apple HIG: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) informs discoverable actions using familiar labels and symbols. The existing content action row is retained rather than replacing the app’s navigation architecture.
- [SwiftUI selection-aware context menu](https://developer.apple.com/documentation/swiftui/view/contextmenu%28forselectiontype%3Amenu%3Aprimaryaction%3A%29) supplies the action target IDs and native double-click behavior. Current API documentation was fetched through Context7.

Reference review by Claude-dev-max is recorded with its final findings in the ignored local QA evidence; this page records the chosen product behavior rather than treating every reference as a mandatory requirement.

## Verification boundary

Five focused app-state regressions cover same-URL identity deletion, persisted deletion/undo, unique descendant impact, invalid/protected targets, changed selection, stale work/profile rejection, persistence failure rollback, and selection pruning after folder/search/duplicate/change-filter edits. The complete suite has 112 passing tests (85 core + 27 app-state). Four-language resources have 205 entries and 117 literal native keys.

The synthetic Debug harness opens the actual editor with Return, captures it, verifies Delete edits the focused name field without deleting a bookmark, and cancels with Escape without changing the working copy. It also verifies `⌘Z` restores a deleted bookmark and does not undo bookmark edits while search is focused. Editor/selection/Settings/review renders are captured in four locales. The deletion preview is hosted as a native attached sheet; Return invokes its actual confirmation action, and undo restores the full folder. This does not exercise the physical toolbar click that presents the SwiftUI sheet or context-menu gestures. Installed Release smoke includes persistent deletion, undo and original preservation. VoiceOver, physical search text undo, table Delete focus and context-click selection gestures, native-speaker review, large-content stress and full user acceptance remain pending. Browser profile access, real writes/sync and Keychain are outside this change.

## Claude-dev-max review resolution

The review compared the baseline and the in-progress implementation with Safari/Finder behavior and Apple HIG. Its five findings were addressed as follows:

1. Give the deletion list an explicit bounded height, wrap explanatory text, present the QA preview as an attached sheet and provide Return confirmation after deliberate selection. The earlier collapsed captures are superseded by the final captures.
2. Intersect selection with currently visible rows after every edit, including folder moves, search, Same URL and Pending changes; add a regression covering all four.
3. Disable the app Undo shortcut while search or a modal editor/review is active; select changed/restored visible rows after undo. Native in-process search/Undo checks preserve the bookmark tree. Query-text undo was inconsistent under synthetic routing and remains a physical-input acceptance item; no pass is claimed for that text behavior.
4. Use pending-state copy for the pending-removal list and update Korean copy and the glossary to “Delete (working copy)”.
5. Use Return for table editing, remove the duplicate File → New Window command while retaining `⌘N` for a new bookmark, and bind Move to its opening profile/tree/IDs.

The retained folder/batch preview is an explicit product choice; the optional suggestion to skip every undoable batch confirmation was not adopted. Named Edit-menu undo/redo, sidebar folder context actions, and revealing/scanning restored items outside the current filter are later work.

Additional primary references: [Safari bookmark management](https://support.apple.com/guide/safari/bookmark-webpages-to-revisit-ibrw1039/mac), [Safari keyboard shortcuts](https://support.apple.com/guide/safari/keyboard-and-other-shortcuts-cpsh003/mac), [Safari deletion](https://support.apple.com/guide/safari/delete-a-bookmark-in-safari-on-mac-ibrw708a7101/mac), [Finder deletion](https://support.apple.com/guide/mac-help/delete-files-and-folders-on-mac-mchlp1093/mac), [Apple HIG Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards). These references inform the design; they are not proof of Galmuri runtime behavior.


## Folder navigation and type separation · 2026-10-27

Task 2.6 responds to the maintainer's report that opening a folder offered no return route and mixed folders/links obscured browsing. The detail top bar now provides Back (`⌘[`), Forward (`⌘]`) and Enclosing Folder (`⌘↑`); unavailable actions are disabled and retain labels/help for accessibility. Back/Forward follow visited destinations and restore the prior query. Up follows the current parent, including the current tree after moves; protected roots lead to All Bookmarks. Clickable ancestors and All Bookmarks form a horizontally scrollable path above the folder title. Current folder names remain user content.

A folder with no query shows only immediate children. Searching includes descendants; All Bookmarks remains a recursive profile view and Same URL/Pending Changes retain their filters. The displayed bookmark count reflects visible links. Folders appear first with a filled folder icon, heavier names and explicit Folder/Bookmark type labels. Both groups retain their original traversal order. Browsing/grouping never rewrites the stored child arrays, Base or original file. Explicit Move Up/Down swaps the previous/next same-type sibling in stored order; no applicable peer means no edit or undo entry. Reorder is per parent even in a recursive view.

Every destination change clears selection; the view also invalidates drag authorization. History is transient, resets on profile switch/workspace import, and ignores deleted folder destinations. Deleting or undoing creation of the current folder returns to All Bookmarks. Bookmark double-click/Return still edits, and the pencil/context Edit remains available for folder renaming. Back/Forward does not undo edits, and navigation is not persisted across relaunch. No new framework dependency, browser/permission action or external-write capability is added.

Verification and remaining limits are recorded in [validation](validation.md#folder-navigation-and-type-separation--2026-10-27). Physical mouse/trackpad use, long-path scrolling, full VoiceOver and native-speaker acceptance remain separate from synthetic native key routing.


## Cancel saved pending changes · 2026-10-27

Task 2.7 responds to the maintainer's Release22 acceptance: Back/Up work on the tested route, folders and links are distinguishable, working edits persist after relaunch and session undo works before quit. The maintainer also found that pending changes survived relaunch while their undo history did not. Session-only undo is intentional; omitting a way to cancel the saved work was a product gap. This report is bounded maintainer evidence, not complete physical/VoiceOver or browser acceptance.

Pending Changes now exposes **Discard All Changes…**, even when filters hide every result or no rows are selected. The scope is the current profile's entire working copy, never the selected rows, all profiles, or Chrome itself. The confirmation names the profile and reuses the full before/after review from current working tree to persisted Base: additions are removed, deletions restored, and edits/moves/order returned to the stored source snapshot. This is the source state already held by Galmuri, not a fresh read or the newest Chrome model. Show the complete scope and impact before the explicit destructive confirmation; Cancel/Escape leaves work untouched, and Return confirms the opened review.

The captured request is bound to profile ID, source URL, Base and working tree. Changed state, busy I/O or an active apply review rejects the request. Reuse validated local edit/persist rollback and session undo. A successful reset persists the restored tree, clears pending differences and selection, preserves Base, connection metadata, restrictions and other profiles, and can itself be undone until quitting. It also works after relaunch or when the original is changed/unavailable, without reading/writing it. The reset does not generate a browser backup or update browser state. No automatic discard, persistent undo stack, schema migration, per-item revert or external-write capability is added.

The existing Undo control explains its lifetime in help text. Undo history is transient; persisted pending differences remain until supported apply, manual edits that restore equality, or explicit full-profile discard. [Verification](validation.md#cancel-saved-pending-changes--2026-10-27).


## Pre-use profile and source workflows · 2026-10-27

Profile Management lists saved real/sample entries and pending-change counts. Removing an entry requires a named confirmation. First save the complete current workspace to a private local `Disconnected-<UUID>.json` using Workspace's existing validation/permissions. Only then remove the entry and persist; failure restores the in-memory workspace/undo state. Browser originals, test originals, original-backup history and other profiles are never deleted. Removing the selected entry chooses another real connection or Welcome; removing another entry preserves current navigation/selection. Importing the archived JSON restores the prior whole workspace, not just one profile. The manager is reachable from the sidebar and from Welcome when saved entries remain. This does not automatically remove existing samples or user data during installation.

Refresh is a user-triggered plaintext disk read and three-way merge, not a live browser API, sync assertion or implicit source write. Preserve Base/Ours until explicit conflict choices and final local review. The first stable read and merge run off the main actor under the existing scoped grant. Before acceptance, reread and recheck the source identity/raw bytes, current profile/Base/working state, request identity/acknowledgement and restriction classification. Closed/stale reviews do not commit. Save the previous workspace to private `BeforeRefresh-<UUID>.json`, update Base to the reviewed file and working to the merge result, then persist with rollback. Clear old session undo because the baseline changed; explain this and show the recovery JSON path. Companion payloads remain excluded and their write restrictions retained. Chrome may have newer in-memory contents; no claim of complete/latest browser state follows from a disk snapshot. Source writes stay gated.

Pending Changes offers Revert Selected Changes… and individual restore actions beside pending deletions. The same captured confirmation and local edit/undo guards review the complete working-to-target difference. Reverting a folder includes original/current descendants, including items moved in/out; reverting a deleted child restores required ancestor folders but not unrelated deleted siblings. Preserve unrelated edits and sibling relative ordering, and validate the complete result before applying it locally. No URL-based matching or guessed tree repair. Full-profile discard remains available.

Open in Browser is explicit, single-item and available in the action row/context menu for valid HTTP/HTTPS URLs. It dispatches to the OS default browser, not a selected Chrome/Ego profile; unsupported schemes/folders/failed dispatch report an error. Agent checks inject an opener and do not browse private links.
