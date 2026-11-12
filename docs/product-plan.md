# Product plan

Draft v0.2 · 2026-10-23. Accepted product requirements and proposed implementation choices are distinguished below. An experimental native app now implements persistent editing, fixture-driven merge, and synthetic-only apply/recovery. No native public release or real Chrome write support is claimed; see [validation](validation.md).

## Purpose

Galmuri is a native Mac app for organizing bookmarks across Chrome profiles and applying reviewed edits back to each original profile. Users should not need to install extensions per profile or repeatedly export and reimport files to maintain their collection.

The name **Galmuri · 갈무리** evokes gathering and putting things in order. The English tagline is “Bring your bookmarks together. Refine them. Apply them back to your browser.” Trademark and product-name availability have not been researched.

## Requirements and assumptions

| Status | Decision |
| --- | --- |
| Accepted | Standalone macOS app with a SwiftUI native interface; Chrome first; existing file workflow needs no per-profile extension; optional API bridge accepted separately with dedicated-test write gates |
| Accepted | Persistent profile management and direct apply, not an export-only substitute |
| Accepted | Preserve Base and Ours; read Theirs at apply time; perform a three-way merge |
| Accepted | Chrome remains usable during editing; verified browser exit before apply; explicit conflict review, original backup, and recovery |
| Accepted | Calm dark sidebar/list design, with editing and apply review separated |
| Accepted | Encrypted-bookmark support is deferred; Settings → Labs shows only a disabled “Planned” item, with no activation preference or Keychain access |
| Accepted | MIT open-source licensing; English source language; Korean, Japanese, and Chinese localization |
| Working scope | Simplified Chinese (`zh-Hans`) for the first Chinese localization; Traditional Chinese later if requested |
| Proposed | One profile per apply operation; independent working copies for other profiles |
| Proposed | Start with validated plaintext local storage; distinguish readable from write-verified support |
| Local development | macOS 14 build target, Swift 6, ad-hoc `forked.galmuri.local` identity; [ADR 0003](adr/0003-local-development-boundary.md) |
| Accepted local preview | Browser selection and explicit default-location lookup; experimental read-only Ego Lite plaintext connection, without a validated Ego support claim |
| Open | Validated macOS/Chrome/Ego support matrix, public signing/distribution, App Sandbox, account/managed stores, direct Ego apply |

Unsupported formats must explain why apply is unavailable. Read-only access or HTML export alone does not complete the MVP. If safe direct apply cannot be validated, revisit the product scope explicitly.

**2026-10-28 interim handoff:** following the maintainer’s fallback request, use existing HTML export plus manual Chrome import while direct apply remains blocked. Import adds items; it does not replay edits/deletions against existing Chrome identities. No automatic reset/replacement is provided, and a partial plaintext working copy must not replace the complete Chrome collection. The original direct-apply goal remains open. See the [research and manual-use guide](research/chrome-apply-and-html-handoff.md).

**2026-10-28 API exploration:** the maintainer subsequently requested design review of an optional Chrome bookmark API route. The [bridge proposal](chrome-api-bridge-plan.md) evaluates per-profile extension installation, Native Messaging, live Base/Ours/Theirs review and non-atomic operation recovery. This is reconsideration of the extension-free preference, not implementation approval or a change to installed support. API apply would require a running paired Chrome profile; the exit requirement remains specific to direct file writes. Encrypted-file/Keychain integration stays deferred.

## MVP scope

