import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), integer(Int64), decimal(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self) { self = .decimal(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .decimal(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    public var object: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    public var containsUnverifiedNumber: Bool {
        switch self {
        case .decimal: true
        case .object(let v): v.values.contains { $0.containsUnverifiedNumber }
        case .array(let v): v.contains { $0.containsUnverifiedNumber }
        default: false
        }
    }
    public var display: String {
        if case .string(let v) = self { return v }
        return (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "null"
    }
}

public enum GalmuriError: LocalizedError, Equatable {
    case invalid(String), unsupported(String), staleSource, browserRunning, localTestsOnly, unresolved, permission, missingBackup

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): "Invalid bookmark data: \(reason)"
        case .unsupported(let reason): "Read-only format: \(reason)"
        case .staleSource: "The original changed. Read it again and review the latest changes."
        case .browserRunning: "Chrome is using this data folder. Finish your browser work and quit before applying."
        case .localTestsOnly: "Direct writes are currently limited to Galmuri's local test data. Connected profiles remain read-only."
        case .unresolved: "Resolve every conflict before applying changes."
        case .permission: "This location cannot be accessed. Choose the folder again and check its permissions."
        case .missingBackup: "The original backup could not be verified. Nothing was applied."
        }
    }
}
