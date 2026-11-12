import XCTest
@testable import GalmuriCore

final class CoreTests: XCTestCase {
    func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("galmuri-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func item(_ file: BookmarkFile, named name: String) -> String { file.tree.nodes.values.first { $0.name == name }!.id }

    func testNoChangePreservesExactBytesAndDuplicateURLs() throws {
        let file = try SampleData.file()
        XCTAssertEqual(try file.serialize(file.tree), file.original)
        XCTAssertEqual(file.tree.nodes.values.filter { $0.url == "https://example.com/interface" }.count, 2)
        var changed = file.tree
        let id = item(file, named: "Typography notes")
        try changed.edit(id, name: "한글 日本語 中文", url: "https://example.com/new")
        let parsed = try BookmarkFile(data: file.serialize(changed))
        XCTAssertEqual(parsed.tree.nodes[id]?.name, "한글 日本語 中文")
        XCTAssertEqual(parsed.tree.nodes[id]?.chromeID, file.tree.nodes[id]?.chromeID)
        XCTAssertEqual(parsed.tree.nodes[id]?.metadata, file.tree.nodes[id]?.metadata)
        XCTAssertEqual(parsed.payload["meta_info"], file.payload["meta_info"])
    }

    func testFolderValidationAndUnsafeEdits() throws {
        let file = try SampleData.file(); var tree = file.tree
        let design = item(file, named: "Design references")
        let child = try tree.add(name: "Nested", url: nil, to: design)
        let before = tree
        XCTAssertThrowsError(try tree.move([design], to: child))
        XCTAssertEqual(tree, before)
        XCTAssertThrowsError(try tree.remove([SampleData.bar]))
        XCTAssertThrowsError(try tree.add(name: "Bad", url: "javascript:alert(1)", to: design))
        try tree.remove([design]); XCTAssertNil(tree.nodes[child]); try tree.validate()
    }

    func testIndependentFieldsAndBrowserAdditionArePreserved() throws {
        let file = try SampleData.file(), id = item(file, named: "Typography notes")
        var ours = file.tree, theirs = file.tree
        try ours.edit(id, name: "App name", url: file.tree.nodes[id]!.url)
        try theirs.edit(id, name: file.tree.nodes[id]!.name, url: "https://example.com/browser")
        let added = try theirs.add(name: "Browser new", url: "https://example.com/added", to: SampleData.other)
        let merged = try MergeEngine.merge(base: file.tree, ours: ours, theirs: theirs)
        XCTAssertTrue(merged.conflicts.isEmpty)
        XCTAssertEqual(merged.tree.nodes[id]?.name, "App name")
        XCTAssertEqual(merged.tree.nodes[id]?.url, "https://example.com/browser")
        XCTAssertNotNil(merged.tree.nodes[added])
    }

    func testNameConflictRequiresChoiceAndDeleteVersusEdit() throws {
        let file = try SampleData.file(), id = item(file, named: "Typography notes")
        var ours = file.tree, theirs = file.tree
        try ours.edit(id, name: "App", url: file.tree.nodes[id]!.url)
        try theirs.edit(id, name: "Browser", url: file.tree.nodes[id]!.url)
        let pending = try MergeEngine.merge(base: file.tree, ours: ours, theirs: theirs)
        XCTAssertEqual(pending.unresolved.count, 1)
        let resolved = try MergeEngine.merge(base: file.tree, ours: ours, theirs: theirs, resolutions: [pending.conflicts[0].id: .ours])
        XCTAssertTrue(resolved.unresolved.isEmpty); XCTAssertEqual(resolved.tree.nodes[id]?.name, "App")
        ours = file.tree; try ours.remove([id])
        let removed = try MergeEngine.merge(base: file.tree, ours: ours, theirs: theirs)
        XCTAssertEqual(removed.unresolved.count, 1)
        XCTAssertNotNil(removed.tree.nodes[id])
    }

    func testFolderDeletionVersusDescendantEditIsOneSubtreeChoice() throws {
        let file = try SampleData.file(), folder = item(file, named: "Design references"), child = item(file, named: "Typography notes")
        var ours = file.tree, theirs = file.tree
        try ours.remove([folder]); try theirs.edit(child, name: "Browser changed child", url: file.tree.nodes[child]!.url)
        let extra = try theirs.add(name: "Added inside", url: "https://example.com/child", to: folder)
        let result = try MergeEngine.merge(base: file.tree, ours: ours, theirs: theirs)
        XCTAssertEqual(result.unresolved.count, 1)
        XCTAssertEqual(result.tree.nodes[child]?.name, "Browser changed child"); XCTAssertNotNil(result.tree.nodes[extra])
        let deleted = try MergeEngine.merge(base: file.tree, ours: ours, theirs: theirs, resolutions: [result.conflicts[0].id: .ours])
        XCTAssertNil(deleted.tree.nodes[folder]); XCTAssertNil(deleted.tree.nodes[extra]); try deleted.tree.validate()
    }

    func testBothSideAdditionsRequireOrderChoiceAndAllocateDistinctIDs() throws {
        let file = try SampleData.file(); var ours = file.tree, theirs = file.tree
        let a = try ours.add(name: "App added", url: "https://example.com/a", to: SampleData.other)
        let b = try theirs.add(name: "Browser added", url: "https://example.com/b", to: SampleData.other)
        let result = try MergeEngine.merge(base: file.tree, ours: ours, theirs: theirs)
        XCTAssertTrue(result.conflicts.contains { $0.field == "Sibling order" })
        let choices = Dictionary(uniqueKeysWithValues: result.conflicts.map { ($0.id, MergeSide.ours) })
        let resolved = try MergeEngine.merge(base: file.tree, ours: ours, theirs: theirs, resolutions: choices)
        let parsed = try BookmarkFile(data: file.serialize(resolved.tree))
        XCTAssertNotNil(parsed.tree.nodes[a]); XCTAssertNotNil(parsed.tree.nodes[b])
        XCTAssertNotEqual(parsed.tree.nodes[a]?.chromeID, parsed.tree.nodes[b]?.chromeID)
    }

    func testCombinedMovesCannotCreateCycle() throws {
        let file = try SampleData.file(), a = item(file, named: "Design references"), b = item(file, named: "Development")
        var ours = file.tree, theirs = file.tree
        try ours.move([a], to: b); try theirs.move([b], to: a)
        let pending = try MergeEngine.merge(base: file.tree, ours: ours, theirs: theirs)
        XCTAssertEqual(pending.unresolved.map(\.field), ["Combined folder moves"])
        for side in [MergeSide.ours, .theirs] {
            let resolved = try MergeEngine.merge(base: file.tree, ours: ours, theirs: theirs, resolutions: [pending.conflicts[0].id: side])
            XCTAssertTrue(resolved.unresolved.isEmpty)
            XCTAssertEqual(resolved.tree.nodes[a]?.parent, (side == .ours ? ours : theirs).nodes[a]?.parent)
            XCTAssertEqual(resolved.tree.nodes[b]?.parent, (side == .ours ? ours : theirs).nodes[b]?.parent)
            try resolved.tree.validate()
        }
    }

    func testWorkspaceRoundTripAndInvalidOriginalAreRejected() throws {
        let root = try temporaryRoot(), file = try SampleData.file()
        var p = ConnectedProfile(name: "Test", source: root.appendingPathComponent("Bookmarks"), base: file)
        try p.working.edit(item(file, named: "Typography notes"), name: "Saved edit", url: "https://example.com/saved")
        let workspace = Workspace(profiles: [p]), url = root.appendingPathComponent("workspace.json")
        try workspace.save(to: url)
        let loaded = try Workspace.load(from: url)
        XCTAssertEqual(loaded.profiles[0].working, p.working)
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try Workspace.load(from: url)); XCTAssertEqual(try Data(contentsOf: url), Data("broken".utf8))
    }

