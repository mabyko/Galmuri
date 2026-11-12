import AppKit
import Darwin

enum BrowserUsage {
    enum ProcessKind { case unrelated, main, unknown }

    @MainActor
    static func isRunning(for source: URL) -> Bool {
        // shortcut: NSWorkspace is a snapshot, not a restart lock; lifecycle validation remains required before external writes.
        NSWorkspace.shared.runningApplications.contains { app in
            switch processKind(bundleIdentifier: app.bundleIdentifier, executableName: app.executableURL?.lastPathComponent, name: app.localizedName) {
            case .unrelated: return false
            case .unknown: return true
            case .main: return blocks(arguments: arguments(for: app.processIdentifier), for: source)
            }
        }
    }

    static func processKind(bundleIdentifier: String?, executableName: String?, name: String?) -> ProcessKind {
        let labels = [bundleIdentifier, executableName, name].compactMap { $0?.lowercased() }
        guard labels.contains(where: { $0.contains("chrome") || $0.contains("chromium") }) else { return .unrelated }
        let mainNames = ["Google Chrome", "Google Chrome Beta", "Google Chrome Dev", "Google Chrome Canary", "Google Chrome for Testing", "Chromium"]
        guard let executableName, mainNames.contains(executableName),
              !labels.contains(where: { $0.contains("helper") }) else { return .unknown }
        return .main
    }

    // nil means default, malformed, helper, or otherwise unknown; never infer a default root.
    static func explicitRoot(arguments: [String]?) -> String? {
        guard let arguments, let executable = arguments.first, !executable.isEmpty,
              !arguments.contains(where: { $0.contains("\0") }) else { return nil }
        var root: String?
        for argument in arguments.dropFirst() {
            guard argument == argument.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{000B}\u{000C}")) else { return nil }
            if argument == "--" { break }
            if argument == "--type" || argument.hasPrefix("--type=") || argument == "-type" || argument.hasPrefix("-type=") { return nil }
            if argument.hasPrefix("-user-data-dir") { return nil }
            guard argument.hasPrefix("--user-data-dir") else { continue }
            // Chromium's POSIX switch values use '='; a separate argv value is not a root override.
            guard root == nil, argument.hasPrefix("--user-data-dir=") else { return nil }
            let value = String(argument.dropFirst("--user-data-dir=".count))
            guard value.hasPrefix("/"), !value.hasPrefix("//") else { return nil }
            root = value
        }
        return root
    }

    static func blocks(arguments: [String]?, for source: URL) -> Bool {
        guard source.isFileURL, source.host == nil || source.host == "localhost", source.lastPathComponent == "Bookmarks",
              let root = explicitRoot(arguments: arguments),
              let processRoot = canonicalComponents(URL(fileURLWithPath: root)),
              let profile = canonicalComponents(source.deletingLastPathComponent()), profile.count > 2 else { return true }
        let sourceRoot = Array(profile.dropLast())
        // Conservatively equate case variants even on a case-sensitive volume.
        return processRoot.count == sourceRoot.count && zip(processRoot, sourceRoot).allSatisfy {
            $0.compare($1, options: .caseInsensitive) == .orderedSame
        }
    }

    private static func canonicalComponents(_ url: URL) -> [String]? {
        guard let path = url.withUnsafeFileSystemRepresentation({ path in
            path.flatMap { realpath($0, nil) }
        }) else { return nil }
        defer { free(path) }
        guard let canonical = String(validatingCString: path) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: canonical).pathComponents
    }

    static func arguments(for pid: pid_t) -> [String]? {
        guard pid > 0 else { return nil }
        var maximum: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var limitMIB = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&limitMIB, u_int(limitMIB.count), &maximum, &size, nil, 0) == 0,
              maximum > 0, maximum <= 16 * 1024 * 1024 else { return nil }
        // The kernel may include environment bytes; keep them raw and decode only argc arguments.
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(maximum), alignment: MemoryLayout<Int32>.alignment)
        defer { buffer.deallocate() }
        size = Int(maximum)
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, u_int(mib.count), buffer, &size, nil, 0) == 0,
              size <= Int(maximum) else { return nil }
        return decodeArguments(UnsafeRawBufferPointer(start: buffer, count: size))
    }

    static func decodeArguments(_ bytes: UnsafeRawBufferPointer) -> [String]? {
        guard bytes.count >= MemoryLayout<Int32>.size else { return nil }
        let count = Int(bytes.loadUnaligned(as: Int32.self))
        guard count > 0, count <= bytes.count - MemoryLayout<Int32>.size else { return nil }
        var offset = MemoryLayout<Int32>.size
        while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
        guard offset > MemoryLayout<Int32>.size, offset < bytes.count else { return nil }
        while offset < bytes.count, bytes[offset] == 0 { offset += 1 }
        var arguments: [String] = []
        // KERN_PROCARGS2: argc, executable path, padding, then argc NUL-terminated argv strings.
        // Stop at argc: trailing environment bytes are never decoded or examined.
        for _ in 0..<count {
            let start = offset
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            guard offset < bytes.count, let argument = String(bytes: bytes[start..<offset], encoding: .utf8) else { return nil }
            arguments.append(argument)
            offset += 1
        }
        return arguments
    }
}
