import XCTest
@testable import GalmuriCore

final class CoreModelVerificationTests: XCTestCase {
    private func item(_ tree: BookmarkTree, named name: String) -> String {
        tree.nodes.values.first { $0.name == name }!.id
    }

    private func temporaryWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("galmuri-model-verification-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("workspace.json")
    }

    func testEditedAndAddedNumericMetadataStayFailClosed() throws {
        let file = try SampleData.file()
        let existing = item(file.tree, named: "Typography notes")
        for addNew in [false, true] {
            var edited = file.tree
            let id = try addNew ? edited.add(name: "New", url: nil, to: SampleData.other) : existing
            edited.nodes[id]?.metadata["future"] = .object(["nested": .array([.decimal(0.5)])])
            XCTAssertThrowsError(try file.serialize(edited)) { error in
                XCTAssertEqual(error as? GalmuriError, .unsupported("Unverified numeric metadata"))
            }
        }
        XCTAssertEqual(try file.serialize(file.tree), file.original)
    }

    func testIndependentRelativeOrdersMergeDeterministicallyWithoutMutatingInputs() throws {
        let base = try SampleData.file().tree
        let folder = item(base, named: "Design references"), children = base.nodes[folder]!.children
        var ours = base, theirs = base
        try ours.reorder(children[0], offset: 1)
        try theirs.reorder(children[2], offset: 1)
        let snapshots = [base, ours, theirs]
        let first = try MergeEngine.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertTrue(first.conflicts.isEmpty)
        XCTAssertEqual(first.tree.nodes[folder]?.children, [children[1], children[0], children[3], children[2]])
        let repeated = try MergeEngine.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(repeated.tree, first.tree)
        XCTAssertEqual(repeated.conflicts, first.conflicts)
        XCTAssertEqual([base, ours, theirs], snapshots)
        try first.tree.validate()
    }

    func testExtremeReorderOffsetsLeaveTreeUnchanged() throws {
        var tree = try SampleData.file().tree
        let id = item(tree, named: "Typography notes"), before = tree
        for offset in [Int.max, Int.min, -100, 100] {
            try tree.reorder(id, offset: offset)
            XCTAssertEqual(tree, before)
        }
    }

    func testMalformedTreeIdentitiesEdgesAndStructuralMetadataAreRejected() throws {
        let base = try SampleData.file().tree
        let id = item(base, named: "Typography notes"), sibling = item(base, named: "Interface archive")
        let parent = try XCTUnwrap(base.nodes[id]?.parent)
        var invalid = base
        invalid.nodes[parent]?.children.append(id)
        XCTAssertThrowsError(try invalid.validate())
        invalid = base
        invalid.nodes[id]?.parent = SampleData.other
        XCTAssertThrowsError(try invalid.validate())
        invalid = base
        invalid.nodes[parent]?.children.removeAll { $0 == id }
        XCTAssertThrowsError(try invalid.validate())
        invalid = base
        invalid.nodes[id]?.chromeID = base.nodes[sibling]!.chromeID
        XCTAssertThrowsError(try invalid.validate())
        invalid = base
        invalid.roots["alias"] = SampleData.bar
        XCTAssertThrowsError(try invalid.validate())
        for key in ["guid", "id", "name", "type", "url", "children"] {
            invalid = base
            invalid.nodes[id]?.metadata[key] = .string("shadow")
            XCTAssertThrowsError(try invalid.validate(), key)
        }
    }

    func testMetadataDeletionVersusNullRequiresExplicitChoiceAndPreservesDates() throws {
        var base = try SampleData.file().tree
        let id = item(base, named: "Typography notes")
        base.nodes[id]?.metadata["future"] = .object(["precise": .integer(Int64.max)])
        var ours = base, theirs = base
        ours.nodes[id]?.metadata.removeValue(forKey: "future")
        theirs.nodes[id]?.metadata["future"] = .null
        let snapshots = [base, ours, theirs]
        let pending = try MergeEngine.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(pending.unresolved.map(\.field), ["future"])
        let conflict = try XCTUnwrap(pending.conflicts.first)
        XCTAssertEqual(conflict.ours, "Not present")
        XCTAssertEqual(conflict.theirs, "null")
        for side in [MergeSide.ours, .theirs] {
            let resolved = try MergeEngine.merge(base: base, ours: ours, theirs: theirs, resolutions: [conflict.id: side])
            XCTAssertTrue(resolved.unresolved.isEmpty)
            XCTAssertEqual(resolved.tree.nodes[id]?.metadata, (side == .ours ? ours : theirs).nodes[id]?.metadata)
            XCTAssertEqual(resolved.tree.nodes[id]?.chromeID, base.nodes[id]?.chromeID)
        }
        XCTAssertEqual([base, ours, theirs], snapshots)
    }

