import CoreGraphics
import Vision
#if targetEnvironment(simulator)
import CoreImage
#endif

nonisolated enum QRDecoder {
    struct Code {
        let payload: String
        /// Where the code is in the image, in pixels from the top left.
        let bounds: CGRect
    }

    /// Text payloads of every QR code found in `image`.
    static func payloads(in image: CGImage) throws -> [String] {
        try codes(in: image).map(\.payload)
    }

    /// Every QR code found in `image`, with where it is.
    static func codes(in image: CGImage) throws -> [Code] {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        #if targetEnvironment(simulator)
        // Vision's barcode detector finds nothing in the iOS Simulator, which has no Neural Engine.
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil)
        return (detector?.features(in: CIImage(cgImage: image)) ?? []).compactMap { feature in
            guard let qr = feature as? CIQRCodeFeature, let payload = qr.messageString else { return nil }
            // Core Image measures from the bottom left.
            let box = qr.bounds
            return Code(payload: payload, bounds: CGRect(x: box.minX, y: height - box.maxY, width: box.width, height: box.height))
        }
        #else
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue else { return nil }
            // Vision's box is a fraction of the image, measured from the bottom left.
            let box = observation.boundingBox
            return Code(payload: payload, bounds: CGRect(
                x: box.minX * width, y: (1 - box.maxY) * height,
                width: box.width * width, height: box.height * height))
        }
        #endif
    }
}