1. **Profile connection:** select a browser and explicitly attempt its known standard location using normal OS permissions; show name, path, storage, permission, and read/write capability. Disambiguate identical display names. Disconnecting archives the current workspace before removing a saved entry and never deletes browser originals or original-backup history.
2. **Persistent working copies:** retain Base, Ours, identity mapping, and editing state locally across app restarts. App autosave is separate from browser apply. Keep work when a profile disappears and offer reconnection. Offer explicit source refresh with three-way merge/review and a recoverable workspace archive before advancing Base; do not silently reload over local edits or infer live-browser freshness.
3. **Editing:** create, rename, nest, move, and reorder folders; add/edit bookmark names and URLs; multi-select move; drag-and-drop with menu/keyboard alternatives; search; same-URL view; delete from the working copy and undo. Duplicate URLs are not automatically removed. Use visible Edit, Move and Delete actions; label deletion plainly and explain its working-copy boundary. A single bookmark deletion is immediately undoable. Folder or multi-item deletion previews names and the unique count including folder contents before confirmation. Pending deletion becomes an explicit browser removal only after apply review.
4. **Direct apply:** verified exit, latest read, three-way merge, conflict choices, final diff, verified original backup, source recheck, safe replacement, and result verification for supported formats.
5. **Recovery:** per-profile apply history and original backups, restore review, current-state backup before restore, interruption recovery. Proposed retention: keep backups until the user removes them.
6. **Compatibility:** Netscape HTML export for all bookmarks or a folder subtree; workspace JSON backup/import. Imported HTML does not acquire Chrome identity. Workspace backups and original backups are different artifacts.
7. **Localization:** English source/default with Korean, Japanese, and Simplified Chinese; consistent editing, permission, conflict, error, backup, and recovery copy. See [localization policy](localization.md).

Encrypted bookmark storage and its Keychain authorization/integration are outside the current implementation scope. Its Settings → Labs entry remains an unavailable, off placeholder with explanatory text in all four languages; it does not persist a preference or request credentials. The disconnected core experiment's source was removed on 2026-11-12; its recorded evidence remains historical, not app support. Encrypted-only connections remain unsupported; encrypted companions never authorize plaintext writes.

No hosted account, cloud sync service, AI classification, link crawling, Windows app, or cross-profile atomic move is in the initial MVP. The optional extension is an explicit Labs experiment and is not required for ordinary file-workspace editing/export. Cross-profile copy is a later feature; first complete safe editing within a profile.

## User journey

### Connect a profile

Explain the required folder and access purpose, then present the macOS folder picker. Normal startup opens a Chrome connection screen without generating sample data. After an explicit Connect action, try normal read access to Chrome’s standard location and reuse a matching saved grant. Show names for explicit profile selection when permitted. On denial or missing location, show in-app guidance and offer a secondary access/custom-folder picker; do not bypass the OS or scan on startup. Reread discovery when confirming and import only the selected supported profiles. Unselected unsupported profiles do not block supported selections. Synthetic profiles belong only to explicit development/demo/QA entry points; old samples and working copies remain available without automatic conversion or deletion. Cancellation returns to the previous screen without modification. A prior environment investigation returned `Operation not permitted` for a Chrome data directory; the cause is unconfirmed. Do not promise that the picker resolves all access restrictions or automatically request unrestricted disk access. Offer reselection and relevant permission guidance.

### Edit a working copy

Use a profile/folder sidebar and searchable table. Provide Back/Forward/Up and clickable folder ancestors. Ordinary folder browsing shows immediate children; search includes descendants. Distinguish folder and bookmark types, displaying folders first without implicitly changing stored order. Switching profiles preserves each working copy. Clearly distinguish “Saved in Galmuri” from “Not applied to Chrome.” Show changed names, URLs, folders, ordering, and pending removals; allow individual undo and reviewed selected-change cancellation, including pending deletion restoration. The primary action is “Review changes,” disabled when nothing changed. Session undo need not survive relaunch, but saved pending changes must remain cancelable. Offer an explicit current-profile-wide discard to the persisted source snapshot with complete before/after review, stale-state checks and local persistence rollback. Include additions/deletions/moves/order and hidden/filter-excluded items; preserve other profiles and browser originals.

### Verify Chrome exit

Show the exact target profile and pending app changes. Ask the user to finish browser work and quit Chrome, then check again. Do not force-quit. Other profile windows may share the same browser process; closing a window is not proof of exit. If background processes, target user-data directory, or a restart cannot be verified, block apply and preserve work.

### Merge and resolve conflicts

After exit, reread Theirs and compare it with Base and Ours. Separate independent browser additions, app edits, automatic merges, and unresolved conflicts. Use user-facing labels “When first imported,” “Edited in Galmuri,” and “Edited in Chrome,” rather than requiring Git vocabulary.

