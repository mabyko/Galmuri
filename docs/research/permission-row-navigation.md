# Direct permission-row navigation investigation

Task 1.15 · 2026-10-27 · historical research/implementation; mechanism subsequently withdrawn (see follow-up below)

The maintainer wants **Allow Files & Folders in Settings** to open the expanded **Galmuri → Google Chrome** entry, avoiding manual app lookup. The existing pane URL works, and the maintainer supplied a screenshot confirming the row and its off switch. This investigation separates app selection/disclosure from authorization: no permission control may be changed to test navigation.

## Controlled runtime checks

Host: macOS 27.0.1. Target identity: local Release `forked.galmuri.local.release`. Baseline URL:

`x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders`

The QA observer uses existing accessibility access and searches only Settings windows for the exact Galmuri heading, its containing row and its disclosure triangle. It does not ship with Galmuri and does not request access. A positive control presses that disclosure only, observes expansion and restores the collapsed state. This checks the observer rather than assuming URL acceptance proves success.

| Candidate | Observed destination | Galmuri expanded? |
| --- | --- | --- |
| Bare pane URL | Files & Folders; Galmuri row found | No; remains collapsed as expected |
| Append `&bundleId=forked.galmuri.local.release` | Privacy & Security parent page; row absent | No |
| Append `&bundleID=forked.galmuri.local.release` | Privacy & Security parent page; row absent | No |
| Append `&id=forked.galmuri.local.release` | Privacy & Security parent page; row absent | No |
| Append `&bundleid=forked.galmuri.local.release` | Privacy & Security parent page; row absent | No |

NSWorkspace accepted every URL. Each extra query item regressed to the parent page, so acceptance is insufficient even for pane navigation. The baseline pane and row were recovered between candidates. The initial and final disclosure states are both collapsed. No permission checkbox was acted on. Selection was observed on the row; off-screen visibility/scrolling was not controlled, so this is not a complete scroll-only test matrix.

Early observer iterations had a too-short launch wait and a field-lookup error; these are QA failures, not candidate evidence. The final complete run includes the positive control, five cases, baseline recovery and restored state. Its JSON/log and the observer are retained locally under `build/qa/20261027-app-row-research/`.

## Documentation boundary

Current Context7 AppKit resolution/queries did not establish a per-app Files & Folders contract. Apple's [OpenConfiguration.appleEvent documentation](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/appleevent) describes generic event delivery, not a Privacy pane app-row parameter. The official JSON was checked after the indexed results were incomplete. Generic event support alone does not establish that a structured app identity reaches this pane, or justify shipping a private payload.

The native Settings extension has reveal/open-parameter entry points and bundle-ID-related strings. Their presence alone is not a row-navigation contract. Claude-dev-max's bounded static investigation reported that both Privacy extension entry points converge on an exact service key; unlike Notifications, the inspected path does not parse an app identity into the row's expansion/selection state. Its host Highlight & Scroll finding did not establish an inbound row route for this extension. These are version-specific static-analysis findings, not proof about every OS implementation. A synthesis-only Claude-dev-max reconciliation reviewed the parent runtime matrix and agreed that no new zero-extra-permission route is justified. The original static round was stopped after its bounded routing analysis; the reconciliation did not repeat or independently re-verify that analysis. No new payload is applied from these findings.

## Research checkpoint before authorization

No new production navigation route is applied. At that checkpoint, the additional-permission implementation decision was pending. Release 15 retains the pane URL, manual app selection and the requested label. Swift production/test logic, localization, configuration, app identities and data are unchanged in this investigation. Existing source writes and encrypted/Keychain support remain disabled/deferred. This report does not claim that every possible OS-specific mechanism is impossible.

## Separate Accessibility design choice

The positive control demonstrates an available QA UI-automation mechanism: the exact Galmuri disclosure triangle can be pressed while leaving Chrome's permission checkbox alone. Shipping that behavior would require the Galmuri process to have Accessibility permission, separately from Chrome-folder access. [Apple’s Accessibility guide](https://support.apple.com/guide/mac-help/mh43185/mac) requires the user to grant that app control access in Privacy & Security settings. Existing trust held by the QA process is not a grant to Galmuri. The app had no such implementation or prompt at that research checkpoint.

