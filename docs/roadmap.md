# Roadmap

Use [TASKS.md](../TASKS.md) for the current milestone, next task, checkboxes, and blockers. This page explains the sequence; it deliberately does not maintain a second set of progress states.

The maintainer has resumed native implementation and local testing, with parallel core and UI work. Draft review, synthetic integration, and native execution are tracked in `TASKS.md`; public publication remains deferred.

Encrypted-bookmark support was deferred by the maintainer on 2026-10-25. It is represented only by a disabled “Planned” item in Settings → Labs. Real Keychain access and encrypted-store native integration are not part of this sequence; plaintext permission, preservation and lifecycle gates remain in scope. Existing core experiments are historical evidence, not a reason to bypass unsupported-format checks.

The 2026-10-29 Labs decision separates ordinary persistent editing/export from experimental API/file apply. Extension ZIP/source-folder distribution is prepared locally; actual GitHub or store publication is still deferred. Moving direct-file review to Labs does not activate real originals or automatic writes on exit. See [Labs](labs.md).

## Delivery sequence

1. **Product preparation:** a reviewable specification, synthetic prototype, open-source documents, and localization resources.
2. **Native app and profile reading:** build a SwiftUI workspace and validate user-approved profile access before enabling original writes (technical gate A).
3. **Persistent editing and format preservation:** complete app working copies and prove that supported source data can survive a no-change/edited round-trip (gate B).
4. **Merge and review:** implement fixture-driven three-way merge and native conflict choices (gate C).
5. **Direct apply and recovery:** verify exit, backups, source rechecks, replacement, restart adoption, synchronization, and restore in dedicated profiles (gates D–E).
6. **Four-language quality and local acceptance:** complete native localization/accessibility, run the native app locally, exercise the full supported flow, and document reproducible local build/test results. This is the endpoint of the implementation plan.
7. **Later publication:** create/publish the GitHub repository, enable hosted CI/security reporting, and prepare public distribution only when separately requested after local review.

The validation order A–E is a proposed implementation sequence. Native UI can progress against synthetic data alongside read-only investigation, but direct writes stay disabled until the relevant gates pass. All locales need UI and language review; a populated catalog alone is not release support.

GitHub source publication and public binary release are deferred until after implementation and local testing. Product completion still requires verified direct apply; export-only editing does not satisfy that goal. Dates, supported versions, and release commitments will be recorded when established.

See the [task list](../TASKS.md), [product plan](product-plan.md), and [technical validation gates](technical-validation.md).

Task 1.8 replaces mandatory file navigation with user-initiated normal default-location discovery and in-app failure guidance. The native folder picker is a secondary explicit access/custom-location action. Fixture coverage does not close native TCC acceptance. See [connection flow](profile-connection.md).

Task 1.9 adds browser selection and an explicitly experimental, read-only Ego Lite default-location preset. This does not expand validated browser/write support; preserve the native TCC, authoritative-format and runtime adoption gates.

Task 1.10 improves the denied-access path with a dedicated permission guide. It does not close the real TCC/picker acceptance gate or change data, signing and external-write boundaries.

The 2026-10-25 permission research (1.11) distinguishes native folder choice, targeted macOS 27 browser-data switches and Full Disk Access. Task 1.12 implements conditional Settings-first guidance, separate EACCES copy, bounded error codes and fresh selected-URL priority. Native grant/persistence/revocation under 1.3/1.6 still requires acceptance. [Research](research/macos-bookmark-access.md).

Task 1.13 follows maintainer feedback that opening Settings at its home screen still requires too much navigation. The button targets Files & Folders using a locally verified Settings anchor, with a normal-launch fallback and visible manual path. Pane navigation is separate from OS grants and does not close 1.3/1.6.

Task 1.14 renames the action to **Allow Files & Folders in Settings**. The maintainer screenshot confirms an app-specific Chrome switch exists, but a reliable URL to select/expand that app row was not established. That checkpoint retained manual app selection. Task 1.15 subsequently received explicit approval for optional Accessibility navigation; it adds a separate request and guarded own-row expansion, while Chrome approval remains manual. Test actual installed-app grants separately under 1.3/1.6.


Task 1.16 pauses further grant/automatic-row acceptance after the maintainer’s freeze/reboot report. Contain by removing the Accessibility implementation and request rather than retrying it on this machine. Release 17 returns to pane/manual navigation. System-level causality is unconfirmed; the maintainer subsequently rejected the mechanism, so automatic-row work is not planned. [Incident review](research/accessibility-freeze.md).

Task 1.17 records the second review and withdrawal as a product boundary. Existing native accessibility and ordinary app loops remain in scope. No reproduction or additional log diagnostics are required.

Task 1.19 makes standard folder consent primary and pre-opens the exact target. It supersedes the earlier Settings-first initial-denial route, retains Settings only after selected-folder failure, and reuses explicit one-shot discovery. Synthetic panel/routing checks precede any user-operated native grant acceptance; this does not reinstate external UI automation.

Task1.20 separates source inventory/readability from current-store authority. Readable primary plaintext is selectable alongside excluded companion files; metadata/problem evidence is visible without decryption. This does not close format-authority, current Chrome freshness, direct-write or encrypted-support gates.


## Proposed API-assisted branch · 2026-10-28

The maintainer asked to prepare an optional extension-assisted direct-apply approach before implementation. See the [bridge proposal](chrome-api-bridge-plan.md) and task 4.8. Start any future implementation with a dedicated-profile Native Messaging registration/pairing proof, then API snapshots/schema preservation, small reversible writes/restart adoption, interrupted-batch recovery and native integration. This branch uses a running paired browser and separate API-visible snapshots, not offline file replacement or original-byte backup guarantees. It does not enable existing write gates, encryption work, real-profile tests or publication. Scope stages remain proposals until requested.


The 2026-10-29 [API checkpoint](chrome-api-workspace.md) implements snapshot/persistence and reversible local-scope apply. Its real CFT model/restart evidence advances the API branch, independently of raw-file gates. Broader recovery/process/power-loss, real Google Chrome registration, account/sync and physical native acceptance remain staged work; publication is still deferred.


Release27 closes the bounded transport bug and implements acknowledged stop plus the [gray/blue native refinement](native-refinement.md), backed by measured Core improvements and synthetic/dedicated-browser checks. Next acceptance remains actual Chrome setup, physical editing/keyboard/VoiceOver and independently authorized write/sync scope; no public publication or real-profile write enablement is implied.
