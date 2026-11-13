import Foundation

let usage = """
    usage: sesame [-n] <name>   print the current code for the matching account
           sesame list          list accounts

    <name> matches the issuer, the account name or "issuer:name", ignoring case; failing an
    exact match, any unique substring will do. -n omits the trailing newline.
    Use "sesame get <name>" for an account called "list". Accounts are managed in the Sesame app.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sesame: \(message)\n".utf8))
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
