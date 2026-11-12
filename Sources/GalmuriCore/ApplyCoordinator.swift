import Foundation
import Darwin

public struct BackupReceipt: Codable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var profileName: String
    public var source: URL
    public var backup: URL
    public var beforeHash: String
    public var afterHash: String
    public var state: String
    public var sourceIdentity: ApplySourceIdentity? = nil
    public var temporary: URL? = nil
    public var sourceMode: UInt16? = nil
}

public struct ApplySourceIdentity: Codable, Equatable, Sendable {
    let path: String
    let device: Int32
    let inode: UInt64
    let birthSeconds: Int
    let birthNanoseconds: Int
    let parentDevice: Int32
    let parentInode: UInt64
}

public struct ApplyReview: Sendable {
    public var latest: BookmarkFile
    public var result: MergeResult
    public var sourceIdentity: ApplySourceIdentity?
    public init(latest: BookmarkFile, result: MergeResult, sourceIdentity: ApplySourceIdentity? = nil) {
        self.latest = latest; self.result = result; self.sourceIdentity = sourceIdentity
    }
}

public struct ApplyCoordinator: Sendable {
    public let testRoot: URL
    public let backupRoot: URL
    public init(testRoot: URL, backupRoot: URL) { self.testRoot = testRoot.standardizedFileURL; self.backupRoot = backupRoot.standardizedFileURL }

    // shortcut: direct writes are limited to app-owned test profiles until dedicated Chrome restart/sync verification passes.
    public func canWrite(_ source: URL) -> Bool {
        let normalized = source.standardizedFileURL
        guard source.isFileURL, source.host == nil || source.host == "localhost",
              testRoot.isFileURL, testRoot.host == nil || testRoot.host == "localhost",
              normalized.lastPathComponent == "Bookmarks", normalized.path.hasPrefix(testRoot.path + "/"),
              normalized.resolvingSymlinksInPath().path == normalized.path,
              testRoot.resolvingSymlinksInPath().path == testRoot.path else { return false }
        return true
    }

    /// Capture bytes and identity together; restore approval must retain both values.
    public func readForReview(_ source: URL) throws -> (file: BookmarkFile, identity: ApplySourceIdentity) {
        guard source.isFileURL, source.host == nil || source.host == "localhost" else { throw GalmuriError.permission }
        let directory = try openDirectory(source.deletingLastPathComponent())
        defer { close(directory) }
        let snapshot = try readSource(source, directory: directory)
        defer { try? snapshot.handle.close() }
        return (snapshot.file, snapshot.identity)
    }

    public func prepare(profile: ConnectedProfile) throws -> ApplyReview {
        let snapshot = try readForReview(profile.source)
        let merge = try MergeEngine.merge(base: profile.base.tree, ours: profile.working, theirs: snapshot.file.tree)
        return ApplyReview(latest: snapshot.file, result: merge, sourceIdentity: snapshot.identity)
    }

    public func apply(profile: ConnectedProfile, review: ApplyReview, browserRunning: () -> Bool) throws -> BackupReceipt {
        guard review.result.unresolved.isEmpty else { throw GalmuriError.unresolved }
        guard profile.sourceRestriction == nil else { throw GalmuriError.unsupported(profile.sourceRestriction!) }
        guard let identity = review.sourceIdentity else { throw GalmuriError.staleSource }
        let data = try review.latest.serialize(review.result.tree)
        return try commit(data: data, source: profile.source, expectedHash: review.latest.fingerprint, expectedIdentity: identity, name: profile.name, browserRunning: browserRunning)
    }

    public func restore(_ receipt: BackupReceipt, expectedCurrentHash: String, expectedCurrentIdentity: ApplySourceIdentity? = nil, browserRunning: () -> Bool) throws -> BackupReceipt {
        guard validBackupLocation(receipt) else { throw GalmuriError.missingBackup }
        let bytes = try ProfileIO.read(receipt.backup).original
        guard BookmarkFile.hash(bytes) == receipt.beforeHash else { throw GalmuriError.missingBackup }
        // shortcut: legacy callers bind identity at invocation; review UIs must pass the identity captured with their reviewed bytes.
        return try commit(data: bytes, source: receipt.source, expectedHash: expectedCurrentHash, expectedIdentity: expectedCurrentIdentity, name: receipt.profileName + " — restore", browserRunning: browserRunning)
    }

    public func receipts() throws -> [BackupReceipt] { try receiptHistory().receipts }

    public func receiptHistory() throws -> (receipts: [BackupReceipt], unreadableCount: Int) {
        guard FileManager.default.fileExists(atPath: backupRoot.path) else { return ([], 0) }
        let directory = try openDirectory(backupRoot)
        defer { close(directory) }
        let urls = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let receipts = urls.compactMap { url -> BackupReceipt? in
            let fd = openat(directory, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard fd >= 0 else { return nil }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close() }
            guard let info = try? status(fd), info.st_mode & S_IFMT == S_IFREG, info.st_size < 1_000_000,
                  let bytes = try? handle.read(upToCount: 1_000_000), bytes.count < 1_000_000,
                  let receipt = try? JSONDecoder().decode(BackupReceipt.self, from: bytes),
                  url.lastPathComponent == receipt.id.uuidString + ".json", validBackupLocation(receipt) else { return nil }
            return receipt
        }
        return (receipts.sorted { $0.date > $1.date }, urls.count - receipts.count)
    }

