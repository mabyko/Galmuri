# Experimental browser apply routes

Release31 · 2026-10-29. Settings → Labs is the explicit entry for both browser-apply experiments. Moving an entry here does not grant write access or make an unsupported profile supported. There are no automatic writes, background exit-triggered replacements or new privileges.

## Settings navigation

Settings opens from the visible gear **Settings…** link at the bottom of the main sidebar, from the initial connection screen, or with the existing app menu / Command-Comma. These use the app’s Settings scene, not macOS System Settings. Its sidebar separates **General** (version and registered-profile count) and **Labs**. Selection is session UI state and does not migrate the workspace.

## Opt-in switches

API editing and direct-file apply have independent, persistent switches, both off by default. The private `labs.json` sidecar is separate from file workspace v1 and API sidecars. Invalid/unreadable settings leave experiments off; a failed save preserves the last in-memory state and all working copies. Switching off never deletes work or uninstalls a Chrome extension. It closes the app’s associated tools; existing workbench disappearance/stop behavior still allows a previously started browser call to finish. It does not revoke a Chrome port or grant/revoke OS access.

## Chrome API editing

Turning **Chrome API editing** from off to on reveals its explanation, installation guide and connection/editor tools, and starts one pass over the profiles already registered in Galmuri. The table lists each saved profile, record status and check time, including profiles not selected in the editor. **Recheck all profiles** is explicit; reopening Settings, changing sidebar pages or choosing another editor profile does not rescan. Results are memory-only. After app restart the saved switch can still be on, but rows start unchecked until manual rescan.

Each read uses only that registered profile’s existing scoped grant and bounded `Preferences` / `Secure Preferences` records for the exact packaged extension ID. Unpacked extension records are included; arbitrary recorded extension paths are never opened. No unregistered Chrome profiles are discovered or added. Results are **Found · Connection unverified**, **Not found**, **Could not check**, or **Not checked**. Missing/inaccessible/malformed/changed metadata never becomes an authoritative uninstalled/disabled claim. Failure in one row does not stop others. A record can be stale, disabled or retained after removal; activation and actual API pairing remain separate. A human-readable label is not a binding between API and file profiles.

Changing the editor selection preserves the registered-profile table. Removed or rebound profiles cannot receive late results, and a new profile stays unchecked until the next manual pass. Turning off clears results and stops before any further profile read; an already-running bounded read may finish but its result is discarded. A newer batch supersedes older callbacks.

Choose **Extension installation** for instructions and **Save extension ZIP** for an archive matched to the running Debug/Release app. Extract it and load the folder containing `manifest.json` from `chrome://extensions` in the intended Chrome profile. Developer mode and the user's Load unpacked confirmation are required in each profile. Keep the unpacked folder at a stable path.

The source folder [`Bridge/extension`](../Bridge/extension) is itself a complete unpacked **Release** extension. It includes a public identity key and host configuration, not credentials. No build tool is required to load that folder. After GitHub publication, users can download the repository source ZIP and extract this folder; GitHub's source ZIP is a repository download. A standalone extension ZIP can later be attached as a release asset. No repository, extension or asset has been published as part of this change.

**Extension installation alone is insufficient.** The matching Galmuri native messaging host must be registered. Existing setup is for explicitly marked dedicated test roots only; it is not a real-profile installer, and macOS may restrict the registration location. Do not bypass this with an unrelated profile or broader privilege. See [dedicated setup](chrome-bridge-proof.md).

Choose **API connections and editor** to refresh/approve a matching label/code and open the separate API workbench. Chrome and its connection page remain open; sessions expire after five minutes and require fresh approval. A successful approved handshake confirms a connection. No response is not proof of noninstallation; the extension can be disabled/disconnected. User-supplied labels and installation/session identifiers do not automatically identify an on-disk Chrome profile by its display name.

Normal real-profile writes remain disabled. Existing explicit dedicated API markers/flags, per-call checks, scope restrictions, merge/review and partial-apply recovery remain unchanged. Account/managed writes, cross-store operations and permanent deletion remain unsupported. [API behavior](chrome-api-workspace.md).

## Direct-file apply

Turn on **Direct file apply** to reveal its explanation and review entry. The entry explains the full quit → reread → three-way merge → review → backup → recheck → replace flow. **Review test-file apply** is available only when the selected profile has pending changes and a supported unrestricted source under Galmuri's app-owned synthetic test root. It opens the existing review in a Settings sheet. The browser-running check still runs on reread and final apply; closing Chrome never submits approval or triggers a replacement. No polling daemon or exit monitor is introduced.

Actual Chrome and Ego Lite originals stay source-read-only, including in Labs. Unknown/mixed/encrypted/account/ordering stores keep their existing restrictions. The switch does not bypass format, permission or lifecycle checks. Switching it off also blocks prepared apply/restore calls and disables restore actions; reading backup history remains available.

The ordinary editor's **Review changes** compares the saved Base with the edited working copy, including deletions and folder contents, without source I/O or acknowledgement. **Refresh** separately rereads/merges the source and previews changes *to the current working copy*. A refresh with no additional working-copy changes says so without claiming pending browser edits are gone. Neither action enters quit-and-replace. Editing, saved copies, pending restoration, refresh and HTML/JSON export remain available; saved file workspace v1 and API sidecars are not migrated or cleared.

## Deferred encryption

Encrypted-bookmark support stays off and disabled with a Planned label. No Keychain access, encrypted-source integration or activation preference is added.

## Acceptance limits

Synthetic tests and native captures verify the entry gates, original preservation, resource packaging and translated guidance. They are not evidence of actual Chrome installation/registration/TCC, physical input/VoiceOver, sync, or real-profile writing. Those remain tracked in [TASKS](../TASKS.md).
