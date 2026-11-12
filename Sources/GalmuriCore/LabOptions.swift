import Foundation

public struct LabOptions: Codable, Equatable, Sendable {
    public var version = 1
    public var apiEnabled = false
    public var fileEnabled = false
    public init() {}

    public static func load(from url: URL) throws -> LabOptions {
        let data: Data
        do { data = try ProfileIO.readData(url, limit: 4096) }
        catch let error as POSIXError where error.code == .ENOENT { return LabOptions() }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1 else { throw GalmuriError.invalid("Labs options version") }
        return result
    }

    public func save(to url: URL) throws {
        guard version == 1, url.isFileURL, url.host == nil,
              url.standardizedFileURL == url, url.resolvingSymlinksInPath() == url else { throw GalmuriError.permission }
        let data = try JSONEncoder().encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum ExtensionPresence: Equatable, Sendable {
    case recordFound, notDetected, unavailable
}

public enum ProfileExtensionInventory {
    /// Observes registration records only; never proves activation, live pairing or absence.
    public static func inspect(source: URL, extensionID: String) throws -> ExtensionPresence {
        guard source.isFileURL, source.lastPathComponent == "Bookmarks", extensionID.count == 32,
              extensionID.utf8.allSatisfy({ (97...112).contains($0) }) else { throw GalmuriError.permission }
        var filesRead = 0, found = false
        for name in ["Preferences", "Secure Preferences"] {
            let data: Data
            do { data = try ProfileIO.readData(source.deletingLastPathComponent().appendingPathComponent(name), limit: 16_000_000) }
            catch let error as POSIXError where error.code == .ENOENT { continue }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GalmuriError.invalid("extension preference format") }
            filesRead += 1
            if let extensions = object["extensions"] {
                guard let extensions = extensions as? [String: Any] else { throw GalmuriError.invalid("extension preference format") }
                if let settings = extensions["settings"] {
                    guard let settings = settings as? [String: Any] else { throw GalmuriError.invalid("extension preference format") }
                    if let record = settings[extensionID] {
                        guard record is [String: Any] else { throw GalmuriError.invalid("extension preference format") }
                        found = true
                    }
                }
            }
        }
        return filesRead == 0 ? .unavailable : found ? .recordFound : .notDetected
    }
}
