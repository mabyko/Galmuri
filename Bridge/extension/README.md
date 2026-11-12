# Galmuri Chrome extension (experimental)

In the repository, this folder is a complete, unpacked **Release** extension. No npm build is needed. A ZIP saved from the app is generated for that app’s Debug/Release variant.
It is not on the Chrome Web Store. It requires a matching Galmuri Release app and
native-messaging host registration; installing this folder alone is insufficient.
Normal connections remain browser-read-only. Only dedicated, explicitly marked
synthetic proof connections can apply changes. Installing is not approval to write.

## Download and install

After the repository is published on GitHub, download its source ZIP and extract
`Bridge/extension`, or download a matching `Galmuri-Chrome-Extension.zip` asset if
one is attached to a release. GitHub's source ZIP contains the whole repository,
not a single-folder download. No repository or release asset has been published yet.

The matching local app also provides Settings → Labs → Extension installation →
Save extension ZIP. Extract that ZIP first.

1. Open the Chrome profile you intend to connect.
2. Navigate to `chrome://extensions` and enable Developer mode.
3. Choose **Load unpacked**, then select the folder containing `manifest.json`.
4. Keep the folder at a stable location while the extension is installed.
5. Use the extension's connection page to request a code. In Galmuri, open
   Settings → Labs → API connections and editor, refresh requests and approve
   only the matching profile label/code. Check approval in the extension.

Repeat installation/activation for each profile you want to connect. No response
does not prove the extension is absent: it may be disabled or disconnected.
Keep Chrome and the connection page open during API operations. Sessions currently
expire after five minutes and require approval again. The extension has no website
permissions or content scripts. Its permissions are `bookmarks`, `nativeMessaging`
and `storage`.

## Native host and supported tests

Use the repository's [dedicated setup guide](../../docs/chrome-bridge-proof.md).
The existing setup script only supports marked test roots; do not point it at a
real/shared profile to bypass current gates. macOS may deny host-manifest access.
The app does not register the host in actual Chrome automatically.

Debug apps require the separately generated Debug extension from
`python3 scripts/build-bridge.py debug`. Do not pair the Release folder with Debug.
For source changes, rerun the build and choose Reload in the corresponding profile.

English documentation is canonical. The extension UI supports English, Korean,
Japanese and Simplified Chinese. Read the current limits before using it.
