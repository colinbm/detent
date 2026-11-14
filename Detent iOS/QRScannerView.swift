import SwiftUI
import Vision
import VisionKit

/// Full-screen camera that reports the first 2FA setup QR code it sees.
struct QRScannerView: View {
    let found: (String) -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            Scanner(found: found)
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    Text("Point the camera at a 2FA setup QR code")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

private struct Scanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.found = found
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var found: (String) -> Void
        private var done = false

        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let barcode) in items {
                guard let payload = barcode.payloadStringValue,
                      payload.lowercased().hasPrefix("otpauth://") else { continue }
                done = true
                found(payload)
                return
            }
        }
    }
}
