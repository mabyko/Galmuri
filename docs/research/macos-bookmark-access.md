# macOS bookmark access and competing connection models

Research date: 2026-10-25. Task 1.11. This record distinguishes documented platform behavior, competing products’ stated approaches and proposed Galmuri changes. No application, signing, permission record or browser-profile data was changed during this research.

## What the current window is

`AppStore.chooseBrowserFolder` explicitly creates `NSOpenPanel` and calls `runModal`. It does not launch Finder. The Finder-like file browser is Apple’s standard selection UI. The current UI’s “Allow Folder Access” action is a request to open that selection UI; it is not a direct TCC permission prompt.

Apple’s [WWDC23 privacy session](https://developer.apple.com/videos/play/wwdc2023/10053/) explicitly recommends NSOpenPanel for user-approved individual files/folders, explains that confirmation permits access to the selected resource, and supports choosing an initial location. [AppKit documentation](https://developer.apple.com/documentation/appkit/nsopenpanel) describes the panel. Context7 was used for the current API lookup.

## Three mechanisms that must stay separate

| Mechanism | What the user approves | What Galmuri can do | Limits |
| --- | --- | --- | --- |
| User-selected folder | A particular folder in the standard macOS chooser | Present the chooser, constrain the intended folder, retain a scoped bookmark, recheck real access | Selection is not a promise that every independent protection or later revocation is solved |
| Files & Folders / app-data protection | OS-controlled access to particular categories or other apps’ data | Attempt expected access and handle the OS decision; explain an existing Settings entry | An app cannot invent its own “Chrome bookmarks” toggle or guarantee its appearance |
| Full Disk Access | Broad access to protected files beyond browser bookmarks | Open the documented Settings destination and explain how the user adds/enables the installed app | Opening the pane does not register or grant access; no automatic enabling or general public TCC-grant API |

[Apple DTS](https://developer.apple.com/forums/thread/678819) distinguishes Sandbox extensions from mandatory access control, explains that access may prompt or be denied, and states that TCC has no public API surface. A separate [DTS response](https://developer.apple.com/forums/thread/125438) describes historical Files & Folders membership through TCC alerts. Do not extrapolate it into a claim that modern browser-specific entries can never appear: Mozilla’s macOS 27 investigation below records such an entry even after denied access.

[Apple’s Settings guide](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac) documents adding an app under Full Disk Access with the Add button. This broad grant is different from a scoped-folder approval. The installed Apple SDK’s `usr/include/EndpointSecurity/ESClient.h` documents the macOS 13+ destination:

`x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles`

The header was inspected read-only; the endpoint was not opened. This is evidence for navigation, not for self-registration. Endpoint Security’s entitlement-restricted client APIs must not be added merely to provoke registration or test unrelated permissions.

Apple’s [2026-10-02 announcement](https://developer.apple.com/news/?id=p6zjojqw) says further Full Disk Access controls will require very explicit user action. It announces future direction, without a specific rollout guarantee; do not infer that every announced change is already active on the maintainer’s machine.

## Why Chrome may differ from Ego Lite

The maintainer reports successful direct Ego connection and Chrome read denial. The local system reports macOS 27.0.1. This is an observation, not a diagnosed TCC service. We did not inspect a real browser store or TCC database.

Apple’s [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes) explicitly document default denial rather than a prompt for other teams’ app/app-group data and new XProtect restrictions on frequently targeted app data, with user control in Privacy & Security. This changes the earlier expectation that every first read will produce an Allow dialog. It still does not identify the exact policy behind this particular denial.

Mozilla’s [comment 10](https://bugzilla.mozilla.org/show_bug.cgi?id=2078922#c10) records **Google Chrome** beneath **Firefox** in **Files & Folders** as a result of the denied read. Its [comment 11](https://bugzilla.mozilla.org/show_bug.cgi?id=2078922#c11) says enabling the toggle permits reads. This supports a targeted Settings route; it does not confirm Galmuri’s entry exists. None was inspected here.

Mozilla also documents a standard folder-picker import route and location/selection fixes. These are product-specific observations, not a universal guarantee.

Galmuri is currently signed ad hoc. Apple DTS explains that ad-hoc builds do not provide the stable identity needed to recognize successive versions consistently. Production signing may improve grant continuity; it does not itself grant Chrome access or prove the present cause. No signing/team/identifier changes are part of this research.

## What other products document

| Product | Documented approach | Implication for Galmuri |
| --- | --- | --- |
| [Raindrop.io](https://help.raindrop.io/import/) | Export a browser file, then upload/import it into its own collections | This is migration into an independent library, not evidence of editing the original browser profile |
| [Anybox](https://anybox.app/getting-started) | Migration Assistant imports; browser extensions save links; AppleScript saves the current tab through Automation consent | Current-tab automation is not a general bookmark-tree storage grant; the cited page does not disclose the migration implementation |
| [BookMacster](https://sheepsystems.com/bookmacster/HelpBook/SSYMH.04.07.html) | Browser extensions import/export while browsers are running and notify the native app of bookmark changes; a native messaging helper bridges them | A comparable multi-browser manager uses explicit browser integration rather than a universal OS bookmark toggle |
| [Firefox browser migration](https://bugzilla.mozilla.org/show_bug.cgi?id=2078922) | Standard NSOpenPanel folder approval appears in its modern macOS migration investigation/fixes | A system folder picker is also used by browsers, not just this prototype |

The official [Chrome bookmarks API](https://developer.chrome.com/docs/extensions/reference/api/bookmarks) requires the extension manifest’s `bookmarks` permission. A native macOS file-access grant does not confer that browser API permission, and the extension route does not establish safe native-file replacement.

## Proposed Galmuri flow

Keep persistent profile connection as the main product; browser migration/import is a separate path. The maintainer’s no-per-profile-extension preference and deferred encryption scope remain in effect.

1. Select Chrome/Ego and try a user-initiated normal read, reusing a matching saved grant. Never probe at startup.
2. On a compatible macOS 27 denied-data case, make the **targeted Settings route** easy to find: Privacy & Security → Files & Folders → Galmuri → Google Chrome, **if the OS has created that entry**. The user enables it, returns, and triggers a normal read check. This is not Full Disk Access. Do not promise an app-created toggle or automatically modify it.
3. Keep the standard folder chooser as a separate, explicitly named route: “Choose Chrome Folder and Allow Access…”. Prefer an attached sheet and a known initial location so the user does not need to find a hidden Library path. The Firefox case suggests starting inside the intended folder and confirming Open; the appropriate default and exact-folder validation need native QA before changing Galmuri’s current parent-directory picker.
4. After selection or a settings change, recheck actual access. Retain the scoped grant through the existing persistence rules. Subsequent attempts reuse it, subject to revocation, OS behavior and signing continuity. A new binary is not proof that a prior permission will remain effective.
5. If scoped access and any available targeted Settings entry still do not work, an explicitly advanced Full Disk Access route can open the SDK-documented pane. The user must add/enable the installed Galmuri app. Explain that it grants broader access than bookmarks. Do not add/toggle it automatically or make this broader grant the default.
6. An optional HTML import could provide migration/copy editing when a profile cannot be connected. It cannot silently replace the agreed original-profile/three-way/direct-apply goal. The native app currently has Workspace JSON import and Netscape HTML export; this research does not implement native HTML import.

These are recommendations, not implemented changes. The installed application remains Release 12. Actual selected-folder approval/persistence/revocation, System Settings navigation and broader grant acceptance need a deliberate native QA round. Permission success also does not establish readable encrypted stores, browser write adoption or sync safety.

## Claude-dev-max discussion

Two rounds were completed with the requested **Claude-dev-max** provider, Claude Opus 5.5, effort max. Initial and reconciliation notes are retained as ignored QA evidence under `build/qa/20261025-permission-research/`. The parent independently checked the Apple SDK, official product docs and Mozilla’s first-party investigation.

Agreed recommendation: make targeted Settings instructions prominent for the relevant macOS 27 Chrome denial, retain the standard chooser, recheck real access, and preserve the persistent-profile product goal. Do not create/flip OS permission rows or imply an unobserved Galmuri switch exists.

Corrections to the initial review:

- NSOpenPanel is a documented explicit-selection mechanism without a blanket sandbox-only condition in the WWDC23 guidance. What remains unverified is this app’s grant lifetime and coverage of current browser protection.
- The FDA navigation URL is documented in the inspected Apple SDK header. This does not document a Files & Folders/app-specific anchor, registration API or grant operation. No supported direct Files & Folders link was established here; this is different from claiming no unofficial link can exist.
- Mozilla supplies first-party evidence for the browser-specific Settings switch and picker import. Neither establishes Galmuri’s row, and BookMacster’s runtime-extension documentation does not prove its exact offline storage implementation or Galmuri compatibility.
- Rebuilt ad-hoc code can require reauthorization; the lifetime of each actual grant must be tested. Do not say every permission certainly disappears on every rebuild.
- Round 2 assumed that the active SDK establishes Galmuri’s linked SDK and therefore its notification behavior. Parent inspection of the installed Release 12’s `LC_BUILD_VERSION` reports **SDK 14.0 / minimum macOS 14.0**. The active Xcode SDK path is not evidence that this installed binary advertises SDK 27. Do not apply the Mozilla SDK-27 notification claim to Galmuri without further proof, or assume a banner will/will not appear.

Implementation follow-up (task 1.12): preserve underlying error domain/code in technical details; distinguish ordinary file-permission failures from an undiagnosed EPERM; route a freshly user-selected URL directly instead of substituting an older saved bookmark; reorder the guide with conditional exact Settings instructions. The cached-grant routing risk is visible in code but a real stale-token failure has not been reproduced. Picker default-location changes, activation-triggered retries and broader-access UI require their own scoped validation.

Actual OS grants, permission resets, broad access, signing changes, Keychain work and browser writes were not performed. Statements about picker persistence or write access are **unverified**, not claims that those capabilities are inherently impossible.

## Implementation checkpoint: task 1.12

The subsequent local app change implements conditional Settings-first guidance for Chrome on macOS 27+, separate known-EACCES instructions, explicit chooser fallback, bounded domain/code details and fresh selected-URL priority. The generic Settings app is opened through the existing public API; no direct Files & Folders link, activation-triggered retry or broad-access action was added. The picker still starts at the parent pending native acceptance. Earlier Release 12 statements above describe the research checkpoint, not the subsequent implementation. Real Galmuri switch/grant/relaunch/revocation and signing continuity remain unverified; see [current connection behavior](../profile-connection.md) and [validation](../validation.md).

## Subsequent navigation verification · 2026-10-27

Following maintainer feedback about the generic launch, a bounded local check found `allowsXAppleSystemPreferencesURLScheme = true` and the extension ID `com.apple.settings.PrivacySecurity.extension` in the installed SecurityPrivacyExtension Info.plist. Its executable contains `Privacy_FilesAndFolders`. Opening `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders` through NSWorkspace produced the Settings window title **파일 및 폴더**, confirmed through existing accessibility access. No checkbox, grant, TCC database or browser profile was accessed or modified by this navigation check. Ignored evidence is under `build/qa/20261027-settings-navigation/`.

This adds runtime evidence for a best-effort anchor; it does not turn the earlier absence of a documented Files & Folders link into a public API guarantee. Task 1.13 uses this destination with a generic launch fallback and manual instructions. Actual OS-created Galmuri entry/grant tests remain pending.

## Expanded app-row request · 2026-10-27

The maintainer supplied a screenshot showing Galmuri → Google Chrome, with the switch off, and requested direct navigation to that expanded row. Presence is now supported by that screenshot; authorization and persistence are still unverified. Bounded checks found the existing Files & Folders pane anchor but did not establish an app-specific selection/disclosure contract. Neither the installed extension’s bundle-ID/reveal-related strings nor unrelated app-specific URL examples are proof that this pane accepts a bundle-ID parameter. No guessed query parameters or UI automation are shipped. This is a limit of the verified implementation, not a claim that every possible OS-specific technique is impossible.

Task 1.14 changes the button wording to **Allow Files & Folders in Settings** in four languages. It retains the pane route and current-app/manual instructions, without another Accessibility/Automation grant or permission toggle. The user-provided screenshot remains an attachment and was not copied into public source/assets.

## Focused follow-up investigation

Task 1.15 independently reviews the row-navigation request with Claude-dev-max and tests candidates against a collapsed Galmuri row. The [focused investigation](permission-row-navigation.md) records positive/negative controls and separates accepted URLs from actual destinations. Four bundle-ID query variants currently regress to Privacy & Security rather than opening an app row. The independent reconciliation is complete: no tested app-row URL works, while a QA Accessibility disclosure action works under existing trust. That research checkpoint required a separate maintainer choice. The maintainer subsequently explicitly approved the additional grant: Release 16 implements optional, button-triggered own-row expansion with strict guards and manual fallback, never permission switches. See [ADR 0008](../adr/0008-optional-accessibility-settings-navigation.md) and the [implementation follow-up](permission-row-navigation.md#authorized-implementation-follow-up). QA-process runtime checks do not establish installed-Galmuri trust.


## Freeze-report containment · 2026-10-27

After Release 16 installation, the maintainer reported input unresponsiveness: pointer movement continued, clicks and keys had no effect, and the user powered off to recover. The clicked control was Allow Files & Folders in Settings; the causal mechanism and trust state remain unconfirmed. Release 17 removes automatic AX lookup/selection/scroll/disclosure, passive trust checks and the Accessibility request, retaining the ordinary pane/manual route. Earlier successes above are historical QA evidence, not current feature availability or system-stability proof. No reproduction or permission changes are performed during this investigation. [Incident review](accessibility-freeze.md); [current behavior](../profile-connection.md).


The second independent review incorporates the clarified symptom and withdraws earlier absolute timing/deadlock guarantees. The maintainer rejects the mechanism; this is no longer a feature awaiting optimization. Keep manual pane guidance and native accessibility support, with no external UI automation or extra grant for connection. Root cause remains unconfirmed. [Decision](../adr/0008-optional-accessibility-settings-navigation.md); [reconciliation](accessibility-freeze.md).


## Folder-first superseding implementation · 2026-10-27

The maintainer subsequently chose standard folder consent first, with the exact browser data folder pre-opened and a single user confirmation, before Settings fallback. Release20 uses existing selection origin to distinguish initial denial from confirmed-folder failure and preserves known EACCES handling. This supersedes the research-era Settings-first priority above. Apple’s explicit-selection guidance and Mozilla’s pre-opened Chrome-folder fix support this design; they are not proof of this app’s native grant or persistence. No new source research, real picker or Settings action was used to validate it. [Current flow](../profile-connection.md#folder-first-consent--2026-10-27).
