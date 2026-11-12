# 0007 — Browser selection and an experimental Ego Lite connection

Accepted for local read-only evaluation · 2026-10-25.

The maintainer requested browser selection and permission-aware automatic profile discovery, including Ego Lite when feasible. Reuse the existing direct-read, saved-grant, staged-selection and parser boundaries. A welcome selector, sidebar add menu and File menu name the browser. No additional onboarding sheet, background scan, broad home-directory search, permission helper, TCC reset or credential access is introduced.

Chrome and Ego Lite have fixed, distinct default-location presets. Ego Lite 0.6.1.9’s installed app bundle declares `CrProductDirName = Citro Labs/ego lite`. [Chromium’s user-data-directory documentation](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md) explains the macOS Application Support convention. This inference supplies a candidate path only; overridden locations require explicit selection. App metadata is not proof of actual profile availability or bookmark correctness.

Ego’s [official quick start](https://lite.ego.app/document/en/docs/quick-start) describes importing browser data. That feature does not establish an external storage API or authorize Galmuri to emulate Ego’s password/cookie migration. Galmuri reads only recognized plaintext bookmark payloads, with the existing parser and unsupported-store gates. Ego import is visibly experimental and read-only; the existing sourceRestriction field retains that warning across relaunch/reconnect without changing Workspace v1. Account/encryption/ordering restrictions take priority. No browser apply capability is granted by the browser name.

An attempt at a known path may trigger a macOS consent prompt or fail. [Apple’s permission explanation](https://developer.apple.com/forums/thread/678819) does not guarantee a uniform approval prompt for every location/version. Keep explicit native folder access as the fallback and do not label an in-app button as an already-completed OS grant. A stable distribution signing identity remains separate work.

Use synthetic fixtures for browser routing, atomic selection/error behavior and native renders. Actual user approval, Ego runtime freshness and browser-version compatibility are pending. Encrypted support, Keychain and external writes remain deferred/gated. This extends [ADR 0006](0006-user-initiated-profile-discovery.md).
