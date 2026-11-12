# Guided Chrome profile connection

Tasks 1.7–1.19 · updated 2026-10-27. Normal startup no longer generates a synthetic profile. Existing workspaces remain schema 1 and are never deleted or converted by this change.

## User flow

1. Open Galmuri, select **Chrome** or **Ego Lite**, and choose **Connect**.
2. The app attempts normal read access to the selected browser’s standard location. A matching saved grant is reused. If access works, profile names appear directly in the in-app chooser.
3. If the OS denies access, Galmuri opens a folder-consent guide first. **Allow Browser Folder Access…** opens the standard picker inside the exact browser data folder. The user keeps that location and chooses **Allow Access to This Folder**; confirmation starts one discovery read and opens the profile chooser only on success. Chrome/macOS27 Settings instructions appear only after a confirmed-folder denial, except that known `EACCES` always gets ordinary file-permission guidance. **Check Again** is explicit; **Back** preserves work. Missing/custom locations retain separate guidance.
4. Select and confirm the profiles to add. Galmuri rediscovers the selected identities and reads only those supported bookmark payloads. Browser originals remain read-only.

The folder picker is Apple’s standard user-selection interface. Its confirmation and a saved scoped bookmark do not establish that all Chrome app-data protections are satisfied or that access persists across relaunch/rebuild. Setting its initial directory does not establish that a privacy grant will succeed. The prior `Operation not permitted` observation is still a permission QA item; the app must report denial rather than bypass it. A custom directory can be selected through the same dialog. No scan of Chrome directories is performed during startup; direct lookup is triggered only by the explicit Connect action.

## Permission guide

A denied lookup replaces the welcome/editor with a dedicated scrollable page; the editor’s data and selection remain intact underneath. Existing access must actually be checked before the page advances. Retrying keeps the guide visible while checking and leaves it visible on another denial. Selecting a folder or opening System Settings is not treated as proof of a grant.

After a confirmed Chrome-folder denial on macOS 27+, the fallback route is **System Settings → Privacy & Security → Files & Folders → Galmuri → Google Chrome**, **if the OS-created entry appears**. The displayed app name comes from the current bundle (Galmuri Dev in Debug). The user enables the switch, returns and chooses **Check Again**. The **Allow Files & Folders in Settings** button first opens `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders` through NSWorkspace. On the checked macOS 27.0.1 host, native accessibility confirmed that this opens the **Files & Folders** window. This is an observed Settings anchor, not a documented cross-version guarantee. If macOS rejects the URL, the app falls back to opening Settings normally. If it accepts the URL but ignores the destination, visible instructions tell the user to follow the full path. A successful launch never means permission was granted; the maintainer has now provided a screenshot of the Galmuri → Google Chrome switch, while actual authorization/effectiveness remains unverified.

**Allow Browser Folder Access…** is the first denied-access action and remains available to retry from the Settings fallback. The exact-folder panel starts inside the target and validates that same folder; it labels confirmation **Allow Access to This Folder**. Custom-location browsing still starts at the parent and uses the ordinary Choose Folder label. A freshly selected URL is used directly; an older stored scoped URL cannot replace it. The selected origin remains attached to retries and staged profile requests. Default-location attempts continue to reuse a matching saved grant.

An underlying `EACCES` shows file read-permission guidance and an alternate-location action, rather than suggesting that an app-data switch changes ordinary file permissions. `EPERM` does not prove a specific TCC service. Technical details retain a bounded chain of up to four error domains/codes, plus the existing localized message. No startup probe, automatic permission change, TCC reset or signing change is added. The pane destination is best-effort navigation only; it cannot create, expand or enable the OS-controlled Galmuri/Chrome entry. Full Disk Access is mentioned only as a broader advanced alternative, without a new action or automatic request.
Reference: [Apple’s Files & Folders instructions](https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac), [NSWorkspace app lookup](https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication(withbundleidentifier:)), [opening URLs](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:)). API details were verified through Context7. The maintainer’s screenshot showed a Chrome read-permission error; no additional real-profile access was attempted by the agent.

## Research and implementation boundary

[Task 1.11 research](research/macos-bookmark-access.md) informed the task 1.12 guide, diagnostics and selected-URL fix. Rendering a synthetic `EPERM` and routing a mode-000 fixture denial do not establish actual OS grants. Native picker approval, the Galmuri Settings row, same-build relaunch, revocation and replacement-build authorization still require acceptance under tasks 1.3/1.6. No real-profile probe or OS permission change was performed by agent tools.

