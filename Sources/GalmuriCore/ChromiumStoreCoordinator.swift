import Foundation
import Darwin

/// Test-only group replacement. The caller must maintain a controlled no-launch interval through
/// apply/recovery. Separate renames are not atomic; fsync/F_FULLFSYNC are not a power-loss guarantee.
public struct ChromiumStoreCoordinator: Sendable {
    public struct Review: Sendable {
        public let store: ChromiumBookmarkStore
        fileprivate let snapshot: Snapshot
    }

    /// Retain this value outside the journal. Its hash/identity anchor detects journal replacement.
    /// Contains no cipher or password; the caller supplies a cipher for each operation.
    public struct Receipt: Codable, Sendable {
        public let id: UUID
        public let journal: URL
        public let fingerprint: String
        fileprivate let stamp: Stamp
    }

    public let ownedRoot: URL
    public let backupRoot: URL
    private var io: ApplyCoordinator { ApplyCoordinator(testRoot: ownedRoot, backupRoot: backupRoot) }
    private static let names = ["Bookmarks", "EncryptedBookmarks2", "BookmarkMergedSurfaceOrdering"]
    private static let sidecars = ["Bookmarks.bak", "EncryptedBookmarks2.bak"]
    private static var trackedNames: [String] { names + sidecars }
    private func canonical(_ files: [String: Data]) -> [String: Data] { files.filter { Self.names.contains($0.key) } }

    public init(ownedRoot: URL, backupRoot: URL) {
        self.ownedRoot = ownedRoot
        self.backupRoot = backupRoot
    }

    public func readForReview(_ profile: URL, cipher: ChromiumBookmarkCipher? = nil) throws -> Review {
        let snapshot = try capture(profile)
        let store = try ChromiumBookmarkStore(files: canonical(snapshot.bytes), cipher: cipher)
        return Review(store: store, snapshot: snapshot)
    }

    /// Reload the separate durable receipt after interruption; reject a corrupt journal or backup.
    public func readReceipt(_ journal: URL) throws -> Receipt {
        guard scoped(journal), journal.lastPathComponent == "journal.json" else { throw GalmuriError.missingBackup }
        let directory = try io.openDirectory(journal.deletingLastPathComponent())
        defer { close(directory) }
        let file = try read("receipt.json", directory: directory, limit: 1_000_000)
        defer { try? file.handle.close() }
        let receipt = try JSONDecoder().decode(Receipt.self, from: file.bytes)
        guard receipt.journal == journal else { throw GalmuriError.missingBackup }
        _ = try load(receipt)
        return receipt
    }

    public func apply(_ review: Review, edited: BookmarkTree, cipher: ChromiumBookmarkCipher? = nil,
                      browserRunning: () -> Bool) throws -> Receipt? {
        let output = try review.snapshot.bytes.merging(review.store.serialize(edited, cipher: cipher)) { _, new in new }
        _ = try writableStore(output, cipher: cipher)
        return try commit(review.snapshot, output: output, metadata: nil, browserRunning: browserRunning)
    }

    /// A fresh review explicitly approves the current state, including browser changes since apply.
    /// Backs up that entire current set before restoring original bytes and metadata.
    public func restore(_ receipt: Receipt, review: Review, cipher: ChromiumBookmarkCipher? = nil,
                        browserRunning: () -> Bool) throws -> Receipt? {
        let saved = try load(receipt)
        guard review.snapshot.profile == saved.journal.profile, review.snapshot.root == saved.journal.before.root,
              review.snapshot.directory == saved.journal.before.directory else { throw GalmuriError.staleSource }
        _ = try writableStore(saved.originals, cipher: cipher)
        let output = saved.originals.filter { Self.names.contains($0.key) }.merging(review.snapshot.bytes.filter { Self.sidecars.contains($0.key) }) { _, new in new }
        return try commit(review.snapshot, output: output, metadata: saved.metadata.filter { Self.names.contains($0.key) }, originalReceipt: receipt, browserRunning: browserRunning)
    }

