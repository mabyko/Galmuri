# Product discussion and decisions

This is the public product record, distilled from the initial planning discussions on 2026-10-23. It contains decisions and rationale, not a private chat transcript. Accepted behavior is specified in the [product plan](product-plan.md); unresolved feasibility is in the [technical plan](technical-validation.md).

| Decision | Outcome and reason |
| --- | --- |
| Name | **Galmuri · 갈무리**. The name conveys gathering and putting things in order. Explain editing and applying through the tagline. Trademark/name availability is unresearched. |
| Product boundary | A standalone Mac app that continuously manages connected Chrome profiles. Per-profile extensions and export-only editing do not meet the intended experience. |
| Editing and apply | Preserve Base and Ours, then read Theirs at apply time and perform a three-way merge. This preserves independent browser changes and exposes real conflicts. |
| Browser lifecycle | Let users keep using Chrome during editing. Ask them to finish work and quit before apply. Never force-quit. Exit is necessary but does not prove synchronization safety. |
| Direct writes | The agreed product goal, subject to format, permission, recovery, and restart/sync validation. No claim of proven support yet. |
| Design | Continue the calm, dark, sidebar-and-list design. Separate editing from apply review, conflicts, and recovery. |
| Native stack | Use **SwiftUI**. Reusing HTML inside a web shell was considered; the user chose a fully native Mac interface. HTML stays a design reference. |
| Open source | Prepare for GitHub publication under **MIT**, explicitly selected by the maintainer. Copyright notice: Galmuri contributors. Repository publication has not occurred. |
| Work sequencing | The maintainer explicitly resumed implementation and local native testing in parallel after the planning revision. GitHub publication and public release remain later work. |
| Encrypted bookmarks (2026-10-25) | Defer support and further implementation. Show only an unavailable “Planned” item in Settings → Labs; do not implement Keychain access, an activation preference or native encrypted-store integration. Retain the disconnected core experiment and evidence. (2026-11-12: experiment source removed; evidence retained.) |
| Languages | English as source/default; Korean, Japanese, and Chinese requested. The initial Chinese script is **Simplified Chinese (`zh-Hans`)** as a working scope assumption. |

## Proposed implementation scope

One apply operation targets one profile. Start validation with known plaintext local storage, use synthetic fixtures and dedicated profiles, preserve unknown metadata, and block writes to unsupported formats. Keep HTML compatibility export. These are implementation proposals rather than evidence of shipped support.

## Still open

- Supported macOS and Chrome versions; public signing, distribution, and App Sandbox behavior. Local development uses a macOS 14 target and ad-hoc `forked.galmuri.local` identity; see [ADR 0003](adr/0003-local-development-boundary.md).
- Profile permissions in a signed app, persistent access, and privacy prompts.
- Authoritative storage detection, secondary files, account and managed bookmarks. Encrypted-store support is deferred by the decision above.
- Identity remapping, ordering, sync metadata, restart races, and verified recovery.
- Direct Ego support and any later Traditional Chinese support.
- Native string-catalog integration, language review, and localization QA.
- GitHub repository URL, private security reporting, and the first release process.

New decisions should update the relevant specification and this record. Use [ADRs](adr/README.md) for costly architectural trade-offs, not for every small UI choice.

On 2026-10-25, the maintainer accepted browser selection with normal permission-aware default-location discovery. Chrome remains first; Ego Lite gains only an experimental read-only recognized-plaintext connection based on observed app-bundle metadata and Chromium path rules. Actual Ego storage authority, native TCC acceptance and direct apply remain unverified. See [ADR 0007](adr/0007-browser-selection-and-ego-preview.md).

On 2026-10-25, after the maintainer supplied a Chrome read-permission error, task 1.10 replaced the denied-access card with a dedicated permission guide. It explains scoped-folder approval and optional existing-permission review in System Settings; successful access is established only by a subsequent read. No signing, entitlement, TCC-record or source-write change is implied.


### 2026-10-27 · Folder-first explicit consent

The maintainer approved opening the browser data folder in the standard picker, asking for confirmation, then automatically reading profile metadata once. This replaces initial Settings-first Chrome guidance. Settings is a fallback after confirmed-folder denial; known EACCES remains ordinary permission help. The decision follows Apple’s explicit folder-selection guidance and Mozilla’s pre-opened Chrome-folder import fix, but is not evidence of actual Galmuri TCC success. ADR 0008 remains withdrawn.


### 2026-10-27 · Plaintext selection with separate file evidence

The maintainer requested showing readable plaintext while excluding encrypted payloads, with observed source-file metadata and precise failure states. Remove generic freshness/unavailable badges and show filename classification, modification time and inspection problems. Import only the supported primary plaintext; retain companion-store write restrictions. Do not infer latest/active authority from timestamps, clear safety gates, merge separate stores or reactivate encrypted support.


