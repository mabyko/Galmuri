# Accessibility navigation freeze incident

2026-10-27 · investigation and containment; system-level cause unconfirmed.

## Report and diagnostic scope

After local Release 16, the maintainer initially described a freeze requiring reboot. They subsequently clarified the symptom: the pointer continued moving, but mouse/trackpad clicks and keyboard input produced no response. Treat this as reported input unresponsiveness, not established full-machine/kernel freeze. The maintainer clarified that the clicked control was **Allow Files & Folders in Settings**, and explicitly requested code-first review without another click. Whether Accessibility had already been granted and which individual apps/menus could still receive events are not confirmed. Pointer movement is confirmed to have continued. Do not infer that row automation actually ran from this report alone. No reproduction is attempted on the affected machine.

Read-only checks confirm a new boot at 14:22:39 KST. A subsequent reset report records forced-off/reset flags; this supports the reset report, not its cause. A bounded inventory found no recent Galmuri, System Settings, WindowServer, panic or watchdog crash report. Hard resets can leave no useful report. A filtered preboot unified-log query includes WindowServer unresponsive messages without sufficient target attribution or stacks to establish causality. An initial substring `hang` filter also matched `change` and is explicitly discarded as evidence. A postboot Jetsam report cannot establish the cause of the earlier freeze. Raw system logs, private diagnostic identifiers and browser data are not copied into public documentation or fixtures.

## Confirmed code risk in the withdrawn implementation

`SettingsAccessibility` entry/confirmation methods were isolated to `@MainActor`; their synchronous validation, attribute queries and mutations therefore ran on the main thread. An async wrapper does not offload synchronous calls made directly within it. The nested async finder’s exact executor was not established by the earlier policy tests; no claim is made that every finder call ran on main. Deadline/cancellation checks run between calls; they cannot interrupt a blocked synchronous call. Whole root-row snapshots were reacquired repeatedly for uniqueness validation. Per-element messaging timeouts and policy unit tests did not establish a hard watchdog or system-wide stability. This is a credible Galmuri/Settings responsiveness risk; without a causal trace it is not proof of kernel, WindowServer or full-machine failure.

Earlier harness-trusted adapter successes and safe permission-target checks cover only their recorded cases. They did not test the installed app’s permission prompt/identity or establish freeze immunity. Previous claims of bounded attempts must be read as cooperative software checks, not a preemptive guarantee.

## Containment

Release 17 removes the AX implementation, all callers, trust checks/request and obsolete policy tests/strings. It keeps the existing ordinary Files & Folders pane URL, normal-launch/manual fallback and user-operated approval instructions, plus a four-language suspension notice. No Accessibility permission is needed. This removes the suspect extra mechanism; it does not prove the original system-level cause was fixed.

Existing workspaces, preferences, original backups and OS permission records remain protected. Do not reset TCC, revoke/grant controls automatically, inspect real browser stores or rerun the old adapter. Source-write/encrypted/Keychain gates are unchanged. Preserved incident source and bounded diagnostic summaries remain in ignored local `build/qa/20261027-freeze-investigation/`. Any future row automation requires a separate decision and isolated failure testing, not merely moving these calls to another Task.

## Independent review and reconciliation

Claude-dev-max (Opus 5.5, effort max) completed a read-only review of the preserved Release 16 source, current containment and bounded evidence. It agrees with removal rather than restructuring, confirms that automation depended on existing trust, and identifies repeated main-thread validation/IPC plus retry pressure as responsiveness risks. Its nested-type isolation correction is reflected above. The exact finder executor was not runtime-observed. We do not adopt an absolute “about six seconds maximum” or claim to rule out OS/service deadlocks: cooperative checks and the bounded source loops do not prove those guarantees.

