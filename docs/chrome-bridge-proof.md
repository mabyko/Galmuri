# Chrome bridge: pairing-only local proof

Historical pairing checkpoint: Release25 · 2026-10-28. Release26/27 extend the bridge with [API workspaces and reviewed editing](chrome-api-workspace.md); its manifest now requests bookmarks permission, and the client reads bookmarks only after explicit pairing. The pairing-only descriptions below record Stage A, not the current complete capability set. This is a developer/maintainer proof for **dedicated synthetic test profiles**, not real Chrome bookmark editing.

## What works

Settings → Labs → API connections and editor displays explicitly refreshed connection requests (the historical Release25 tab was Settings → Chrome Bridge). In the extension's full connection tab, enter a profile label and choose Show connection code. Keep that tab open, switch to Galmuri, refresh requests and approve only a matching label/code. Then Check approval in the extension. The extension acknowledges the exact approved session to the host. A new session always needs approval, even when its profile-local installation UUID is unchanged.

Sessions last at most five minutes; each command checks expiration. Closing the extension tab normally closes the native port and removes request, approval and acknowledgement files. The UI refresh is manual; a previously displayed card is not proof that its tab is still connected. Failed/expired/stale requests reject approval. Abrupt host death can leave expired files; they do not grant future sessions access. Inventory is capped and no automatic user-data deletion is performed.

This does not add a connected bookmark workspace, read bookmarks, mutate them or invoke Keychain. The extension manifest deliberately has only `nativeMessaging` and `storage`. Stage B will add API-visible snapshots; later stages will separately prove writes and recovery. Existing file-based connections and their write restrictions are unchanged.

## Local build and identity

Run from the repository root:

```sh
bash scripts/build-local.sh debug
python3 scripts/build-bridge.py debug
python3 scripts/test-bridge-host.py 'build/debug/Galmuri Dev.app'
```

Use `release` and `build/release/Galmuri.app` for the matching Release build. Packaging embeds and separately ad-hoc signs `Contents/Helpers/GalmuriBridgeHost`; the helper loads its variant and exact allowed extension ID from signed app resources. `Config/BuildIdentities.json` remains the source of app identities; `Config/BridgeIdentities.json` pins distinct public extension keys/IDs and host names. No private keys, Apple team IDs, App ID registration or Web Store publication is included. Never mix Debug and Release registrations/workspaces.

## Dedicated registration only

Prepare two **new canonical private directories**: a disposable Chrome user-data root and an isolated Galmuri workspace. Each must be owned by the current user with mode `0700`. Place a regular, owner-only (`0600`), single-link `.galmuri-bridge-proof` marker in each: exactly `Galmuri dedicated Chrome proof v1` plus newline for the browser root, and `Galmuri pairing-only proof v1` plus newline for the app workspace.

```sh
python3 scripts/setup-bridge-proof.py --variant debug \
  --app '/absolute/project/build/debug/Galmuri Dev.app' \
  --browser-root '/absolute/dedicated/ChromeUserData' \
  --workspace '/absolute/dedicated/GalmuriWorkspace'
```

The script checks identities/signature/markers, writes an exact-origin native-host manifest only inside that root's `NativeMessagingHosts` directory, and creates a private launcher in the dedicated app workspace. It refuses existing targets; inspect them rather than overwriting. It never scans/registers user profiles, writes system-wide manifests, changes permission records or uses `sudo`. The helper's marker-bound `--proof-workspace` override is supplied by this local launcher, never by extension message payloads. All marker/data paths are developer-owned test inputs, not production bookmarks.

Load the matching generated extension in the permitted dedicated Chrome for Testing profile, then open its connection page from the toolbar launcher or its Options entry. Use the isolated Galmuri workspace when launching the app (`--workspace`); do not accidentally pair into normal app data. Public extension installation, actual Google Chrome host registration and TCC acceptance remain separate future work. Current Chrome for Testing and Google Chrome use different default host locations; do not assume a test-root registration installs the production bridge.

## Protocol and boundaries

Version 1 allows `hello`, `status` and `acknowledge` only. Native-endian length-prefixed UTF-8 JSON is capped at 64 KiB. Each request has a UUID, protocol version and strict command; the host limits a connection to 64 unique requests. `hello` creates one random session and a six-digit display code. The app rechecks the full saved request and expiry before approval. `status` reports only that same session; an acknowledgement is accepted only after an approved status was delivered. No request accepts a file path or a bookmark operation. The client validates correlation, variant, session, label, lifetime and `bookmarkAccess: false`; malformed replies/timeouts/disconnects reject pending calls without mutation retries.

The private proof-file directory and reads reject symlinks, nonregular files, hardlinks, broad permissions, unexpected ownership, oversized/changed files and mismatched identities. Same-user code is not a new OS security boundary: a locally compromised account can run host executables or modify its own files. Native Messaging's exact extension-origin allowlist and deliberate app confirmation are routing/consent safeguards, not protection from an attacker controlling the user's account.

## Evidence and remaining acceptance

Core framing/store regressions and extension-client tests cover approval/acknowledgement, isolation, expiry, stale or malformed messages/files, disconnect and rejection. Packaged Debug/Release host tests cover actual stdin/stdout framing, wrong origin/version/command, duplicate IDs, truncated/oversized input, premature acknowledgement and normal cleanup.

The dedicated CFT153 proof used two distinct synthetic profiles plus a normal reconnect and separate Release combination. A QA-only background worker drives the same client module and Core approval method, then verifies browser acknowledgement. It is not part of the generated product extension and is not a physical click/picker test. Normal exits preserve the three synthetic bookmarks and clean session JSON. Own native window captures cover the new panel in four locales; translated strings still require language review.

Maintainer checks remain: toolbar launcher/connection tab, focus switching and approval buttons, stale-card presentation and VoiceOver. No actual user Chrome setup, OS permission grant, bookmark API read/write, sync or crash-durability claim is made. See [validation](validation.md) and [future stages](chrome-api-bridge-plan.md).

The completed QA run removed its dedicated host manifests/launchers after all browser instances exited. Retained synthetic profile/evidence directories are not active registrations; rebuild the matching helper and rerun marked-root setup for a later proof. No real Chrome host registration was installed.


Current API write testing requires a separate `.galmuri-api-write` marker in both dedicated roots and `--enable-api-test-writes` during setup. The old pairing-only marker never enables writes on its own. Ordinary registrations remain read-only. See the current API guide before using Release26.


Release27 requires bidirectional `apiProtocol: 2` during hello/replies; framing remains version1. It adds bounded chunked operation records and acknowledged stop. The guide's Stage A protocol description is historical, and old unpacked clients must be rebuilt/reloaded rather than used with the current helper. See [native refinement](native-refinement.md).
