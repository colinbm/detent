import CoreGraphics
import ScreenCaptureKit

enum ScreenScanner {
    /// Captures every display and returns the text of each QR code visible on any of them.
    /// Throws if Screen Recording permission has not been granted.
    static func qrPayloads() async throws -> [String] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var payloads: [String] = []
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = CGFloat(filter.pointPixelScale)
            let config = SCStreamConfiguration()
            config.width = Int(filter.contentRect.width * scale)
            config.height = Int(filter.contentRect.height * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            payloads += try QRDecoder.payloads(in: image)
        }
        return payloads
    }
}
