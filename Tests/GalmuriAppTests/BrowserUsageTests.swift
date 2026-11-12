import XCTest
import Darwin
@testable import GalmuriApp

final class BrowserUsageTests: XCTestCase {
    func testExplicitRootParserPreservesSpacesAndOnlyAcceptsOneAbsoluteOverride() {
        XCTAssertEqual(BrowserUsage.explicitRoot(arguments: ["Chrome", "--user-data-dir=/tmp/Test Root"]), "/tmp/Test Root")
        XCTAssertEqual(BrowserUsage.explicitRoot(arguments: ["Chrome", "--user-data-dir=/tmp/Root", "--", "--user-data-dir=/ignored"]), "/tmp/Root")
        let unknown: [[String]?] = [
            nil, [], [""], ["Chrome"], ["Chrome", "--profile-directory=Default"],
            ["Chrome", "--", "--user-data-dir=/tmp/Root"],
            ["Chrome", "--user-data-dir"], ["Chrome", "--user-data-dir", "/tmp/Root"],
            ["Chrome", "--user-data-dir="], ["Chrome", "--user-data-dir=relative"],
            ["Chrome", "--user-data-dir=~/Root"], ["Chrome", "--user-data-dir=\"/tmp/Root\""],
            ["Chrome", "--user-data-dir=//host/Root"], ["Chrome", "--user-data-dir=/tmp/Root\0extra"],
            ["Chrome", "--user-data-directory=/tmp/Root"],
            ["Chrome", "--user-data-dir=/tmp/Root", "--user-data-dir=/tmp/Root"],
            ["Chrome", "--user-data-dir=/tmp/Root", "--user-data-dir"],
            ["Chrome", "--user-data-dir=/tmp/Root", "-user-data-dir=/tmp/Other"],
            ["Chrome", "--user-data-dir=/tmp/Root", " --user-data-dir=/tmp/Other"],
            ["Chrome", "--user-data-dir=/tmp/Root "],
            ["Chrome", "--user-data-dir=/tmp/Root", "--type=renderer"]
        ]
        for arguments in unknown { XCTAssertNil(BrowserUsage.explicitRoot(arguments: arguments)) }
    }

    func testCanonicalRootComparisonAndUnknownState() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("GalmuriBrowserUsage-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("Test Root")
        let profile = root.appendingPathComponent("Profile 1")
        let other = temporary.appendingPathComponent("Test Root Extra")
        for directory in [profile, other] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let source = profile.appendingPathComponent("Bookmarks")
        func blocks(_ root: URL) -> Bool { BrowserUsage.blocks(arguments: ["Chrome", "--user-data-dir=" + root.path], for: source) }
        XCTAssertTrue(blocks(root))
        XCTAssertTrue(blocks(root.appendingPathComponent("../Test Root")))
        XCTAssertFalse(blocks(other))
        let alias = temporary.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        XCTAssertTrue(blocks(alias))
        XCTAssertTrue(BrowserUsage.blocks(arguments: ["Chrome", "--user-data-dir=" + root.path], for: alias.appendingPathComponent("Profile 1/Bookmarks")))
        let profileAlias = temporary.appendingPathComponent("Profile Alias")
        try FileManager.default.createSymbolicLink(at: profileAlias, withDestinationURL: profile)
        XCTAssertTrue(BrowserUsage.blocks(arguments: ["Chrome", "--user-data-dir=" + root.path], for: profileAlias.appendingPathComponent("Bookmarks")))
        XCTAssertTrue(blocks(temporary.appendingPathComponent("Missing")))
        let file = temporary.appendingPathComponent("Not a directory")
        try Data().write(to: file)
        XCTAssertTrue(blocks(file))
        XCTAssertTrue(BrowserUsage.blocks(arguments: nil, for: source))
        XCTAssertTrue(BrowserUsage.blocks(arguments: ["Chrome"], for: source))
        XCTAssertTrue(BrowserUsage.blocks(arguments: ["Chrome", "--user-data-dir=relative"], for: source))
        XCTAssertTrue(BrowserUsage.blocks(arguments: ["Chrome", "--user-data-dir=" + other.path], for: profile.appendingPathComponent("History")))
        XCTAssertTrue(BrowserUsage.blocks(arguments: ["Chrome", "--user-data-dir=" + other.path], for: URL(string: "https://example.org/Root/Profile/Bookmarks")!))
    }

    func testOnlyRecognizedChromeMainProcessesAreInspectable() {
        XCTAssertEqual(BrowserUsage.processKind(bundleIdentifier: "com.google.Chrome", executableName: "Google Chrome", name: "Google Chrome"), .main)
        XCTAssertEqual(BrowserUsage.processKind(bundleIdentifier: "org.chromium.Chromium", executableName: "Chromium", name: nil), .main)
        XCTAssertEqual(BrowserUsage.processKind(bundleIdentifier: "com.google.Chrome.helper", executableName: "Google Chrome Helper", name: nil), .unknown)
        XCTAssertEqual(BrowserUsage.processKind(bundleIdentifier: "com.google.Chrome", executableName: nil, name: nil), .unknown)
        XCTAssertEqual(BrowserUsage.processKind(bundleIdentifier: nil, executableName: "Chrome Unknown", name: nil), .unknown)
        XCTAssertEqual(BrowserUsage.processKind(bundleIdentifier: "com.example.Other", executableName: "Other", name: nil), .unrelated)
    }

    func testDecoderStopsAfterArgcWithoutDecodingEnvironment() {
        let argv = ["/Synthetic/Google Chrome", "--user-data-dir=/tmp/Test Root", ""]
        var count = Int32(argv.count)
        var bytes = withUnsafeBytes(of: &count) { Array($0) }
        bytes += Array("/Synthetic/Google Chrome".utf8) + [0, 0, 0]
        for argument in argv { bytes += Array(argument.utf8) + [0] }
        let argvEnd = bytes.count
        bytes += [0xff, 0xfe, 0x3d, 0, 0xff]
        XCTAssertEqual(bytes.withUnsafeBytes(BrowserUsage.decodeArguments), argv)
        XCTAssertNil(Array(bytes.prefix(argvEnd - 1)).withUnsafeBytes(BrowserUsage.decodeArguments))
        XCTAssertNil([UInt8]().withUnsafeBytes(BrowserUsage.decodeArguments))
        XCTAssertNil([UInt8](repeating: 0, count: 12).withUnsafeBytes(BrowserUsage.decodeArguments))
        var invalidCount = bytes
        invalidCount.replaceSubrange(0..<4, with: [0xff, 0xff, 0xff, 0xff])
        XCTAssertNil(invalidCount.withUnsafeBytes(BrowserUsage.decodeArguments))
        invalidCount.replaceSubrange(0..<4, with: [0xff, 0xff, 0xff, 0x7f])
        XCTAssertNil(invalidCount.withUnsafeBytes(BrowserUsage.decodeArguments))
        var invalidUTF8 = bytes
        invalidUTF8[MemoryLayout<Int32>.size + "/Synthetic/Google Chrome".utf8.count + 3] = 0xff
        XCTAssertNil(invalidUTF8.withUnsafeBytes(BrowserUsage.decodeArguments))
    }

    func testCurrentProcessArgumentDecodingWithoutLoggingArguments() {
        let arguments = BrowserUsage.arguments(for: getpid())
        XCTAssertTrue(arguments == CommandLine.arguments)
        XCTAssertNil(BrowserUsage.arguments(for: -1))
    }
}
