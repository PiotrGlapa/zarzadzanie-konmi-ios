import SwiftUI
import UIKit

/// Miniatura konia: okrąg 40 pt (lista, kafle) albo 72 pt (karta konia); bez zdjęcia — głowa konia w kolorze działu Konie.
struct HorseAvatar: View {
    var photo: UIImage?
    var diameter: CGFloat = 40

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(SectionAccent.horses.color.opacity(accentTintAlpha))
                    HIcon(name: "horse_head", size: diameter * 0.6).foregroundStyle(SectionAccent.horses.color)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
