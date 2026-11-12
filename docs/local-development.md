# Local development and review installation

This is an experimental native app, not a public release. Use synthetic data and approved copies for development; actual profile reads require the user’s folder grant. Applying to real Chrome profiles remains disabled until dedicated browser restart and synchronization gates pass.

## Build

Use macOS, Xcode command-line tools, and Swift 6+. The package targets macOS 14; actual OS/toolchain coverage is in [validation](validation.md).

```sh
swift test
python3 scripts/check-localization.py
scripts/build-local.sh release
```

The script assembles `build/release/Galmuri.app` from the current worktree, including uncommitted changes. It compiles the selected asset catalog and String Catalog and verifies its ad-hoc signature. It does not install, select an Apple team, register an App ID, or publish anything. No third-party runtime package is required.

For a development build, use `scripts/build-local.sh debug` (also the default). Its output is `build/debug/Galmuri Dev.app`. Packaging uses a fresh staging bundle; existing output must have the expected identity/configuration and must not be running. A failed preparation leaves the previous output intact; unresolved staging/recovery paths are reported rather than silently discarded.

## Identities and data

`Config/BuildIdentities.json` resolves the one SwiftPM app target. There is no Xcode project/xcconfig to consume Xcode build settings.

| Mode | Bundle ID | Name | Primary icon | Application Support directory |
| --- | --- | --- | --- | --- |
| Debug | `forked.galmuri.local` | Galmuri Dev | `AppIcon-Dev` with blue badge | `~/Library/Application Support/forked.galmuri.local/` |
| Local Release | `forked.galmuri.local.release` | Galmuri | `AppIcon` | `~/Library/Application Support/forked.galmuri.local.release/` |

Both use local ad-hoc signing with no signing team, entitlements, or provisioning profile. The existing Debug identity is preserved; the new Release has a separate identity instead of inheriting development preferences and permissions. Public canonical identity/signing remain undecided. See [ADR 0004](adr/0004-separate-local-release-identity.md).

Each workspace contains `workspace.json` (Base and working copies). Explicit sample/QA workspaces may also contain `TestProfiles/` (synthetic originals) and `OriginalBackups/` (original bytes and receipts). Normal startup does not generate samples. These can contain private bookmarks after connection/import. App removal never implies removal of these files, preferences, TCC grants, Keychain, Containers, or user-selected folders. No automatic migration between development and Release data occurs.

## Review installation and post-development workflow

The maintainer's standing preference is to finish development with a verified **Release installed at `/Applications/Galmuri.app`**, then remove development app bundles and their exact-path registrations. `AGENTS.md` records this workflow.

Use `macos-release-reinstall`: inspect the exact installed destination and data, build/validate a complete candidate outside it, normally quit only matched running instances, preserve a rollback copy when replacing an existing installation, verify the installed signature/resources/runtime and user data, then remove this run's temporary rollback/staging/test material after success. Do not merge bundle directories, reset data, or bypass permissions. Ad-hoc replacement may require the user to authorize privacy access again.

Then use `macos-dev-app-cleanup`: inventory exact project-owned development paths, preserve every Release and all user data, normally quit matched instances, inspect/unregister their exact LaunchServices records, remove proven bundles, and verify absence. Defer ambiguous/running/prompt-blocked items. Do not force-quit or reset the LaunchServices database. Public GitHub/binary publication is still deferred.

For source contributors, a built Release can be run without installing it:

```sh
open "build/release/Galmuri.app"
```

Normal first launch shows Chrome connection. Choose **Connect Chrome** to attempt normal read access and show profile names. If the OS denies access, follow the in-app guidance; the scoped picker opens inside the exact known browser folder for confirmation, with custom locations available separately. Existing saved samples are preserved behind an explicit “Open saved test workspace” action. Edits autosave to the working copy. Review rereads and performs the real three-way merge. Apply/restore are restricted to app-owned `TestProfiles`; external connected sources remain read-only. The exit guard distinguishes explicit user-data roots and conservatively blocks unknown/default/helper process states; it never quits a browser. File picker access in this unsandboxed local build does not prove distribution/TCC support.

## Disposable smoke check

Both build modes support an explicit smoke check with a **fresh isolated workspace**:

```sh
 galmuri_smoke="$(mktemp -d -t GalmuriSmoke)"
 "/Applications/Galmuri.app/Contents/MacOS/Galmuri" \
   --workspace "$galmuri_smoke/workspace" --smoke-test
```

