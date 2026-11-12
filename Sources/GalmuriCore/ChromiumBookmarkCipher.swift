import Foundation
import CommonCrypto

/// Compatibility with the macOS v10 envelope in Chromium 153; never reads or persists Keychain credentials.
public struct ChromiumBookmarkCipher: Sendable {
    private let key: Data
    private static let prefix = Data("v10".utf8)
    private static let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)

    public init(password: Data) throws {
        guard !password.isEmpty else { throw GalmuriError.unsupported("Bookmark encryption key is unavailable.") }
        let salt = Data("saltysalt".utf8)
        var derived = Data(count: kCCKeySizeAES128)
        let status = derived.withUnsafeMutableBytes { output in
            password.withUnsafeBytes { input in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), input.bindMemory(to: CChar.self).baseAddress, password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        output.bindMemory(to: UInt8.self).baseAddress, kCCKeySizeAES128)
                }
            }
        }
        guard status == kCCSuccess else { throw GalmuriError.unsupported("Bookmark encryption key is unavailable.") }
        key = derived
    }

    public func decrypt(_ encrypted: Data) throws -> Data {
        if encrypted.isEmpty { return Data() }
        guard encrypted.count < 50_000_000, encrypted.starts(with: Self.prefix),
              encrypted.count > Self.prefix.count, (encrypted.count - Self.prefix.count) % kCCBlockSizeAES128 == 0 else {
            throw GalmuriError.unsupported("Unsupported encrypted bookmark format.")
        }
        let plaintext = try crypt(Data(encrypted.dropFirst(Self.prefix.count)), operation: CCOperation(kCCDecrypt))
        // The deterministic v10 encoding lets us reject noncanonical padding without claiming authentication.
        guard try encrypt(plaintext) == encrypted else { throw GalmuriError.invalid("Encrypted bookmark data could not be verified.") }
        return plaintext
    }

    public func encrypt(_ plaintext: Data) throws -> Data {
        if plaintext.isEmpty { return Data() }
        guard plaintext.count < 49_999_980 else { throw GalmuriError.invalid("file exceeds size limit") }
        return Self.prefix + (try crypt(plaintext, operation: CCOperation(kCCEncrypt)))
    }

    private func crypt(_ input: Data, operation: CCOperation) throws -> Data {
        var output = Data(count: input.count + kCCBlockSizeAES128), count = 0
        let capacity = output.count
        let status = output.withUnsafeMutableBytes { target in
            input.withUnsafeBytes { source in
                key.withUnsafeBytes { keyBytes in
                    Self.iv.withUnsafeBytes { iv in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress, key.count,
                            iv.baseAddress, source.baseAddress, input.count, target.baseAddress, capacity, &count)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw GalmuriError.invalid("Encrypted bookmark data could not be verified.") }
        output.count = count
        return output
    }
}
