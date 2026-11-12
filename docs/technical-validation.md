# Native architecture and technical validation

Proposed implementation plan · 2026-10-23. No real user profile was read or changed during this project work. The earlier failed access attempt does not establish signed-app permission behavior.

## Native stack

Use **SwiftUI for the native macOS UI**, per [ADR 0001](adr/0001-swiftui-native-app.md). HTML/CSS is design reference material, not a web-shell runtime. Use Foundation and limited AppKit integration for file selection and OS behavior. Local development uses Swift 6, a macOS 14 target, ad-hoc signing, and an unsandboxed app with its own data directory; see [ADR 0003](adr/0003-local-development-boundary.md). Validated OS/Chrome versions and public signing/distribution/Sandbox remain open.

| Area | Initial proposal |
| --- | --- |
| UI | Split navigation, selectable table, search, inspector, sheets, toolbar; native keyboard and accessibility behavior |
| Working copies | Versioned local documents in app Application Support; preserve Base, Ours, identity map, review/apply state; start without a database dependency |
| Merge | Deterministic Swift logic independent of views, parsing, and file replacement |
| Chrome adapter | Explicit, format-specific capabilities; separate readable support from verified write support |
| Localization | English-source String Catalog; Korean, Japanese, Simplified Chinese; catalog compiled into the local bundle; basic runtime selection/fallback checked |
| Tests | Synthetic fixtures and focused Swift tests; choose Swift Testing/XCTest with the toolchain and deployment target |

Use narrow state ownership. Keep selection/search local to the view; the app owns per-profile work. Model apply phases so contradictory states cannot coexist. Do not perform file IO or merge work inside a SwiftUI view body. Avoid a plugin framework or extra service layers before they are needed.

## Evidence and version boundaries

The following official documents and Chromium HEAD sources were consulted on 2026-10-23. HEAD is not the installed Chrome version. For a supported combination, pin actual Chrome build/channel, source revision, macOS, signing/Sandbox configuration, account state, authoritative files, and observed feature stage.

