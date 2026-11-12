# 0006 — User-initiated default profile discovery

Accepted for the local unsandboxed build · 2026-10-25.

The maintainer found the mandatory file-browser step difficult: Chrome’s internal files and numbered folders appeared before the app showed profile names. A suggested path alone did not make this a usable primary connection flow.

An explicit **Connect Chrome** action now authorizes a normal, read-only metadata lookup at the known standard Chrome data directory. There is no startup scan, home-directory search or agent-side real-profile probe. Reuse a valid saved security-scoped bookmark only when it resolves to that exact directory, without UI or mounting. Otherwise use normal file APIs under the app’s current OS permissions. An accessible result shows the existing profile chooser; only explicitly selected supported payloads are subsequently read.

A permission failure stops that attempt and shows an in-app explanation with explicit access/custom-location/retry controls. No retry with higher privileges, altered entitlements, TCC reset, copied browser store, encryption override or key access is allowed. A missing directory is distinguished from denied access. Folder selection is secondary; it starts at the target’s parent rather than inside Chrome, uses a short instruction, and validates the exact requested folder for an access request. Custom locations use a separate explicit picker.

The local bundle remains unsandboxed and ad-hoc signed under the existing separate Debug/Release identities. App Sandbox describes entitlement-based restrictions; it does not prove that TCC or protected browser data will permit this read. The OS remains the authority. A normal API attempt may still require the user’s native approval or fail. Do not extrapolate fixture access to a successful real Chrome grant or future sandboxed distribution.

Selected file errors retain atomic workspace preservation. Only genuine OS source-read permission failures redirect a selected-profile import to access guidance. Malformed/unsafe stores and app-workspace save failures keep their own errors; a Chrome folder grant cannot fix them. Known regular/structural core failures are not used to justify broader access.

External writes, encrypted support and Keychain access remain disabled/deferred. Workspace v1, existing Base/Ours, backups and source preservation rules are unchanged.

Sources: [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox), [sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox), [open/save panel URL validation](https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:validate:)). Current panel validation documentation was fetched through Context7; Apple Security documentation was retained in local QA evidence. This decision extends [ADR 0003](0003-local-development-boundary.md) without enabling additional privileges.
