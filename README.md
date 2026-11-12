# Galmuri · 갈무리

**Bring your bookmarks together. Refine them. Apply them back to your browser.**

English · [한국어](README.ko.md) · [日本語](README.ja.md) · [简体中文](README.zh-Hans.md)

Galmuri is an experimental **SwiftUI native macOS bookmark editor**. It brings multiple Chrome profiles into persistent working copies and merges app edits with the latest source before review. Existing file-based working copies do not require an extension. An optional per-profile extension bridge now reads the running Chrome bookmark model and supports persistent editing, three-way review and reversible apply in explicitly enabled dedicated tests.

## Status

Settings → Labs → API connections and editor opens the separate API workflow and profile approval. Extension installation includes a matched ZIP; the standalone Release folder in `Bridge/extension` is prepared for future GitHub downloads. Direct-file apply is also in Labs, restricted to app-owned synthetic test files; Chrome exit never applies changes automatically. See [Labs and installation](docs/labs.md). The extension requires `bookmarks`, `nativeMessaging` and `storage`, with no website permissions. Ordinary connections remain read-only at Chrome; only explicitly marked dedicated test connections can apply. Create/rename/move/order, recovery-folder removal, reviewed restore, interrupted-state adoption and normal browser restart have dedicated Chrome for Testing evidence. See [API setup, behavior and limits](docs/chrome-api-workspace.md).

Release27 fixes large progress/result transfer, adds acknowledged stop/current-state recovery and improves native navigation, multi-selection and drag targets. The interface uses quiet gray surfaces and muted blue actions/selection. Measured Core merge improvements and limits are in [native refinement](docs/native-refinement.md). Real-user writes, physical accessibility and actual Chrome setup/sync acceptance remain gated.

Release28 makes deleted items and folder-content changes visible in Pending Changes, with reviewed restoration. Connection details now open in a separate bounded sheet; saved edits and workspace compatibility are preserved.

Release30 adds independent, default-off persistent Labs switches. When API editing is on, Labs checks only the selected profile’s on-disk extension installation records, keeping activation/pairing unverified. Review changes now shows saved-source versus working-copy edits; Refresh remains a separate merge operation. Turning features off preserves saved work and does not unlock real-profile writes.

Release31 adds visible Settings links in the main sidebar and welcome screen, plus General/Labs navigation within Settings. API opt-in checks all profiles already registered in Galmuri once; later scans are manual, with per-profile evidence and check times. Editor selection does not trigger scans. No unregistered browser profiles are discovered, and record evidence remains separate from activation/pairing.

Release32 applies a code audit. HTML export now skips non-http(s) addresses and reports the count instead of failing; such bookmarks can be renamed. API editing normalizes changed addresses, orders items as displayed, keeps one restore checkpoint, refuses to start an apply shortly before the session expires and removes finished job files. Edits no longer re-read every source, unchanged edits are not saved, Undo keeps 100 steps and only the ten newest “before refresh” archive copies remain; “Disconnected” and “before import” archives are never deleted automatically.

Release33 completes the audit follow-ups. Review reading, merging, apply and restore run off the main thread, cannot be interrupted by closing their sheet, and restore reports whether it completed. API editing stores changed addresses the way Chrome does, including international host names, rejects addresses Chrome would change, and refuses an apply up front when the session has under two minutes left or a stored address is not in Chrome’s form. The disconnected encrypted-store experiment was removed, and the main table no longer logs an AppKit reentrancy warning.

Native local development is underway. The app includes a sidebar/table editor, nested folders, bookmark editing, multi-select move and same-profile drag movement, ordering, search, same-URL browsing, exclusion/undo, workspace JSON backup/import, and full/subtree Netscape HTML export. A real Swift three-way merge drives conflict choices and final review. Original backup, replacement, and restore currently work **only with app-owned synthetic test files**.

Connected file-based Chrome profiles remain read-only at the source; their app working copies can be edited even when folder access is lost. Choose the original folder again to restore access without resetting edits. Apply/restore approval binds both original bytes and file identity; damaged receipt records do not hide valid backups. **Encrypted-bookmark support is deferred.** Settings → Labs shows an off, disabled “Planned” item; there is no Keychain access or native encrypted-store integration. The disconnected core experiment's source was removed on 2026-11-12; its [historical evidence](docs/encrypted-store-adapter.md) remains, and it was never supported app behavior. External direct-file writes remain disabled; the separately gated API tests above do not enable them. Plaintext-local permission/lifecycle, browser adoption/sync, native accessibility/language and distribution checks remain pending. Direct apply is the product goal; HTML export does not replace it. Same-URL items remain distinct.

New workspaces start with Chrome connection. Connect Chrome first tries normal access to the standard location and shows profile names directly when permitted. An in-app explanation and optional folder access/custom-location picker appear only when needed. Only selected supported profiles are added. Previous test profiles and edits are preserved and can be opened explicitly. Editing has visible Edit/Move/Delete controls, per-row pencil buttons and Undo. Single-bookmark deletion is immediately undoable; folder or multiple-item deletion previews its targets and total impact first. See the [editing UX decisions](docs/editing-ux.md).

