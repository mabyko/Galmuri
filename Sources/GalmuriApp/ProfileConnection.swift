import Foundation
import GalmuriCore

enum BookmarkBrowser: String, CaseIterable, Identifiable {
    case chrome, egoLite
    var id: Self { self }
    var name: String { self == .chrome ? "Chrome" : "Ego Lite" }
    var dataDirectory: URL { dataDirectory(home: FileManager.default.homeDirectoryForCurrentUser) }
    func dataDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(self == .chrome ? "Google/Chrome" : "Citro Labs/ego lite", isDirectory: true)
    }
    var storageWarning: String? {
        self == .egoLite ? "Ego Lite connection is experimental and read-only. Browser freshness and format compatibility are not verified." : nil
    }
}

struct ProfileConnection: Identifiable {
    let id = UUID()
    let directory: URL
    let profiles: [DiscoveredProfile]
    var browser: BookmarkBrowser = .chrome
    var origin: ProfileDiscoveryOrigin = .knownLocation
}

enum ProfileDiscoveryIssue: Equatable {
    case permissionDenied, missingLocation, unavailable

    static func classify(_ error: Error) -> Self {
        var missing = false
        for error in connectionErrorChain(error) {
            if error as? GalmuriError == .permission { return .permissionDenied }
            let current = error as NSError
            if current.domain == NSCocoaErrorDomain {
                if current.code == NSFileReadNoPermissionError { return .permissionDenied }
                missing = missing || [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(current.code)
            }
            if current.domain == NSPOSIXErrorDomain {
                if [Int(POSIXErrorCode.EACCES.rawValue), Int(POSIXErrorCode.EPERM.rawValue)].contains(current.code) { return .permissionDenied }
                missing = missing || current.code == Int(POSIXErrorCode.ENOENT.rawValue)
            }
        }
        return missing ? .missingLocation : .unavailable
    }
}

struct ProfileConnectionNotice {
    let directory: URL
    let issue: ProfileDiscoveryIssue
    var detail: String? = nil
    var browser: BookmarkBrowser = .chrome
    var origin: ProfileDiscoveryOrigin = .knownLocation
    var diagnostic: ProfileReadDiagnostic? = nil

    func guidance(onMacOSMajorVersion major: Int) -> ProfileAccessGuidance {
        if diagnostic?.posixCode == Int(POSIXErrorCode.EACCES.rawValue) { return .filePermissions }
        return browser == .chrome && major >= 27 && origin == .folderSelection ? .systemSettings : .folderSelection
    }
}

enum ProfileDiscoveryOrigin: Equatable { case knownLocation, folderSelection }
enum ProfileAccessGuidance: Equatable { case systemSettings, folderSelection, filePermissions }

struct ProfileReadDiagnostic: Equatable {
    let codes: [String]
    let posixCode: Int?

    init(error: Error) {
        let chain = connectionErrorChain(error).map { $0 as NSError }
        codes = chain.map { "\($0.domain) (\($0.code))" }
        posixCode = chain.reversed().first { $0.domain == NSPOSIXErrorDomain }?.code
    }
}

private func connectionErrorChain(_ error: Error) -> [Error] {
    var current = error, chain = [Error]()
    for _ in 0..<4 {
        chain.append(current)
        guard let underlying = (current as NSError).userInfo[NSUnderlyingErrorKey] as? Error else { break }
        current = underlying
    }
    return chain
}