    func testDiscoveryAndNetscapeExportPreserveDuplicates() throws {
        let root = try temporaryRoot(), file = try SampleData.file()
        for name in ["Default", "Profile 1"] {
            let folder = root.appendingPathComponent(name); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try file.original.write(to: folder.appendingPathComponent("Bookmarks"))
        }
        let found = try ProfileIO.discover(in: root); XCTAssertEqual(found.count, 2)
        let html = String(data: try ProfileIO.exportHTML(file.tree), encoding: .utf8)!
        XCTAssertEqual(html.components(separatedBy: "HREF=\"https://example.com/interface\"").count - 1, 2)
    }

    func testDiscoveryDoesNotFollowLocalStateLinksOrReadOversizeMetadata() throws {
        let root = try temporaryRoot(), profile = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try SampleData.file().original.write(to: profile.appendingPathComponent("Bookmarks"))
        let state = root.appendingPathComponent("Local State")
        let json = Data("{\"profile\":{\"info_cache\":{\"Default\":{\"name\":\"Friendly name\"}}}}".utf8)
        try json.write(to: state)
        XCTAssertEqual(try ProfileIO.discover(in: root).first?.name, "Friendly name")
        let outside = try temporaryRoot().appendingPathComponent("Local State")
        try json.write(to: outside)
        try FileManager.default.removeItem(at: state)
        try FileManager.default.createSymbolicLink(at: state, withDestinationURL: outside)
        XCTAssertEqual(try ProfileIO.discover(in: root).first?.name, "Default")
        try FileManager.default.removeItem(at: state)
        try Data().write(to: state)
        let handle = try FileHandle(forWritingTo: state)
        try handle.truncate(atOffset: 20_000_000); try handle.close()
        XCTAssertEqual(try ProfileIO.discover(in: root).first?.name, "Default")
        XCTAssertEqual(try Data(contentsOf: outside), json)
    }

