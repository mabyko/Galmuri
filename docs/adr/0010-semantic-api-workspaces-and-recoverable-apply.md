---
status: accepted
date: 2026-10-29
---

# Separate semantic API working copies from browser-file snapshots

The maintainer requested completing the API design and implementation. Keep the existing file workspace v1 unchanged and store API working copies in a separate versioned `BridgeAPI/workspace.json`. API node IDs are opaque, profile-local identifiers mapped to Galmuri UUIDs; they are not file GUIDs or URL identities. Project only editable names/URLs/hierarchy/order into the existing semantic tree and three-way merge. Read-only capabilities stay in the API snapshot; raw file serializers/checksums are never used for this backend.

Use a deliberately separate, bounded private mailbox for the native host: approved-session snapshots, chunked jobs, pre-write source/working archives, durable per-call intent/results and final receipts. This extends ADR 0009 explicitly rather than reusing its handshake files for bookmark payloads. The Chrome extension tab polls only during its five-minute approved session. No listener, privileged service, external UI inspection, background reconnection or Keychain implementation is added. The host verifies the owning Galmuri PID, kernel start timestamp and exact sibling executable before issuing an apply and acknowledging each new mutation intent; an already in-flight call can still finish after exit.

Writes remain restricted to explicit dedicated API-write markers plus a host launch flag; ordinary hosts provide read access only. Within that scope, account/managed/unknown-capability nodes and cross-store changes stay blocked. Deletion moves top-level removed subtrees into an explicitly tracked, visible `Galmuri Recovery …` folder. Restore uses a fresh three-way review and moves existing API IDs back; permanently missing IDs cannot be recreated silently. Chrome owns encryption, dates and persistence, so API archives are semantic recovery records, not byte-identical browser backups.

Every apply binds a fresh full-model fingerprint, paired session and reviewed target. The extension verifies per-call transitions and stops on unexpected changes. Partial/lost responses persist a pending operation and block replay after app restart. Explicit interruption review archives the working copy, rechecks the chosen Chrome snapshot and adopts it locally before clearing the retry block. This does not promise atomicity, exactly-once execution, automatic rollback or remote sync completion. See the [implementation guide](../chrome-api-workspace.md) and [validation record](../validation.md).


Release27 refines this boundary with bidirectional API-protocol2 negotiation, bounded chunked records, compact per-operation mapping deltas and sequential intent/observed files. A job/session/installation-bound stop marker must be checked before another mutation intent is acknowledged; the app requests it on explicit stop, workbench close and apply timeout/cancellation. It cannot undo an already-started call. Keeping pending state until explicit review preserves the original interruption policy. See [refinement](../native-refinement.md).