## Ego Lite experimental boundary

The installed Ego Lite 0.6.1.9 app identifies itself as `com.citrolabs.ego.lite` and declares `CrProductDirName = Citro Labs/ego lite`. Chromium documents the macOS default as Application Support plus the product directory. Only app bundle metadata was inspected; no real profile or browser session was accessed. This establishes a default-location preset, not a verified Ego bookmark-store contract.

Ego Lite can stage candidate profiles through the same bounded discovery and import only explicitly selected plaintext payloads accepted by the existing parser. Every imported Ego working copy retains an experimental/read-only warning through save/relaunch/reconnection. Unknown/encrypted-only payloads remain unavailable; mixed storage retains its plaintext-only scope and blocked-apply warning. The native chooser also labels this experimental boundary. Existing Base/Ours, schema v1, Core APIs and external-write gates are unchanged. No direct Ego apply, encryption handling or browser runtime acceptance is claimed. See [ADR 0007](adr/0007-browser-selection-and-ego-preview.md).

Selecting a browser does not read its data. Only Connect or an explicit alternate-location selection begins discovery. Notices and staged requests retain their browser identity, so retry/access cannot silently switch to Chrome. Browser selection is transient; persistent identity continues to be the source URL and existing profile UUID, not a browser display label.

## Data and capability boundaries

- Discovery is a staged operation: it lists approved profile metadata and does not import bookmark payloads or alter the workspace. Canceling the native panel or dismissing the chooser preserves existing work.
- Confirmation accepts a nonempty set of discovered directory identities and rediscovers before reading. A stale/missing identity, a forced encrypted-only selection or a selected unreadable payload aborts the entire addition without discarding prior profiles or edits. The chooser disables missing/unreadable plaintext selections, and import still checks source contents independently.
- Unselected unsupported or malformed profiles do not block a supported explicit selection. This avoids treating every profile under a root as an instruction to import it.
- Readable plaintext remains selectable alongside account/encryption/ordering companions. The working copy retains its source-write restriction and explicit plaintext-only scope note. Companion payloads are not imported and do not establish the newest browser model. Encrypted-only and other unverified formats remain unavailable; no Keychain access or decryption path is added.
- Selected folders are stored with read-only security-scoped bookmarks. Future reads remain subject to OS authorization, scope validity and signing continuity; persistence of the reference is not proof of persistent permission. Existing source identity, Base/Ours preservation, reconnect rules and external-write gates remain intact.
- Existing real connections are preferred on normal relaunch. A workspace containing only old test profiles opens the connection welcome; **Open saved test workspace** explicitly reopens those preserved samples. The profile menu retains access to saved profiles.

This is an explicit user action, not an automatic startup read; it does not bypass a denial or establish real TCC acceptance. See [ADR 0006](adr/0006-user-initiated-profile-discovery.md).

