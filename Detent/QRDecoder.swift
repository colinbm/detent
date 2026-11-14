import CoreGraphics
import Vision

nonisolated enum QRDecoder {
    /// Text payloads of every QR code found in `image`.
    static func payloads(in image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}
