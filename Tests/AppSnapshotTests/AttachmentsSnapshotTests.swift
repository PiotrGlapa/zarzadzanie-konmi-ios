import HorselyCore
import HorselyKit
import SwiftUI
import UIKit
import XCTest
@testable import Horsely

/// Zakładka „Załączniki” konia (T115) w trybie samodzielnym: zdjęcie z miniaturą i dokument PDF z ikoną; jasny / ciemny / 200 %.
@MainActor
final class AttachmentsSnapshotTests: XCTestCase {
    private func environment(_ variant: SnapshotVariant) async throws -> (AppEnvironment, String) {
        let env = makeEnvironment(mode: .standalone, variant: variant)
        let horses = try await SnapshotHorses.seed(env)
        let grom = try XCTUnwrap(horses.first { $0.name == "Grom" }?.id)
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor(red: 0.18, green: 0.49, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            UIColor.white.setFill()
            context.fill(CGRect(x: 100, y: 60, width: 100, height: 80))
        }
        let store = env.attachments
        let owner = AttachmentOwner(type: .horse, id: grom, horseId: grom)
        try await store.add(owner, [PendingAttachment(file: try store.prepare(data: photo, fileName: "zdjecie.jpg", mimeType: "image/jpeg"))])
        try await store.add(owner, [PendingAttachment(file: try store.prepare(data: Data("%PDF-1.4".utf8), fileName: "faktura-weterynarz.pdf", mimeType: "application/pdf"))])
        return (env, grom)
    }

    func testHorseAttachmentsTab() async throws {
        for variant in SnapshotVariant.allCases {
            let (env, grom) = try await environment(variant)
            let view = ScrollView {
                AttachmentsSection(owner: AttachmentOwner(type: .horse, id: grom, horseId: grom), horseWide: true).padding(Spacing.screenEdge)
            }
            .background(HorselyColor.background)
            await assertSettledScreen(view.environment(env), name: "horse-attachments", variant: variant)
        }
    }
}