The explicit smoke flag seeds a disposable synthetic workspace. The app checks its visible native window, localized resources and icon, persists synthetic edits/deletion, undoes them, verifies the original is unchanged, writes `smoke-result.json`, and exits normally. It never applies to Chrome. Copy the result to the validation record before removing the disposable workspace. AppKit can initialize window geometry in the variant's preferences; this is an expected first-launch runtime write, not a user-data migration/reset. Preserve existing settings.

To review another isolated workspace interactively:

```sh
 galmuri_workspace="$(mktemp -d -t GalmuriLocal)"
 open -n "/Applications/Galmuri.app" --args --workspace "$galmuri_workspace"
```

## Native rendering checks

Debug builds also support `--capture-ui` with an explicit pristine app-owned synthetic workspace:

```sh
 galmuri_capture="$(mktemp -d -t GalmuriCapture)"
 "build/debug/Galmuri Dev.app/Contents/MacOS/Galmuri" \
   --workspace "$galmuri_capture/workspace" \
   --capture-ui "$galmuri_capture/screens" -AppleLanguages '(ko)'
```

This creates a real synthetic conflict, captures the editor/reconnection/conflict/final-review windows with macOS `screencapture` and the app's exact window IDs, saves PNGs and `capture.json`, and exits. It neither captures the desktop/other apps nor changes permission settings. AppKit bitmap caching omitted compositor-backed controls and was rejected as visual evidence.

Use `(en)`, `(ja)`, `(zh-Hans)`, or unsupported `(fr)` for preferred-language/fallback checks. These captures do not replace native-speaker, VoiceOver, keyboard, picker permission, or actual Chrome adoption tests. Clean the development app after verification and leave the installed Release for review.

See [validation](validation.md), [technical gates](technical-validation.md), [icon provenance](../Assets/README.md), and [TASKS.md](../TASKS.md).

## Planned Labs item

Open Galmuri → Settings… (`⌘,`) → Labs to view the disabled encrypted-bookmark support item. It is always off, marked “Planned · Unavailable” and localized in all four languages. It has no stored preference, credential prompt or activation path. Encrypted-only source connections remain unsupported; mixed-store write restrictions are unchanged. The retained encrypted-core experiment is not connected to the app.

## Editing the local test profile

Normal startup now connects real Chrome profiles through folder access and an in-app chooser. Sample data is generated only for explicit QA or `--workspace <fresh-path> --sample-data`; existing saved samples remain available without data deletion.

Select a table row and use the always-visible Edit, Move or Delete controls. A row’s pencil button also opens its editor (Return on a selected bookmark; Return opens a selected folder); double-click a bookmark to edit it or a folder to open it. The native table context menu offers the same actions. Single-bookmark deletion can be undone immediately. Folder or multi-item deletion first shows the exact selected names and unique affected-item count including descendants. Delete applies only to the working copy; Chrome originals are unchanged until a separately supported review/apply. Undo (`⌘Z`) is visible beside the selection controls.

Use `--workspace <fresh-path> --smoke-onboarding` to verify an empty welcome and absence of generated test profiles, separately from the synthetic editing smoke. See [profile connection](profile-connection.md) for scope and permission limits.

The welcome browser selector and File/sidebar actions support Chrome and experimental Ego Lite. Only an explicit Connect action attempts the selected standard location; no startup scan is performed. Use synthetic fixtures for automated testing. The Ego preset comes from app-bundle metadata, not a validated live profile; its imported workspaces retain the read-only warning.

The permission guide can be rendered through the isolated Debug capture harness using an owned mode-000 `PermissionFixtures/Chrome` directory. Its EACCES guide, Back/retry and later successful-read transitions are fixture-only; synthetic EPERM notices separately render initial Chrome folder consent, the selected-folder Chrome Settings fallback, and Ego folder consent. Do not infer native TCC grants from chmod restoration. The System Settings action is not invoked by automated capture.


Release 17 removes all production Accessibility trust checks/requests and Settings-row automation after the reported input-unresponsiveness incident. Synthetic captures never invoke Settings or approval controls. Do not run the retained Release 16 adapter probe, reproduce the reported click or reset TCC during this incident review. Historical ignored evidence is not current app code. [Incident findings](research/accessibility-freeze.md).