    /// Explicit recovery only: never rolls back an unrecognized/newer writer. Raw validation permits
    /// the temporary disagreement of copies after a partial apply, without parsing that mixed pair.
    public func recover(_ receipt: Receipt, cipher: ChromiumBookmarkCipher? = nil,
                        browserRunning: () -> Bool) throws -> Receipt? {
        if browserRunning() { throw GalmuriError.browserRunning }
        let saved = try load(receipt), journal = saved.journal
        let current = try capture(journal.profile)
        guard current.root == journal.before.root, current.directory == journal.before.directory,
              current.inventory.filter({ !journal.stages.contains($0) }) == journal.before.inventory else { throw GalmuriError.staleSource }
        for name in Self.trackedNames {
            let actual = current.files[name]
            if actual == journal.before.files[name] { continue }
            guard let staged = journal.outputs[name], let actual,
                  actual.matchesRenamed(staged) else { throw GalmuriError.staleSource }
        }
        try validateStages(journal, current: current)
        let targetReceipt = journal.recoveryTarget ?? receipt
        let target = try load(targetReceipt)
        guard target.journal.recoveryTarget == nil, target.journal.profile == journal.profile else { throw GalmuriError.missingBackup }
        _ = try writableStore(target.originals, cipher: cipher)
        // A recovery interrupted again keeps targeting the first valid original set, not a mixed pair.
        let output = canonical(target.originals).merging(current.bytes.filter { Self.sidecars.contains($0.key) }) { _, new in new }
        return try commit(current, output: output, metadata: target.metadata.filter { Self.names.contains($0.key) }, originalReceipt: targetReceipt,
                          recoveryTarget: targetReceipt, browserRunning: browserRunning)
    }

    fileprivate struct Identity: Codable, Equatable, Sendable {
        let device: Int32
        let inode: UInt64
        let birthSeconds: Int
        let birthNanoseconds: Int
        let uid: UInt32
        let gid: UInt32
        let mode: UInt16
        let flags: UInt32
        init(_ s: stat) {
            device = s.st_dev; inode = s.st_ino
            birthSeconds = s.st_birthtimespec.tv_sec; birthNanoseconds = s.st_birthtimespec.tv_nsec
            uid = s.st_uid; gid = s.st_gid; mode = s.st_mode; flags = s.st_flags
        }
    }

    fileprivate struct Stamp: Codable, Equatable, Sendable {
        let identity: Identity
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
        let attributes: String
        init(_ s: stat, attributes: String) {
            identity = Identity(s); size = s.st_size
            modifiedSeconds = s.st_mtimespec.tv_sec; modifiedNanoseconds = s.st_mtimespec.tv_nsec
            changedSeconds = s.st_ctimespec.tv_sec; changedNanoseconds = s.st_ctimespec.tv_nsec
            self.attributes = attributes
        }
        func matchesRenamed(_ other: Stamp) -> Bool {
            identity == other.identity && size == other.size && attributes == other.attributes &&
            modifiedSeconds == other.modifiedSeconds && modifiedNanoseconds == other.modifiedNanoseconds
        }
    }

    fileprivate struct FileState: Codable, Equatable, Sendable {
        let hash: String
        let stamp: Stamp
        func matchesRenamed(_ other: FileState) -> Bool { hash == other.hash && stamp.matchesRenamed(other.stamp) }
    }

    fileprivate struct Snapshot: Sendable {
        let profile: URL
        let root: Identity
        let directory: Identity
        let inventory: [String]
        let files: [String: FileState]
        let bytes: [String: Data]
        var recorded: RecordedSnapshot { RecordedSnapshot(root: root, directory: directory, inventory: inventory, files: files) }
    }

    fileprivate struct RecordedSnapshot: Codable, Equatable {
        let root: Identity
        let directory: Identity
        let inventory: [String]
        let files: [String: FileState]
    }

    private struct Journal: Codable {
        let version: Int
        let id: UUID
        let profile: URL
        let before: RecordedSnapshot
        let backups: [String: FileState]
        let outputs: [String: FileState]
        let recoveryTarget: Receipt?
        var stages: [String] { outputs.keys.sorted().map { stage($0) } }
        func stage(_ name: String) -> String { ".galmuri-" + id.uuidString + "-" + name }
    }

