---
status: accepted
date: 2026-10-23
---

# Isolate local native development from browser write support

The maintainer requested implementation and local tests before GitHub publication. The native direction is accepted; Chrome direct-write compatibility and distribution identity are not established.

Use SwiftPM with Swift 6 and a macOS 14 build target, Foundation core logic, and SwiftUI with limited AppKit integration. The local bundle is `Galmuri Dev`, signed ad hoc under `forked.galmuri.local`, with its own Application Support directory. No signing team or organization App ID is selected. Local development is unsandboxed; user-selected folders use persistent security-scoped bookmarks, without assuming this proves future Sandbox/TCC behavior.

Retain the reviewed draft rather than introduce a web runtime, database, or project-generation dependency. Use focused core and app-state tests plus actual native window rendering. Preserve original bytes, keep working copies separate, and restrict replacement/restore to the app-owned synthetic test directory. External connected profiles remain read-only until the corresponding technical gates pass.

This permits useful native editing, merge, backup, and recovery verification while protecting real originals. It does not satisfy the final direct-apply product requirement. Correct-profile lifecycle detection, browser restart adoption, synchronization, file attributes/durability, public bundle identity, Sandbox, signing, notarization, and supported OS/Chrome version claims require further evidence.

The later local Release/Debug split extends this initial boundary in [ADR 0004](0004-separate-local-release-identity.md). The original identity/data stay with Debug.
