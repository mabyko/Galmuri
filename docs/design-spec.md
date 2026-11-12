# Design specification

Draft · 2026-10-23. The target is a native SwiftUI macOS app.

## Visual direction

Continue the existing bookmark editor's charcoal surfaces, quiet separators, blue actions, folder sidebar, breadcrumb, and list-centered editing. Use native macOS controls, system typography, table selection, inspector, sheets, and keyboard behavior rather than embedding the HTML UI. The original HTML is a reference, not a production shell.

The self-contained prototype uses synthetic profiles and URLs. Imported source labels are not actual Chrome connections. Its 12 sample items across two profiles and its counts are illustrative. Do not copy real bookmark data into public mockups.

## Screen structure

| Screen | Information and primary action |
| --- | --- |
| Connect | Access purpose, system folder selection, discovered profiles, permission/support state; allow cancel and retry |
| Edit | Profiles/folders in the sidebar, search and bookmark table, optional inspector, selected-item actions, working-copy state; Review changes |
| Browser exit | Exact profile and pending changes; finish work and quit, then recheck; no force-quit |
| Merge/conflicts | Preserved browser changes and three-state comparison, explicit unresolved choices; continue only when resolved |
| Final review | All additions, field/move/order changes and removals, original backup, source recheck; Back up and apply to Chrome |
| Result | Distinct file verification, restart, and synchronization states; show backup/recovery path |
| Backup/restore | Original backup history, differences including later additions to remove, current-state backup, exit/recheck; restore after review |

Editing is the main workspace. Apply review replaces the content area as a separate flow. Keep the target profile visible and avoid unrelated dashboard panels. Autosave copy belongs to the app; direct apply is an explicit action.

## Prototype scope

Open [galmuri-prototype.html](../design/galmuri-prototype.html) locally. It currently has a Korean UI, synthetic profile/folder navigation, search, name/URL editing, add, batch move/exclude, undo, scripted conflict review, and restore demonstration. It does not persist after reload.

The mock uses a dialog for item editing. The native design will evaluate an inspector beside the table. Folder structure editing, drag-and-drop, and HTML/JSON IO are planned product behavior, not implemented prototype features. Export/folder dialogs state this explicitly.

Conflict examples are scripted item-level choices, not a general field/tree merge. Chrome process checks, permissions, original backup, direct apply, and restore are simulated. Label simulations before the user acts and on the result screen.

## Native composition and ownership

Use split navigation, a multi-select table, searchable toolbar, inspector, and sheets as appropriate to the chosen deployment target. The app owns profile working copies; views own transient selection, search, and layout state. Keep one coherent apply phase instead of independent booleans that can represent contradictory steps. IO and merge computation do not belong in a view body.

English is the app source language; use [String Catalog resources](../localization/Localizable.xcstrings) when the target is created. Full language, formatting, and terminology requirements are in [localization policy](localization.md). Native system controls may localize themselves, but app-authored permission/error/recovery copy still needs translations.

## Layout, text, and accessibility

The desktop reference is roughly 1280×820 with a sidebar around 220px and a flexible content area. At smaller widths, reduce optional columns/collapse navigation rather than clipping critical actions. The HTML rearranges at chat/mobile widths for review; this does not imply an iOS product.

Use system fonts and clear primary/secondary text hierarchy. Support long URLs, mixed-script names, and Korean/Japanese/Chinese wrapping without losing full conflict values or recovery warnings. Avoid fixed control widths that only fit one locale. Never translate bookmark titles, profile/folder names, URLs, or file paths supplied by users.

Provide meaningful labels, visible focus, keyboard alternatives to drag-and-drop, table multi-selection, cancellable sheets, and focus restoration. Mark states with text as well as color. Conflict choices are explicit radio selections with no preselected destructive answer. Focus the step heading when the review phase changes.

Native acceptance includes VoiceOver, enlarged text, resize/reflow, all four locales, keyboard-only editing/review, and large collections. The [validation record](validation.md) separates HTML checks, native fixture integration, and basic default-window rendering; it is not a native accessibility certification.

## API workbench checkpoint · 2026-10-29

The [API editor](chrome-api-workspace.md) is a separate native sheet, opened from Settings → Labs → API connections and editor. Labs also contains extension ZIP/instructions and the separately gated direct-file experiment. It keeps the selected connection/folder scope visible, separates local editing from modal merge/review, and exposes local discard, reviewed restore and interrupted-state adoption. File editing remains the ordinary workspace; Review changes previews saved Base versus the working copy, Refresh separately merges the source, and direct-file replacement belongs to Labs. The API route keeps Chrome open and does not show the file backend's exit/replace flow. Removal previews include descendants and apply moves originals to a visible recovery folder.

Own-window workspace/review renders cover four locales. This checkpoint uses single selection and Up navigation; full editing parity, physical keyboard/VoiceOver behavior, enlarged text and actual setup acceptance remain open under task 4.13. Renders and model-driven smoke do not close those checks.


## Native refinement · Release27

The [refinement checkpoint](native-refinement.md) replaces broad green emphasis with muted blue primary actions/row selection and gray chrome. File-connection limits are compact disclosures; saved-local state is visible in the toolbar. API editing adds Back/Forward/Up, multi-selection movement/deletion, guarded drag targets and explicit stop/current-state review. Theme code only touches Galmuri's own native row/table ancestors; it does not alter system preferences or inspect external UI. Dark appearance remains the current design choice. Physical VoiceOver/keyboard/gesture, light appearance and enlarged-text acceptance are not inferred from captures.


## Settings navigation and registered-profile checks · Release31

The main sidebar footer and initial connection view expose a labeled Settings gear. SwiftUI’s [SettingsLink](https://developer.apple.com/documentation/swiftui/settingslink) opens the app’s existing Settings scene (macOS14+), retaining Command-Comma. No external Settings automation or focus control is used. The Settings sidebar separates General and Labs; General presents current build/version and saved-profile count without adding unrelated preferences.

API opt-in performs one existing-grant batch over saved profiles. A bounded native table shows name/folder, compact record evidence and attempt time; a single manual rescan action avoids repeated checks during navigation. Failure, off, source replacement, disconnection and stale callbacks remain distinct from activation or paired write access. [Behavior](labs.md).
