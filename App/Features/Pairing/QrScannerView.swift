import AVFoundation
import SwiftUI
import VisionKit

/// Skan kodu QR z programu (VisionKit `DataScannerViewController`). Bez aparatu albo bez zgody — wyjaśnienie i wpis ręczny.
struct QrScannerView: View {
    let onCode: (String) -> Void
    let onManual: () -> Void

    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        VStack(spacing: Spacing.beforeSection) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable && authorization == .authorized {
                ScannerRepresentable(onCode: onCode)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cardRadius))
                    .accessibilityLabel(tr("pairing_scanner_title"))
                Text("pairing_scanner_hint").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant).multilineTextAlignment(.center)
            } else if authorization == .notDetermined {
                Spacer()
                Text("pairing_camera_permission_title").font(.title3.weight(.semibold))
                Text("pairing_camera_permission_body").font(.body).foregroundStyle(HorselyColor.onSurfaceVariant).multilineTextAlignment(.center)
                Button {
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        authorization = AVCaptureDevice.authorizationStatus(for: .video)
                    }
                } label: {
                    Text("pairing_camera_permission_grant").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.primaryFilled)
                .tint(HorselyColor.primary)
                Spacer()
            } else {
                Spacer()
                Text("pairing_camera_permission_denied").font(.body).foregroundStyle(HorselyColor.onSurfaceVariant).multilineTextAlignment(.center)
                Spacer()
            }
            Button(action: onManual) {
                Text("pairing_enter_manually").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
            }
            .buttonStyle(.bordered)
            .tint(HorselyColor.primary)
        }
        .padding(Spacing.screenEdge)
        .navigationTitle(tr("pairing_scanner_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case let .barcode(code) = item, let text = code.payloadStringValue {
                    delivered = true
                    dataScanner.stopScanning()
                    onCode(text)
                    return
                }
            }
        }
    }
}
