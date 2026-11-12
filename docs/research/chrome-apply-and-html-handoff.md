# Chrome direct apply and HTML handoff

Research date: 2026-10-28. This is a source/code review and manual-use recommendation. Installed Release24, browser data, permissions and encryption scope are unchanged. No Chrome import, deletion, restart or sync experiment was performed in this review.

## Finding

Direct editing of Chrome bookmarks is technically possible. It is not currently supported safely by Galmuri for general connected profiles under the accepted no-extension/deferred-encryption boundary. Use the existing Netscape HTML export as an **interim manual handoff**, with additive-import guidance. This does not complete the original direct-apply MVP or convert HTML into synchronization.

The maintainer requested this fallback if direct apply cannot be supported. The long-term persistent-profile goal is retained; no new encrypted adapter, extension, browser UI automation or permission mechanism is authorized by this review.

Follow-up: the maintainer subsequently requested a planning review of the extension-assisted option. See the [Chrome API bridge proposal](../chrome-api-bridge-plan.md); the installed app and this manual fallback remain unchanged.

## Direct-apply evidence

- **Official browser editing surface:** Chrome's [bookmarks API](https://developer.chrome.com/docs/extensions/reference/api/bookmarks) supports reading, creation, title/URL updates, movement and removal, subject to the extension's `bookmarks` permission and protected/managed-folder restrictions. [Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) connects an extension to a registered native host. This provides a possible extension-assisted architecture, not an API that a standalone Swift app can invoke directly. It would introduce a per-profile extension dependency and a separate integration/validation project; it is not being implemented.
- **Files are implementation details:** pinned Chromium 153 [loader configuration](https://chromium.googlesource.com/chromium/src/+/78e5e45d4bb41035e17ea4da2cc257f496416ac9/components/bookmarks/browser/model_loader.cc#145) chooses plaintext or encrypted primary storage according to the feature stage. [Secondary verification](https://chromium.googlesource.com/chromium/src/+/78e5e45d4bb41035e17ea4da2cc257f496416ac9/components/bookmarks/browser/model_loader.cc#94) repairs a differing secondary from the selected primary. [Writing](https://chromium.googlesource.com/chromium/src/+/78e5e45d4bb41035e17ea4da2cc257f496416ac9/components/bookmarks/browser/bookmark_storage.cc#249) handles the two copies separately. Editing only plaintext can therefore be ineffective or overwritten; finding a readable file does not establish write authority.
- **Observed current blocker:** the prior dedicated CFT153 initial/restart check produced `Bookmarks`, `EncryptedBookmarks2` and `BookmarkMergedSurfaceOrdering`. Galmuri correctly rejected apply, preserved source bytes and created no receipt. Unknown/default browser states also retained the lifecycle blocker. See the [recorded experiment](../validation.md#dedicated-chrome-storage-decision). This result is specific to that version/configuration, not proof that every Chrome profile is encrypted or that all offline writes are impossible.
- **Current app boundary:** `ApplyCoordinator.canWrite` restricts replacement to app-owned test profiles. Removing that check is not a solution: format authority, mixed-store consistency, restart/restore and sync gates remain open. Historical controlled encrypted-store evidence is not current plaintext support and does not authorize encryption work.

Context7 resolved Chrome Extensions, then returned official bookmarks/native-messaging API material. Current Chrome Help and the existing pinned Chromium source copies were also inspected. The pinned sources are not a claim about all future versions.

## What HTML import does

Google's [import/export instructions](https://support.google.com/chrome/answer/96816?hl=en) describe importing an HTML file through Chrome's menu. Existing bookmarks are retained; imported content is added, with placement depending on whether Chrome already has bookmarks. Do not promise one fixed localized destination-folder name.

Consequences for Galmuri's edited output:

| Change in Galmuri | Result of importing HTML into an existing Chrome collection |
| --- | --- |
| Add an item | Imported items are added; verify the destination in Chrome. |
| Rename, edit a URL or move an existing item | The exported version can be added; the existing Chrome item is not updated through a shared ID. |
| Delete an item from the working copy | It is absent from the export; HTML does not instruct Chrome to remove its original. |
| Import a whole collection repeatedly | Copies can accumulate. No automatic deduplication or idempotence is promised. |

`ProfileIO.exportHTML` exports folder names, bookmark titles/URLs and tree order; it does not export Chrome IDs/GUIDs, timestamps, sync metadata, favicons or a change log. HTML is not a lossless original backup. Workspace JSON retains Galmuri's Base/working state and is a separate recovery artifact.

## Safe manual handoff using Release24

1. In the **intended Chrome profile**, use Bookmark Manager → menu → Export bookmarks to save a separate pre-change HTML backup. Also save Galmuri's workspace JSON if its pending edits need recovery.
2. In Galmuri, choose the intended connected profile and export scope. The existing HTML action exports the open folder's children/subfolders when browsing a folder, or the whole working tree from a global view. Filters/selection are not an export scope. Use a distinct output filename; keep the backup separate.
3. In that Chrome profile, use menu → Bookmarks and lists → Import bookmarks and settings, choose the bookmarks HTML file and complete the import. Inspect the added names, URLs and hierarchy before importing again or changing old items.
4. Keep the old collection initially. If replacing a particular folder, compare the old and imported copies first, then deliberately remove only the superseded scope in Chrome. This is manual replacement, not a Galmuri apply or merge. Reconnect/refresh intentionally afterward; HTML imports are new Chrome items and must not be matched to old identities by URL alone.

**No reset is required for an additive import. Do not erase all existing bookmarks as the default instruction.** Full replacement would require a complete, independently checked collection and an explicit user decision. Account-saved bookmarks are shared across devices ([Google account guidance](https://support.google.com/chrome/answer/165139?hl=en)); conservatively treat changes to that collection as potentially affecting the other devices. A local HTML backup is not an atomic account-wide undo.

## Coverage warning and remaining work

A current connected working copy can contain **only primary plaintext Bookmarks**, excluding encrypted/account/other stores. It is not established as Chrome's complete or latest model. Exporting that tree cannot recover omitted bookmarks. Never recommend replacing the full Chrome collection from a partial working copy, even after a file refresh.

Release24 already provides HTML export and workspace JSON import/export; Galmuri does **not** currently import arbitrary bookmark HTML. Do not describe Chrome-export → Galmuri-HTML-import as an implemented path. If complete Chrome-model ingestion becomes necessary while native encrypted reads remain deferred, an explicit HTML-import feature is a possible separate task.

A dedicated Chrome HTML round-trip with nonempty originals, changed/deleted items, repeat imports, nested folders and same-URL duplicates remains untested here. Chrome-specific placement, HTML preservation and account-sync behavior need that evidence before stronger support claims. No new app UI or automatic import/replace action was implemented in this research pass.
