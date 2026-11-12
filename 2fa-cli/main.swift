import Foundation
import ImageIO

let usage = """
    usage: 2fa [-n] <name>          print the current code for the matching account
           2fa list                 list accounts
           2fa add <uri-or-image>   add an account from an otpauth:// URI or a QR code image file
           2fa remove <name>        remove the matching account

    <name> matches the issuer, the account name or "issuer:name", ignoring case; failing an
    exact match, any unique substring will do. -n omits the trailing newline.
    Use "2fa get <name>" for an account whose name clashes with a command.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("2fa: \(message)\n".utf8))
    exit(1)
}

/// The one account identified by `query`; exits with an error if there are none or several.
func resolve(_ query: String) throws -> Account {
    let matches = try AccountStore.load().matching(query)
    switch matches.count {
    case 1: return matches[0]
    case 0: fail("no account matches \"\(query)\"")
    default: fail("\"\(query)\" is ambiguous: " + matches.map(\.label).joined(separator: ", "))
    }
}

func otpauthURIs(inImageAt path: String) throws -> [String] {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("cannot read image \(path)") }
    return try QRDecoder.payloads(in: image).filter { $0.lowercased().hasPrefix("otpauth://") }
}

func printCode(for query: String) {
    do {
        let code = try resolve(query).code()
        FileHandle.standardOutput.write(Data((code + (newline ? "\n" : "")).utf8))
    } catch {
        fail(error.localizedDescription)
    }
}

var newline = true
var args = Array(CommandLine.arguments.dropFirst())
if let index = args.firstIndex(of: "-n") {
    newline = false
    args.remove(at: index)
}

do {
    switch (args.first, args.count) {
    case ("list", 1):
        for account in try AccountStore.load() { print(account.label) }

    case ("add", 2):
        let source = args[1]
        let uris = source.lowercased().hasPrefix("otpauth://") ? [source] : try otpauthURIs(inImageAt: source)
        if uris.isEmpty { fail("no 2FA QR code found in \(source)") }
        for uri in uris {
            let account = try Account(otpauthURI: uri)
            try AccountStore.add(account)
            print("added \(account.label)")
        }

    case ("remove", 2):
        let account = try resolve(args[1])
        try AccountStore.remove(id: account.id)
        print("removed \(account.label)")

    case ("get", 2):
        printCode(for: args[1])

    case (let name?, 1) where !name.hasPrefix("-"):
        printCode(for: name)

    default:
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        exit(2)
    }
} catch {
    fail(error.localizedDescription)
}
