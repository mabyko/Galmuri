import Foundation
import Darwin

/// Pairing-only proof. This does not grant access to bookmarks or create a workspace connection.
public struct BridgeProof: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let installationID: UUID
    public let name: String
    public let code: String
    public let variant: String
    public let expires: Date

    public init(installationID: UUID, name: String, variant: String, now: Date = Date()) throws {
        guard ["debug", "release"].contains(variant), !name.isEmpty, name.count <= 80,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw GalmuriError.invalid("bridge profile label or variant")
        }
        id = UUID(); self.installationID = installationID; self.name = name; self.variant = variant
        code = String(format: "%06d", Int.random(in: 0...999_999))
        expires = now.addingTimeInterval(300)
    }

    func validate(variant: String, now: Date) throws {
        guard self.variant == variant, ["debug", "release"].contains(variant),
              code.utf8.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }),
              !name.isEmpty, name.count <= 80, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              expires.timeIntervalSince1970.isFinite, expires > now,
              expires <= now.addingTimeInterval(300) else { throw GalmuriError.invalid("expired or invalid bridge request") }
    }
}

public struct BridgeProofStore: Sendable {
    public let directory: URL
    public let variant: String

    public init(workspace: URL, variant: String) {
        directory = workspace.appendingPathComponent("BridgeProof", isDirectory: true)
        self.variant = variant
    }

    init(directory: URL, variant: String) { self.directory = directory; self.variant = variant }

    func checkDirectory(create: Bool) throws {
        guard ["debug", "release"].contains(variant), directory.isFileURL, directory.host == nil,
              directory.standardizedFileURL.path == directory.path,
              directory.resolvingSymlinksInPath().path == directory.path else { throw GalmuriError.invalid("bridge directory") }
        if create { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else { throw GalmuriError.invalid("bridge directory permissions") }
    }

    private func url(_ id: UUID, approval: Bool = false) -> URL {
        directory.appendingPathComponent(id.uuidString.lowercased() + (approval ? ".approval.json" : ".request.json"))
    }

    private func read(_ source: URL) throws -> BridgeProof {
        try JSONDecoder().decode(BridgeProof.self, from: readData(source, limit: 4096))
    }

    func readData(_ source: URL, limit: Int) throws -> Data {
        guard source.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path else { throw GalmuriError.invalid("bridge file path") }
        let fd = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw GalmuriError.invalid("bridge request unavailable") }
        defer { Darwin.close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == geteuid(), before.st_nlink == 1, before.st_mode & 0o077 == 0,
              before.st_size > 0, before.st_size < limit else { throw GalmuriError.invalid("bridge request attributes") }
        var data = Data(count: Int(before.st_size))
        let length = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
        var after = stat()
        guard length == data.count, fstat(fd, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw GalmuriError.staleSource }
        return data
    }

    private func write(_ request: BridgeProof, approval: Bool = false) throws {
        try write(request, target: url(request.id, approval: approval))
    }

    private func write(_ request: BridgeProof, target: URL) throws {
        let data = try JSONEncoder().encode(request)
        try writeData(data, target: target)
    }

    func writeData(_ data: Data, target: URL) throws {
        guard target.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path else { throw GalmuriError.invalid("bridge file path") }
        let fd = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw GalmuriError.invalid("bridge request already exists") }
        defer { Darwin.close(fd) }
        let length = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
        guard length == data.count, fsync(fd) == 0 else {
            _ = unlink(target.path)
            throw GalmuriError.invalid("bridge request could not be saved")
        }
    }