    func testWorkspaceV1RetainsBaseBytesUnsavedIdentitiesAndPreciseMetadata() throws {
        let url = try temporaryWorkspace(), file = try SampleData.file()
        var profile = ConnectedProfile(name: "Synthetic", source: url.deletingLastPathComponent().appendingPathComponent("Bookmarks"), base: file)
        let added = try profile.working.add(name: "Offline addition", url: nil, to: SampleData.other)
        profile.working.nodes[added]?.metadata["date_added"] = .string("13370000000000003")
        profile.working.nodes[added]?.metadata["future"] = .object(["precise": .integer(Int64.max)])
        try Workspace(profiles: [profile]).save(to: url)
        let loaded = try Workspace.load(from: url)
        XCTAssertEqual(loaded.version, 1)
        XCTAssertEqual(loaded.profiles.first?.id, profile.id)
        XCTAssertEqual(loaded.profiles.first?.base, file)
        XCTAssertEqual(loaded.profiles.first?.base.original, file.original)
        XCTAssertEqual(loaded.profiles.first?.working, profile.working)
        XCTAssertEqual(loaded.profiles.first?.working.nodes[added]?.chromeID, "0")
        XCTAssertEqual(loaded.profiles.first?.hasChanges, true)
        var invalid = loaded
        invalid.version = 2
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(try invalid.save(to: url))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testTamperedWorkspaceBaseIsRejectedWithoutRewritingFile() throws {
        let url = try temporaryWorkspace(), file = try SampleData.file()
        let profile = ConnectedProfile(name: "Synthetic", source: url.deletingLastPathComponent().appendingPathComponent("Bookmarks"), base: file)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Workspace(profiles: [profile]))) as? [String: Any])
        var profiles = try XCTUnwrap(json["profiles"] as? [[String: Any]])
        var storedBase = try XCTUnwrap(profiles[0]["base"] as? [String: Any])
        var payload = try XCTUnwrap(storedBase["payload"] as? [String: Any])
        payload["version"] = 99
        storedBase["payload"] = payload
        profiles[0]["base"] = storedBase
        json["profiles"] = profiles
        let bytes = try JSONSerialization.data(withJSONObject: json)
        try bytes.write(to: url)
        XCTAssertThrowsError(try Workspace.load(from: url))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testSaveSkipsBaseReparseWhileLoadStillRejectsTamperedBase() throws {
        let url = try temporaryWorkspace(), file = try SampleData.file()
        let profile = ConnectedProfile(name: "Synthetic", source: url.deletingLastPathComponent().appendingPathComponent("Bookmarks"), base: file)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Workspace(profiles: [profile]))) as? [String: Any])
        var profiles = try XCTUnwrap(json["profiles"] as? [[String: Any]])
        var storedBase = try XCTUnwrap(profiles[0]["base"] as? [String: Any])
        var payload = try XCTUnwrap(storedBase["payload"] as? [String: Any])
        payload["version"] = 99
        storedBase["payload"] = payload
        profiles[0]["base"] = storedBase
        json["profiles"] = profiles
        // Decoding directly bypasses `load`, so only the full check can notice the mismatch.
        let tampered = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try tampered.validate())
        XCTAssertNoThrow(try tampered.save(to: url))
        XCTAssertThrowsError(try Workspace.load(from: url))
    }

    func testOversizedWorkspaceSavePreservesPreviousRecoverableFile() throws {
        let url = try temporaryWorkspace()
        var profile = ConnectedProfile(name: "Synthetic", source: url.deletingLastPathComponent().appendingPathComponent("Bookmarks"), base: try SampleData.file())
        try Workspace(profiles: [profile]).save(to: url)
        let before = try Data(contentsOf: url)
        profile.name = String(repeating: "x", count: 100_000_000)
        XCTAssertThrowsError(try Workspace(profiles: [profile]).save(to: url))
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try Workspace.load(from: url).profiles.first?.name, "Synthetic")
    }
}
