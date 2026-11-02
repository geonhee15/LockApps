import Foundation
import CommonCrypto
import Security

/// PBKDF2-HMAC-SHA256 with a random per-lock salt. Only the salt + derived key are stored, never the password.
enum PasswordHasher {
    static let iterations: UInt32 = 150_000
    static let keyLength = 32

    static func randomSalt(count: Int = 16) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            for i in 0..<count { bytes[i] = UInt8.random(in: 0...255) }
        }
        return Data(bytes)
    }

    static func derive(password: String, salt: Data, iterations: UInt32 = iterations) -> Data {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: keyLength)
        let saltBytes = [UInt8](salt)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBytes.map { CChar(bitPattern: $0) }, passwordBytes.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            iterations,
            &derived, keyLength
        )
        precondition(status == kCCSuccess, "PBKDF2 failed: \(status)")
        return Data(derived)
    }

    /// Constant-time comparison so timing does not leak how many bytes matched.
    static func verify(password: String, salt: Data, iterations: UInt32, expected: Data) -> Bool {
        let candidate = derive(password: password, salt: salt, iterations: iterations)
        guard candidate.count == expected.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(candidate, expected) { diff |= a ^ b }
        return diff == 0
    }
}