The rejected external Settings-control mechanism must not be reintroduced through a helper or another automation API. QA remains limited to Galmuri’s own UI unless the maintainer explicitly requests otherwise; no incident reproduction is authorized.

FolderConsentTests constructs AppKit panels using owned temporary directories and never presents them. The Debug capture harness renders 31 own-window images with six pre-use, five reset, five navigation, 14 connection and seven editing checks; it does not invoke the actual folder picker or Settings button.

Release21 capture fixtures include mixed plaintext/companion, plaintext-only, encrypted-only and unreadable-plaintext profiles. `profile-files.png` captures the production details component in an own window; it is not evidence of the actual disclosure gesture. Invalid companion payloads are intentionally not decoded.


Release22 adds `folder-navigation.png` and `folder-parent.png`, with synthetic in-process Return / `⌘↑` / `⌘[` / `⌘]` routing against the app's own window. The title path, direct contents, folder-first grouping and type column can be inspected in these captures. See [editing UX](editing-ux.md#folder-navigation-and-type-separation--2026-10-27); actual pointer/VoiceOver/deep-path acceptance remains pending.


Release23 adds `pending-changes.png` and `discard-preview.png`. The harness reloads a synthetic saved working copy into a fresh AppStore without session undo, renders the real confirmation component as an attached own-window sheet, invokes its Return action, and verifies discard/undo with unchanged original bytes. It does not click the main SwiftUI action or claim physical sheet-presentation acceptance. Installed editing smoke additionally verifies reopened pending changes, reset to saved source and reset undo using isolated synthetic data. This is persisted model reload, not a separate process-relaunch test.


Release24 adds profile-management, refresh-conflicts/review/complete, selected-revert and minimum-window native captures. Agent URL tests use an injected opener and never open user URLs. The feature fixture is a separate app-owned synthetic workspace; removal archives it without deleting originals. These are own-window/native-model checks, not physical gesture, VoiceOver or real-browser write acceptance.


## Pairing-only Chrome bridge · 2026-10-28

Local app packaging now requires the `GalmuriBridgeHost` SwiftPM product beside `Galmuri`; `scripts/build-local.sh` builds both. The package signs the helper separately and embeds its exact variant/extension ID configuration. Use `python3 scripts/build-bridge.py debug` (or `release`) for the separate unpacked extension output under `build/bridge/<variant>`. The existing app bundle IDs/icons/team settings are unchanged. No browser registration occurs during build or reinstall.

The [proof guide](chrome-bridge-proof.md) documents marked dedicated-root setup and `scripts/test-bridge-host.py`. This stage carries only connection data, not bookmarks. Normal app startup does not enumerate requests or ask for additional privileges; request refresh and approval live in Settings. The Debug own-window capture adds `bridge-proof.png` with a fixed 580×460 content size, bringing the manifest to 32 screenshots. This checks rendering and Core approval, not physical app/extension gestures.


## Chrome API workbench · Release26

See [API workspaces](chrome-api-workspace.md) for current setup and boundaries. The extension now declares bookmarks/nativeMessaging/storage; it still has no content scripts, website permissions, background auto-connect or Keychain integration. Explicit marker/flag consent is required for dedicated writes. App-owned semantic workspaces and API receipts live separately under `BridgeAPI`; do not commit them. Existing app identities/icons and file workspace schema remain unchanged. Native own-window capture now includes `api-workspace.png` and `api-review.png`, for 34 images per locale. QA-only extension workers/native smoke flags do not prove physical button interaction.


## Release27 refinement checks

[Native refinement](native-refinement.md) describes protocol2, bounded records and stop semantics. Reload matching extension/helper builds together: old clients/helpers fail negotiation. `node --test Bridge/*.test.mjs` covers client/planner/chunking; `python3 scripts/test-bridge-host.py <packaged-app>` checks the native helper, 13 rejection cases and a >32 KB result. The optional reproducible Core benchmark uses `GALMURI_MERGE_BENCH=1 swift test --filter MergePerformanceTests` (Release adds `-c release -Xswiftc -enable-testing`); it makes no timing assertions. Default tests skip the opt-in benchmark but run 400 seeded old/new equivalence scenarios. Debug own-window capture produces 35 images per locale, including native API multi-selection. Dedicated browser/stop proofs never operate System Settings or user profiles.