    private func validBackupLocation(_ receipt: BackupReceipt) -> Bool {
        receipt.source.isFileURL && (receipt.source.host == nil || receipt.source.host == "localhost") &&
        receipt.backup.standardizedFileURL == backupRoot.appendingPathComponent(receipt.id.uuidString + ".bookmarks") &&
        receipt.backup.resolvingSymlinksInPath().path == receipt.backup.standardizedFileURL.path &&
        backupRoot.resolvingSymlinksInPath().path == backupRoot.path
    }

    private struct SourceSnapshot {
        let file: BookmarkFile
        let identity: ApplySourceIdentity
        let handle: FileHandle
        let status: stat
    }

    private func readSource(_ source: URL, directory: Int32) throws -> SourceSnapshot {
        let fd = openat(directory, source.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw posixError() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            let before = try status(fd), parent = try status(directory)
            guard before.st_mode & S_IFMT == S_IFREG, before.st_size < 50_000_000 else { throw GalmuriError.permission }
            var bytes = Data()
            while let chunk = try handle.read(upToCount: min(65_536, 50_000_000 - bytes.count)), !chunk.isEmpty {
                bytes.append(chunk)
                guard bytes.count < 50_000_000 else { throw GalmuriError.invalid("file exceeds size limit") }
            }
            let after = try status(fd)
            guard unchanged(before, after) else { throw GalmuriError.staleSource }
            let identity = ApplySourceIdentity(path: source.standardizedFileURL.path, device: before.st_dev, inode: before.st_ino,
                birthSeconds: before.st_birthtimespec.tv_sec, birthNanoseconds: before.st_birthtimespec.tv_nsec,
                parentDevice: parent.st_dev, parentInode: parent.st_ino)
            return SourceSnapshot(file: try BookmarkFile(data: bytes), identity: identity, handle: handle, status: before)
        } catch { try? handle.close(); throw error }
    }

