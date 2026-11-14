import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenScanner {
    struct Found {
        let payload: String
        /// The site of the browser page the code was on, if it was on one.
        let host: String?
    }

    /// Captures every display and returns each QR code visible on any of them.
    /// Throws if Screen Recording permission has not been granted.
    static func scan() async throws -> [Found] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var found: [Found] = []
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = CGFloat(filter.pointPixelScale)
            let config = SCStreamConfiguration()
            config.width = Int(filter.contentRect.width * scale)
            config.height = Int(filter.contentRect.height * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            for code in try QRDecoder.codes(in: image) {
                // Pixels in this display's image, to points in global screen coordinates.
                let center = CGPoint(x: display.frame.minX + code.bounds.midX / scale,
                                     y: display.frame.minY + code.bounds.midY / scale)
                let host = code.payload.lowercased().hasPrefix("otpauth://") ? BrowserPage.host(at: center) : nil
                found.append(Found(payload: code.payload, host: host))
            }
        }
        return found
    }
}

/// Finds which browser page is showing at a point on screen, by asking the browser over
/// Apple Events. The first time, macOS asks whether Detent may control that browser.
enum BrowserPage {
    private enum Dialect { case safari, chromium }

    /// Browsers that can report their tabs' addresses. Firefox cannot.
    private static let browsers: [String: Dialect] = [
        "com.apple.Safari": .safari,
        "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chromium,
        "com.google.Chrome.beta": .chromium,
        "com.google.Chrome.dev": .chromium,
        "com.google.Chrome.canary": .chromium,
        "org.chromium.Chromium": .chromium,
        "com.brave.Browser": .chromium,
        "com.microsoft.edgemac": .chromium,
        "com.vivaldi.Vivaldi": .chromium,
        "company.thebrowser.Browser": .chromium,
    ]

    /// The site shown in the browser window at `point` (global points, from the top left), if
    /// the frontmost window there is a browser's.
    static func host(at point: CGPoint) -> String? {
        guard let window = topWindow(at: point),
              let app = NSRunningApplication(processIdentifier: window.pid),
              let bundleID = app.bundleIdentifier,
              let dialect = browsers[bundleID]
        else { return nil }

        let tab = dialect == .safari ? "current tab" : "active tab"
        let source = """
            tell application id "\(bundleID)"
                set found to {}
                repeat with w in windows
                    try
                        set end of found to {bounds of w, URL of \(tab) of w}
                    end try
                end repeat
                return found
            end tell
            """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else { return nil }

        // Each item is {{left, top, right, bottom}, url}. Prefer the window at the point; the
        // browser lists its front window first, which is the likeliest otherwise.
        var pages: [(bounds: CGRect, url: String)] = []
        for index in stride(from: 1, through: result.numberOfItems, by: 1) {
            guard let item = result.atIndex(index), item.numberOfItems == 2,
                  let box = item.atIndex(1), box.numberOfItems == 4,
                  let url = item.atIndex(2)?.stringValue
            else { continue }
            let edges = (1...4).map { CGFloat(box.atIndex($0)?.int32Value ?? 0) }
            pages.append((CGRect(x: edges[0], y: edges[1], width: edges[2] - edges[0], height: edges[3] - edges[1]), url))
        }
        let page = pages.first { $0.bounds.insetBy(dx: -2, dy: -2).contains(window.bounds) && window.bounds.insetBy(dx: -2, dy: -2).contains($0.bounds) }
            ?? pages.first
        return page.flatMap { Domain.host(from: $0.url) }
    }

    /// The frontmost ordinary window containing `point`.
    private static func topWindow(at point: CGPoint) -> (pid: pid_t, bounds: CGRect)? {
        // Listed front to back. Reading bounds and owners needs no permission.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in windows {
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.contains(point)
            else { continue }
            return (pid, bounds)
        }
        return nil
    }
}