Conflicts include different values for the same field, deletion versus modification, competing parent moves, and incompatible sibling ordering. Folder deletion includes changes to its descendants. Show item identity/context, full path, all three relevant values, and the result of each choice. No preselected destructive resolution; block progression until conflicts are resolved.

### Review and apply

Review additions, edits, moves, order changes, and removals, including automatically merged changes and affected descendants. Back up and verify the original after approval. Recheck the target identity, raw content fingerprint, supported format, and browser exit before replacement. If anything changed, invalidate the old approval and merge again.

Permission revocation, low disk space, failed backup, or failed validation must not result in an unreviewed replacement. After a verified file write, update Base and distinguish file verification from browser restart and synchronization checks. Later browser changes form a new comparison; do not repeatedly overwrite changes that revert after sync.

### Restore

Show the backup's profile, time, format/version context, and verification status. Explain the concrete differences, including bookmarks created after the backup that would be removed. Verify browser exit, back up the current state, review differences, recheck the target, and perform recoverable replacement. Do not claim that file restore also rolls back server-side sync state.

## Completion criteria

| Area | Evidence required |
| --- | --- |
| Connection | Denial, revocation, restart, profile rename/move, stale access, and minimal reads handled |
| Working copy | Last completed edits survive app interruption; no profile confusion or unintended original writes |
| Editing | Cycle prevention, distinct same-URL items, nested folder changes, batch actions, undo, search, export/import behavior |
| Merge | Independent edits preserved; field, delete/edit, move, and ordering conflicts exposed; valid final tree |
| Apply/recovery | Format-specific no-change preservation and edited round-trip; verified backup; external changes/restarts block stale apply; failure and restore tests |
| Browser adoption | Dedicated-profile restart preserves meaning, identity, and metadata; every claimed sync combination checked after synchronization |
| Native UI | Keyboard, VoiceOver, enlarged text, window resizing, and large collections checked on macOS |
| Localization | Four locales wired to the target, correct fallback/formatting/plurals, no translated user content, layout and language review |

The HTML prototype, passing prototype tests, and populated strings are not proof of these native completion criteria. See the [technical plan](technical-validation.md), [roadmap](roadmap.md), and [decision history](decisions.md).

The local Ego Lite preset and recognized-plaintext import are experimental and read-only. Keep a persisted warning on these working copies. Browser selection alone never reads a profile or enables writes. Actual macOS consent/folder fallback and Ego runtime fidelity remain acceptance gates. See [connection behavior](profile-connection.md).