The Chrome default is `~/Library/Application Support/Google/Chrome`; Ego Lite’s experimental preset is `~/Library/Application Support/Citro Labs/ego lite`. Custom `--user-data-dir` locations use the explicit alternate-location action. The scoped approval picker begins inside that target; custom-location browsing begins at its parent. The panel is configured through AppKit’s [`directoryURL`](https://developer.apple.com/documentation/appkit/nssavepanel/directoryurl), with directory selection enabled. Current AppKit documentation was fetched through Context7. No native permission or real Chrome access result is inferred from this configuration.

## Explicit development and QA data

Synthetic data is opt-in. Use a fresh isolated workspace with `--sample-data` for interactive sample work. `--smoke-test` explicitly seeds the existing editing smoke, and Debug `--capture-ui` explicitly seeds its native QA fixture. These flags require `--workspace`; default application data is never seeded through these entry points.

`--workspace <fresh-path> --smoke-onboarding` checks an empty visible welcome, localized resources, persisted Workspace v1 and absence of generated `TestProfiles`. The normal installed application remains separate from all disposable QA workspaces.

## Verification and remaining acceptance

Fourteen onboarding tests cover normal empty startup, saved-sample preservation, existing connection preference, metadata-only discovery/cancel, selected subset imports, missing/empty/unsupported IDs, atomic unreadable failure, rediscovery and stale sessions. Existing synthetic tests now request samples explicitly.

Fifteen additional direct-connection tests cover normal lookup staging, missing/denied notices, wrapped errors, saved-grant scope, exact-folder validation, cancellation and atomic source/workspace failure.

Native synthetic captures render missing/denied guidance, the welcome, the actual chooser sheet with supported/unavailable profile names, and a model-confirmed selected read-only connection in four languages. They do not exercise the real Chrome picker, physical checkbox gestures or TCC approval. The installed Release is checked with both onboarding and synthetic-editing smoke modes. Actual user-folder permission success, revocation, real-format freshness and Chrome write/sync support remain separate acceptance items. Public publication and encrypted support remain deferred.

Six SettingsFirstTests cover bounded domain/code diagnostics, browser/OS/errno routing, fresh selected-URL priority, denial/retry origin retention, atomic failed import and clearing transient diagnostics without losing work. Native captures distinguish real fixture `EACCES` from explicitly synthetic Chrome/Ego `EPERM`; these are separate from TCC acceptance.

Task 1.13 adds three SettingsNavigationTests for exact destination-first routing, rejected-link fallback and missing/unlaunchable Settings. These tests inject launch results and never open Settings themselves. Separate native navigation observed the target window title without changing a permission toggle. Four-language copy names the destination and the current app to expand, and keeps the return/recheck action explicit.

On 2026-10-27 the maintainer requested the authorization-oriented action label and supplied a screenshot of the expanded Galmuri row with Google Chrome off. The label is now **Allow Files & Folders in Settings**; selecting it navigates to the pane and does not grant access. The existing URL opens the whole Files & Folders list. No app-specific URL that reliably selects/expands Galmuri was established in the bounded checks, so no speculative bundle-ID parameters are shipped. Release 16 briefly added the separately authorized Accessibility option below; it was withdrawn after the input-unresponsiveness report and its mechanism is rejected. Finding and expanding the app is now manual. The screenshot establishes UI presence, not a grant, current-build identity match, persistence or write capability.


## Withdrawn Release 16 Accessibility navigation · 2026-10-27

**Current behavior (Release 17 onward):** automatic row navigation and all Accessibility trust checks/requests are removed after reported input unresponsiveness (pointer moving; clicks and keys ineffective; user powered off to recover). The Settings button only opens the ordinary pane/fallback; manually find and expand the app. No additional Accessibility permission is required. Existing OS permission records are preserved. This is containment, not a proven fix for a confirmed system-level cause. See [incident findings](research/accessibility-freeze.md).

The following describes the withdrawn Release 16 implementation. The maintainer explicitly approved this additional permission in [ADR 0008](adr/0008-optional-accessibility-settings-navigation.md). The Chrome Settings-first guide offers **Allow Accessibility Access…** as a separate opt-in. Only that button asks macOS for Accessibility trust. The user enables Galmuri in Privacy & Security → Accessibility, returns, and clicks **Allow Files & Folders in Settings**. With existing trust, that click attempts to reveal and expand the row named for the running app; the user must confirm it is this installed copy and turn on **Google Chrome** themselves. No saved preference, AppleScript permission or automatic grant is added. The OS permission is broader than the limited actions implemented here.

Automation requires an actual named `.app` bundle, the expected System Settings bundle/executable and a stable process launch identity. It scans only known Files & Folders windows, checks the outline’s complete root `AXRows` list for an unambiguous exact app name, and revalidates roles/parents before each action. It may select that app row, scroll its owning viewport and press only its collapsed disclosure triangle, once. Permission switches are never action targets. Unknown or incomplete rows, duplicate names, unsupported layouts/locales and stale process/UI state fall back to manual instructions. Selection/scroll/disclosure require Settings in the foreground; activation is handed off only while Galmuri itself is foreground. Cancellation and revoked trust stop the attempt.

The withdrawn design checked a four-second discovery deadline and a separate 1.5-second confirmation deadline, with 100 ms timeouts set on AX reads. These cooperative checks were not a guaranteed wall-time bound or a watchdog. A timed-out disclosure action may already have been delivered: it is not repeated; fresh expanded/visible state decides success. Known pane titles cover English, Korean, Japanese and Simplified Chinese; native Settings automation was observed only on this Korean macOS 27.0.1 host. Layouts and code-signing permission continuity are not guaranteed across updates. An unbundled `swift run` cannot automate a different installed copy’s row.

Passive trust checks occur when this view appears or the app becomes active. They never request permission, navigate Settings, scan browser stores or run automatic connection retries. Leaving the view cancels outstanding navigation. Without trust, the ordinary pane/manual route remains available. Actual installed-Galmuri permission approval, revocation and relaunch acceptance remain under tasks 1.3/1.6; QA-process trust is not a grant to Galmuri. See [research](research/permission-row-navigation.md) and [validation](validation.md#optional-accessibility-settings-navigation--2026-10-27).


The maintainer rejected this mechanism after the second review. Do not reinstate one-shot or repeated external UI inspection, selection, scrolling, disclosure, focus control or an Accessibility/Automation request for browser connection. This does not affect Galmuri’s own accessibility or native file panels. Release 18 removes the obsolete “temporarily unavailable” notice; the existing manual steps remain. [Withdrawal decision](adr/0008-optional-accessibility-settings-navigation.md).


## Manual guide action placement · 2026-10-27

Release 19 associates each button with its numbered instruction rather than placing both below the card: step 1 contains the Settings button, full manual route and opening/fallback explanation; step 2 names the current app and its left disclosure arrow, then asks the user to enable Google Chrome underneath if listed; step 3 contains Check Again and explains returning to Galmuri after approval. The Settings button still only opens the pane/fallback once. Check Again still performs the existing explicit source-read check. No Settings inspection, automatic expansion, trust request or activation retry is added. Layout checks use only owned synthetic app windows, never the reported Settings action.


## Folder-first consent · 2026-10-27

Release 20 supersedes the earlier Settings-first ordering for initial denials. Selection origin is the gate: an initial known-location denial uses folder consent; only a selected-folder failure can use the applicable Chrome Settings fallback. Ordinary EACCES remains separate. Initial folder guidance does not expose the generic Settings section; it is available after a selected-folder failure on other browser/OS combinations. No grant is inferred from the panel response: the existing source read must succeed. Cancellation schedules no read; fresh selection stays authoritative over an old saved reference. Profiles are still explicitly selected before import.

The shared AppKit panel configuration is tested with owned synthetic directories without presenting a window: exact initial directory, confirmation label and folder-only/single-selection/no-new-folder constraints, plus unchanged custom-location behavior. Native capture renders initial Chrome/Ego guides and the post-selection Settings fallback separately. Neither proves actual TCC approval, enabled confirmation on the real folder, grant persistence or browser freshness. The withdrawn external UI mechanism remains prohibited. There is no Settings scripting, foreground watcher, auto-approval, permission polling, new Keychain access or external write support.


## Source-file inventory and plaintext-only import · 2026-10-27

Release21 separates observed files from content support and current-browser authority. Profiles show **Plaintext file selectable**, **No plaintext file**, or **Plaintext file unreadable**, with an expandable file inventory. Recognized plaintext, encrypted, separate account/ordering, backup and other related filenames have modification times where safe metadata is available. Problems such as symlinks, nonregular objects, denied reads or oversized plaintext are shown separately. Classification is by filename, not validated encrypted/account contents. The ambiguous generic unavailable/freshness badges are removed.

Discovery inspects only metadata and opens the plaintext descriptor to check regular-file identity/access/size; it does not read bookmark payloads at this stage. Non-plaintext payloads are never opened by the inventory. The selected plaintext file is reread and parsed by the existing bounded/no-follow loader at import, so a selectable file can still fail later content validation or change after discovery. The existing atomic selected-import behavior remains. Modification times are observations, not an active/latest-store ranking; no file is auto-chosen because it is newer.

A readable `Bookmarks` beside encrypted files or even an empty ordering companion stays selectable. Only its plaintext contents enter the working copy; companion contents remain excluded. `hasPlaintext` records detection, while `canImportPlaintext` also requires successful safe access/size inspection. Encrypted-only/backup-only rows stay visible with metadata but cannot be selected. Existing mixed-store write restrictions and browser-original read-only gates are not relaxed; transient inventory is not persisted into Workspace v1 or used as write approval. No decryption, Keychain, authority adapter, store merging, background polling or real-profile probe is added.


## Pre-use management and refresh · 2026-10-27

Saved entries, including old samples, can be explicitly removed through Profile Management after workspace JSON archival; browser files and original backups remain untouched. Refresh separately reads the selected plaintext file and reviews a three-way merge into Galmuri. It neither reuses Connect as a destructive reload nor writes browser originals. Incoming source changes and local edits remain distinct; retained unsupported companion warnings do not become write approval. Read-only editing and explicit refresh remain useful without promising live browser freshness. [Workflow details](editing-ux.md#pre-use-profile-and-source-workflows--2026-10-27).
