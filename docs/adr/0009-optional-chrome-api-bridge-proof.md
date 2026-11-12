---
status: accepted
date: 2026-10-28
---

# Prove an optional Chrome API bridge before bookmark writes

The maintainer chose to proceed after reviewing a per-profile extension/API approach. Implement the first pairing-only stage with a small Native Messaging host and separate Debug/Release extension identities; retain existing extension-free file working copies and HTML export. Chrome will own storage/encryption if API integration succeeds. This does not authorize encrypted-file/Keychain integration or bypass the existing direct-file write gates.

The first stage requests only `nativeMessaging` and `storage`, not `bookmarks`. A five-minute session shows a matching code and exact request identity in the extension and Galmuri Settings; explicit app approval is acknowledged by the extension. A regular extension tab keeps the connection alive while the user switches to Galmuri. Closing it normally disconnects and removes session files. Host registration is permitted only in marked dedicated QA roots by the supplied setup tool; actual Google Chrome installation/permission UX is still unverified.

For this proof, bounded private request/approval files carry only handshake data in the app-owned workspace. They avoid building a general socket server before its need is proven; they must not become a bookmark-payload transport by accident. Abrupt host death may leave expired proof files; expiration rejects them and capacity is bounded, not automatically cleaned as user data. Stage B must choose its own transport/schema with fixture evidence. Current Workspace v1, profile originals and synthetic-only file-write restrictions remain unchanged.

The broader [API proposal](../chrome-api-bridge-plan.md) remains staged work: live semantic snapshots and 3-way merge, reversible API writes and restart adoption, then partial-apply recovery and separately gated deletion/account/sync. Chrome must run for that future backend; quit-before-write still applies to the file backend. API operations are not an atomic transaction and cannot promise original-byte/ID-preserving restoration after deletion. External-app UI automation remains prohibited by ADR 0008.
