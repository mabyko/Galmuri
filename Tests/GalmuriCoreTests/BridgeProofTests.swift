import XCTest
import Foundation
import Darwin
@testable import GalmuriCore

final class BridgeProofTests: XCTestCase {
    private var root: URL!
    private var store: BridgeProofStore!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        store = BridgeProofStore(workspace: root, variant: "debug")
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func path(_ request: BridgeProof, _ suffix: String = "request") -> URL {
        store.directory.appendingPathComponent(request.id.uuidString.lowercased() + ".\(suffix).json")
    }

    func testApprovalAcknowledgementAndDisconnectAreBoundToExactSession() throws {
        let id = UUID()
        let a = try store.create(installationID: id, name: "QA Profile")
        let b = try store.create(installationID: id, name: "QA Profile")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertFalse(try store.approved(a))
        XCTAssertThrowsError(try store.acknowledge(a))
        try store.approve(a); try store.approve(a)
        XCTAssertTrue(try store.approved(a)); XCTAssertFalse(try store.approved(b))
        try store.acknowledge(a); try store.acknowledge(a)
        XCTAssertEqual(try JSONDecoder().decode(BridgeProof.self, from: Data(contentsOf: path(a, "verified"))), a)
        try store.close(a)
        XCTAssertEqual(try store.requests().map(\.id), [b.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(a, "verified").path))
    }

    func testExpiryAndVariantRejectApprovalAndDoNotGrantLaterSession() throws {
        let now = Date()
        let request = try store.create(installationID: UUID(), name: "QA", now: now)
        XCTAssertThrowsError(try store.approve(request, now: now.addingTimeInterval(301)))
        XCTAssertEqual(try store.requests(now: now.addingTimeInterval(301)), [])
        let release = BridgeProofStore(workspace: root, variant: "release")
        XCTAssertThrowsError(try release.approve(request, now: now))
        XCTAssertThrowsError(try release.requests(now: now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(request, "approval").path))
    }

    func testInvalidLabelsAndVariantsDoNotCreateRequests() throws {
        for label in ["", " ", " QA", "QA\n", String(repeating: "a", count: 81)] {
            XCTAssertThrowsError(try store.create(installationID: UUID(), name: label))
        }
        XCTAssertThrowsError(try BridgeProofStore(workspace: root, variant: "unknown").create(installationID: UUID(), name: "QA"))
        XCTAssertEqual(try store.requests(), [])
    }

    func testChangedRequestCannotBeApprovedOrRemoved() throws {
        let request = try store.create(installationID: UUID(), name: "QA")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: path(request))) as! [String: Any]
        object["name"] = "Different profile"
        try JSONSerialization.data(withJSONObject: object).write(to: path(request))
        XCTAssertThrowsError(try store.approve(request))
        XCTAssertThrowsError(try store.close(request))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(request, "approval").path))
    }

    func testSymlinksHardlinksAndPermissionsAreRejected() throws {
        let request = try store.create(installationID: UUID(), name: "QA")
        let original = path(request), saved = root.appendingPathComponent("saved.json")
        try FileManager.default.moveItem(at: original, to: saved)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: saved)
        XCTAssertThrowsError(try store.requests())
        try FileManager.default.removeItem(at: original)
        try FileManager.default.linkItem(at: saved, to: original)
        XCTAssertThrowsError(try store.approve(request))
        try FileManager.default.removeItem(at: original)
        try FileManager.default.moveItem(at: saved, to: original)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: original.path)
        XCTAssertThrowsError(try store.requests())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: original.path)
        try store.close(request)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.directory.path)
        XCTAssertThrowsError(try store.create(installationID: UUID(), name: "QA"))
    }

    func testCorruptFIFOAndOversizedRequestsFailClosed() throws {
        let request = try store.create(installationID: UUID(), name: "QA")
        let target = path(request)
        try Data(repeating: 65, count: 4096).write(to: target)
        XCTAssertThrowsError(try store.requests())
        try FileManager.default.removeItem(at: target)
        XCTAssertEqual(mkfifo(target.path, 0o600), 0)
        XCTAssertThrowsError(try store.requests())
    }

    func testFramingMultipleFramesEOFAndTruncation() throws {
        let pipe = Pipe(), message = Data("{\"ok\":true}".utf8)
        try BridgeFraming.write(message, to: pipe.fileHandleForWriting)
        try BridgeFraming.write(message, to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()
        XCTAssertEqual(try BridgeFraming.read(from: pipe.fileHandleForReading), message)
        XCTAssertEqual(try BridgeFraming.read(from: pipe.fileHandleForReading), message)
        XCTAssertNil(try BridgeFraming.read(from: pipe.fileHandleForReading))
        for bytes: [UInt8] in [[1], [1, 0, 0, 0], [0, 0, 0, 0], [1, 0, 1, 0]] {
            let bad = Pipe(); try bad.fileHandleForWriting.write(contentsOf: Data(bytes)); try bad.fileHandleForWriting.close()
            XCTAssertThrowsError(try BridgeFraming.read(from: bad.fileHandleForReading))
        }
        XCTAssertThrowsError(try BridgeFraming.write(Data(), to: .standardOutput))
    }

    func testRequestPermissionsAndBoundedInventory() throws {
        let request = try store.create(installationID: UUID(), name: "QA")
        let info = try FileManager.default.attributesOfItem(atPath: path(request).path)
        XCTAssertEqual((info[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        for i in 0..<129 { FileManager.default.createFile(atPath: store.directory.appendingPathComponent("extra-\(i)").path, contents: Data()) }
        XCTAssertThrowsError(try store.requests())
        XCTAssertThrowsError(try store.create(installationID: UUID(), name: "QA"))
    }
}