The subsequent maintainer preference question asked whether to retain the no-extra-permission flow or authorize an implementation with that separate grant. The maintainer then explicitly chose the additional-permission implementation; no authorization was inferred from silence. If considered, it needs app-specific identity/role guards, stale-element handling and a pane/manual fallback; it must never operate on a permission toggle or other app row. This is a separate design choice, not a verified no-extra-permission deep link.

## Reconciled research outcome and then-retained installation

The verified automatic-expansion mechanism is the QA Accessibility disclosure action, not a new deep link. No app-row URL tested here succeeded. The completed Claude-dev-max reconciliation agrees with retaining the existing route unless the maintainer separately chooses an Accessibility-based implementation. Review notes remain ignored local evidence. Other URL formats, AppleEvent payload variants, other OS versions/locales and off-screen scroll behavior remain untested; the claim is bounded to the recorded cases.

No Swift/test/catalog/configuration change or new app bundle was made. Both installed/build Release 15 copies retain their expected identity and pass strict signature verification. A read-only scoped inventory confirms the prior Debug/rollback paths and exact LaunchServices records remain absent. No reinstall is needed for this research/documentation-only round; it would not add a working route. Actual browser data, permission toggles and Keychain/TCC databases were not accessed by the experiments.


## Authorized implementation follow-up

The maintainer explicitly selected **additional-permission automatic expansion**. [ADR 0008](../adr/0008-optional-accessibility-settings-navigation.md) records the superseding decision. Release 16 adds the opt-in request and bounded, button-triggered row navigation described in [profile connection](../profile-connection.md#withdrawn-release-16-accessibility-navigation--2026-10-27); the earlier unchanged-Release-15 statements above describe the research-only checkpoint.

A subsequent Claude-dev-max source review found an unsafe literal-name fallback, incomplete duplicate enumeration, a hard-coded match count, premature timeout failures and unverified visibility. The parent removed the fallback, requires a named app bundle, uses the outline’s complete root `AXRows` list with a shared actual uniqueness selector, rechecks fresh process/structure, separates bounded post-action confirmation and verifies viewport containment. Known transient read failures permit read-only reacquisition; disclosure is never retried even if AX reports a timeout after delivering it. The final changes were parent-verified, not a further independent Claude approval.

A QA-only extension exercised the production adapter source under the QA process’s existing trust. On Korean macOS 27.0.1, both normal and 850×580 Settings windows produced **expanded**, with the exact Galmuri row selected and visible. Each run observed one permission control and verified its value unchanged; the harness restored the initial disclosure, selection and window size. The public entry separately rejected the unbundled QA process. This does not prove that the installed Galmuri has Accessibility trust or that its row corresponds to the current TCC identity; the user must verify that copy before granting Chrome access. No browser profile, permission switch, TCC/Keychain database or real key was accessed. Other OS versions and Settings languages remain unverified. Full test, capture and installation scope is recorded in [validation](../validation.md#optional-accessibility-settings-navigation--2026-10-27). Local review/runtime evidence is under `build/qa/20261027-accessibility-navigation/`.


## Freeze-report containment · 2026-10-27

After Release 16 installation, the maintainer reported input unresponsiveness: pointer movement continued, clicks and keys had no effect, and the user powered off to recover. The clicked control was Allow Files & Folders in Settings; the causal mechanism and trust state remain unconfirmed. Release 17 removes automatic AX lookup/selection/scroll/disclosure, passive trust checks and the Accessibility request, retaining the ordinary pane/manual route. Earlier successes above are historical QA evidence, not current feature availability or system-stability proof. No reproduction or permission changes are performed during this investigation. [Incident review](accessibility-freeze.md); [current behavior](../profile-connection.md).


The second independent review incorporates the clarified symptom and withdraws earlier absolute timing/deadlock guarantees. The maintainer rejects the mechanism; this is no longer a feature awaiting optimization. Keep manual pane guidance and native accessibility support, with no external UI automation or extra grant for connection. Root cause remains unconfirmed. [Decision](../adr/0008-optional-accessibility-settings-navigation.md); [reconciliation](accessibility-freeze.md).
