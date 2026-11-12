import CryptoKit
import Foundation

nonisolated enum OTPAlgorithm: String, Codable, Sendable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

/// RFC 6238 time-based one-time passwords.
nonisolated enum TOTP {
    static func code(secret: Data, algorithm: OTPAlgorithm, digits: Int, period: Int, at date: Date = Date()) -> String {
        let counter = UInt64(max(0, date.timeIntervalSince1970)) / UInt64(period)
        let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let key = SymmetricKey(data: secret)

        let mac: [UInt8]
        switch algorithm {
        case .sha1: mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: mac = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }

        // Dynamic truncation (RFC 4226 §5.3).
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let binary = (UInt32(mac[offset] & 0x7f) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])

        var modulus: UInt32 = 1
        for _ in 0..<digits { modulus *= 10 }
        let value = String(binary % modulus)
        return String(repeating: "0", count: max(0, digits - value.count)) + value
    }

    /// Seconds until the code generated at `date` stops being valid.
    static func secondsRemaining(period: Int, at date: Date = Date()) -> Double {
        let p = Double(period)
        return p - date.timeIntervalSince1970.truncatingRemainder(dividingBy: p)
    }
}

nonisolated enum Base32 {
    /// Decodes RFC 4648 base32, ignoring case, padding, spaces and dashes. Returns nil on invalid input.
    static func decode(_ string: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var buffer: UInt32 = 0
        var bits = 0
        var out = Data()
        for ch in string.uppercased() {
            if ch == "=" || ch == " " || ch == "-" { continue }
            guard let index = alphabet.firstIndex(of: ch) else { return nil }
            buffer = (buffer << 5) | UInt32(index)
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((buffer >> UInt32(bits)) & 0xff))
            }
        }
        return out.isEmpty ? nil : out
    }
}
