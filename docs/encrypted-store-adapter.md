# Encrypted-store adapter checkpoint

2026-10-24 · [ADR 0005](adr/0005-local-encrypted-store-boundary.md) defines the development boundary. This checkpoint implements and verifies a core adapter and an app-owned transaction path. **It does not activate general-profile writes in the native app.**

## Current product decision · 2026-10-25

The maintainer deferred encrypted-bookmark support. Settings → Labs shows only an off, disabled “Planned” placeholder in English, Korean, Japanese and Simplified Chinese. There is no activation preference, Keychain access or native encrypted-store integration. The disconnected experiment's source and synthetic tests (`ChromiumBookmarkCipher`, `ChromiumBookmarkStore`, `ChromiumStoreCoordinator` and their two test files) were removed on 2026-11-12; the findings and evidence below remain as the historical record. The removed source remains in the repository history, in the initial commit. No further encrypted-store implementation is planned in the current scope. Native external writes remain disabled; encrypted-only profiles stay unsupported and mixed stores retain their safety restrictions.

## Implemented and checked (historical experiment)

- `ChromiumBookmarkCipher`: explicit in-memory password bytes, the pinned macOS `v10` envelope and no Keychain reads/writes. System CommonCrypto is used; no third-party runtime dependency or stored key is introduced. Independent OpenSSL interoperability and malformed-input checks pass. CBC has no authentication tag; canonical encoding, JSON/codec checks and identity/hash validation remain separate layers.
- `ChromiumBookmarkStore`: local plaintext, encrypted-only, or byte-identical dual copies; optional empty-object merged ordering. Exact no-op bytes/presence, existing identities/metadata/order and duplicate URLs are preserved. Unknown envelopes, missing keys, disagreeing copies, account/custom ordering and unverified file sets fail closed. An encrypted-only edit never introduces a plaintext copy.
- `ChromiumStoreCoordinator`: an explicitly configured app-owned root; complete-set identity/attribute/inventory snapshots, original backups, staged replacements and durable journals. Exact no-ops return without replacement. Known Chrome `.bak` sidefiles are captured and backed up but never replaced. Restore backs up the current set; interrupted recovery recognizes original/staged states and refuses newer writers, including another interruption during recovery. Receipts can be reloaded from their journals.
- Metadata: mode, ownership, flags, ACL and all raw xattrs are checked. Apple `copyfile` applies quarantine through its quarantine API. For the observed four-field `0081` case with matching UUID or matching empty events, a copied destination may restore the exact source quarantine bytes with `XATTR_REPLACE`, then must pass full raw metadata equality. No attribute is removed and no protection flag is weakened. Unknown encodings or any other difference remain blocked. Raw source/journal/stage checks were not normalized or relaxed.

The six descriptor helpers shared from `ApplyCoordinator` became module-internal without behavior changes. Existing public APIs and Workspace schema 1 remain compatible.

## Actual Chrome proof

Environment: visible Chrome for Testing **153.0.8010.52**, macOS **27.0.1 (26A434)**, no account/sync, the authorized dedicated synthetic profile and separate DevTools connection. The recorded mock-keychain flags establish the public test password; no real credentials were accessed. No bookmark encryption feature override was used.

The temporary, local QA observer used Chrome's bookmark API to observe the actual model and create one independent browser edit. It existed only in the disposable profile, was not bundled with Galmuri, and is not a product extension requirement. Shared QA/user browser profiles were untouched.

| Step | Observed result |
| --- | --- |
| Read actual encrypted file | Decrypted bytes exactly equal the 1,756-byte plaintext copy; re-encryption reproduces the 1,763-byte encrypted copy |
| Base/Ours/Theirs | Ours adds folders/bookmarks, changes an existing name/URL, moves/reorders and removes an item; Theirs changes a distinct item through Chrome's API |
| Group apply | Merge retains the independent browser edit; full-set backup/journal/rechecks complete while the dedicated browser is stopped |
| Restart/model | Chrome's live model has the expected four bookmarks, numeric IDs, names, URLs, parents, child order, additions and removals, including distinct same-URL items |
| Exit/reread | Full persisted GUID/ID/date/metadata/order tree matches the expected adapter output |
| Restore/restart | Current set is backed up; original pre-apply set returns to three bookmarks and matches both the live model and full persisted reread. The independent pre-apply browser edit is retained |

Two bounded apply/restart/restore rounds passed; the second explicitly edits an existing bookmark URL. Chrome's desktop API omits the empty mobile permanent node, which was checked in the persisted full-tree reread.

The initial synthetic seed used noncanonical permanent-root GUIDs. Chrome's first native serialization supplied its standard root GUIDs; merge correctly rejected the stale Base before any app replacement. A fresh Base was captured after initialization, without guessed identity remapping. Another pre-commit attempt rejected quarantine copy differences before replacement; the exact-copy correction above was regression-tested before retrying. These failures remain evidence of the guards, not passed adoption attempts.

This proof uses a **controlled no-launch interval** owned by the QA runner. Separate renames are not atomic, the production aggregate browser guard remains conservative, and a noncooperating restart can still race final checks. Do not extrapolate this proof to arbitrary live profiles, all encryption stages, account stores or crash/power-loss durability.

## Test and artifact evidence

`swift test`: **107 tests pass — 85 core + 22 app-state**. The 21 new tests cover the cipher/store and transaction/quarantine cases. `python3 scripts/check-localization.py --self-test` passes with **194 entries** in four locales and 107 literal native keys. Debug and Release packaging compile the resources and verify their signatures.

Ignored local evidence lives in `build/qa/20261024-adapter/`: source research, working Base/Ours, expected/native model results, apply/restore receipts, persisted reread logs, full tests, build and installation/cleanup receipts. Original test-store backups/journals are retained in the private owned fixture's `AdapterBackups` directory. No keys are stored in journals/receipts; all bookmark values are synthetic.

The checkpoint review installation was **Release 0.1.0 (6)** at `/Applications/Galmuri.app`. It contains the core work; its existing native external-source write restriction is unchanged.

## Deferred work if support is separately resumed

1. Explicit browser identity and user-initiated real Keychain authorization, with cancellation/denial handling, no credential creation/replacement, and no persisted/logged keys.
2. Native encrypted-source connection/review and complete file-set approval, group backup/history/restore/recovery UI, preserving Base/Ours on every failure.
3. Permission/lifecycle and version/account capability gates for activating the native write path. Keep unknown formats/account/custom ordering and unverified restart conditions blocked.

These items are not the next active tasks. If the maintainer separately resumes this feature, user-assisted checks would cover the actual permission/Keychain dialogs, gestures/focus/VoiceOver, language/layout quality and the complete app flow. Sync accounts/devices and isolated physical failure scenarios are separate validation work, not work to silently delegate entirely to the user. Publication remains deferred.
