import XCTest
@testable import GalmuriCore

final class PreservationTests: XCTestCase {
    private let item = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
    // Fixed hashes were calculated independently from Chromium's UTF-16LE title sequence.
    private let fixture = """
    {
      "version": 1,
      "checksum": "ddc7a58f17d6bbb25bf5c34fe5a87712",
      "checksum_sha256": "11340b6d6e127bcb0aa5e9f26f8e55950f5ac1b093f74b3a662b0181d310b362",
      "opaque": {"integer": 9223372036854775807, "array": [true, null, {"future": "value"}]},
      "roots": {
        "bookmark_bar": {
          "id": "1", "guid": "00000000-0000-4000-a000-000000000001", "name": "Bar", "type": "folder",
          "date_modified": "13370000000000001", "unknown": {"keep": "folder metadata"},
          "children": [
            {"id": "9223372036854775806", "guid": "AAAAAAAA-AAAA-4AAA-AAAA-AAAAAAAAAAAA", "name": "A😀한", "type": "url",
             "url": "https://example.com/duplicate", "date_added": "13370000000000003", "date_last_used": "0", "meta_info": {"future": "keep"}},
            {"id": "5", "guid": "bbbbbbbb-bbbb-4bbb-abbb-bbbbbbbbbbbb", "name": "Copy", "type": "url",
             "url": "https://example.com/duplicate", "date_added": "13370000000000005"}
          ]
        },
        "other": {"id": "2", "guid": "00000000-0000-4000-a000-000000000002", "name": "Other", "type": "folder", "children": []},
        "synced": {"id": "3", "guid": "00000000-0000-4000-a000-000000000003", "name": "Mobile", "type": "folder", "children": []}
      }
    }

    """

    func testEditedRoundTripPreservesPrecisionGUIDSpellingMetadataDatesAndOrder() throws {
        let file = try BookmarkFile(data: Data(fixture.utf8))
        XCTAssertNil(file.writeRestriction)
        XCTAssertEqual(try file.serialize(file.tree), Data(fixture.utf8))
        var edited = file.tree
        try edited.edit(item, name: "Edited😀", url: edited.nodes[item]!.url)
        let parsed = try BookmarkFile(data: file.serialize(edited))
        XCTAssertNil(parsed.writeRestriction)
        XCTAssertEqual(parsed.payload["checksum"], .string("9d8cf047f1ec5cd5345ab07eb4609255"))
        XCTAssertEqual(parsed.payload["checksum_sha256"], .string("dc61a1abac0cefce78af1a4e8a7585bbfb6d809dca8f31392fe9053ce60b508e"))
        XCTAssertEqual(parsed.tree, edited)
        XCTAssertEqual(parsed.payload["opaque"], file.payload["opaque"])
        let rawItem = parsed.payload["roots"]?.object?["bookmark_bar"]?.object?["children"]?.array?.first
        XCTAssertEqual(rawItem?.object?["guid"], .string(item.uppercased()))
        XCTAssertEqual(parsed.tree.nodes[item]?.chromeID, "9223372036854775806")
        XCTAssertEqual(parsed.tree.nodes.values.filter { $0.url == "https://example.com/duplicate" }.count, 2)
        XCTAssertEqual(file.tree.nodes[item]?.name, "A😀한")
    }

    func testUnverifiedChecksumsAndMetadataAreReadOnlyButNoOpIsExact() throws {
        let file = try BookmarkFile(data: Data(fixture.utf8))
        let cases: [(String, JSONValue?)] = [
            ("checksum", nil), ("checksum", .string("incorrect")),
            ("checksum_sha256", .string("incorrect")),
            ("opaque_number", .decimal(0.5)), ("sync_metadata", .string("unverified"))
        ]
        for (key, value) in cases {
            var payload = file.payload
            payload[key] = value
            let bytes = try JSONEncoder().encode(JSONValue.object(payload)), restricted = try BookmarkFile(data: bytes)
            XCTAssertNotNil(restricted.writeRestriction, key)
            XCTAssertEqual(try restricted.serialize(restricted.tree), bytes)
            var edited = restricted.tree
            try edited.edit(item, name: "Changed", url: edited.nodes[item]!.url)
            XCTAssertThrowsError(try restricted.serialize(edited), key)
        }
    }

    func testAmbiguousNodeFieldsAndNumericIdentitiesFailClosed() throws {
        for (old, new) in [
            ("\"type\": \"url\",", "\"type\": \"url\", \"children\": [],"),
            ("\"id\": \"5\"", "\"id\": \"05\""),
            ("\"id\": \"5\"", "\"id\": \"+5\""),
            ("\"id\": \"5\"", "\"id\": \"9223372036854775806\"")
        ] {
            XCTAssertThrowsError(try BookmarkFile(data: Data(fixture.replacingOccurrences(of: old, with: new).utf8)))
        }
    }

    func testNewIDsDoNotReuseIDsDeletedInSameEditAndDatesRemainPrecise() throws {
        let file = try BookmarkFile(data: Data(fixture.utf8))
        var edited = file.tree
        try edited.remove([item])
        let added = try edited.add(name: "New", url: "https://example.com/new", to: SampleData.bar)
        let parsed = try BookmarkFile(data: file.serialize(edited))
        XCTAssertEqual(parsed.tree.nodes[added]?.chromeID, String(Int64.max))
        XCTAssertEqual(parsed.tree.nodes[SampleData.bar]?.metadata, file.tree.nodes[SampleData.bar]?.metadata)
        _ = try edited.add(name: "Overflow", url: nil, to: SampleData.bar)
        XCTAssertThrowsError(try file.serialize(edited))
    }
}
