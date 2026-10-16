import HorselyKit
import SwiftUI
import UIKit

/// Ekran kadrowania zdjęcia konia (FR-ZDK-02): kwadratowy kadr, przesuwanie, powiększanie (gest i przyciski), obrót o 90°, „Anuluj”
/// i „Zapisz”. Okrąg pokazuje, jak zdjęcie zobaczysz na liście koni. Wynik jest zmniejszany jak inne zdjęcia i nie niesie lokalizacji.
struct PhotoCropView: View {
    let source: PreparedImage
    let onCancel: () -> Void
    let onSave: (PreparedImage) -> Void

    @State private var quarterTurns = 0
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetAtGestureStart: CGSize = .zero
    @State private var saving = false
    @State private var failed = false
    /// Bok kadru z ostatniego układu — potrzebny przy zapisie (poza `GeometryReader`).
    @State private var measuredSide: CGFloat = 300

    private let uiImage: UIImage?

    init(source: PreparedImage, onCancel: @escaping () -> Void, onSave: @escaping (PreparedImage) -> Void) {
        self.source = source
        self.onCancel = onCancel
        self.onSave = onSave
        self.uiImage = UIImage(data: source.jpeg)
    }

    /// Wymiary obrazu po obrocie (w pikselach).
    private var rotatedSize: CGSize {
        quarterTurns % 2 == 0 ? CGSize(width: source.width, height: source.height) : CGSize(width: source.height, height: source.width)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let side = max(min(geometry.size.width - 2 * Spacing.screenEdge, geometry.size.height - 220), 120)
                VStack(spacing: Spacing.beforeSection) {
                    Text("photo_crop_hint")
                        .font(.footnote)
                        .foregroundStyle(HorselyColor.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                    cropArea(side: side)
                    controls(side: side)
                    if failed { Text("photo_crop_failed").foregroundStyle(HorselyColor.error) }
                    Spacer(minLength: 0)
                }
                .padding(Spacing.screenEdge)
                .frame(maxWidth: .infinity)
                .onChange(of: side, initial: true) { _, new in measuredSide = new }
            }
            .background(HorselyColor.background)
            .navigationTitle("photo_crop_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("common_cancel"), action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("common_save")) { save() }.disabled(saving).accessibilityIdentifier("crop-save")
                }
            }
        }
    }

    // MARK: Widok

    /// Ile punktów ekranu przypada na piksel obrazu przy powiększeniu 1 (krótszy bok wypełnia kadr).
    private func baseScale(side: CGFloat) -> CGFloat {
        side / max(min(rotatedSize.width, rotatedSize.height), 1)
    }

    private func cropArea(side: CGFloat) -> some View {
        let scale = baseScale(side: side)
        return ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .frame(width: CGFloat(source.width) * scale, height: CGFloat(source.height) * scale)
                    .rotationEffect(.degrees(Double(quarterTurns) * 90))
                    .scaleEffect(zoom)
                    .offset(offset)
            }
            Circle()
                .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                .shadow(radius: 1)
            Rectangle().strokeBorder(.white.opacity(0.6), lineWidth: 1)
        }
        .frame(width: side, height: side)
        .background(Color.black)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    offset = clamped(CGSize(width: offsetAtGestureStart.width + value.translation.width, height: offsetAtGestureStart.height + value.translation.height), side: side)
                }
                .onEnded { _ in offsetAtGestureStart = offset }
                .simultaneously(with:
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = min(max(zoomAtGestureStart * value.magnification, 1), 6)
                            offset = clamped(offset, side: side)
                        }
                        .onEnded { _ in zoomAtGestureStart = zoom }
                )
        )
        .accessibilityElement()
        .accessibilityLabel(tr("photo_crop_viewport"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setZoom(zoom + 0.25, side: side)
            case .decrement: setZoom(zoom - 0.25, side: side)
            @unknown default: break
            }
        }
    }

    private func controls(side: CGFloat) -> some View {
        HStack(spacing: Spacing.beforeSection) {
            controlButton("minus.magnifyingglass", label: "photo_crop_zoom_out") { setZoom(zoom - 0.5, side: side) }
            controlButton("rotate.right", label: "photo_crop_rotate") { rotate(side: side) }
            controlButton("plus.magnifyingglass", label: "photo_crop_zoom_in") { setZoom(zoom + 0.5, side: side) }
        }
    }

    private func controlButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .frame(width: Spacing.minTouchTarget + 8, height: Spacing.minTouchTarget + 8)
        }
        .buttonStyle(.bordered)
        .tint(HorselyColor.primary)
        .accessibilityLabel(tr(label))
    }

    // MARK: Zachowanie

    private func setZoom(_ value: CGFloat, side: CGFloat) {
        zoom = min(max(value, 1), 6)
        zoomAtGestureStart = zoom
        offset = clamped(offset, side: side)
        offsetAtGestureStart = offset
    }

    private func rotate(side: CGFloat) {
        quarterTurns = (quarterTurns + 1) % 4
        offset = .zero
        offsetAtGestureStart = .zero
    }

    /// Obraz zawsze przykrywa cały kadr: przesunięcie nie przekracza połowy nadwyżki obrazu nad kadrem.
    private func clamped(_ proposed: CGSize, side: CGFloat) -> CGSize {
        let scale = baseScale(side: side) * zoom
        let limitX = max(rotatedSize.width * scale / 2 - side / 2, 0)
        let limitY = max(rotatedSize.height * scale / 2 - side / 2, 0)
        return CGSize(width: min(max(proposed.width, -limitX), limitX), height: min(max(proposed.height, -limitY), limitY))
    }

    /// Kadr w ułamkach obrazu po obrocie: środek obrazu przesunięty o `offset`, bok kadru = bok widoku / skala.
    private func normalizedRect(side: CGFloat) -> CGRect {
        let scale = baseScale(side: side) * zoom
        let size = rotatedSize
        let cropSide = side / scale
        let centerX = size.width / 2 - offset.width / scale
        let centerY = size.height / 2 - offset.height / scale
        let originX = min(max(centerX - cropSide / 2, 0), max(size.width - cropSide, 0))
        let originY = min(max(centerY - cropSide / 2, 0), max(size.height - cropSide, 0))
        return CGRect(x: originX / size.width, y: originY / size.height, width: min(cropSide / size.width, 1), height: min(cropSide / size.height, 1))
    }

    private func save() {
        guard !saving else { return }
        saving = true
        failed = false
        let rect = normalizedRect(side: measuredSide)
        let turns = quarterTurns
        let data = source.jpeg
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try PhotoCropper.crop(data, quarterTurns: turns, normalizedRect: rect)
                }.value
                onSave(result)
            } catch {
                failed = true
                saving = false
            }
        }
    }

}
