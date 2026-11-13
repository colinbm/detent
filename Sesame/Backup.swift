import CommonCrypto
import CryptoKit
import Foundation

/// A passphrase-encrypted file holding every account, for backups and moving between machines.
nonisolated enum Backup {
    static let fileExtension = "sesamebackup"

    private struct File: Codable {
        var format = "sesame-backup"
        var version = 1
        var iterations: Int
        var salt: Data
        /// AES-256-GCM (nonce, ciphertext and tag) over the JSON-encoded accounts.
        var sealed: Data
    }

    enum Failure: LocalizedError {
        case notABackup
        case wrongPassphrase

        var errorDescription: String? {
            switch self {
            case .notABackup: "That file is not a Sesame backup."
            case .wrongPassphrase: "The passphrase is wrong, or the backup is damaged."
            }
        }
    }

    static func encrypt(_ accounts: [Account], passphrase: String) throws -> Data {
        let iterations = 600_000
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(JSONEncoder().encode(accounts), using: key)
        guard let combined = sealed.combined else { throw Failure.notABackup }
        return try JSONEncoder().encode(File(iterations: iterations, salt: salt, sealed: combined))
    }

    static func decrypt(_ data: Data, passphrase: String) throws -> [Account] {
        guard let file = try? JSONDecoder().decode(File.self, from: data),
              file.format == "sesame-backup", file.version == 1,
              (1...10_000_000).contains(file.iterations)
        else { throw Failure.notABackup }

        let key = try deriveKey(passphrase: passphrase, salt: file.salt, iterations: file.iterations)
        guard let box = try? AES.GCM.SealedBox(combined: file.sealed),
              let plain = try? AES.GCM.open(box, using: key),
              let accounts = try? JSONDecoder().decode([Account].self, from: plain)
        else { throw Failure.wrongPassphrase }
        return accounts
    }

    /// PBKDF2-HMAC-SHA256, 32-byte key.
    private static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let password = Array(passphrase.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            password.withUnsafeBufferPointer { passwordBytes in
                passwordBytes.withMemoryRebound(to: CChar.self) { chars in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2), chars.baseAddress, chars.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        &derived, derived.count)
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.notABackup }
        return SymmetricKey(data: derived)
    }
}
