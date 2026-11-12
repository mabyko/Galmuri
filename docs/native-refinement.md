# Native editor and API refinement

Release27 checkpoint · 2026-10-29. The maintainer requested fixing the remaining blockers, measured performance work with claude-dev-max and a calmer interface with less green.

## Appearance and editing

Keep the charcoal macOS layout, system typography and quiet separators. Use muted blue for primary actions and selection; secondary controls and explanatory text stay gray. Retain orange for actionable warnings and destructive review. The app's own table-row background uses a narrow native AppKit adapter; it changes only Galmuri's row/table ancestors, does not intercept input, and retains native selection/keyboard/accessibility semantics. It does not inspect other applications or change the system accent preference. Native picker/checkbox appearance can still follow macOS.

The file editor shows a compact read-only/test-workspace status with an explicit Connection details button. Release28 replaces inline expansion with a bounded, scrollable native sheet that can be closed without changing the working copy. Saved-in-Galmuri status is also visible near the toolbar actions. Existing Back/Forward/Up, export, profile management, undo and review remain available.

The API workbench now includes Back/Forward/Up, folder-first ordered rows, multi-selection move/delete, process-local drag tokens and same-profile folder targets, context actions, Return navigation/editing, Delete, and move shortcuts. Search follows descendants of the current folder; changing navigation/search clears selection and drag authorization. Removal previews show the whole affected selection, including descendants. Stale profile/tree captures still block changes. Physical gestures, keyboard focus and VoiceOver acceptance are separate from code/native render checks.

## Bounded transport and stopping

Pairing now explicitly negotiates `apiProtocol: 2` in both directions. Older peers reject rather than ignore new stop semantics; rebuild/reload matching extension and native helper together. The framing protocol remains version1. Snapshots, jobs and progress/results use at most 32,000 decoded bytes per chunk, at most 256 chunks and <8 MB per aggregate. Partial/interleaved/duplicate/foreign transfers reject. Job targets remain capped at 10,000 nodes; snapshot depth/node limits and local-only write gates are unchanged. The session request cap is 131,072, still bounded by its five-minute lifetime.

Each mutation persists a small intent before the API call and a small observed record afterward. Created-item mappings are recorded as deltas; the final result carries the complete mapping through chunked transport. The host retains sequential `.operation-N.intent.json` and `.operation-N.observed.json` records. This avoids resending the whole growing identity map on every call and closes the earlier 600+300-item progress limit blocker.

**Stop after current call** writes a private marker bound to job/session/installation. The host checks it before acknowledging a new mutation intent; the extension stops before issuing that call, refreshes the browser snapshot and reports `stopped`. A started or already-acknowledged call may finish. Earlier changes are not rolled back; the pending job remains blocked until explicit current-state review/adoption. A late stop can arrive after successful completion. Timeouts/task cancellation request stop too, and closing the workbench requests stop without controlling Chrome UI. Stopping/disconnecting can still leave uncertainty; no automatic replay, rollback, atomicity or exactly-once claim is made.

## Measured performance

The merge engine caches depths, builds conflict paths only when needed, avoids repeated parent-chain scans, groups folder membership once, tracks placed order members in a set, and uses in-degree topological ordering. The pairwise three-way order rules remain unchanged. Four hundred seeded scenarios compare full results/conflict order with a frozen pre-change engine, with both unresolved and selected choices.

| Synthetic Core workload | Release before | Release after |
| --- | ---: | ---: |
| 300 folders / 5,000 items, sparse edits | 103.5 ms | 69.3 ms |
| 300-level chain / 300 items, sparse edits | 396.7 ms | 60.8 ms |
| 400-sibling order merge | 125.2 ms | 65.9 ms |

Measurements are the best of three, old/new in the same process, not a frame-rate or universal latency guarantee. The 300-level stress case exceeds the API adapter's depth64 limit; it measures the Core engine only. Ordering still has quadratic pairwise work. Deep deletion conflicts, full diagnostic rendering and native frame times remain unbenchmarked. The initial 1,500-level legacy stress run did not finish within its test budget; it is not counted as a successful benchmark.

The app also removes per-item recomputation of changed IDs, unnecessary duplicate grouping, repeated path comparisons in move sorting and quadratic returned-ID-map validation. API row listing preserves stored traversal order in linear passes; review cards are lazy. See [validation](validation.md#transport-stop-performance-and-native-refinement--2026-10-29) for checked scope and remaining acceptance.

## Pending list correction · Release28

The pending count continues to count changed records, including a folder whose child list changed. The list now includes protected root folders and deleted records from the saved Base, so an unfiltered list covers every counted record. Deleting one bookmark directly under the bookmarks bar can therefore show two rows: the bar’s folder contents changed, and the bookmark pending removal. This preserves existing workspace v1 and merge semantics rather than changing saved edits to fit a display count.

Deleted rows retain their saved title, URL and folder path, use a removal icon and strikethrough, and offer reviewed restoration through Revert Selected or Return/double-click. Protected roots and missing records cannot be edited, moved or deleted as ordinary items. Folder-content changes have a distinct label. Empty pending results explain whether there are no changes or a search has no matches. The previous collapsed removal list is replaced by these main-list rows.

The reported source-chevron blank screen was not independently reproduced. That inline expansion path was removed; native synthetic checks exercise actual sheet presentation/dismissal and verify that the editor, saved working copy and source bytes are preserved. Physical mouse and VoiceOver acceptance remain separate.