Denied browser reads use a dedicated folder-consent guide first. Open the standard picker inside the exact browser data folder so the user confirms its current location; confirm by a successful read, then show profile names for explicit selection. Only a selected-folder denial reaches applicable Chrome/macOS27 Files & Folders guidance; ordinary EACCES gets file-permission help. Keep custom-location browsing, cancellation and existing work. Settings fallback remains a one-shot pane open and manual steps. Galmuri must not inspect or operate other apps’ UI or request Accessibility/Automation for browser connection; the Release 16 mechanism remains withdrawn. [Connection behavior](profile-connection.md#folder-first-consent--2026-10-27).


The manual Settings guide keeps actions inside their numbered steps: open Settings, manually find/expand the current app and enable Google Chrome if listed, then return and choose Check Again. Explain that opening Settings is navigation rather than approval, and keep the full manual route available. Approval and any scope restrictions remain OS/user decisions.


Profile selection must separate file observations, content-read support and current-browser authority. Show file names/types/modification times and specific inspection problems. Keep readable primary plaintext selectable when companion encrypted/account/ordering/backup files are present, excluding their payloads. Label no-plaintext and unreadable-plaintext cases precisely. Do not imply that filename checks or modification times establish the latest browser contents. Preserve original-write restrictions and validate selected plaintext contents before committing an import.


## Optional API bridge checkpoint · 2026-10-28

The maintainer authorized Stage A after the API review. Release25 adds only explicit extension/native-host pairing: Settings → Chrome Bridge, matching code/session approval and Chrome acknowledgement with a five-minute lifetime. The extension deliberately lacks `bookmarks` permission. Existing file connections, Workspace v1, deferred encrypted-file/Keychain support and external-write restrictions remain unchanged. [ADR 0009](adr/0009-optional-chrome-api-bridge-proof.md) records the scope; [setup and limits](chrome-bridge-proof.md) distinguish the dedicated proof from future API editing. Bounded app-owned handshake files are the first proof transport; no bookmark-payload or general server framework was introduced.


## API editing checkpoint · 2026-10-29

[ADR 0010](adr/0010-semantic-api-workspaces-and-recoverable-apply.md) implements a distinct versioned API working copy without migrating existing file workspace v1. Paired API snapshots drive persistent editing, semantic 3-way refresh/review and guarded local-scope operation batches. Removed items move to a tracked visible Chrome recovery folder; reviewed restore moves existing IDs back. Uncertain/partial operations persist a retry block, with explicit archived-work/current-Chrome adoption. The host checks the exact owning app's kernel process identity before new mutation intents; no external app UI is inspected.

[The API workbench](chrome-api-workspace.md) is available through Settings → Labs → API connections and editor, with full/subfolder HTML export. Ordinary hosts remain read-only; only explicitly marked dedicated write-proof connections can mutate, and account/managed/cross-store/permanent deletion stay unsupported. Local API adoption/restart evidence does not close real Google Chrome registration, OS grants, remote sync, physical keyboard/VoiceOver, large-data stress or public distribution gates. No original-file encryption or Keychain implementation was added.


## Native refinement · Release27 · 2026-10-29

The maintainer requested correcting the newly found transport problem, performance collaboration with claude-dev-max and less green. [Native refinement](native-refinement.md) records compact chunked operation records, explicit stop/current-state recovery, measured merge improvements and gray/blue native editing. Existing file workspaces and private data remain compatible. Implemented interaction parity and native captures do not replace actual Chrome setup, physical accessibility/gesture or broader failure/sync acceptance; normal original writes remain gated.

## Pending visibility and connection details · Release28

Every counted file-workspace change must be discoverable in the unfiltered Pending Changes list, including deleted Base records and protected-root folder-content changes. Deleted rows support reviewed restoration; protected/missing rows do not expose ordinary mutation actions. A search can narrow results without changing the profile-wide count. Connection details use an explicitly labeled bounded native sheet; opening/closing it must preserve edits and source bytes. Workspace v1, merge rules and original-write gates remain unchanged. See [native refinement](native-refinement.md#pending-list-correction--release28).

## Labs distribution boundary · Release29

Both browser-apply routes are explicit experiments in Settings → Labs. API setup includes per-profile unpacked installation instructions, a matched app-bundled extension ZIP and a complete Release source folder for later GitHub download. Publication remains deferred; a ZIP does not install/register the native host or grant writing. Direct-file apply keeps its owned-synthetic-only gates, on-demand exit checks and reviewed backup/replacement; browser exit does not trigger automatic writes. Ordinary Review changes previews saved Base versus the working copy; Refresh separately merges the source. Saved workspaces remain compatible. [Labs behavior and limits](labs.md).

## Persistent experiments and pending review · Release30

Labs uses two independent default-off persistent switches. On reveals explanation/setup, not write authorization. Selected-profile extension checks report only observed disk installation records for the packaged ID, with separate unverified/unavailable states; they do not inspect another app’s UI, scan every profile or infer API pairing from labels. Turning features off preserves edits; file apply/restore are blocked when off and stale inspection results cannot appear under a different profile. Normal Review changes always exposes pending Base→Ours edits, including deletion; a no-op refresh must not imply these edits vanished. [Labs](labs.md).


## Settings discoverability and registered-profile inspection · Release31

Expose Settings in both the editor sidebar and initial connection screen. Settings has a General/Labs sidebar. API on initiates one evidence check for each Galmuri-registered profile using its existing grant; later checks are explicit and do not follow editor selection. Do not discover unregistered profiles, infer active API pairing, or treat failure as definitive absence. Keep memory-only statuses and visible check times; newly added/rebound profiles require manual recheck. Off must discard late results and stop future reads while preserving work and existing write gates. [Labs](labs.md).
