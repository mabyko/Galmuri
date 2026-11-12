# Galmuri · 갈무리

**Bring your bookmarks together. Refine them. Apply them back to your browser.**

English · [한국어](README.ko.md) · [日本語](README.ja.md) · [简体中文](README.zh-Hans.md)

Galmuri is an experimental **native macOS bookmark editor** written in SwiftUI. It reads the bookmarks of several Chrome profiles into working copies that you can edit safely, shows you every change before anything leaves the app, and merges your edits with whatever the browser changed in the meantime.

> **Status: experimental.** There is no packaged download yet; you build it from source. Galmuri never writes to your real Chrome profile files. Getting changes back into Chrome today means exporting an HTML file and importing it, or using the opt-in extension route described under [Labs](#labs-experimental).

## What it does

- **Connects to Chrome profiles, read-only.** Pick the profiles you want; Galmuri keeps its own copy of each and leaves the originals untouched.
- **Edits like a file manager.** Nested folders, search, multi-select move, drag and drop, ordering, same-address browsing, and Undo.
- **Shows what changed.** A Pending Changes view lists every added, edited, moved and deleted item. Revert a selection or discard everything.
- **Merges instead of overwriting.** Refresh rereads the browser's bookmarks and runs a three-way merge with your edits. Conflicts are shown side by side and you choose.
- **Exports.** Netscape HTML (whole profile or one folder) that any browser can import, and a JSON backup of the whole workspace.
- **Speaks four languages.** English, Korean, Japanese and Simplified Chinese.

## What it does not do yet

- Write to real Chrome profile files. Direct file apply exists only for app-owned synthetic test files.
- Read encrypted or account-only bookmark stores. Profiles need a plaintext `Bookmarks` file.
- Sync, cloud storage or accounts. Everything stays on your Mac.
- Ship a signed, notarized build.

## Build and run

Requires macOS 14 or later, the Xcode command-line tools and Swift 6. There are no third-party dependencies.

```sh
swift test
python3 scripts/check-localization.py
scripts/build-local.sh release
open "build/release/Galmuri.app"
```

The script produces an ad-hoc-signed local app; it does not install anything or register an Apple team. See [local development](docs/local-development.md) for Debug builds, data locations and the disposable smoke check.

On first launch choose **Connect Chrome**. macOS may ask for access to the browser's data folder; Galmuri explains the step and only reads the profiles you select.

## How changes are kept safe

1. Galmuri saves the bookmarks it first read (**Base**) and you edit a separate working copy (**Ours**).
2. Before anything is applied or refreshed, it rereads the browser's current bookmarks (**Theirs**).
3. A three-way merge combines the two sides. Anything changed on both sides becomes a conflict that you resolve explicitly.
4. You review the final result, including removals, before it is used.

Local copies of your work are written before a refresh, before a profile is disconnected and before a workspace import.

## Labs (experimental)

Settings → Labs holds two switches that are off by default:

- **API connections and editor.** A small Chrome extension plus a helper inside the app read and edit bookmarks through Chrome's own bookmarks API while Chrome stays open. Each profile is paired by an on-screen code. Ordinary connections are read-only at Chrome; applying changes is limited to dedicated test setups. Removed items are moved to a recovery folder, not deleted. See [API setup, behavior and limits](docs/chrome-api-workspace.md).
- **Direct file apply.** Backup, replace and restore of a `Bookmarks` file, restricted to synthetic test files that Galmuri owns.

The extension asks for `bookmarks`, `nativeMessaging` and `storage` only, with no website permissions. Details are in [Labs and installation](docs/labs.md).

## Privacy

Galmuri has no network features, analytics or accounts. Bookmarks are read from, and saved to, your Mac only. Please keep real bookmarks, browser profiles, backups and private URLs out of issues, pull requests and test fixtures; use synthetic data.

## Documentation

- [Documentation index](docs/README.md)
- [Release notes and detailed status](docs/release-notes.md)
- [Product plan](docs/product-plan.md) and [roadmap](docs/roadmap.md)
- [Technical validation gates](docs/technical-validation.md) and [validation record](docs/validation.md)
- [Architecture decisions](docs/adr/README.md) and [glossary](GLOSSARY.md)
- [Task tracker](TASKS.md)

English is the canonical documentation language. The [HTML design prototype](design/galmuri-prototype.html) is a design reference with synthetic data, not the app.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md) first.

## License

[MIT](LICENSE) · Copyright (c) 2026 Galmuri contributors.
