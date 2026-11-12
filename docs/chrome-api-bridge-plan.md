# Chrome bookmark API bridge: implementation proposal

Status: **bounded API read/edit/apply checkpoint implemented and locally verified; broader acceptance remains gated** · 2026-10-29. The original proposal below records the 2026-10-28 design; [current setup and limits](chrome-api-workspace.md) and [ADR 0010](adr/0010-semantic-api-workspaces-and-recoverable-apply.md) describe the implemented scope.

**2026-10-29 implementation update:** API snapshots, separate persistent working copies, native editing/3-way review, dedicated local-scope apply, recoverable removal/restore and interrupted-state adoption are implemented. See [current behavior and limits](chrome-api-workspace.md), [ADR 0010](adr/0010-semantic-api-workspaces-and-recoverable-apply.md) and the task tracker. Historical proposed stages below remain the design reference; they are not blanket acceptance of production/account/sync or physical UI gates.

The maintainer first requested a design review, then authorized the staged proof and subsequent implementation. Workspace v1, real-user browser originals, permission records and deferred encrypted-file scope remain unchanged. The optional bridge supplements existing extension-free file working copies; unrestricted real-profile API editing is not supported.

## Recommendation

Try a small Chrome extension + Native Messaging proof before further offline-storage work. Keep the SwiftUI app as the editor and reviewer. The extension acts on the running profile's browser model through `chrome.bookmarks`; Chrome owns disk encryption and persistence. Galmuri neither decrypts bookmark files nor requests Keychain access. HTML remains the fallback when the bridge is absent or unsupported.

The main trade-off is installation/connection in every intended Chrome profile. This path does not automatically connect every installed profile, and it requires Chrome running during reads and apply. Verified browser exit remains a requirement for the separate file-writing path, not this proposal. No Accessibility, Automation, System Settings scripting, page scraping or posted input is involved.

## Evidence and limits

