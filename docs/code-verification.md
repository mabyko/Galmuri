# Code verification and remaining acceptance

This record separates code/fixture evidence from operating-system, browser and human acceptance. It accompanies [TASKS.md](../TASKS.md), which remains the only progress checklist. Results are bounded to the tested local build and synthetic inputs; this is not a public release acceptance.

## Verification layers

| Area | What code/fixtures can establish | What still needs the real environment |
| --- | --- | --- |
| Permission handling | Cancel/no-op behavior, unusable/missing/out-of-scope grants, offline edits, same-path reconnect and persistence rollback | Native picker, actual TCC denial/revocation, privacy reauthorization after ad-hoc reinstall |
| Editing | Tree invariants, folder/multi-selection moves, opaque drag tokens, filters, duplicate identity, exclusion/undo, per-profile state | Actual pointer drag, keyboard focus/shortcut routing and VoiceOver navigation |
| Persistence | Reopen saved working copies, roll back failed edits, retain retryable Undo, preserve damaged workspace/receipts | Host permission changes and OS interruption during actual application use |
| Format preservation | Exact no-op bytes, precise IDs/dates, GUIDs, duplicate URLs, unknown fields, checksums and structural validation | Authoritative encrypted/account/order stores and edited browser-model adoption |
| Three-way review | Base/Ours/Theirs fixtures, explicit conflicts, source/working-copy approval invalidation, valid result trees | Human review clarity and complete native interaction flow |
| Apply/restore | Identity/hash binding, fresh capability checks, protected backup/receipt paths, simulated restart/interruption, retained recovery artifacts | Browser restart races, actual disk-full/power-loss durability and account synchronization |
| Localization | Catalog completeness, placeholders/plural structure, resource compilation, basic runtime selection/fallback | Native-speaker review, long text/enlarged UI layouts, VoiceOver pronunciation and usability |
| Packaging | Debug/Release identity separation, compiled resources/icon, signature, installed-path smoke, compatible synthetic schema-1 workspaces | Distribution signing/notarization and end-user permission behavior |

## Completed code checks · 2026-10-24

**86 Swift tests pass: 64 core + 22 app-state**, including 20 new tests in this pass. The complete command is `swift test`. Focused suites and the final combined run use synthetic/disposable files; no real user/shared QA browser profile was used.

| Finding or verification | Result and evidence |
| --- | --- |
| New nested decimal metadata could bypass the original format restriction | Serialization now rejects it; no-op bytes and the parser remain unchanged (`CoreModelVerificationTests`) |
| Extreme reorder offsets could overflow | Overflow-safe addition treats out-of-range offsets as no-ops (`CoreModelVerificationTests`) |
| A save could replace a good workspace with output too large to load | Encoded workspaces at or above 100 MB are rejected before replacement; previous bytes remain readable (`CoreModelVerificationTests`) |
| Ordering-only and encrypted-only stores were not identified fully | Ordering companions restrict writes; `hasPlaintext` exposes unreadable discoveries without decoding encrypted bytes; native connect/reconnect rejects them clearly (`StorageCapabilityTests`, `AppStoreVerificationTests`) |
| Filesystem APIs could accept nonlocal URL path components | Read, review, write and receipt boundaries now require local file URLs (`IOVerificationTests`) |
| Profile reads used separate metadata/path checks | Bounded descriptor reads now reject redirected/nonregular files and detect changes during reading; symlink, FIFO and oversized-file checks pass (`IOVerificationTests`) |
| Hidden selection could survive a search change | Search/navigation clear selection and drag authorization; build/static verified, actual gesture acceptance remains pending (`RootView`) |
| App-state persistence and review failures | Filters/duplicate identity, exclusion/undo, independent profile Undo, failed edit/Undo/connect persistence, failed reread invalidation and unsupported connection preservation pass (`AppStoreVerificationTests`) |
| File recovery trust boundaries | Corrupt backup/receipt, outside paths, nonlocal source, temporary inode swap, late hardlink and late store-companion cases preserve the original and expose available prepared history (`IOVerificationTests`, `StorageCapabilityTests`, existing recovery tests) |
| Merge and Workspace v1 | Independent ordering and metadata conflicts are deterministic and leave inputs unchanged; tampered Base is rejected; persisted identities/dates/unknown integer metadata survive (`CoreModelVerificationTests`) |
| Catalog structure/resources | 186 keys cover all four locales; format positions/types and plural branches checked; checker self-tests and 124 compiled-resource assertions pass |
| Upgrade compatibility | A disposable workspace written by installed Release 0.1.0 (4) loads and round-trips under the new code; schema remains 1 and original bytes remain unchanged |

Reproduce the catalog checks with `python3 scripts/check-localization.py --self-test`. Both Debug and Release bundles build with valid ad-hoc signatures, separate identifiers, compiled icons and localized resources. At that checkpoint the review installation was **Release 0.1.0 (5)**; installed-path smoke and state-preserving cleanup are recorded in [validation](validation.md#code-and-structure-verification--2026-10-24).

Public signatures and persisted Base/parser representation remain compatible; `DiscoveredProfile.hasPlaintext` is an additive discovery property. No dependency, data migration, encryption override or external write capability was introduced. Mixed connection batches containing an unreadable encrypted-only store abort before changing the workspace; connect a supported profile directory separately when needed. Readable mixed-format snapshots remain read-only with unverified freshness.

Ignored detailed evidence is in `build/qa/20261024-code-verification/`: `full-tests.log`, `localization-check.log`, `ui-localization-assertions.log`, `compatibility.log`, build logs and installation/cleanup receipts. A separate bounded assertion harness passed a 250-sibling independent-order merge/round-trip and a 64-folder nesting/no-op round-trip (`stress-check.log`). This is not an interactive app benchmark or an unbounded scale guarantee. The bounded review is complete; no unresolved failure remains in the checks that ran. Extreme depth/size, all malformed inputs and noncooperating-writer outcomes remain unproven.

## Remaining acceptance

- Native permission flow: select the synthetic copy through the picker, cancel/reselect, relaunch and exercise actual denial/revocation while retaining offline edits. Do not reset TCC or broaden access automatically.
- Native editing/accessibility: exercise multi-selection drag, Move and ordering shortcuts, focus behavior, exclusion/undo and VoiceOver in the four supported locales.
- Language/layout review: inspect English, Korean, Japanese and Simplified Chinese, including long diagnostics, enlarged text, plurals and literal user content.
- Browser storage: identify the authoritative encryption stage/file set for the observed Chrome for Testing build, validate the adapter and recoverable file set, then run edited adoption and restore. A stable readable plaintext file is insufficient.
- Synchronization: use separately authorized disposable accounts/devices for offline/online edits and convergence. Existing signed-in user profiles stay untouched.
- Failure environment: verify real disk-full, permissions, process restart and interruption behavior in an isolated environment. Fixture failures cannot prove all physical power-loss or noncooperating-writer outcomes.
- Publication: GitHub, CI, distribution signing and release publication remain deferred until separately requested.


The subsequent [encrypted-store checkpoint](encrypted-store-adapter.md) reaches 107 passing tests, 194 catalog entries and bounded dedicated Chrome adoption/restore evidence. General-profile credential authorization and native activation are still development tasks, followed by the remaining OS/human/environment checks.