    private struct RawFile {
        let bytes: Data
        let state: FileState
        let handle: FileHandle
    }

    private func local(_ url: URL) -> Bool {
        url.isFileURL && url.user == nil && url.password == nil && url.port == nil && (url.host == nil || url.host == "localhost") && url.query == nil && url.fragment == nil &&
        url.standardizedFileURL.path == url.path && url.resolvingSymlinksInPath().path == url.path
    }

    private func scoped(_ url: URL) -> Bool {
        local(ownedRoot) && local(url) && url.path.hasPrefix(ownedRoot.path + "/")
    }

    private func capture(_ profile: URL, ignoring stages: [String] = []) throws -> Snapshot {
        guard scoped(profile) else { throw GalmuriError.localTestsOnly }
        let root = try io.openDirectory(ownedRoot), directory = try io.openDirectory(profile)
        defer { close(root); close(directory) }
        let rootIdentity = Identity(try io.status(root)), parentIdentity = Identity(try io.status(directory))
        guard rootIdentity.uid == geteuid(), parentIdentity.uid == geteuid() else { throw GalmuriError.permission }
        let inventory = try listing(directory).filter { !stages.contains($0) }
        let relevant = inventory.filter { $0.lowercased().contains("bookmark") && !$0.hasPrefix(".galmuri-") }
        guard Set(relevant).isSubset(of: Set(Self.trackedNames)) else { throw GalmuriError.unsupported("Unverified bookmark file inventory.") }
        var states = [String: FileState](), bytes = [String: Data]()
        for name in Self.trackedNames where relevant.contains(name) {
            let file = try read(name, directory: directory)
            defer { try? file.handle.close() }
            states[name] = file.state; bytes[name] = file.bytes
        }
        guard inventory == (try listing(directory)).filter({ !stages.contains($0) }) else { throw GalmuriError.staleSource }
        return Snapshot(profile: profile, root: rootIdentity, directory: parentIdentity, inventory: inventory, files: states, bytes: bytes)
    }

