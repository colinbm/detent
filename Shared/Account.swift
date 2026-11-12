import Foundation

nonisolated struct Account: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var issuer: String
    var name: String
    var secret: Data
    var algorithm: OTPAlgorithm = .sha1
    var digits = 6
    var period = 30

    /// "Issuer:name", or whichever half is present.
    var label: String {
        if issuer.isEmpty { return name }
        if name.isEmpty { return issuer }
        return "\(issuer):\(name)"
    }

    func code(at date: Date = Date()) -> String {
        TOTP.code(secret: secret, algorithm: algorithm, digits: digits, period: period, at: date)
    }
}

nonisolated enum AccountError: LocalizedError {
    case notOTPAuth
    case unsupportedType(String)
    case badSecret
    case badParameter(String)

    var errorDescription: String? {
        switch self {
        case .notOTPAuth: "Not an otpauth:// URI."
        case .unsupportedType(let type): "Only time-based (totp) codes are supported, not \"\(type)\"."
        case .badSecret: "The secret is missing or is not valid base32."
        case .badParameter(let name): "Invalid \"\(name)\" parameter."
        }
    }
}

nonisolated extension Account {
    /// Parses the standard `otpauth://totp/Issuer:name?secret=…&issuer=…&algorithm=…&digits=…&period=…` format.
    init(otpauthURI: String) throws {
        guard let components = URLComponents(string: otpauthURI.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "otpauth"
        else { throw AccountError.notOTPAuth }

        let type = components.host?.lowercased() ?? ""
        guard type == "totp" else { throw AccountError.unsupportedType(type) }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = item.value ?? ""
        }

        guard let secret = Base32.decode(query["secret"] ?? "") else { throw AccountError.badSecret }

        // Label is "Issuer:name" or just "name"; an explicit issuer parameter wins.
        let label = components.path.drop(while: { $0 == "/" })
        var issuer = ""
        var name = String(label)
        if let colon = label.firstIndex(of: ":") {
            issuer = String(label[..<colon])
            name = String(label[label.index(after: colon)...])
        }
        if let explicit = query["issuer"], !explicit.isEmpty { issuer = explicit }

        var algorithm = OTPAlgorithm.sha1
        if let value = query["algorithm"], !value.isEmpty {
            guard let parsed = OTPAlgorithm(rawValue: value.uppercased().replacingOccurrences(of: "-", with: ""))
            else { throw AccountError.badParameter("algorithm") }
            algorithm = parsed
        }

        var digits = 6
        if let value = query["digits"], !value.isEmpty {
            guard let parsed = Int(value), (6...9).contains(parsed) else { throw AccountError.badParameter("digits") }
            digits = parsed
        }

        var period = 30
        if let value = query["period"], !value.isEmpty {
            guard let parsed = Int(value), parsed > 0 else { throw AccountError.badParameter("period") }
            period = parsed
        }

        self.init(
            issuer: issuer.trimmingCharacters(in: .whitespaces),
            name: name.trimmingCharacters(in: .whitespaces),
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period
        )
    }
}

nonisolated extension Array where Element == Account {
    /// Accounts identified by `query`, case-insensitively: an exact match on issuer, name or
    /// "issuer:name" if there is one, otherwise everything containing `query`.
    func matching(_ query: String) -> [Account] {
        let q = query.lowercased()
        let exact = filter { [$0.issuer, $0.name, $0.label].contains { $0.lowercased() == q } }
        if !exact.isEmpty { return exact }
        return filter { $0.label.lowercased().contains(q) }
    }
}
