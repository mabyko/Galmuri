import Foundation

public struct BookmarkSourceFile: Identifiable, Sendable {
    public enum Kind: Equatable, Sendable { case plaintext, encrypted, account, ordering, backup, other }
    public var id: String { name }
    public let name: String
    public let kind: Kind
    public let modifiedAt: Date?
    public let problem: String?
    public var canImport: Bool { kind == .plaintext && problem == nil }
}