    // Enumerate the opened directory, not a re-resolved path. No profile caches/credentials are read.
    private func listing(_ directory: Int32) throws -> [String] {
        let fd = openat(directory, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw io.posixError() }
        guard let stream = fdopendir(fd) else { close(fd); throw io.posixError() }
        defer { closedir(stream) }
        var names = [String]()
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
            errno = 0
        }
        guard errno == 0 else { throw io.posixError() }
        return names.sorted()
    }

    private func read(_ name: String, directory: Int32, limit: Int = 50_000_000) throws -> RawFile {
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw io.posixError() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            let before = try io.status(fd)
            guard before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1, before.st_size >= 0,
                  before.st_size < limit, before.st_uid == geteuid() else { throw GalmuriError.permission }
            let attributes = try attributeHash(fd)
            var bytes = Data()
            while let chunk = try handle.read(upToCount: min(65_536, limit - bytes.count)), !chunk.isEmpty {
                bytes.append(chunk)
                guard bytes.count < limit else { throw GalmuriError.invalid("file exceeds size limit") }
            }
            let after = try io.status(fd)
            guard io.unchanged(before, after), Identity(before) == Identity(after),
                  attributes == (try attributeHash(fd)), after.st_nlink == 1 else { throw GalmuriError.staleSource }
            return RawFile(bytes: bytes, state: FileState(hash: BookmarkFile.hash(bytes), stamp: Stamp(after, attributes: attributes)), handle: handle)
        } catch { try? handle.close(); throw error }
    }

    private func attributeHash(_ fd: Int32) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return BookmarkFile.hash(try encoder.encode(attributes(fd)))
    }

    private func attributes(_ fd: Int32) throws -> [String: Data] {
        let count = flistxattr(fd, nil, 0, 0)
        guard count >= 0, count < 1_000_000 else { throw GalmuriError.permission }
        var names = [CChar](repeating: 0, count: count)
        guard flistxattr(fd, &names, names.count, 0) == count else { throw GalmuriError.staleSource }
        let keys = names.split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }.sorted()
        var attributes = [String: Data]()
        for name in keys {
            let length = fgetxattr(fd, name, nil, 0, 0, 0)
            guard length >= 0, length < 1_000_000 else { throw GalmuriError.permission }
            var data = Data(count: length)
            let actual = data.withUnsafeMutableBytes { fgetxattr(fd, name, $0.baseAddress, length, 0, 0) }
            guard actual == length else { throw GalmuriError.staleSource }
            attributes[name] = data
        }
        if let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var length = 0
            guard let text = acl_to_text(acl, &length) else { throw io.posixError() }
            defer { acl_free(text) }
            attributes["\u{0}acl"] = Data(bytes: text, count: length)
        } else if errno != ENOENT { throw io.posixError() }
        return attributes
    }

    // shortcut: only the observed 0081/four-field encoding is repairable; verify other encodings before extending.
    static func canRestoreCopiedQuarantine(_ source: Data, _ copied: Data) -> Bool {
        func fields(_ data: Data) -> [Substring]? {
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            let fields = text.split(separator: ";", omittingEmptySubsequences: false)
            guard fields.count == 4, fields[0] == "0081", fields[1].utf8.count == 8,
                  fields[1].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  fields[2].unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
            if !fields[3].isEmpty {
                guard let event = UUID(uuidString: String(fields[3])), event.uuidString == fields[3] else { return nil }
            }
            return fields
        }
        guard let original = fields(source), let destination = fields(copied) else { return false }
        return original[0] == destination[0] && original[3] == destination[3]
    }

    private func writableStore(_ files: [String: Data], cipher: ChromiumBookmarkCipher?) throws -> ChromiumBookmarkStore {
        let store = try ChromiumBookmarkStore(files: canonical(files), cipher: cipher)
        if let restriction = store.file.writeRestriction { throw GalmuriError.unsupported(restriction) }
        return store
    }

    private func backupDirectory() throws -> Int32 {
        guard scoped(backupRoot) else { throw GalmuriError.localTestsOnly }
        // The configured root must already exist; create only its direct, private backup child.
        let parent = try io.openDirectory(backupRoot.deletingLastPathComponent())
        defer { close(parent) }
        if mkdirat(parent, backupRoot.lastPathComponent, 0o700) != 0, errno != EEXIST { throw io.posixError() }
        let directory = try io.openDirectory(backupRoot)
        do {
            let status = try io.status(directory)
            guard status.st_uid == geteuid(), status.st_mode & 0o777 == 0o700 else { throw GalmuriError.permission }
            try io.synchronize(parent)
            return directory
        } catch { close(directory); throw error }
    }

    private func write(_ bytes: Data, named name: String, directory: Int32, metadata: RawFile?) throws -> FileState {
        let handle = try io.createFile(name, directory: directory)
        defer { try? handle.close() }
        try handle.write(contentsOf: bytes)
        if let metadata {
            guard fcopyfile(metadata.handle.fileDescriptor, handle.fileDescriptor, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else { throw io.posixError() }
            let sourceAttributes = try attributes(metadata.handle.fileDescriptor)
            var copiedAttributes = try attributes(handle.fileDescriptor)
            let quarantine = "com.apple.quarantine"
            if sourceAttributes[quarantine] != copiedAttributes[quarantine] {
                guard let original = sourceAttributes[quarantine], let copied = copiedAttributes[quarantine],
                      Self.canRestoreCopiedQuarantine(original, copied) else { throw GalmuriError.permission }
                copiedAttributes[quarantine] = original
                guard copiedAttributes == sourceAttributes,
                      try attributeHash(metadata.handle.fileDescriptor) == metadata.state.stamp.attributes else { throw GalmuriError.permission }
                // copyfile applies quarantine via qtn_file_apply_to_fd; restore its opaque bytes with fsetxattr(2).
                guard original.withUnsafeBytes({ fsetxattr(handle.fileDescriptor, quarantine, $0.baseAddress, $0.count, 0, XATTR_REPLACE) }) == 0 else { throw io.posixError() }
            }
            let actual = try io.status(handle.fileDescriptor), original = metadata.state.stamp.identity
            guard actual.st_uid == original.uid, actual.st_gid == original.gid, actual.st_mode == original.mode,
                  actual.st_flags == original.flags, try attributeHash(handle.fileDescriptor) == metadata.state.stamp.attributes else { throw GalmuriError.permission }
        }
        try io.synchronize(handle.fileDescriptor, full: true)
        let verified = try read(name, directory: directory)
        defer { try? verified.handle.close() }
        guard verified.bytes == bytes else { throw GalmuriError.missingBackup }
        return verified.state
    }

    private struct SavedMetadata {
        let url: URL
        let state: FileState
    }

    private func sameMetadata(_ lhs: FileState, _ rhs: FileState) -> Bool {
        let a = lhs.stamp.identity, b = rhs.stamp.identity
        return a.mode == b.mode && a.uid == b.uid && a.gid == b.gid && a.flags == b.flags && lhs.stamp.attributes == rhs.stamp.attributes
    }

    private func commit(_ before: Snapshot, output: [String: Data], metadata: [String: SavedMetadata]?, originalReceipt: Receipt? = nil, recoveryTarget: Receipt? = nil,
                        browserRunning: () -> Bool) throws -> Receipt? {
        if browserRunning() { throw GalmuriError.browserRunning }
        guard try capture(before.profile).recorded == before.recorded else { throw GalmuriError.staleSource }
        guard Set(output.keys) == Set(before.files.keys) else { throw GalmuriError.unsupported("Store membership changes are unsupported.") }
        if output == before.bytes, metadata == nil || before.files.allSatisfy({ name, state in
            metadata?[name].map { sameMetadata($0.state, state) } ?? true
        }) { return nil }
        guard scoped(backupRoot), !backupRoot.path.hasPrefix(before.profile.path + "/"), backupRoot != before.profile else { throw GalmuriError.localTestsOnly }
        let directory = try io.openDirectory(before.profile), backups = try backupDirectory()
        defer { close(directory); close(backups) }
        let id = UUID(), folder = id.uuidString
        guard mkdirat(backups, folder, 0o700) == 0 else { throw io.posixError() }
        try io.synchronize(backups)
        let transactionURL = backupRoot.appendingPathComponent(folder), transaction = try io.openDirectory(transactionURL)
        defer { close(transaction) }
        var backupStates = [String: FileState](), outputs = [String: FileState]()
        for name in Self.trackedNames where before.files[name] != nil {
            let current = try read(name, directory: directory)
            defer { try? current.handle.close() }
            guard current.state == before.files[name] else { throw GalmuriError.staleSource }
            backupStates[name] = try write(current.bytes, named: name, directory: transaction, metadata: current)
            let attributes: RawFile
            if let source = metadata?[name] {
                let parent = try io.openDirectory(source.url.deletingLastPathComponent())
                defer { close(parent) }
                attributes = try read(source.url.lastPathComponent, directory: parent)
                guard attributes.state == source.state else { try? attributes.handle.close(); throw GalmuriError.missingBackup }
            } else { attributes = current }
            defer { if metadata?[name] != nil { try? attributes.handle.close() } }
            // An unchanged file needs no rename; restoration can still require original attributes.
            if Self.names.contains(name), output[name] != current.bytes || !sameMetadata(attributes.state, current.state) {
                let stage = ".galmuri-" + id.uuidString + "-" + name
                outputs[name] = try write(output[name]!, named: stage, directory: directory, metadata: attributes)
            }
        }
        try io.synchronize(transaction); try io.synchronize(directory)
        let journal = Journal(version: 1, id: id, profile: before.profile, before: before.recorded, backups: backupStates, outputs: outputs, recoveryTarget: recoveryTarget)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(journal)
        let journalState = try write(bytes, named: "journal.json", directory: transaction, metadata: nil)
        try io.synchronize(transaction)
        let receipt = Receipt(id: id, journal: transactionURL.appendingPathComponent("journal.json"), fingerprint: journalState.hash, stamp: journalState.stamp)
        _ = try write(encoder.encode(receipt), named: "receipt.json", directory: transaction, metadata: nil)
        try io.synchronize(transaction)
        do {
            var expected = before.recorded
            for name in Self.names where outputs[name] != nil {
                if browserRunning() { throw GalmuriError.browserRunning }
                let now = try capture(before.profile, ignoring: journal.stages)
                guard now.recorded == expected else { throw GalmuriError.staleSource }
                _ = try load(receipt)
                if let originalReceipt { _ = try load(originalReceipt) }
                try validateStages(journal, current: now)
                let stage = journal.stage(name)
                // shortcut: rename has no inode compare-and-swap; a writer can race this final check.
                guard renameat(directory, stage, directory, name) == 0 else { throw io.posixError() }
                try io.synchronize(directory)
                let written = try capture(before.profile, ignoring: journal.stages)
                guard let actual = written.files[name], actual.matchesRenamed(outputs[name]!) else { throw GalmuriError.staleSource }
                var files = expected.files; files[name] = actual
                expected = RecordedSnapshot(root: expected.root, directory: expected.directory, inventory: expected.inventory, files: files)
                guard written.recorded == expected else { throw GalmuriError.staleSource }
            }
            if browserRunning() { throw GalmuriError.browserRunning }
            guard try capture(before.profile, ignoring: journal.stages).recorded == expected else { throw GalmuriError.staleSource }
            _ = try load(receipt)
            if let originalReceipt { _ = try load(originalReceipt) }
            return receipt
        } catch { throw ChromiumStoreInterruption(receipt: receipt, reason: String(describing: error)) }
    }

    private func validateStages(_ journal: Journal, current: Snapshot) throws {
        let directory = try io.openDirectory(journal.profile)
        defer { close(directory) }
        let inventory = try listing(directory)
        for (name, state) in journal.outputs {
            let stageName = journal.stage(name)
            if inventory.contains(stageName) {
                let stage = try read(stageName, directory: directory)
                defer { try? stage.handle.close() }
                guard stage.state == state, current.files[name] == journal.before.files[name] else { throw GalmuriError.staleSource }
            } else {
                guard let actual = current.files[name], actual.matchesRenamed(state) else { throw GalmuriError.staleSource }
            }
        }
    }

    private func load(_ receipt: Receipt) throws -> (journal: Journal, originals: [String: Data], metadata: [String: SavedMetadata]) {
        let expected = backupRoot.appendingPathComponent(receipt.id.uuidString).appendingPathComponent("journal.json")
        guard scoped(receipt.journal), receipt.journal == expected else { throw GalmuriError.missingBackup }
        let directory = try io.openDirectory(expected.deletingLastPathComponent())
        defer { close(directory) }
        let file = try read("journal.json", directory: directory, limit: 1_000_000)
        defer { try? file.handle.close() }
        guard file.state.hash == receipt.fingerprint, file.state.stamp == receipt.stamp else { throw GalmuriError.missingBackup }
        let journal = try JSONDecoder().decode(Journal.self, from: file.bytes)
        guard journal.version == 1, journal.id == receipt.id, scoped(journal.profile),
              Set(journal.before.files.keys).isSubset(of: Set(Self.trackedNames)),
              Set(journal.backups.keys) == Set(journal.before.files.keys),
              Set(journal.outputs.keys).isSubset(of: Set(Self.names)),
              Set(journal.outputs.keys).isSubset(of: Set(journal.before.files.keys)) else { throw GalmuriError.missingBackup }
        var bytes = [String: Data](), metadata = [String: SavedMetadata]()
        for (name, state) in journal.backups {
            let backup = try read(name, directory: directory)
            defer { try? backup.handle.close() }
            guard backup.state == state, backup.state.hash == journal.before.files[name]?.hash else { throw GalmuriError.missingBackup }
            bytes[name] = backup.bytes; metadata[name] = SavedMetadata(url: expected.deletingLastPathComponent().appendingPathComponent(name), state: state)
        }
        return (journal, bytes, metadata)
    }
}

/// No rollback is attempted. Keep the receipt/journal/backups and recover only after exit is verified.
public struct ChromiumStoreInterruption: Error, Sendable {
    public let receipt: ChromiumStoreCoordinator.Receipt
    public let reason: String
}