### 2026-10-27 · Folder browsing with return routes and display-only grouping

Use transient Back/Forward history plus parent navigation and clickable ancestors. Show direct children unless searching; retain recursive global views. Folders precede links in the table, with explicit types, without sorting/replacing source order. Explicit ordering acts between same-type siblings. Keep editing/undo and stale-selection safeguards, profile-isolated history and read-only original boundaries. [Editing behavior](editing-ux.md#folder-navigation-and-type-separation--2026-10-27).


### 2026-10-27 · Discard persisted working changes independently of session undo

Keep session undo transient. Add an explicitly reviewed full-profile discard to persisted Base under Pending Changes, available after relaunch and independent of source access. Bind approval to the captured profile/source/Base/working state and reuse local edit rollback/undo. A discard never refreshes or writes Chrome and does not affect other profiles. Per-item revert and persisted undo are outside this bounded request. [Behavior](editing-ux.md#cancel-saved-pending-changes--2026-10-27).


### 2026-10-27 · Pre-use recovery and plaintext-only boundary

Finish profile list management, reviewed source refresh, selective revert and explicit HTTP/HTTPS opening before asking for broader live use. Removal and refresh archive the previous workspace locally before advancing; browser originals and original-backup history are preserved. Refresh is a disk snapshot with three-way merge, not a live/sync authority claim. Keep encrypted support deferred. The dedicated CFT153 normal launch/restart again creates encrypted/ordering companions; safe rejection, not plaintext write support, is the validated result. Do not enable external writes or move destructive browser acceptance onto the maintainer's normal profiles. [Evidence](validation.md#pre-use-management-refresh-and-selective-recovery--2026-10-27).


### 2026-10-28 · Interim HTML handoff while direct apply is blocked

Research distinguishes technically possible extension-assisted or format-specific offline editing from current app support. Under no per-profile extensions and deferred encrypted support, general direct apply remains disabled. The maintainer requested HTML handoff if direct apply cannot be supported; existing full/folder HTML export can serve as a manual fallback. Chrome import adds content rather than applying Galmuri edits/deletions to original IDs. Preserve old items initially; no default reset or automatic replacement. Plaintext-only coverage must not be represented as a complete Chrome backup. The original direct-apply MVP stays incomplete; no new API integration or app UI was implemented. [Evidence and procedure](research/chrome-apply-and-html-handoff.md).


### 2026-10-28 · Review an optional Chrome API bridge before implementation

The maintainer asked to evaluate bookmark-API direct apply in advance. Prepared a [proposal](chrome-api-bridge-plan.md) with a per-profile extension, Native Messaging, live 3-way review, backend-specific identity/persistence and partial-apply recovery. Reconsidering the earlier extension-free preference is authorized for design, not an accepted replacement architecture or permission to implement/install. Recommend a registration/pairing-only dedicated proof first if implementation is later requested. No ADR is accepted yet; no code, app install, original write or encrypted-file work changed.


### 2026-10-28 · Begin the API route with pairing-only Stage A

After reviewing API feasibility, the maintainer requested implementation. Implemented the limited dedicated-profile connection proof with separate extension/host identities, private expiring session files and app approval acknowledged by Chrome. The extension's full connection tab avoids losing the native port when switching to Galmuri. No bookmark permission, schema migration, editor API integration or new OS privilege is included. See [ADR 0009](adr/0009-optional-chrome-api-bridge-proof.md) and the [checkpoint guide](chrome-bridge-proof.md). Later stages remain incomplete.


### 2026-10-29 · Implement semantic API working copies and reversible local apply

The maintainer requested completing the design/implementation. [ADR 0010](adr/0010-semantic-api-workspaces-and-recoverable-apply.md) records the separate API sidecar, opaque identity map, approved mailbox protocol, live semantic merge, operation journal and explicit interrupted-state adoption. Prefer visible recovery-folder moves over permanent deletion, and verify the owning app through kernel PID/start/path metadata rather than AppKit launch dates, which were unavailable for the direct CLI smoke launch. Only separate dedicated API-write markers and an explicit launch flag enable writes; previous pairing-only registrations do not gain them. No real-user profile, account/sync claim or original-file write gate was changed.


### 2026-10-29 · Bounded records, acknowledged stop and calmer native editing

Fix the known progress/result size mismatch before broader writes. Negotiate matching API-protocol2 peers, chunk records, retain compact sequential operations and check a source-bound stop marker before acknowledging a new mutation intent. Preserve the pending/reviewed-adoption boundary because stopping cannot undo an in-flight call. The maintainer also requested less green: retain dark native surfaces, use muted blue for primary actions/selection and quiet gray secondary UI, without changing global accent preferences. Measure Core improvements against the frozen old merge semantics; do not infer native FPS from those benchmarks. [Refinement](native-refinement.md).
