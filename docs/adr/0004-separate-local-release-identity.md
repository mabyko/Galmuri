---
status: accepted
date: 2026-10-23
---

# Separate the installed local Release from development

The maintainer wants a verified Release installed for review after development and development bundles cleaned up. Debug and Release must be distinguishable and must not share preferences or privacy identity.

Preserve the existing Debug ID `forked.galmuri.local` and its data instead of migrating it silently. Assign the new local Release `forked.galmuri.local.release`, display name `Galmuri`, and a separate Application Support directory. Debug remains `Galmuri Dev`; its primary icon adds a blue DEV badge to the Release artwork. Both IDs are sacrificial, with ad-hoc signing and no Apple team or organization identifier. The unusual existing Debug suffix is retained deliberately to preserve its identity; a future canonical identity needs a separate ownership/migration decision.

`Config/BuildIdentities.json` resolves this one SwiftPM app target in both configurations. The packaging script passes the selected primary set to the asset compiler and consumes its generated Info.plist keys. An xcconfig would not be consumed by this SwiftPM packaging workflow, so no inactive Xcode configuration is introduced.

Working copies and backups are never removed by app cleanup. The new Release starts its own workspace; no automatic copy of development data or permission records occurs. Ad-hoc replacements can require privacy reauthorization. Public signing, App ID registration, notarization, publication, and real Chrome write support remain separate decisions/gates.
