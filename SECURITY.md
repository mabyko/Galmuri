# Security and data-loss reports

## Current status

There is no public native release or supported release series yet. Local native builds implement profile reading, persistent editing/merge and app-owned test-file apply/recovery. The optional Chrome extension/native-host bridge also has dedicated synthetic local-scope API apply/restore/recovery evidence; ordinary connections remain read-only at Chrome and real-user writes remain gated. The HTML prototype uses synthetic data. See the [supported scope and remaining limits](docs/chrome-api-workspace.md) and [validation record](docs/validation.md).

Potential loss, exposure, or corruption of bookmarks is a security concern. Report permission bypasses, unintended file access, path traversal, metadata loss, unsafe URL handling, and recovery failures privately when possible.

## Reporting privately

Once the GitHub repository is published, use **Security → Report a vulnerability** if private vulnerability reporting is enabled. If unavailable, do not post sensitive details publicly. Open a minimal issue asking the maintainer to establish a private reporting channel, without exploit steps, private URLs, or affected data.

No separate security email or private reporting service is configured in this checkout. A response deadline is not promised. Maintainers must configure and verify a private contact path before the first native release.

Include the version or commit, macOS and Chrome versions, a synthetic reproducer, expected and actual behavior, and whether recovery succeeded. Redact user names, local home paths, profile contents, tokens, sync metadata, and private URLs. Do not upload a real profile directory or original backup.

## Safe investigation

Reproduce storage issues with synthetic fixtures and a dedicated test profile. Preserve affected data locally, stop repeated writes, and keep the original and current states separate. Do not clear the user's sessions, force-quit their browser, or repeatedly overwrite files to diagnose synchronization. See the [technical validation plan](docs/technical-validation.md).

API snapshots, semantic archives and operation journals can contain private titles and URLs; do not attach them publicly. A pending/uncertain API operation must not be blindly replayed. The bridge's per-call checks and recovery folders do not provide atomicity, exactly-once execution, byte-identical backups or synchronization guarantees. Neither browser connection nor permission guidance requests Accessibility/Automation permission or operates System Settings UI.
