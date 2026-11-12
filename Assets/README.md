# App icons

Two primary icons correspond to the separate local install identities in `Config/BuildIdentities.json`:

- `AppIcon-masters/release.png`: warm ivory tile with a copper bookmark and an offset paper ribbon.
- `AppIcon-masters/dev.png`: derivative of the release master with an obvious blue DEV badge.
- `Assets.xcassets/AppIcon.appiconset` and `Assets.xcassets/AppIcon-Dev.appiconset`: macOS raster slots derived from those masters.

The original images were created for this project using the built-in image-generation tool on 2026-10-23, following the existing UI's warm bookmark motif. No third-party artwork was supplied. The generated masters are retained at full resolution; the app only packages the compiled catalog resources. This is local preview artwork; name/trademark review remains a publication task.

Run `python3 scripts/generate-icons.py` after an intentional master change. It reads the catalog's slot sizes/scales and resizes with macOS `sips`; it never edits the masters. `scripts/package-app.py` selects the configuration's primary icon through `actool --app-icon` and merges the compiler's generated Info.plist keys. This SwiftPM project has no Xcode project settings to override.

Both configurations compile without asset warnings. Masters and representative 128px/32px previews were inspected: the bookmark remains recognizable and the blue development badge is distinct. Prompt text is recorded in [AppIcon-masters/prompts.json](AppIcon-masters/prompts.json).
