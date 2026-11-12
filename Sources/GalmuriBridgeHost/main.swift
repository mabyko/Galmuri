import Foundation
import Darwin
import GalmuriCore

struct Configuration: Decodable {
    let variant: String
    let bundleIdentifier: String
    let extensionID: String
}

struct Request: Decodable {
    let version: Int
    let apiProtocol: Int?
    let requestID: UUID
    let command: String
    let installationID: UUID?
    let name: String?
    let payload: String?
    let part: Int?
    let total: Int?
    let transfer: UUID?
}

func run() throws {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
    let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: contents.appendingPathComponent("Resources/BridgeConfiguration.json")))
    guard [2, 4, 5].contains(CommandLine.arguments.count),
          CommandLine.arguments[1] == "chrome-extension://\(configuration.extensionID)/",
          ["debug", "release"].contains(configuration.variant),
          configuration.bundleIdentifier == (configuration.variant == "debug" ? "forked.galmuri.local" : "forked.galmuri.local.release") else {
        throw GalmuriError.invalid("native host origin or configuration")
    }
    var workspace = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(configuration.bundleIdentifier)
    if CommandLine.arguments.count >= 4 {
        // A marker-bound override lets dedicated QA use the packaged host without user data.
        workspace = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        guard CommandLine.arguments[2] == "--proof-workspace", workspace.path == workspace.resolvingSymlinksInPath().path,
              try String(contentsOf: workspace.appendingPathComponent(".galmuri-bridge-proof"), encoding: .utf8) == "Galmuri pairing-only proof v1\n" else {
            throw GalmuriError.invalid("native host proof workspace")
        }
    }
    var writable = false
    if CommandLine.arguments.count == 5 {
        let marker = workspace.appendingPathComponent(".galmuri-api-write")
        var info = stat()
        guard CommandLine.arguments[4] == "--api-test-writes", lstat(marker.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_nlink == 1,
              info.st_mode & 0o077 == 0,
              try String(contentsOf: marker, encoding: .utf8) == "Galmuri dedicated API write proof v1\n" else { throw GalmuriError.localTestsOnly }
        writable = true
    }
    let store = BridgeProofStore(workspace: workspace, variant: configuration.variant)
    let api = BridgeAPIStore(workspace: workspace, variant: configuration.variant)
    var session: BridgeProof?
    var approvalDelivered = false
    defer {
        if let session {
            try? store.close(session)
            for suffix in [".snapshot", ".outbox"] { try? api.remove(name: session.id.uuidString + suffix) }
        }
    }
    var seen = Set<UUID>()
    var received = Data(), transfer: UUID?, nextPart = 0, totalParts = 0
    var outgoing: (job: APIJob, data: Data, part: Int)?
    var recordData = Data(), recordTransfer: UUID?, recordPart = 0, recordTotal = 0, recordCommand: String?
    var journalNext = [UUID: Int](), awaitingObservation = Set<UUID>()
    var delivered = Set<UUID>()
    var issued = [UUID: APIJob]()
    func ownerActive(_ job: APIJob) -> Bool {
        guard let owner = job.owner,
              owner.executable == contents.appendingPathComponent("MacOS/Galmuri").path,
              let fresh = try? APIOwner.read(owner.pid), fresh == owner else { return false }
        return true
    }
    while let data = try BridgeFraming.read(from: .standardInput) {
        let request = try JSONDecoder().decode(Request.self, from: data)
        guard recordTransfer == nil || request.command == recordCommand,
              transfer == nil || request.command == "upload" else { throw GalmuriError.invalid("interleaved API transfer") }
        guard request.version == 1, seen.count < 131_072, seen.insert(request.requestID).inserted else {
            throw GalmuriError.invalid("native host protocol version or request")
        }
        var response: [String: Any] = ["version": 1, "requestID": request.requestID.uuidString.lowercased(), "variant": configuration.variant, "bookmarkAccess": true, "apiProtocol": 2]
        switch request.command {
        case "hello":
            guard request.apiProtocol == 2, session == nil, let installation = request.installationID, let name = request.name else { throw GalmuriError.invalid("native host handshake") }
            session = try store.create(installationID: installation, name: name)
            response["status"] = "pending"
        case "status":
            guard let session else { throw GalmuriError.invalid("native host session missing") }
            approvalDelivered = try store.approved(session)
            response["status"] = approvalDelivered ? "approved" : "pending"
        case "acknowledge":
            guard let session, approvalDelivered else { throw GalmuriError.invalid("native host acknowledgement") }
            try store.acknowledge(session)
            response["status"] = "verified"
        case "upload", "poll", "result", "progress":
            guard let session, approvalDelivered, try store.approved(session) else { throw GalmuriError.invalid("API approval missing") }
            response["status"] = "verified"
            response["writable"] = writable
            if request.command == "upload" {
                guard let part = request.part, let total = request.total, let id = request.transfer,
                      total > 0, total <= 256, part >= 0, part < total,
                      let encoded = request.payload, let bytes = Data(base64Encoded: encoded), bytes.count <= 32_000 else { throw GalmuriError.invalid("API upload chunk") }
                if part == 0 { guard transfer == nil else { throw GalmuriError.invalid("API upload already active") }; transfer = id; nextPart = 0; totalParts = total; received = Data() }
                guard transfer == id, nextPart == part, totalParts == total, received.count + bytes.count < 8_000_000 else { throw GalmuriError.invalid("API upload sequence") }
                received.append(bytes); nextPart += 1
                if nextPart == total {
                    _ = try ChromeAPISnapshot(data: received)
                    let envelope = APIEnvelope(session: session, writable: writable, raw: String(decoding: received, as: UTF8.self))
                    try api.put(envelope, name: session.id.uuidString + ".snapshot")
                    transfer = nil; received = Data()
                }
            } else if request.command == "poll" {
                if outgoing == nil, delivered.count < 64,
                   let job = try? api.get(APIJob.self, name: session.id.uuidString + ".outbox"), !delivered.contains(job.id) {
                    guard job.sessionID == session.id, job.installationID == session.installationID,
                          ["snapshot", "adopt"].contains(job.command) || (job.command == "apply" && writable) else { throw GalmuriError.invalid("API job scope") }
                    guard job.command != "apply" || ownerActive(job) else { throw GalmuriError.invalid("API app disconnected") }
                    // The host exits when the session expires, so an apply must have time to finish first.
                    if job.command == "apply", session.expires.timeIntervalSinceNow < 90 {
                        response["sessionExpiring"] = true
                    } else {
                        let data = try JSONEncoder().encode(job)
                        guard data.count < 8_000_000 else { throw GalmuriError.invalid("API job size") }
                        outgoing = (job, data, 0)
                        issued[job.id] = job
                    }
                }
                if var current = outgoing {
                    response["stopped"] = try api.stopRequested(current.job)
                    let start = current.part * 32_000, end = min(start + 32_000, current.data.count)
                    response["job"] = ["id": current.job.id.uuidString.lowercased(), "part": current.part, "total": (current.data.count + 31_999) / 32_000, "payload": current.data.subdata(in: start..<end).base64EncodedString()]
                    current.part += 1
                    if end == current.data.count { delivered.insert(current.job.id); outgoing = nil } else { outgoing = current }
                }
            } else {
                guard let payload = request.payload, let bytes = Data(base64Encoded: payload), bytes.count <= 32_000 else { throw GalmuriError.invalid("API result chunk") }
                let complete: Data
                guard let id = request.transfer, let part = request.part, let total = request.total,
                      total > 0, total <= 256, part >= 0, part < total else { throw GalmuriError.invalid("API record bounds") }
                if part == 0 {
                    guard recordTransfer == nil else { throw GalmuriError.invalid("API record already active") }
                    recordTransfer = id; recordPart = 0; recordTotal = total; recordCommand = request.command; recordData = Data()
                }
                guard recordTransfer == id, recordPart == part, recordTotal == total, recordCommand == request.command,
                      recordData.count + bytes.count < 8_000_000 else { throw GalmuriError.invalid("API record sequence") }
                recordData.append(bytes); recordPart += 1
                if recordPart < total { complete = Data() }
                else { complete = recordData; recordTransfer = nil; recordData = Data(); recordCommand = nil }
                if !complete.isEmpty {
                    let result = try JSONDecoder().decode(APIJobResult.self, from: complete)
                    guard delivered.contains(result.jobID), ["succeeded", "uncertain", "stopped", "intent", "observed"].contains(result.state) else { throw GalmuriError.invalid("API result identity") }
                    if result.state == "intent", let job = issued[result.jobID], try api.stopRequested(job) {
                        try api.put(APIStop(job: job), name: job.id.uuidString + ".stop-ack")
                        response["stopped"] = true
                    } else {
                        if result.state == "intent" {
                            guard let job = issued[result.jobID], ownerActive(job) else { throw GalmuriError.invalid("API app disconnected") }
                        }
                        if request.command == "progress" {
                            guard let sequence = result.sequence else { throw GalmuriError.invalid("API operation sequence") }
                            let next = journalNext[result.jobID, default: 0]
                            guard sequence == next, sequence < 40_001,
                                  (result.state == "intent" && !awaitingObservation.contains(result.jobID)) ||
                                  (result.state == "observed" && awaitingObservation.contains(result.jobID)) else { throw GalmuriError.invalid("API operation sequence") }
                            try api.put(result, name: result.jobID.uuidString + ".operation-" + String(sequence) + "." + result.state)
                            if result.state == "intent" { awaitingObservation.insert(result.jobID) }
                            else { awaitingObservation.remove(result.jobID); journalNext[result.jobID] = next + 1 }
                        } else {
                            try api.put(result, name: result.jobID.uuidString + ".result")
                        }
                    }
                }
            }
        default:
            throw GalmuriError.unsupported("native host command")
        }
        if let session {
            response["sessionID"] = session.id.uuidString.lowercased()
            response["code"] = session.code
            response["name"] = session.name
            response["expires"] = session.expires.timeIntervalSince1970
        }
        try BridgeFraming.write(JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]), to: .standardOutput)
    }
}

// A closed Chrome pipe must surface as a thrown write error so `run`'s cleanup runs.
signal(SIGPIPE, SIG_IGN)
do { try run() }
catch {
    FileHandle.standardError.write(Data("Galmuri pairing host rejected or disconnected.\n".utf8))
    if CommandLine.arguments.contains("--proof-workspace") {
        FileHandle.standardError.write(Data("Dedicated proof diagnostic: \(String(describing: error))\n".utf8))
    }
    exit(1)
}