- [Bookmark API](https://developer.chrome.com/docs/extensions/reference/api/bookmarks): `getTree`, `create`, `update`, `move`, `remove` and `removeTree`; `bookmarks` permission; profile-scoped persistent opaque IDs; browser/managed-folder restrictions; potentially multiple folders of one `folderType`; `syncing` describes account storage rather than completed synchronization. The API does not expose raw GUID/sync-metadata preservation or a batch transaction/CAS primitive. Treat the latter as an API-surface limitation, not a tested claim that races are solved.
- [Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging): an extension connects to a registered executable through `connectNative`; Chrome starts that host and supplies the caller origin. Host registration, exact `allowed_origins`, bounded framed JSON and a stable executable path are required. A native desktop app cannot directly call the extension API. Google Chrome and current Chrome for Testing have distinct host locations.
- [MV3 lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle): workers can terminate and lose globals; a native connection extends lifetime but a host failure disconnects it. Persist progress and tolerate termination. Reconnect only with bounded backoff/user retry; never repeatedly reconnect and replay mutations.

Current official documentation was checked through Context7 library resolution and two focused queries, plus the official pages above. Current source was inspected in `BookmarkTree`, `MergeEngine`, `Workspace`, `AppStore`, `ProfileIO`, `ApplyCoordinator`, `Package.swift` and build identities. That initial design review installed/executed no extension or host and made no browser API calls; later implementation evidence is recorded separately in [validation](validation.md#chrome-api-workspaces-and-reviewed-editing--2026-10-29).

## Original proposed components and minimum permissions

| Component | Responsibility | Proposed change |
| --- | --- | --- |
| Existing SwiftUI app | Persistent edits, Base/Ours/Theirs merge, conflict review, explicit apply/restore | Add a distinct API connection and review mode; retain existing file connections. |
| Small Swift native-host executable | Translate Chrome's stdio messages to the local Galmuri session | Separate executable target; no UI, direct profile-file IO, arbitrary command execution or always-on launch agent. |
| Manifest V3 extension | Explicit profile pairing, semantic snapshot, validated API operations/results | `bookmarks`, `nativeMessaging`, `storage` only initially; popup/service worker, no content scripts or website host permissions. |
| Local transport | Link host instance and running app | Candidate: an app-owned Unix-domain socket with private permissions, same-user peer validation and paired-session authentication. Prove this before choosing it; no network listener needed. |

The implemented transport uses bounded app-owned private mailbox files rather than the candidate socket; see ADR 0010. The product client runs in an explicitly opened connection tab, with no background auto-connect.

`connectNative` is initiated by the extension. The GUI app must not assume it can start a Chrome extension by opening a native port itself. When Galmuri is closed, show a reconnect/open-app instruction; do not mutate in the background. Keep the native connection only for an active user session.

Host registration is an **early feasibility gate**: the user-level Google Chrome manifest is inside its protected data root, so this path does not promise all macOS access prompts disappear. Prove supported registration/lookup and relaunch with a dedicated browser before building the editor integration. A system-wide registration requiring administrative installation is a separate decision, never an automatic fallback. Verify custom test-root lookup instead of assuming default paths apply to it.

Use existing Debug/Release identities/data domains and separate extension/host registrations. Resolve actual new host names/extension IDs during implementation with bundle-ID guardrails; do not change current bundle IDs or register a team. Pin the unpacked extension ID for the local proof and validate the exact caller origin on both sides. Public Web Store/signing/distribution remains deferred.

## Pairing the correct profile

1. The user installs the bridge in the intended Chrome profile and explicitly chooses Connect to Galmuri in its popup.
2. A profile-local installation UUID, protocol version, session nonce and capabilities reach Galmuri. Show a short-lived matching code in both UIs; confirm the association and let the user name it.
3. Give this API connection its own persistent Galmuri UUID. An API connection is not a file-path permission grant and is not automatically equated with a saved disk connection.
4. Store pairing state locally, not Chrome sync storage. Reinstallation, cloned/duplicated installation identities, changed extension identity and ambiguous simultaneous sessions require re-pairing; account email, display name and URL are not identity proofs.

The API does not provide a trusted filesystem profile path or human account identity for this purpose. Do not ask for `identity`, `tabs` or `history` permissions merely to decorate a profile label. Wrong-profile prevention must work with two simultaneously connected profiles carrying identical node IDs and names.

## Snapshot model and reuse

Reuse the existing semantic tree/editor and 3-way merge where their invariants fit, not the raw file serializer/coordinator.

- API identity is `(connection UUID, API node ID)`. Maintain a persistent map to Galmuri's UUID node IDs; new app nodes acquire an API ID from `create` responses. Treat API IDs as opaque strings, without assuming current numeric spelling fits `Int64`. Do not derive identity from URL.
- Current `BookmarkTree.validate` requires UUID internal IDs and decimal `chromeID`; the API adapter needs a separate external-ID map and a semantic representation compatible with this validation. Never invent GUIDs or fake original Chrome JSON to satisfy `BookmarkFile` validation.
- `BookmarkTree.roots` can describe multiple roots, but current presentation/labeling assumes familiar file roots. Adapt root keys/sidecar descriptors for distinct API root IDs, folder types and local/account capabilities. Do not collapse two same-type roots. The synthetic API root and managed folders stay protected; preserve opaque IDs as supplied.
- Keep API-only read-only facts (dates, `syncing`, folder protection) outside merge-editable metadata. The current merge compares metadata too; define a backend semantic projection so Chrome's routine date changes and app-generated file dates do not cause false conflicts or become API writes. Browser-owned fields cannot be restored exactly through this API.
- `ConnectedProfile` currently requires a file URL and `BookmarkFile` Base; Workspace v1 reparses original bytes and enforces roots. Plan an explicit versioned API-connection representation and migration with an archived v1 workspace. Keep v1 load/import support and the existing file backend. Do not repurpose a fake file URL or a source-restriction string as an API connection. Schema changes need fixtures before integration.
- Existing saved file-based edits remain intact. First API pairing creates a separate Base from the browser model; no automatic migration of pending disk edits or HTML-imported identities. A later explicit reconcile can be designed separately.

Initially enable writes only inside one selected writable local subtree. Expose supported browser-model content with accurate read-only states; cross-store/account moves, root topology changes, managed writes and uncertain capability changes block. Expand to account writes only after dedicated identity and sync validation, not merely because a method exists.

## Review and apply

1. Read a browser-model Base after pairing and persist it. Edit Ours locally with existing editor safeguards.
2. On Review, request Theirs from the same paired live session. Build a bounded snapshot with event-generation checks; discard/retry with a small limit if events arrive while reading. These checks are useful consistency signals, not a lock on Chrome.
3. Merge semantic Base/Ours/Theirs, resolve conflicts explicitly, and review the resulting operation list. No full-profile reset or wholesale recreate is needed: target known API IDs.
4. Archive the API-visible before-state, mapping and reviewed plan privately. Re-read immediately before writes; changed session, capabilities or relevant contents invalidates approval and returns to review.
5. Apply one operation at a time with durable intent/result records and expected item/parent/sibling preconditions. Create parents first; map returned IDs; update/move existing items and verify sibling indices. Run final ordering with freshly read children. Process proven-safe deletions last and exclude all unsupported/protected targets.
6. Reread and compare API-visible editable semantics with the approved result. Advance Base only after successful verification, retain mapping/history, and distinguish local API success from restart persistence and remote sync completion.

Chrome and other extensions can still change the model between a read and a write. No browser-wide lock or compare-and-swap is supplied. Detect unexpected differences, stop and expose partial progress; do not advertise atomic apply or guaranteed race prevention. For the first proof ask the tester to avoid concurrent edits; later inject them deliberately.

## Interrupted apply, deletion and recovery

Persist request/session/plan IDs and each operation's state in the app, with extension-side durable acknowledgements where needed. Globals and an open port are not a recovery journal. Bind approvals to one connection/session/snapshot and reject duplicate, stale, oversized or out-of-order requests. Chunk large snapshots under a conservative per-message cap (for example 256 KiB), with bounded aggregate size/node count/depth and missing/duplicate-chunk rejection. No bookmark payloads or pairing secrets in routine logs; stdout is protocol only.

An interrupted mutation may have succeeded without its reply being recorded. Exactly-once `create` cannot be assumed: do not blindly replay it or identify its result by URL. Stop, reread, compare known IDs and durable results, and surface any unresolved operation for explicit recovery. Cancellation stops new calls; it does not undo earlier ones. An API exception may likewise leave earlier operations applied.

**First proof excludes destructive deletion.** Prove read, creation, rename, same-store move/order and recovery before adding it. Later deletion needs a deliberate product decision: a visible recovery-folder move within the same supported store may preserve IDs but changes browser contents and requires its own tests; `remove`/`removeTree` permanently removes originals, and snapshot recreation cannot restore their IDs/dates/hidden metadata. Do not call an API snapshot an original-file backup or promise lossless rollback. A backup can support reviewed semantic reconstruction, with new identity mappings and another 3-way comparison to avoid overwriting later changes.

## Implementation sequence and completion gates

These are the original staged gates; current progress is tracked only in [TASKS.md](../TASKS.md). Stages A–C now have bounded implementation/evidence; D–E remain partial. The table defines required evidence, not a second progress tracker.

| Stage | Scope | Required observable result |
| --- | --- | --- |
| A. Local transport/setup proof | Dedicated CFT profile, unpacked extension, exact host registration and hello/pairing; no bookmark writes | Verified profile-specific connection, version mismatch/error handling, bounded disconnect/reconnect, and no new broad OS permission. Record any setup grant rather than promising none. |
| B. API read + persistent model | Synthetic nested folders, same-URL duplicates, multiple API roots/read-only nodes; new connection schema | Complete API-visible snapshots, preserved separate identities/order after app/browser restart, v1 migration/archive regression tests and no user-profile reads. |
| C. Small reversible write proof | One local subtree: create, rename, move/order; no permanent deletion or account writes | Exact existing IDs retained, new-ID mapping persisted; API reread and normal dedicated browser restart adopt edits; reviewed compensation works within its documented limits. |
| D. Batch safety and recovery | Mixed edit plans, concurrent edits, lost replies, worker/host/app termination, stale approval and wrong-profile routing | No silent overwrite/replay; partial success and uncertain operations are visible; semantic recovery requires fresh review. No promise of atomicity. |
| E. Native integration and scope expansion | Review/restore UI, connection errors, four locales and keyboard/VoiceOver; later deletion/account-store gates | Correct backend-specific UX, clear recovery limits, dedicated sync acceptance for every claimed account combination; maintainer approval before broader real use. |

Tests would use Node's built-in test facilities for extension protocol/planning plus Swift tests for mapping/schema/merge/recovery. Real API adoption requires the approved dedicated Chrome environment and normal restarts, not mocks alone. Do not introduce Playwright/Puppeteer or operate shared/user profiles. Packaging tests must cover the host executable path surviving Release reinstall and exact Debug/Release registration cleanup while retaining user work and permissions.

## Initial decision before implementation · 2026-10-28

The recommended next implementation request is **Stage A only**, then inspect its evidence before further scope. It resolves the important uncertainty: whether per-profile setup and host registration are acceptably simple on this macOS. Choosing this route would relax the earlier extension-free goal and replace quit-before-write with live-session validation for API connections only. The maintainer authorized the pairing-only proof, recorded in ADR 0009. That Stage A decision did not authorize blanket production use. The subsequent 2026-10-29 checkpoint implements separately gated API workspaces/apply with the evidence and remaining limits linked above.
