# Galmuri bookmark editing

Galmuri separates editing a working copy from applying changes to a connected browser profile. These terms keep that boundary clear.

## Language

**Connected profile**:
A browser profile the user has chosen to manage in Galmuri. It is distinct from a browser account and from a label on imported data.
_Avoid_: account, source label

**Original**:
The browser-owned bookmark state of a connected profile. It may change while the user edits in Galmuri.
_Avoid_: working copy

**Base**:
The initial accepted snapshot against which both app edits and later browser changes are compared.
_Avoid_: latest original

**Working copy (Ours)**:
The user's editable bookmark state in Galmuri. Saving it in the app does not apply it to the browser.
_Avoid_: browser save

**Latest original (Theirs)**:
The browser-owned state freshly read for a review: from storage after exit for file-based apply, or from the running browser for API-based apply.
_Avoid_: saved Base, unverified cached state

**Apply**:
The deliberate operation that writes a reviewed result back to the connected browser profile.
_Avoid_: autosave, export

**Conflict**:
Changes that cannot be combined safely without an explicit choice. Identity uncertainty can also block review rather than being guessed away.

**Delete (working copy)**:
Remove selected bookmarks or folders from Galmuri’s working copy, with undo available during the current app session. Removing them from Chrome originals requires separate apply review. The UI uses “Delete”; older planning notes called this “Exclude”.
_Avoid_: immediately delete from Chrome

**Same-URL bookmarks**:
Distinct bookmark items whose addresses match. A matching URL alone does not establish that they are the same item.
_Avoid_: identical bookmark

**Original backup**:
A preserved browser-owned state intended for recovery before apply or restore.
_Avoid_: workspace JSON export

**Workspace backup**:
A portable copy of the app's editing state. It is distinct from a browser-original backup.
_Avoid_: original backup

**File verification**:
Confirmation of the applied file state. Browser restart and synchronization verification are separate outcomes.
_Avoid_: sync success

**API working copy**:
A locally saved editing state for one chosen folder scope in an explicitly paired browser profile. It represents the items exposed by the browser, rather than a complete copy of its storage files.
_Avoid_: original-file backup, imported account

**Recovery folder**:
A visible browser folder holding originals removed by an API apply so they can be reviewed for restoration.
_Avoid_: permanent deletion, hidden backup

**Adopt current Chrome state**:
An explicitly reviewed choice to accept the browser's current items as the new saved source and working copy after an uncertain apply, while retaining the previous work for recovery.
_Avoid_: rollback, retry apply

**Stop after current call**:
A request to stop starting further browser changes; an already-started change may finish. Previously applied changes remain subject to explicit review and recovery.
_Avoid_: undo apply, automatic rollback
