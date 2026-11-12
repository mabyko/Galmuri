import Foundation
import Darwin

public struct DiscoveredProfile: Identifiable, Sendable {
    public var id: String { directory.path }
    public let name: String
    public let directory: URL
    public let file: URL
    public let restriction: String?
    public let hasPlaintext: Bool
    public let files: [BookmarkSourceFile]
    public var canImportPlaintext: Bool { files.contains(where: \.canImport) }
}

public enum ProfileIO {
    private static let bookmarkReadLimit = 50_000_000
    public static func discover(in selected: URL) throws -> [DiscoveredProfile] {
        let fm = FileManager.default
        guard selected.isFileURL, selected.host == nil || selected.host == "localhost",
              selected.standardizedFileURL.path == selected.resolvingSymlinksInPath().path else { throw GalmuriError.permission }
        let listing = try fm.contentsOfDirectory(at: selected, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        let names: [String: JSONValue]
        let state = selected.appendingPathComponent("Local State")
        if let data = try? readData(state, limit: 20_000_000),
           let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            names = json.object?["profile"]?.object?["info_cache"]?.object ?? [:]
        } else { names = [:] }
        let selectedFiles = sourceFiles(in: listing)
        let selectedRestriction = try storageRestriction(in: selected)
        let candidates = selectedFiles.contains { $0.kind == .plaintext } || selectedRestriction != nil ? [selected] : listing
        var profiles = [DiscoveredProfile]()
        for directory in candidates {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let file = directory.appendingPathComponent("Bookmarks")
            let restriction = try storageRestriction(in: directory)
            let files = directory == selected ? selectedFiles : sourceFiles(in: try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            guard !files.isEmpty else { continue }
            let hasPlaintext = files.contains { $0.kind == .plaintext }
            let name = names[directory.lastPathComponent]?.object?["name"]?.string ?? directory.lastPathComponent
            profiles.append(DiscoveredProfile(name: name, directory: directory, file: file, restriction: restriction, hasPlaintext: hasPlaintext, files: files))
        }
        return profiles.sorted { $0.directory.path < $1.directory.path }
    }

    private static func sourceFiles(in entries: [URL]) -> [BookmarkSourceFile] {
        entries.compactMap { url -> BookmarkSourceFile? in
            let name = url.lastPathComponent, lower = name.lowercased()
            guard name == "Bookmarks" || name == "Bookmarks.bak" ||
                  lower.contains("encrypted") && lower.contains("bookmark") ||
                  name.hasPrefix("AccountBookmarks") || name.hasPrefix("BookmarkMergedSurfaceOrdering") else { return nil }
            let kind: BookmarkSourceFile.Kind
            if name == "Bookmarks" { kind = .plaintext }
            else if lower.hasSuffix(".bak") { kind = .backup }
            else if lower.contains("encrypted") { kind = .encrypted }
            else if name == "AccountBookmarks" { kind = .account }
            else if name == "BookmarkMergedSurfaceOrdering" { kind = .ordering }
            else { kind = .other }
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                return BookmarkSourceFile(name: name, kind: kind, modifiedAt: nil, problem: "File information could not be read.")
            }
            guard info.st_mode & S_IFMT == S_IFREG else {
                let problem = info.st_mode & S_IFMT == S_IFLNK ? "Symbolic links are not read." : "This is not a regular file."
                return BookmarkSourceFile(name: name, kind: kind, modifiedAt: nil, problem: problem)
            }
            var problem: String?
            if kind == .plaintext {
                // Check access without loading payloads; selected files are parsed again at import.
                let fd = open(url.path, O_RDONLY | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC)
                if fd < 0 { problem = "The plaintext bookmark file cannot be opened for reading." }
                else {
                    defer { close(fd) }
                    var opened = stat()
                    if fstat(fd, &opened) != 0 || opened.st_mode & S_IFMT != S_IFREG || opened.st_dev != info.st_dev || opened.st_ino != info.st_ino {
                        problem = "The file changed during inspection. Try connecting again."
                    } else {
                        info = opened
                        if info.st_size >= bookmarkReadLimit { problem = "The plaintext bookmark file exceeds the read size limit." }
                    }
                }
            }
            let date = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000)
            return BookmarkSourceFile(name: name, kind: kind, modifiedAt: date, problem: problem)
        }.sorted {
            if ($0.kind == .plaintext) != ($1.kind == .plaintext) { return $0.kind == .plaintext }
            return $0.name < $1.name
        }
    }

    static func storageRestriction(in directory: URL) throws -> String? {
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let complex = files.contains { $0.localizedCaseInsensitiveContains("encrypted") && $0.localizedCaseInsensitiveContains("bookmark") || $0.hasPrefix("AccountBookmarks") || $0.hasPrefix("BookmarkMergedSurfaceOrdering") }
        return complex ? "Account, encrypted, or separate ordering bookmark storage detected; plaintext may not be authoritative." : nil
    }

    public static func read(_ url: URL) throws -> BookmarkFile {
        try BookmarkFile(data: readData(url, limit: bookmarkReadLimit))
    }

    static func readData(_ url: URL, limit: Int) throws -> Data {
        let normalized = url.standardizedFileURL
        guard url.isFileURL, url.host == nil || url.host == "localhost",
              normalized.path == normalized.resolvingSymlinksInPath().path else { throw GalmuriError.permission }
        guard let path = realpath(normalized.path, nil) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { free(path) }
        var expectedPath = normalized.path
        for (alias, physical) in [("/var", "/private/var"), ("/tmp", "/private/tmp"), ("/etc", "/private/etc")] {
            if expectedPath == alias || expectedPath.hasPrefix(alias + "/") {
                expectedPath = physical + expectedPath.dropFirst(alias.count)
                break
            }
        }
        guard String(cString: path) == expectedPath else { throw GalmuriError.permission }
        let fd = open(path, O_RDONLY | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG else { throw GalmuriError.permission }
        guard before.st_size < limit else { throw GalmuriError.invalid("file exceeds size limit") }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65_536, limit - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count < limit else { throw GalmuriError.invalid("file exceeds size limit") }
        }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw GalmuriError.staleSource }
        return data
    }

    public static func exportHTML(_ tree: BookmarkTree, under folder: String? = nil) throws -> Data {
        try tree.validate()
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        func nodeHTML(_ id: String) throws -> String {
            let n = tree.nodes[id]!
            if let url = n.url {
                guard let scheme = URL(string: url)?.scheme?.lowercased(), ["http", "https"].contains(scheme) else { throw GalmuriError.unsupported("HTML export contains a URL scheme that requires review") }
                return "<DT><A HREF=\"\(escape(url))\">\(escape(n.name))</A>\n"
            }
            return "<DT><H3>\(escape(n.name))</H3>\n<DL><p>\n" + (try n.children.map(nodeHTML).joined()) + "</DL><p>\n"
        }
        let ids: [String]
        if let folder { guard tree.nodes[folder]?.isFolder == true else { throw GalmuriError.invalid("export folder") }; ids = tree.nodes[folder]!.children }
        else { ids = tree.orderedRoots }
        let html = "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n<TITLE>Galmuri bookmarks</TITLE>\n<H1>Bookmarks</H1>\n<DL><p>\n" + (try ids.map(nodeHTML).joined()) + "</DL><p>\n"
        return Data(html.utf8)
    }
}