The reviewer’s packaging warning used an intermediate failed attempt. That attempt incorrectly assumed a SwiftPM binary directory; the active build reports `.build/out/Products/Release`. Packaging was rerun using the actual absolute bin path, and installed Release 17 passed signature, source-match and symbol checks. This was not a working-directory fix. Both wrong-path packaging and the Release-only capture-flag invocation are QA mistakes, not incident evidence; no completed native capture set is claimed. Only isolated startup/editing smokes ran, never the reported Settings control.

A follow-up metadata summary finds WindowServer unresponsive messages already at 13:30, before the Release 16 installed-path launch. It contains no direct Galmuri-name/known-PID attribution, so these messages cannot identify the cause. Accessibility-related tccd records mention the app but yield no retained authorization result; they do not establish trust or that automation ran. Timestamp buckets are explicitly filtered because the OS query returned records beyond its requested end. No TCC database or permissions were accessed or changed.

The code review and removal are complete; root cause remains undetermined. No reproduction or further permission-action test is requested. See [tracker](../../TASKS.md) and [validation](../validation.md#freeze-report-review-and-accessibility-removal--2026-10-27).


## Input-symptom clarification and static follow-up

The later pointer/click/keyboard clarification does not fit a claim that Galmuri’s main-thread stall alone disabled all system input. Such a stall could prevent Galmuri from processing its own events; the report does not establish which other UI processes were affected. Possible Settings/session focus or event-delivery involvement remains a hypothesis, not a diagnosed WindowServer failure.

A static search of current app sources and the preserved incident feature found no event-tap/global-input suppression, HID control, secure-input enabling, or global event monitor. The removed feature handed activation to Settings and changed its own named row through AX. Native table key handlers are app-scoped; the explicit `window.sendEvent` helper is inside Debug-only NativeCapture. Existing file-panel `runModal` calls belong to separate chooser/import/export actions and are not invoked by the reported Settings button. This checks direct code paths only; it cannot exclude effects inside system frameworks or other software. No additional UI action, reproduction, app install or permission operation was performed for this follow-up.


## Maintainer direction after symptom clarification

The maintainer rejects adding this permission-navigation automation. Removal remains in force; treat external Settings-row control and its extra Accessibility permission as outside the connection design rather than a feature awaiting optimization. A second Claude-dev-max review is requested with the clarified input symptoms. Review only code and retained evidence; no reproduction. This product decision does not establish the incident’s causal mechanism.


## Second review and final product boundary

Claude-dev-max’s second read-only review incorporates pointer movement with ineffective clicks/keys. Both session-level input delivery trouble and a frontmost app that failed to handle input remain possible; the evidence does not decide between them. No direct global input-suppression API was found in Galmuri, but indirect system effects cannot be excluded. The review withdraws its earlier six-second guarantee and no-mutual-wait claim. We record bounded source loops, not a guarantee that every external call returns or that the operating system is unaffected. No new reproduction, log query, grant check or Settings action follows this review.

The maintainer’s rejection is sufficient for the product decision, independently of cause. [ADR 0008](../adr/0008-optional-accessibility-settings-navigation.md) is **Withdrawn**, not temporarily suspended. Galmuri must not inspect/control another app’s UI or request Accessibility/Automation permission for browser connection; one-shot Settings navigation with written instructions remains. This applies even to a bounded attempt and cannot be bypassed with another thread/helper/API. Ordinary in-app loops, Galmuri’s own activation/windows/accessibility, keyboard/VoiceOver support, file panels, browser process-state checks and own-window Debug QA remain allowed. QA does not script Settings or reproduce the incident without a new explicit request.

No additional runtime containment logic was needed. Release 18 only removes the obsolete temporary-unavailability notice and translations; the manual instructions remain. The 159-test Release 17 result remains the preceding logic baseline, not a new suite run for copy deletion. The second review is retained locally at `build/qa/20261027-freeze-investigation/claude-reconciliation-r2.md`. Further cause diagnosis/reproduction is outside this completed review; unknown trust, exact timing and app/session scope are not silently inferred.
