# Optional Accessibility navigation in System Settings

Withdrawn · 2026-10-27; mechanism rejected by the maintainer. Accepted and shipped in Release 16 the same day; removed in Release 17. The following records the original design. The maintainer explicitly chose to allow a separate Accessibility permission for finding and expanding Galmuri in Files & Folders. The tested app-ID URL suffixes do not work, so the app keeps its pane link and offers an explicit user-initiated Accessibility request; an existing grant is used only after the Settings-access button is clicked.

Only the installed application's named row may be selected/scrolled and its disclosure opened. The app never changes a permission switch. Unknown app identity, duplicate or unreadable rows, unsupported pane/layout, revoked trust, cancellation or stale process/UI state use manual guidance. Startup does not request access or operate on another app. This adds no AppleScript/Automation permission, signing entitlement or browser-store write capability.

The OS grant is broader than this implementation's narrow actions and can persist independently of the feature. Local ad-hoc replacement may require user reauthorization; this work does not reset TCC or change bundle identities. AX layout and localized pane titles are version-dependent, and matching a display name does not prove a TCC record's identity: the user must verify the app before granting Chrome access. See [behavior and evidence](../research/permission-row-navigation.md).


## Withdrawal

After clicking Allow Files & Folders in Settings in Release 16, the maintainer reported that the pointer moved but clicks and keyboard input had no effect, then powered off the Mac to recover. Release 17 removed the implementation, trust checks and request. The maintainer subsequently rejected the mechanism. Permission guidance opens the pane once and gives written steps; Galmuri does not inspect or control another app’s UI for browser connection and does not request Accessibility or Automation permission for that purpose.

This is a product boundary, independent of causality: broad persistent trust and external UI control are disproportionate to the convenience, and in-process timeouts cannot contain work in a system service. Whether the automation ran and what caused the incident remain unknown. Do not port the design to another thread, task or helper or substitute Apple Events, screen capture or posted input. Galmuri’s own native accessibility, keyboard support, file panels, process checks and own-window QA are unaffected. Only a superseding explicit maintainer decision can reopen the rejected mechanism. [Incident findings](../research/accessibility-freeze.md).