    private func commit(data: Data, source: URL, expectedHash: String, expectedIdentity: ApplySourceIdentity?, name: String, browserRunning: () -> Bool) throws -> BackupReceipt {
        guard canWrite(source) else { throw GalmuriError.localTestsOnly }
        if browserRunning() { throw GalmuriError.browserRunning }
        let directory = try openDirectory(source.deletingLastPathComponent())
        defer { close(directory) }
        if let restriction = try ProfileIO.storageRestriction(in: source.deletingLastPathComponent()) { throw GalmuriError.unsupported(restriction) }
        let current = try readSource(source, directory: directory)
        defer { try? current.handle.close() }
        guard current.file.fingerprint == expectedHash, expectedIdentity == nil || current.identity == expectedIdentity else { throw GalmuriError.staleSource }
        guard current.status.st_nlink == 1 else { throw GalmuriError.permission }
        if let restriction = current.file.writeRestriction { throw GalmuriError.unsupported(restriction) }
        let proposed = try BookmarkFile(data: data)
        if let restriction = proposed.writeRestriction { throw GalmuriError.unsupported(restriction) }
        guard backupRoot.resolvingSymlinksInPath().path == backupRoot.path else { throw GalmuriError.permission }
        try createBackupDirectory(backupRoot)
        let backups = try openDirectory(backupRoot)
        defer { close(backups) }
        guard fchmod(backups, 0o700) == 0 else { throw posixError() }

        let id = UUID(), backup = backupRoot.appendingPathComponent(id.uuidString + ".bookmarks")
        let temporary = source.deletingLastPathComponent().appendingPathComponent(".galmuri-" + id.uuidString + ".tmp")
        let backupHandle = try createFile(backup.lastPathComponent, directory: backups)
        defer { try? backupHandle.close() }
        try backupHandle.write(contentsOf: current.file.original)
        guard fcopyfile(current.handle.fileDescriptor, backupHandle.fileDescriptor, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0,
              fchmod(backupHandle.fileDescriptor, 0o600) == 0 else { throw posixError() }
        try synchronize(backupHandle.fileDescriptor, full: true)
        guard try ProfileIO.read(backup).fingerprint == expectedHash else { throw GalmuriError.missingBackup }
        try synchronize(backups)
        var receipt = BackupReceipt(id: id, date: Date(), profileName: name, source: source, backup: backup, beforeHash: expectedHash, afterHash: BookmarkFile.hash(data), state: "prepared", sourceIdentity: current.identity, temporary: temporary, sourceMode: current.status.st_mode & 0o7777)
        try writeReceipt(receipt, directory: backups)

        let temporaryHandle = try createFile(temporary.lastPathComponent, directory: directory)
        defer {
            try? temporaryHandle.close()
            if unlinkat(directory, temporary.lastPathComponent, 0) == 0 { try? synchronize(directory) }
        }
        try temporaryHandle.write(contentsOf: data)
        guard fcopyfile(current.handle.fileDescriptor, temporaryHandle.fileDescriptor, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else { throw posixError() }
        let attributes = try status(temporaryHandle.fileDescriptor)
        guard attributes.st_uid == current.status.st_uid, attributes.st_gid == current.status.st_gid,
              attributes.st_mode == current.status.st_mode else { throw GalmuriError.permission }
        try synchronize(temporaryHandle.fileDescriptor, full: true)
        try synchronize(directory)
        guard try ProfileIO.read(temporary).fingerprint == receipt.afterHash else { throw GalmuriError.invalid("temporary file verification failed") }

        if browserRunning() { throw GalmuriError.browserRunning }
        guard canWrite(source) else { throw GalmuriError.staleSource }
        if let restriction = try ProfileIO.storageRestriction(in: source.deletingLastPathComponent()) { throw GalmuriError.unsupported(restriction) }
        guard try ProfileIO.read(backup).fingerprint == expectedHash else { throw GalmuriError.missingBackup }
        let finalTemporary = try readSource(temporary, directory: directory)
        defer { try? finalTemporary.handle.close() }
        guard finalTemporary.file.fingerprint == receipt.afterHash, unchanged(attributes, finalTemporary.status) else { throw GalmuriError.staleSource }
        let final = try readForReview(source)
        guard final.identity == current.identity, final.file.fingerprint == expectedHash,
              unchanged(current.status, try status(current.handle.fileDescriptor)),
              unchanged(attributes, try status(temporaryHandle.fileDescriptor)) else { throw GalmuriError.staleSource }
        // shortcut: POSIX rename cannot compare-and-swap an inode; a noncooperating writer can still race the final check.
        guard renameat(directory, temporary.lastPathComponent, directory, source.lastPathComponent) == 0 else { throw posixError() }
        do {
            try synchronize(directory)
            let written = try readSource(source, directory: directory)
            defer { try? written.handle.close() }
            guard written.file.fingerprint == receipt.afterHash, written.status.st_dev == attributes.st_dev,
                  written.status.st_ino == attributes.st_ino, written.status.st_mode == attributes.st_mode,
                  written.status.st_uid == attributes.st_uid, written.status.st_gid == attributes.st_gid else { throw GalmuriError.staleSource }
            receipt.state = "fileVerified"
            try writeReceipt(receipt, directory: backups)
        } catch {
            // Keep the backup and last journal; an automatic rollback could overwrite a later writer.
            throw GalmuriError.invalid("replacement may have completed; inspect the source and original backup before retrying")
        }
        return receipt
    }

    private func createBackupDirectory(_ url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let parent = url.deletingLastPathComponent()
        try createBackupDirectory(parent)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let directory = try openDirectory(parent)
        defer { close(directory) }
        try synchronize(directory)
    }

    private func writeReceipt(_ receipt: BackupReceipt, directory: Int32) throws {
        let temporary = "." + receipt.id.uuidString + "-receipt.tmp"
        let handle = try createFile(temporary, directory: directory)
        defer { try? handle.close(); unlinkat(directory, temporary, 0) }
        try handle.write(contentsOf: JSONEncoder().encode(receipt))
        try synchronize(handle.fileDescriptor, full: true)
        guard renameat(directory, temporary, directory, receipt.id.uuidString + ".json") == 0 else { throw posixError() }
        try synchronize(directory)
    }

    func createFile(_ name: String, directory: Int32) throws -> FileHandle {
        let fd = openat(directory, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posixError() }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    func openDirectory(_ url: URL) throws -> Int32 {
        let normalized = url.standardizedFileURL
        guard url.isFileURL, url.host == nil || url.host == "localhost",
              normalized.resolvingSymlinksInPath().path == normalized.path else { throw GalmuriError.permission }
        // Foundation retains system aliases such as /var; resolve those before a no-symlink open.
        guard let path = realpath(normalized.path, nil) else { throw posixError() }
        defer { free(path) }
        var expectedPath = normalized.path
        for (alias, physical) in [("/var", "/private/var"), ("/tmp", "/private/tmp"), ("/etc", "/private/etc")] {
            if expectedPath == alias || expectedPath.hasPrefix(alias + "/") {
                expectedPath = physical + expectedPath.dropFirst(alias.count)
                break
            }
        }
        guard String(cString: path) == expectedPath else { throw GalmuriError.permission }
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard fd >= 0 else { throw posixError() }
        return fd
    }

    func status(_ fd: Int32) throws -> stat {
        var value = stat()
        guard fstat(fd, &value) == 0 else { throw posixError() }
        return value
    }

    func unchanged(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_size == rhs.st_size &&
        lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec &&
        lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    func synchronize(_ fd: Int32, full: Bool = false) throws {
        guard fsync(fd) == 0 else { throw posixError() }
        if full, fcntl(fd, F_FULLFSYNC) != 0 { throw posixError() }
    }

    func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