    func testApplyBackupRestoreStaleAndBrowserGuards() throws {
        let root = try temporaryRoot(), profileRoot = root.appendingPathComponent("test/Default")
        try FileManager.default.createDirectory(at: profileRoot, withIntermediateDirectories: true)
        let source = profileRoot.appendingPathComponent("Bookmarks"), file = try SampleData.file()
        try file.original.write(to: source)
        let coordinator = ApplyCoordinator(testRoot: root.appendingPathComponent("test"), backupRoot: root.appendingPathComponent("backups"))
        var profile = ConnectedProfile(name: "Test", source: source, base: file)
        let id = item(file, named: "Typography notes")
        try profile.working.edit(id, name: "Applied", url: file.tree.nodes[id]!.url)
        let review = try coordinator.prepare(profile: profile)
        XCTAssertThrowsError(try coordinator.apply(profile: profile, review: review, browserRunning: { true }))
        XCTAssertEqual(try Data(contentsOf: source), file.original)
        let receipt = try coordinator.apply(profile: profile, review: review, browserRunning: { false })
        XCTAssertEqual(receipt.state, "fileVerified")
        XCTAssertEqual(try Data(contentsOf: receipt.backup), file.original)
        XCTAssertEqual(try ProfileIO.read(source).tree.nodes[id]?.name, "Applied")
        XCTAssertThrowsError(try coordinator.apply(profile: profile, review: review, browserRunning: { false }))
        _ = try coordinator.restore(receipt, expectedCurrentHash: receipt.afterHash, browserRunning: { false })
        XCTAssertEqual(try Data(contentsOf: source), file.original)
        XCTAssertEqual(try coordinator.receipts().count, 2)
    }

    func testRestartDuringCommitLeavesOriginalAndBackupAvailable() throws {
        let root = try temporaryRoot(), testRoot = root.appendingPathComponent("test"), source = testRoot.appendingPathComponent("Bookmarks")
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        let file = try SampleData.file(); try file.original.write(to: source)
        let coordinator = ApplyCoordinator(testRoot: testRoot, backupRoot: root.appendingPathComponent("backups"))
        var profile = ConnectedProfile(name: "Test", source: source, base: file)
        try profile.working.edit(item(file, named: "Typography notes"), name: "App", url: "https://example.com/app")
        let review = try coordinator.prepare(profile: profile); var checks = 0
        XCTAssertThrowsError(try coordinator.apply(profile: profile, review: review, browserRunning: { checks += 1; return checks == 2 }))
        XCTAssertEqual(try Data(contentsOf: source), file.original)
        XCTAssertEqual(try coordinator.receipts().first?.state, "prepared")
    }

    func testExternalTargetsAndSymlinksAreNeverWritable() throws {
        let root = try temporaryRoot(), testRoot = root.appendingPathComponent("test"), other = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try SampleData.file().original.write(to: other.appendingPathComponent("Bookmarks"))
        let link = testRoot.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        let coordinator = ApplyCoordinator(testRoot: testRoot, backupRoot: root.appendingPathComponent("backups"))
        XCTAssertFalse(coordinator.canWrite(other.appendingPathComponent("Bookmarks")))
        XCTAssertFalse(coordinator.canWrite(link.appendingPathComponent("Bookmarks")))
        XCTAssertThrowsError(try ProfileIO.discover(in: link))
        XCTAssertThrowsError(try ProfileIO.read(link.appendingPathComponent("Bookmarks")))
    }
}