GitHub publication and public releases are deferred until after local review. See [TASKS.md](TASKS.md) for completed work and blockers, and [validation](docs/validation.md) for evidence and limits.

The connection screen now lets you choose Chrome or Ego Lite before looking up its standard location. Ego Lite is an experimental read-only plaintext connection; storage freshness and real-browser compatibility remain unverified. Folder selection is a fallback for permission or custom-location cases, and macOS may still require native approval.

Denied browser access first shows a folder-consent guide. The standard picker opens inside the browser data folder; keep that location and choose Allow Access to This Folder. Galmuri reads profile metadata after confirmation and advances only on success. Settings instructions are a fallback after a selected-folder Chrome denial on applicable macOS versions; ordinary file-permission errors stay separate. Existing work is preserved. Real protected-folder approval and permission persistence remain unverified.

Automatic Settings-row lookup was withdrawn after reported input unresponsiveness (pointer movement continued; clicks and keys had no effect). Release 17 removed the Accessibility implementation and request. The mechanism is rejected: find and expand Galmuri manually in Files & Folders; the Settings button only opens the pane. No extra Accessibility or Automation permission is needed for connection. The incident’s cause remains unknown.

The profile chooser lists detected bookmark files and modification times. Readable plaintext Bookmarks stays selectable beside encrypted/other store files; their payloads are excluded. Missing and unreadable plaintext have separate states and details. File types are inferred from names, and timestamps do not prove current Chrome contents. Selected plaintext is validated at import; source-write restrictions remain.

## Run locally

Use macOS, Xcode command-line tools, and Swift 6+. The build target is macOS 14; tested OS/toolchain details are in the validation record.

```sh
swift test
python3 scripts/check-localization.py
scripts/build-local.sh release
open "build/release/Galmuri.app"
```

The script creates an ad-hoc-signed local Release with identifier `forked.galmuri.local.release`. Debug keeps `forked.galmuri.local`, separate data, and a blue DEV icon. Building does not install into Applications or register an Apple team. First launch opens Chrome connection; samples require explicit QA/sample flags. See [local development](docs/local-development.md) for isolated workspaces, data locations, and native rendering checks. Never use real originals as fixtures.

## Apply workflow

The API editor keeps Chrome open: reread its live API model, merge Base/Ours/Theirs, resolve conflicts, review and acknowledge the target, then apply guarded calls and verify the result. Removed originals move to a visible recovery folder; uncertain operations block replay and require explicit review. This is semantic recovery, without atomicity or sync guarantees. Real-user API writes are still gated.

The original file backend has a different validation target:

1. Preserve the initial snapshot (Base) and edit the working copy (Ours), while Chrome remains usable.
2. Finish browser work and quit Chrome before applying. Galmuri never force-quits it.
3. Reread the source (Theirs), perform a three-way merge, and explicitly resolve conflicts.
4. Review all changes and removals, verify an original backup, recheck the source, and replace safely.
5. Distinguish file verification from browser restart and synchronization, and retain a recovery path.

The full browser workflow is a validation target, not a claim of current real-profile write support. Direct Ego support is undecided.

## Languages and design

English is canonical. Native resources include Korean (`ko`), Japanese (`ja`), and Simplified Chinese (`zh-Hans`); runtime selection and English fallback have basic local checks. Translation quality, full accessibility/layout review, and detailed diagnostic translation remain incomplete. See [localization policy](docs/localization.md). Traditional Chinese is outside the initial scope.

The self-contained [HTML design prototype](design/galmuri-prototype.html) uses synthetic data and resets on reload. It is a design reference, not the native runtime. Its separate checks run with:

```sh
node --test design/prototype.test.mjs
```

## Documentation and contributing

Start with [documentation](docs/README.md), [product plan](docs/product-plan.md), [roadmap](docs/roadmap.md), [technical gates](docs/technical-validation.md), [architecture decisions](docs/adr/README.md), and [glossary](GLOSSARY.md).

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Keep real bookmarks, browser profiles, backups, credentials, and private URLs out of public reports, source, and fixtures.

[MIT](LICENSE) · Copyright (c) 2026 Galmuri contributors.

Folder browsing includes Back/Forward/Up and clickable ancestor paths. Folders appear before bookmark links with explicit type labels; ordinary folders show direct children and search includes descendants. Display grouping preserves stored order; explicit reordering works between same-type siblings.

Undo history lasts until the app quits. After relaunch, Pending Changes → Discard All Changes… can restore the current profile to the source state saved in Galmuri, with a full before/after review. This also restores deleted items and cancels additions, edits, moves and ordering. It does not reread/write Chrome or affect other profiles.

Profile Management can remove saved real/sample entries after saving a private workspace JSON recovery copy, preserving browser files and original backups. Refresh reads plaintext and reviews a three-way merge into Galmuri; it archives the old workspace, advances the saved source snapshot, and clears session undo after confirmation. Selected-change cancellation and individual deleted-item restoration show complete impact before local edits. Explicit HTTP/HTTPS bookmark opening uses the default browser. These features do not enable original writes or prove live-browser freshness.