- [User data directory](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md): profile subdirectories, platform defaults, and custom data locations.
- [Bookmark storage](https://chromium.googlesource.com/chromium/src/+/HEAD/components/bookmarks/browser/bookmark_storage.cc): local/account selections, sync metadata, scheduled writes, shutdown saves, plaintext/encrypted branches.
- [Bookmark features](https://chromium.googlesource.com/chromium/src/+/HEAD/components/bookmarks/common/bookmark_features.cc): stages that affect which plaintext/encrypted file is authoritative and whether secondary files are written.
- [Bookmark node](https://chromium.googlesource.com/chromium/src/+/HEAD/components/bookmarks/browser/bookmark_node.h) and [codec](https://chromium.googlesource.com/chromium/src/+/HEAD/components/bookmarks/browser/bookmark_codec.cc): identity scope, repair/reassignment, metadata, dates, ordering, and checksums.
- [Apple file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox): user-selected folders, persistent security-scoped URL bookmarks, and other permission restrictions that may still deny access.
- [SwiftUI NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) and [Table](https://developer.apple.com/documentation/swiftui/table): native split navigation and table selection. Recheck API availability against the chosen deployment target.
- [Chrome import/export](https://support.google.com/chrome/answer/96816?hl=en): compatibility HTML, not a guarantee of direct-write support.

## Permission and discovery

1. Ask the user to select a Chrome data root or profile directory. Do not implement reads of passwords, cookies, or history as part of bookmark connection.
2. Validate profile metadata against actual directories in the approved scope. A proposed discovery path uses relevant `Local State` profile information; this too needs version-specific verification. Display names and avatars are not profile identity.
3. Give each connection an app profile key, associated with approved root/profile file identity. Distinguish a moved directory from a new profile at an old path.
4. Persist security-scoped URL bookmark data for access across launches; handle stale resolutions and denied access. Balance access acquisition/release. OS URL bookmarks are permission records, not browser bookmarks.
5. Validate normalized paths, symlinks, directory changes, and permission revocation. Do not explore outside the approved location.

The initial permission failure could involve TCC, Sandbox, or other filesystem restrictions. Test a signed app with picker selection, restart, denial, and revocation before promising access. Do not bypass restrictions or automatically change system permissions.

## Format and identity

Preserve the original payload, including unknown fields, alongside the app's semantic model. Change only validated fields. Keep Chrome numeric IDs and timestamp strings precise; do not round-trip them through floating-point numbers.

- Numeric IDs persist between sessions and are unique across local and account stores in the bookmark model; codec repair can reassign invalid/duplicate values.
- GUIDs are unique within an individual store, not necessarily across both stores. They may change during collision repair or store migration.
- Proposed connection identity is `(profileKey, storageKind, GUID)`, with original numeric ID and tree position as supporting evidence. URL is not identity.
- Missing, duplicated, regenerated, or ambiguous identity must block automatic association/write. Do not silently reconnect by URL. New app items need temporary identity and a validated allocation/checksum policy at apply time.
- Cross-profile copies are new items. Equal Chrome IDs in different profiles do not mean equal bookmarks. App IDs and labels on imported tab data are not Chrome identity.

Validate sibling order, permanent roots, dates, `meta_info`, `sync_metadata`, checksum/SHA256 fields, and unknown metadata separately. Copying metadata verbatim does not prove that it remains meaningful after an edit or that sync detects an external write.

| Combination | Initial read plan | Direct-write gate |
| --- | --- | --- |
| Known plaintext local store | First implementation target | No-change preservation, edits, restart, and recovery evidence |
| Local plus account stores | Identify and inspect separately | ID/GUID scope, multiple-file consistency, account/sync evidence |
| Encrypted primary or parallel storage | Deferred; disabled “Planned” Labs placeholder only | No Keychain access or encrypted-source integration; retain current unsupported/mixed-store write restrictions |
| Managed/policy bookmarks | Investigate discovery/read | Initially read-only; preserve management provenance |
| Unknown version, damage, uncertain identity | Explain failure and preserve work | No guessed writes |
| Ego | Undecided | Independent format, permission, version, and restart validation |

## Three-way merge

Keep Base, Ours, and Theirs immutable during review; build the result separately. Apply conflict choices, then validate tree invariants again. See [ADR 0002](adr/0002-three-way-merge-before-apply.md).

| Situation | Intended handling |
| --- | --- |
| Ours unchanged from Base | Preserve Theirs |
| Theirs unchanged from Base | Apply Ours |
| Same field changed to the same value | Apply once |
| Independent changes to different items | Preserve both |
| Independent name and URL edits to one item | Combine by field, then validate |
| Different values for the same field | Explicit conflict with original/app/browser values |
| Delete versus edit/move; folder deletion versus descendant changes | Conflict with full removal impact |
| Competing moves to different parents | Conflict; a compatible move and independent rename may combine |
| Sibling ordering | Merge relative order constraints, not numeric indexes; expose incompatible constraints |
| Independent additions at the same position | Preserve both; ask for ordering if the relative order cannot be established |
| Missing parent, uncertain mapping, protected/managed root change | Block or explicitly resolve; no guessed repair |

Final invariants: no cycles or orphans, valid roots, valid identity in its proper scope, preserved same-URL items, defined sibling order, and no unsupported store transition. Duplicate browsing is separate from identity matching.

## Apply and recovery boundary

`edit → wait for exit → latest read → merge → resolve → review → backup → recheck → replace → verify file → verify restart/sync`

Bind approval to Theirs' raw content hash, file identity, format capability, and browser state. Do not rely only on size/mtime. If the source changes after review, invalidate approval and start merge again.

Proposed replacement uses a validated temporary file in the same directory followed by atomic replacement, preserving required ownership, permissions, and file attributes. Test durability of the original backup, journal, and temporary data, including interruption at every phase. Multiple file renames are not a single atomic transaction; block such writes until a recoverable journal and supported format behavior are verified.

There is no proven mutual-exclusion agreement with Chrome. A browser can restart just after a check, so final hashes alone do not eliminate races. Validate restart detection, abort behavior, post-replacement reads, and recovery. Do not assume `NSFileCoordinator` or a Chrome lock file coordinates external writes. If the originals cannot be kept safe, do not release direct apply.

File verification, adoption after browser restart, and adoption after synchronization are separate outcomes. On sync reversion, stop repeated writes and offer diagnosis/recovery. Restore needs exit verification, a current-state backup, review, source recheck, and recoverable replacement too; it does not promise a server-side rollback. Original backups and working copies can contain private URLs, so keep them out of public fixtures, logs, and uploads.

## Proposed validation sequence

Fixture checks and native app-state integration have run; actual browser and permission gates remain incomplete. See the current evidence below and [validation](validation.md). Continue with dedicated test profiles rather than live user originals.

| Gate | Cases | Passing evidence |
| --- | --- | --- |
| A. Discovery/read | Synthetic roots, approved copies, dedicated profiles; denial/cancel/revocation, duplicate names, custom roots | Exact profile/tree mapping, minimal reads, no changes on denied access |
| B. No-change round-trip | Large IDs/dates, Unicode, same URLs, empty folders, unknown metadata, checksums, local/account, damage | No-op preserves original bytes; edited serialization preserves semantics and survives Chrome reread |
| C. Merge fixtures | Every rule above, both-side additions, subtree deletes/moves, inverse ordering, identity regeneration, repeated merge | Expected trees/conflicts; immutable inputs; no cycles, orphans, or unintended losses |
| D. Dedicated Chrome restart | Synthetic additions/name/URL/move/order/delete; exit, apply, restart, exit/read again | Meaning, identity, metadata, and order adopted and retained by Chrome |
| E. Sync/failure/recovery | Authorized test account/devices; offline/online, remote changes, restart race, disk full, revoked permission, phase crashes | Verified convergence and recovery for every claimed combination; unsupported cases blocked |

If dedicated sync accounts/devices are unavailable, record E as pending. Do not clear a user's sessions or repurpose the shared UI QA browser profile for storage experiments. Follow the user's browser operating rules when preparing a dedicated storage test environment.

`design/prototype.test.mjs` tests the scripted UI model only. It does not test these gates, Swift, the production merge engine, or real Chrome writes.


## Current local support boundary

| Area | Evidence | Remaining gate |
| --- | --- | --- |
| A: profile discovery/read | Synthetic multi-profile roots, bounded Local State reads, symlink rejection; approved synthetic-copy scoped bookmark survives app-state relaunch | Native picker denial/cancellation/TCC/revocation; authoritative encrypted-store mapping (dedicated 153.0.8010.52 plaintext read observed) |
| B: preservation | Exact no-op bytes, independent checksum vectors, precise ID/date strings, GUID spelling, metadata, duplicates, order; unsupported writes rejected | Browser round-trip and authoritative multi-store/account/encryption cases |
| C: merge | 26 core tests include field/subtree/move/order/structural conflicts and fail-closed identity cases; app-state choices invalidate stale approval | Larger adversarial fixture set and full interactive native review QA |
| D: replacement/restart | Synthetic local file backup, hash rechecks, replacement, restore, simulated restart race; native review uses real merge results | Dedicated normal exit/restart observed; aggregate guard remains conservative; edited adoption blocked by encrypted/mixed storage; broader durability acceptance pending |
| E: sync/failure | Corrupt workspace preserved; invalid permission records/out-of-scope reads blocked; prepared backups exposed after abort | Authorized sync account/devices, disk-full/revocation/crash matrix and synchronization convergence |

All external connected profiles remain source-read-only. `ApplyCoordinator.canWrite` permits only the app-owned synthetic test root, and the runtime browser check compares explicit data roots and blocks unknown/default/helper states. This is a deliberate development boundary, not a substitute for direct apply. No production Chrome or synchronization combination is claimed. A subsequent bounded, no-account/mock-keychain core proof for Chrome for Testing 153.0.8010.52 is recorded in the [encrypted-store checkpoint](encrypted-store-adapter.md); native activation remains pending.


## Additional local hardening · 2026-10-24

- Scope loss/reconnection preserves Base/Ours and permits offline working-copy edits. A fresh folder grant must identify the original source path; moved/different sources are not automatically rebound. Missing imported grants fail closed. Native picker/TCC revocation still needs separate verification.
- Same-profile drag movement uses opaque process-local tokens, rejects stale/foreign payloads and invalid moves, and retains move-sheet/keyboard alternatives. The exported data UTI is declared in the bundle and conforms to data per [Apple's type declaration guidance](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app). Context7 lacked applicable coverage; official documentation was used.
- Apply and native restore approval retain source identity with the reviewed bytes. Final source/temp checks, metadata copy, file/directory synchronization, and preserved recovery artifacts have synthetic failure coverage. Malformed receipt records no longer hide valid backups. Unknown post-replacement outcomes are reported without automatic rollback.
- The lifecycle guard parses only Chrome argv, compares explicit canonical user-data roots, and blocks unknown/default/malformed/helper state. NSWorkspace is a snapshot and cannot rule out all restart races or unlisted processes. No real-browser success is implied.
- The maintainer approved a dedicated synthetic profile and separate verification connection on 2026-10-24. The two-launch experiment observed `Bookmarks`, `EncryptedBookmarks2`, and `BookmarkMergedSurfaceOrdering`. Discovery correctly restricted the plaintext source and apply was rejected without backups or source modification. No encryption flags, data deletion, account sign-in, or shared-profile changes were used. See the [experiment evidence](validation.md#dedicated-chrome-storage-experiment--2026-10-24). Authorized sync accounts/devices remain unavailable.


## Observed dedicated-browser boundary · 2026-10-24

Chrome for Testing **153.0.8010.52**, on macOS **27.0.1 (26A434)**, with a fresh synthetic custom user-data root, no account and no encryption feature overrides, created encrypted and ordering companions. The plaintext file remained parseable with three synthetic bookmarks and an exact app no-op serialization. It also retained the same bytes across an unedited browser restart. Neither observation establishes which file is authoritative or that Chrome adopted app edits.

The [version-pinned encryption implementation](https://chromium.googlesource.com/chromium/src/+/refs/tags/153.0.8010.52/components/bookmarks/common/bookmark_features.cc) defines multiple stages: writing both files with cleartext reads, preferring encrypted reads, and writing encrypted only. File presence alone does not identify the active stage. The [storage implementation](https://chromium.googlesource.com/chromium/src/+/refs/tags/153.0.8010.52/components/bookmarks/browser/bookmark_storage.cc) selects a primary writer and may write a secondary file. Do not infer plaintext authority from readability, a stable checksum, or default source flags; the experiment did not establish the runtime feature stage.

The app therefore keeps this combination **read-only with unverified freshness**. Encrypted-only profiles and separate ordering/account stores are not supported by the current adapter. Before enabling writes, identify all authoritative files, their identity/order metadata and the runtime feature stage; validate a recoverable transaction and browser-model adoption. Do not delete companion files or disable encryption to make the gate pass. The shared discovery check now runs again inside apply/restore before backup and before replacement. Cached connection restrictions cannot authorize a newly mixed store. `StorageCapabilityTests` covers companion names, companions appearing after review or at the final lifecycle check, and restore rejection with preserved originals/backups even within an otherwise writable test root.

Normal termination targeted only the recorded dedicated PID, executable and explicit user-data root; two launches/exits completed. Other unknown/default/helper browser states kept the aggregate lifecycle guard true after this instance exited. They were left running. This is conservative blocking evidence, not proof that a selected profile can safely be written while other browsers run.


## Code/structure verification checkpoint · 2026-10-24

The bounded pass completes 86 Swift tests (64 core + 22 app-state), catalog/compiled-resource checks and previous-Release synthetic Workspace v1 compatibility. See the [evidence map](code-verification.md). Descriptor-based profile reads reject symlink/nonregular/nonlocal inputs and detect changes during the read. Separate ordering companions now restrict writes; encrypted-only stores appear in discovery with `hasPlaintext == false`, and connect/reconnect reports unsupported storage without reading encrypted payloads or replacing work. Mixed unreadable connection batches abort without modifying the workspace.

New metadata, extreme offsets and oversized persistence fail safely. The native search/navigation hooks invalidate hidden selection and drag authorization. These checks narrow failure paths; they do not enable encrypted/account/order-store writes or close TCC, actual browser-model adoption, sync, physical durability, native accessibility or language QA. External writes remain disabled.


## Encrypted-store activation gates · historical experiment, 2026-10-24

**Scope change · 2026-10-25:** encrypted-bookmark support and further implementation are deferred. The native Settings → Labs item is an off, disabled “Planned” placeholder. No Keychain access or native encrypted-store activation is implemented. Keep encrypted-only connections unsupported and all mixed-store write restrictions; do not disable Chrome encryption or remove companions to make plaintext validation pass. The historical evidence and conditional gates below do not put activation in the current plan.

The [encrypted-store core](encrypted-store-adapter.md) now passes a dedicated local v10 dual-copy browser-model adoption and restore proof, with empty ordering and no account. Copy equality is verified on decoded bytes; no runtime-primary guess or encryption feature override is used. Complete-set journals/backups and raw identity/metadata rechecks have interruption fixtures. Only the observed quarantine copy encoding can restore exact source bytes on a new destination without changing protection flags; other changes fail closed.

This narrows the unresolved format question, but native activation still requires explicit real browser credential authorization, file-set review/receipt/history/recovery integration and permission/lifecycle capability gating. The production aggregate guard was not substituted by the QA runner's controlled no-launch assumption. Account/custom-ordering and general restart/power-loss/sync combinations remain unsupported/unverified. See [ADR 0005](adr/0005-local-encrypted-store-boundary.md).


## Guided connection checkpoint · 2026-10-25

Task 1.7 now separates normal empty startup from explicit synthetic QA. Staged profile discovery and exact supported selection import are fixture/native-render checked, with retained Base/Ours, atomic selected-failure handling and disabled unsupported entries. Installed Release 9 passes separate onboarding and editing smokes. Actual Chrome-folder access/TCC and freshness are still pending under 1.3/1.6; this does not enable external writes or encrypted support. See [connection scope](profile-connection.md) and [evidence](validation.md#guided-profile-connection--2026-10-25).

### Direct connection scope · 2026-10-25

Task 1.8 attempts default-location discovery only after Connect Chrome. Matching saved grants may be reused; normal read failure stops with in-app guidance. Secondary folder validation accepts only the requested local folder; malformed stores or workspace save errors do not become broader-access requests. Synthetic missing/denied and atomic-failure tests do not establish TCC approval, revocation or real Chrome-format freshness. External writes and encrypted support remain gated. See [ADR 0006](adr/0006-user-initiated-profile-discovery.md).

### Ego Lite preview gate · 2026-10-25

App-bundle metadata and Chromium path rules establish only a candidate default location. Synthetic routing/parser/import tests cannot establish Ego runtime authority or compatibility. Expose recognized plaintext import only as experimental and read-only, retain its warning, and reject unknown/encrypted-only selected payloads atomically. Native OS consent, access persistence/revocation, actual Ego formats and restart/sync acceptance remain unverified. No actual user-profile probe or Keychain access is part of this change.

### Dedicated permission guide · 2026-10-25

The maintainer confirmed a Chrome read-permission failure through a screenshot. The dedicated guide reuses exact-folder access and normal read checks; retries cannot mark access granted, Back preserves Base/Ours and selection, and owned mode-000 fixtures model repeated denial/recovery. System Settings opening uses public AppKit APIs without pane automation or permission writes. Actual Chrome TCC approval, native picker grant/cancel and revocation remain pending; synthetic POSIX permission restoration is not TCC evidence.

### macOS 27 permission research follow-up · 2026-10-25

Apple’s release notes document default denial for other teams’ app data; Mozilla records a targeted Google Chrome switch under the requester in Files & Folders. Verify the installed Galmuri row/switch and read behavior rather than assuming they exist. Test the same binary after relaunch and a replacement ad-hoc binary separately. A successful folder selection is not persistent-grant evidence; task 1.12 implements underlying EACCES/EPERM diagnostics and fresh selected-URL priority with synthetic regressions. Chrome on macOS 27+ gets conditional Settings-first guidance except for known EACCES; no particular TCC service is inferred from EPERM. Existing direct-write/encryption gates are unchanged.

### Files & Folders navigation · 2026-10-27

The installed macOS 27.0.1 Privacy/Security extension advertises the Settings URL scheme and contains the `Privacy_FilesAndFolders` anchor. A native NSWorkspace navigation probe succeeded and the Settings accessibility window title became **Files & Folders** (Korean: 파일 및 폴더). This verifies pane navigation on this host, not public API stability, a Galmuri entry, authorization, grant persistence or write access. The app uses a normal Settings launch on immediate URL rejection and always displays the manual path for silent destination failures. Test injected URL rejection, missing app and failed fallback; keep actual permission changes with the maintainer.

### Maintainer-provided app row · 2026-10-27

The maintainer’s screenshot shows an expanded **Galmuri** entry with **Google Chrome** off under Files & Folders. This supplies UI-presence evidence that was previously absent; it is not proof of a working grant, same/replacement-build identity, relaunch persistence or source writes. A bounded review of the installed Settings extension and external references did not establish a reliable app-row-targeted URL. At task 1.14 the shipped action retained the verified pane-level route with manual app selection. Task 1.15 subsequently received explicit approval for the separate Accessibility mechanism described below; no speculative URL parameters were added.


### Withdrawn Release 16 Accessibility validation · 2026-10-27

The explicit opt-in request is separate from Chrome data access. Check unbundled/unnamed identity rejection, complete unique own-row snapshots, exact role hierarchy, pane language, unreadable/duplicate states, finite visible geometry and scroll direction through the actual policy used by the adapter. Guard each mutation with cancellation, trust, exact Settings process identity/foreground and fresh parent/row validation; never target a permission control. Failed/timed-out disclosure is not repeated, since an action may already have been delivered. Bound discovery, messaging, post-action confirmation and page scrolling; cancel on view exit.

A production-source adapter probe under existing QA trust observed expansion/visibility in normal and reduced Settings windows with the permission value unchanged. This remains separate from actual installed-Galmuri trust. Required manual acceptance: request from the installed Release, enable its Accessibility grant, navigate/expand its actual row, manually grant Chrome access and Check Again, revoke trust, relaunch the same build, and inspect a replacement ad-hoc build. Unknown OS/layout/language and ambiguous app identity must preserve manual navigation. Never automate grant changes to complete these checks. [Decision](adr/0008-optional-accessibility-settings-navigation.md); [evidence](validation.md#optional-accessibility-settings-navigation--2026-10-27).


### Freeze containment · 2026-10-27

A maintainer-reported freeze/reboot invalidates treating the preceding adapter and policy checks as sufficient native stability evidence. Release 17 removes the AX implementation/callers, trust prompt and passive checks. Retain ordinary pane/manual routing and its injected launch tests; verify production code/binary has no Accessibility API calls, obsolete strings/tests are gone and workspace/data boundaries are unchanged. Do not reproduce on the affected machine. Existing OS records are preserved. Static MainActor synchronous IPC and cooperative deadlines establish a responsiveness risk, not a proven kernel/WindowServer cause. Actual grant acceptance and future automation are paused. [Incident review](research/accessibility-freeze.md).


### Withdrawn Settings automation boundary · 2026-10-27

Task 1.17 records the second review and maintainer rejection. The Release 16 external UI mechanism is withdrawn, not awaiting optimization or ordinary acceptance testing. Do not inspect/control another app’s UI, request Accessibility/Automation for connection, substitute another automation API or add a one-shot variant. Keep injected one-shot pane/manual routing and Galmuri’s own accessibility. Bounded own loops do not prove a bound on external call/server work. No new incident reproduction or log diagnostics are required by this review. [Decision](adr/0008-optional-accessibility-settings-navigation.md).

### Folder-first consent · 2026-10-27

For task 1.19, verify default-denial versus selected-folder-denial routing, EACCES separation, exact native panel initial directory/button/constraints without showing it, custom browsing, selected-URL priority and preservation/cancellation. Rendering fixtures distinguish initial Chrome consent from later Settings fallback. Actual protected-folder approval, confirmation availability, TCC effectiveness and same/replacement-build persistence remain under 1.3/1.6; do not infer them from a configured panel or chmod fixture. No source writes, OS control automation or foreground polling are added.


### Per-file source evidence and plaintext import · 2026-10-27

Task1.20 verifies regular/no-follow descriptor metadata and read access without loading all payloads, timestamp reporting, unreadable/symlink/nonregular/oversized states, encrypted/backup-only visibility, and mixed/empty-ordering plaintext eligibility. Use invalid or unreadable companion bytes to demonstrate that their contents are excluded. Verify selected plaintext import and unchanged companion bytes, persistent source-write restriction and atomic forced-unreadable failure. Existing readData parsing/staleness and apply/restore companion rechecks remain authoritative. Inventory dates/types are not Chrome authority/freshness verification; do not change original-write gates, decrypt or inspect real browser data to prove this UI.


## Pre-use source refresh and direct-write decision · 2026-10-27

Explicit refresh may read a supported plaintext disk snapshot while retaining independent local edits through three-way review; it is not proof of the running browser model's latest/full contents. Bind acceptance to the request/profile/Base/Ours and a second matching source identity/raw fingerprint/classification; archive the previous workspace before advancing Base. Keep companion payloads excluded and unsupported write restrictions retained.

The current CFT153.0.8010.52 dedicated three-bookmark fixture again creates `Bookmarks`, `EncryptedBookmarks2` and `BookmarkMergedSurfaceOrdering` on normal initial launch and restart without any encryption-feature overrides. The agent inspected only plaintext and file inventory, not encrypted contents. Both unsupported apply attempts are rejected with identical original bytes and zero receipts. Unknown/default browser roots also keep the aggregate exit guard conservative. No successful plaintext apply/adoption/restore or sync claim follows. In-scope production direct writes stay disabled; the previously deferred encryption/Keychain decision is not overridden. Do not ask the maintainer to exercise original writes during real use.


## Proposed Chrome API route · 2026-10-28

The initial 2026-10-28 [API bridge review](chrome-api-bridge-plan.md) was planning only; the 2026-10-29 checkpoint below records subsequent implementation. It would add a per-profile extension and Native Messaging host, keep Chrome running and use its live bookmark model. File-exit checks, raw JSON serialization and original-byte recovery cannot simply be reused for this backend. Preserve 3-way semantic merge and explicit approval, but require separate connection/node identities, managed/multiple-root capabilities, versioned workspace migration, preconditioned operation journals, partial-success handling and API-visible recovery limits. There is no exposed multi-operation transaction/CAS; event checks and rereads detect some changes but do not eliminate races. Permanent deletion/recreation cannot promise original IDs/dates/metadata.

Before any write, verify native-host registration and profile pairing on the actual dedicated macOS/browser configuration, including protected host-manifest locations and Debug/Release separation. The read proof must cover same-URL items, API root identity and v1 workspace preservation; the write proof starts with reversible local-subtree operations and requires normal browser restart/adoption. Deletion, account/cross-store operations and sync each require additional gates. Current app/format/lifecycle restrictions remain untouched, as do the rejected external-UI-automation boundary and deferred encrypted-file integration.


### Stage A implementation boundary

The pairing-only checkpoint is described in [ADR 0009](adr/0009-optional-chrome-api-bridge-proof.md) and its [guide](chrome-bridge-proof.md). Eight new Core tests cover bounded private handshake files and framing; the extension client and packaged host have independent tests. A QA-only extension worker in dedicated CFT profiles exercised native-host lookup, profile/session separation, app-Core approval, Chrome acknowledgement, normal disconnect and reconnect. At Stage A the product extension had no `bookmarks` permission or background worker; the later API checkpoint adds bookmark access without a product background worker. This does not close API model, write, restore or sync gates. Protected actual Chrome host registration and physical native/extension interaction remain unverified.


## API editing checkpoint · 2026-10-29

The [API workspace implementation](chrome-api-workspace.md) now has separate scope/opaque-ID projection, app persistence with revision/lock guards and unchanged file workspace v1. Approved-session chunks are bounded to 32 KB each, 8 MB raw/20,000 nodes/64 levels for snapshots; apply targets are capped at 10,000 nodes and a sub-8 MB job. The reviewed source/working/target and per-call intent/results remain private. Existing read-only fields and timestamps do not become writes or metadata conflicts. New browser nodes preserve the same minted mapping through detached merge and review.

A dedicated CFT proof covers actual create/rename/move/order/soft removal, existing-ID restoration, independent browser additions, post-update response loss, persisted retry blocking, explicit adoption and subsequent apply, followed by normal browser restart/reread. Ordinary hosts remain write-disabled; test writes require independent API-write markers plus the explicit flag, and all mutations remain within a writable local scope. Host liveness checks compare owner PID, UID, kernel start timestamp and exact app executable before each new mutation intent. Already in-flight calls and final-check races remain possible.

This does not establish real Google Chrome host-registration/TCC success, account/cross-store operations, permanent deletion, account-wide sync/rollback, abrupt process/power-loss/disk-full acceptance, large/deep-folder performance or complete native accessibility. Existing raw-file gates remain unchanged. See the validation record for completed checks, not the design proposal as evidence.


## Unresolved API transport and task-lifetime gates · 2026-10-29

The [remaining-boundary check](validation.md#api-remaining-boundary-check--2026-10-29) adds synthetic client/model and installed-host rejection evidence. It does not close Stage D. An accepted <8 MB/10,000-node job can produce a progress/result payload >=32 KB; unlike snapshots/jobs, those records are not chunked. A 600-item source plus 300 additions reproduces refusal after 96 synthetic creates. Task 4.14 must align transport/preflight bounds before any real-user write gate is opened.

Task cancellation preserves pending work but only stops the app's response wait; it sends no stop signal to the extension. The native view owns unstructured button tasks without a stop action or explicit disappear-cancellation path. Define and implement stop/lifetime semantics, then prove no new calls after acknowledged stop while allowing an already-started call to finish. Current progress stores retain the latest state, not a full append-only operation history. Actual process death, power loss, disk full, real registration/TCC and remote sync remain distinct unverified cases.


## Release27 transport/stop refinement

The preceding 2026-10-29 transport blocker is resolved in the [refinement checkpoint](native-refinement.md). Protocol2 negotiation rejects old peers, progress/results are chunked under the same bounds as snapshots/jobs, and sequential compact per-call files replace the growing-map progress record. A dedicated Release proof with >600 synthetic source bookmarks creates 300 additional items and receives a >32 KB final result. A separate stop attempt records its first intent, delays an already-started QA update, receives a host stop acknowledgement and starts no later creates; reviewed adoption and normal restart pass. These do not prove atomicity, power-loss/disk-full behavior, untested process races or remote sync. Physical input/accessibility and actual Chrome registration remain open.


## Labs apply boundary · 2026-10-29

API and direct-file entry points are now in Settings → Labs. A standalone Release extension source folder and matched bundled archive do not grant access or enable writes. Package checks verify Debug/Release extension ID/native-host matching, source/archive equality, no website permissions/content scripts and included license. The native host still requires separate supported registration, and normal sessions remain read-only. Existing API dedicated marker/flag gates are unchanged.

`canReviewFileApplyExperiment` requires a pending supported unrestricted profile under the app-owned synthetic root, with no busy/review/connection state. Opening its review does not mutate/snapshot originals or bypass browser exit checks; an active browser still blocks loading/applying. Ordinary review uses the refresh/merge workflow. No exit watcher, automatic write, force quit or fallback from partial API failure is added. Existing schema/data/signing identities, actual-profile permission gates and the withdrawn external UI boundary remain unchanged. See [Labs](labs.md).


## Pending review and opted-in extension evidence · Release30

Normal pending review compares the immutable saved Base with the captured working copy, without disk reads, merge/adoption acknowledgement or source mutation. A source refresh separately previews working→merged changes; an empty refresh must not be interpreted as no pending edits. Root folder membership changes and removed Base records remain visible and independently counted.

Two independent Labs flags default off in a versioned, bounded private `labs.json` sidecar. Reading or saving malformed settings cannot enable them or replace workspace data. File apply/restore execution rechecks the flag, including a previously prepared review. Enabling either flag does not relax the existing app-owned/test-session or format/permission gates. API-off closes the app tools and retains existing stop-on-disappear semantics; it is not remote revocation of an already-approved Chrome port.

Selected-profile evidence reads only bounded `Preferences` and `Secure Preferences` JSON under the selected source directory, through the existing saved scoped grant and no-follow/regular-file/change-detection reader. Match only the packaged Debug/Release extension ID. Chromium153 commit `78e5e45d4bb41035e17ea4da2cc257f496416ac9` defines `extensions.settings` in [pref_names.h:72](https://chromium.googlesource.com/chromium/src/+/78e5e45d4bb41035e17ea4da2cc257f496416ac9/extensions/browser/pref_names.h#72), looks up individual dictionaries in [extension_prefs.cc:518](https://chromium.googlesource.com/chromium/src/+/78e5e45d4bb41035e17ea4da2cc257f496416ac9/extensions/browser/extension_prefs.cc#518), and names both files in [chrome_constants.h:101–111](https://chromium.googlesource.com/chromium/src/+/78e5e45d4bb41035e17ea4da2cc257f496416ac9/chrome/common/chrome_constants.h#101). This justifies a bounded on-disk record observation, not a supported Chrome installation-enumeration API or active-state claim.

Do not open an unpacked extension’s arbitrary recorded path, decrypt preferences, inspect another app’s UI, scan every profile, infer absence from failed access, or bind a file profile to a Native Messaging installation by its display name. A missing record is “not detected”; absent/inaccessible/invalid/changed metadata is unavailable. Presence can be stale or disabled. Discard late checks after off, profile/source changes or a newer request; stale completion must clear its own busy state without clearing a newer check. Actual Chrome registration/activation/pairing remains separate acceptance.


## Registered-profile batch inspection · Release31

The explicit scope is now all profiles saved in Galmuri, superseding Release30’s selected-only controller. An off→on UI transition starts one pass; later scans are manual. Opening Settings, changing its page or selecting a different editor profile does not trigger a scan. Cache and attempt times are memory-only; after restart, even a persisted on switch needs manual rescan. No Local State rediscovery or unregistered profile traversal is introduced.

Each iteration resolves that captured profile’s existing saved grant and uses the same bounded/no-follow record reader. One failure becomes an unavailable row and does not prevent later rows. Publish only when the batch token, opt-in, profile UUID and source URL are still current. Removed/rebound rows cannot reappear from late reads, and a newer batch supersedes callbacks. Off clears the cache and prevents another profile read after the current read returns. Changing editor selection must not cancel or relabel an all-registered batch. The record/pairing/activation and original-write boundaries remain unchanged. [Settings behavior](labs.md).
