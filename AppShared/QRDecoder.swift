import CoreGraphics
import Vision
#if targetEnvironment(simulator)
import CoreImage
#endif

nonisolated enum QRDecoder {
    /// Text payloads of every QR code found in `image`.
    static func payloads(in image: CGImage) throws -> [String] {
        #if targetEnvironment(simulator)
        // Vision's barcode detector finds nothing in the iOS Simulator, which has no Neural Engine.
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil)
        return (detector?.features(in: CIImage(cgImage: image)) ?? [])
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #else
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
        #endif
    }
}