    func replaceData(_ data: Data, target: URL, limit: Int = 20_000_000) throws {
        guard data.count < limit, target.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path else { throw GalmuriError.invalid("bridge file size or path") }
        try checkDirectory(create: true)
        if FileManager.default.fileExists(atPath: target.path) { _ = try readData(target, limit: limit) }
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".stage")
        try writeData(data, target: temporary)
        guard rename(temporary.path, target.path) == 0 else { throw GalmuriError.invalid("bridge file replacement") }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw GalmuriError.invalid("bridge directory unavailable") }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw GalmuriError.invalid("bridge directory flush") }
    }

    public func create(installationID: UUID, name: String, now: Date = Date()) throws -> BridgeProof {
        try checkDirectory(create: true)
        // Hard-killed hosts skip their cleanup; purge their expired files so pairing cannot be blocked forever.
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path)
        where [".request.json", ".approval.json", ".verified.json"].contains(where: { name.hasSuffix($0) }) {
            let entry = directory.appendingPathComponent(name)
            if let proof = try? read(entry), proof.variant == variant, proof.expires <= now { _ = unlink(entry.path) }
        }
        guard try FileManager.default.contentsOfDirectory(atPath: directory.path).count < 128 else {
            throw GalmuriError.invalid("too many bridge proof files")
        }
        let request = try BridgeProof(installationID: installationID, name: name, variant: variant, now: now)
        try write(request)
        return request
    }

    public func requests(now: Date = Date()) throws -> [BridgeProof] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        try checkDirectory(create: false)
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard entries.count <= 128 else { throw GalmuriError.invalid("too many bridge proof files") }
        return try entries.filter { $0.lastPathComponent.hasSuffix(".request.json") }.compactMap { entry in
            let request = try read(entry)
            guard entry.standardizedFileURL.path == url(request.id).path else { throw GalmuriError.invalid("bridge request identity") }
            guard request.expires > now else { return nil }
            try request.validate(variant: variant, now: now)
            return request
        }.sorted { $0.expires < $1.expires }
    }

    public func approve(_ request: BridgeProof, now: Date = Date()) throws {
        try checkDirectory(create: false)
        try request.validate(variant: variant, now: now)
        guard try read(url(request.id)) == request else { throw GalmuriError.staleSource }
        if FileManager.default.fileExists(atPath: url(request.id, approval: true).path) {
            guard try read(url(request.id, approval: true)) == request else { throw GalmuriError.staleSource }
            return
        }
        try write(request, approval: true)
    }

    public func approved(_ request: BridgeProof, now: Date = Date()) throws -> Bool {
        try checkDirectory(create: false)
        try request.validate(variant: variant, now: now)
        guard try read(url(request.id)) == request else { throw GalmuriError.staleSource }
        guard FileManager.default.fileExists(atPath: url(request.id, approval: true).path) else { return false }
        guard try read(url(request.id, approval: true)) == request else { throw GalmuriError.staleSource }
        return true
    }

    public func acknowledge(_ request: BridgeProof, now: Date = Date()) throws {
        guard try approved(request, now: now) else { throw GalmuriError.invalid("bridge request is not approved") }
        let target = directory.appendingPathComponent(request.id.uuidString.lowercased() + ".verified.json")
        if FileManager.default.fileExists(atPath: target.path) {
            guard try read(target) == request else { throw GalmuriError.staleSource }
            return
        }
        try write(request, target: target)
    }

    public func close(_ request: BridgeProof) throws {
        try checkDirectory(create: false)
        let verified = directory.appendingPathComponent(request.id.uuidString.lowercased() + ".verified.json")
        for target in [verified, url(request.id, approval: true), url(request.id)] where FileManager.default.fileExists(atPath: target.path) {
            guard try read(target) == request else { throw GalmuriError.staleSource }
            try FileManager.default.removeItem(at: target)
        }
    }
}

public enum BridgeFraming {
    public static let limit = 65_536

    public static func read(from handle: FileHandle) throws -> Data? {
        func exact(_ size: Int) throws -> Data {
            var data = Data()
            while data.count < size {
                guard let next = try handle.read(upToCount: size - data.count), !next.isEmpty else {
                    throw GalmuriError.invalid("truncated native message")
                }
                data.append(next)
            }
            return data
        }
        guard let first = try handle.read(upToCount: 1), !first.isEmpty else { return nil }
        let header = first + (try exact(3))
        let count = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard count > 0, count <= limit else { throw GalmuriError.invalid("native message size") }
        return try exact(Int(count))
    }

    public static func write(_ data: Data, to handle: FileHandle) throws {
        guard !data.isEmpty, data.count <= limit else { throw GalmuriError.invalid("native message size") }
        var length = UInt32(data.count)
        let header = withUnsafeBytes(of: &length) { Data($0) }
        try handle.write(contentsOf: header + data)
    }
}
