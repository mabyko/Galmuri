---
status: accepted
date: 2026-10-23
---

# Compare three states before applying edits

Users may keep editing bookmarks in Chrome while organizing them in Galmuri. Replacing the original with the app's copy would lose independent changes, so preserve an initial Base and editable Ours, then read Theirs after verified browser exit and perform a three-way merge. Expose incompatible field, deletion, move, and ordering changes for explicit resolution.

Browser exit, a verified original backup, final source rechecks, and recovery are required before direct apply. Rechecking a live disk file alone cannot resolve browser memory and write races. Direct storage support remains gated on format-specific restart, synchronization, and failure tests; this ADR accepts the intended flow, not a validated implementation.
