import Foundation

/// The Chrome side of the tool. The Sesame extension reaches it through native messaging:
/// Chrome starts `sesame` with the calling extension's origin as its first argument, then
/// exchanges JSON messages over stdin and stdout, each prefixed with a 32-bit length.
nonisolated enum NativeHost {
    static let name = "com.colinbm.sesame"
    /// Fixed by the "key" in the extension's manifest.json.
    static let extensionOrigin = "chrome-extension://pbgaheeaiiddegjmogimabnlpioggiko/"

    /// Whether Chrome launched the tool as a native messaging host.
    static func isInvocation(_ arguments: [String]) -> Bool {
        arguments.first?.hasPrefix("chrome-extension://") == true
    }

    /// Answers messages until Chrome closes the pipe.
    static func run(origin: String) {
        // Chrome only starts hosts for origins the manifest allows; this covers a manifest
        // someone has edited to let another extension in.
        guard origin == extensionOrigin else {
            write(["error": "This extension may not use Sesame."])
            return
        }
        while let message = read() {
            write(reply(to: message))
        }
    }

    private static func reply(to message: [String: Any]) -> [String: Any] {
        do {
            let accounts = try AccountStore.load()
            switch message["cmd"] as? String {
            case "list":
                return ["accounts": accounts.map { ["id": $0.id.uuidString, "label": $0.label] }]

            case "code":
                guard let id = message["id"] as? String,
                      let account = accounts.first(where: { $0.id.uuidString == id })
                else { return ["error": "That account is no longer in Sesame."] }
                let now = Date()
                return [
                    "code": account.code(at: now),
                    "remaining": TOTP.secondsRemaining(period: account.period, at: now),
                ]

            default:
                return ["error": "Unknown request."]
            }
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    private static func read() -> [String: Any]? {
        let input = FileHandle.standardInput
        guard let header = try? input.read(upToCount: 4), header.count == 4 else { return nil }
        let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        // Chrome never sends more than 4 GB, and nothing the extension says is over a few bytes.
        guard length <= 1 << 20, let body = try? input.read(upToCount: length), body.count == length
        else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }

    private static func write(_ message: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: message) else { return }
        let header = withUnsafeBytes(of: UInt32(body.count)) { Data($0) }
        FileHandle.standardOutput.write(header + body)
    }
}

nonisolated extension NativeHost {
    /// Folders, under ~/Library/Application Support, where Chromium browsers look for hosts.
    private static let browsers = [
        "Google/Chrome", "Google/Chrome Beta", "Google/Chrome Canary", "Chromium",
        "BraveSoftware/Brave-Browser", "Microsoft Edge", "Vivaldi", "Arc/User Data",
    ]

    /// Tells each installed Chromium browser where this tool is, so the extension can start it.
    /// Returns the manifests written.
    static func install() throws -> [URL] {
        guard let tool = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            throw CocoaError(.fileNoSuchFile)
        }
        let manifest = try JSONSerialization.data(
            withJSONObject: [
                "name": name,
                "description": "Sesame two-factor codes",
                "path": tool.path,
                "type": "stdio",
                "allowed_origins": [extensionOrigin],
            ],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])

        let files = FileManager.default
        let support = files.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        var written: [URL] = []
        for browser in browsers {
            let profile = support.appending(path: browser)
            guard files.fileExists(atPath: profile.path) else { continue }
            let folder = profile.appending(path: "NativeMessagingHosts")
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "\(name).json")
            try manifest.write(to: file, options: .atomic)
            written.append(file)
        }
        return written
    }
}
