import HorselyCore
import HorselyKit
import SwiftUI
import UIKit
import XCTest
@testable import Horsely

/// Sekcja „Załączniki” w szczegółach treningu (ZAT-01, ZAT-06): w trybie samodzielnym jest zawsze (ze zdjęciem i „Dodaj załącznik”),
/// w trybie z programem — tylko gdy program ogłasza `trainingAttachments`; na starszym programie jest ukryta. Jasny / ciemny / tekst 200 %.
@MainActor
final class TrainingAttachmentsSnapshotTests: XCTestCase {
    private struct SeedError: Error {}

    /// Koń „Grom” i jeden trening na ujeżdżeniu (tryb samodzielny — rekord od razu w bazie).
    private func seeded(_ variant: SnapshotVariant) async throws -> (env: AppEnvironment, horseId: String, trainingId: String) {
        let env = makeEnvironment(mode: .standalone, variant: variant)
        let horses = try await SnapshotHorses.seed(env)
        let grom = try XCTUnwrap(horses.first { $0.name == "Grom" }?.id)
        try await env.entries.seedDictionariesIfNeeded()
        let dictionary = try await env.entries.allDictionaryItems()
        guard let type = dictionary.first(where: { $0.dictionaryType == .trainingType && $0.value == "Ujeżdżenie" }) else { throw SeedError() }
        var training = TrainingInput()
        training.horseId = grom
        training.trainingDate = LocalDate(year: 2026, month: 10, day: 1)
        training.trainingTypeId = type.id
        training.durationMinutes = 60
        let input = training
        let created = try await env.entries.perform { $0.createTraining(input) }
        guard let id = created.saved?.record?.id else { throw SeedError() }
        return (env, grom, id)
    }

    private func addPhoto(_ env: AppEnvironment, horseId: String, trainingId: String) async throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor(red: 0.18, green: 0.49, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            UIColor.white.setFill()
            context.fill(CGRect(x: 100, y: 60, width: 100, height: 80))
        }
        let store = env.attachments
        let owner = AttachmentOwner(type: .training, id: trainingId, horseId: horseId)
        try await store.add(owner, [PendingAttachment(file: try await store.prepare(data: photo, fileName: "zdjecie.jpg", mimeType: "image/jpeg"))])
    }

    private func detail(_ env: AppEnvironment, _ trainingId: String) -> some View {
        NavigationStack { EntryDetailView(route: EntryRoute(recordType: .training, id: trainingId)) }.environment(env)
    }

    func testTrainingDetailShowsAttachmentsSection() async throws {
        for variant in SnapshotVariant.allCases {
            let (env, horseId, trainingId) = try await seeded(variant)
            try await addPhoto(env, horseId: horseId, trainingId: trainingId)
            let loaded = try await env.entries.record(.training, id: trainingId)
            let training = try XCTUnwrap(loaded)
            XCTAssertEqual(
                EntryDetailView.attachmentOwner(training, mode: env.workMode, capabilities: env.capabilities),
                AttachmentOwner(type: .training, id: trainingId, horseId: horseId), "tryb samodzielny: trening ma sekcję załączników"
            )
            if variant == .xxxl {
                // Przy tekście 200 % szczegóły treningu wypełniają cały ekran (przewijany), więc sekcję pokazuje sama.
                let section = ScrollView {
                    AttachmentsSection(owner: AttachmentOwner(type: .training, id: trainingId, horseId: horseId)).padding(Spacing.screenEdge)
                }
                .background(HorselyColor.background)
                await assertSettledScreen(section.environment(env), name: "training-detail-attachments", variant: variant)
            } else {
                await assertSettledScreen(detail(env, trainingId), name: "training-detail-attachments", variant: variant)
            }
        }
    }

    func testSectionHiddenOnlineWithoutTrainingAttachments() async throws {
        // Bez wariantu 200 %: tam szczegóły przewijają się poza ekran, więc brak sekcji nie byłby widoczny na migawce.
        for variant in [SnapshotVariant.light, .dark] {
            let (env, _, trainingId) = try await seeded(variant)
            env.workMode = .online
            let loaded = try await env.entries.record(.training, id: trainingId)
            let training = try XCTUnwrap(loaded)

            XCTAssertNil(
                EntryDetailView.attachmentOwner(training, mode: .online, capabilities: .none), "program bez trainingAttachments: sekcja ukryta (ZAT-06)"
            )
            XCTAssertNotNil(
                EntryDetailView.attachmentOwner(training, mode: .online, capabilities: ProgramCapabilities(names: [ProgramCapabilities.trainingAttachmentsName])),
                "program 3.0.0 pokazuje sekcję"
            )
            await assertSettledScreen(detail(env, trainingId), name: "training-detail-no-attachments", variant: variant)
        }
    }

    func testOtherEntryKindsKeepTheirAttachmentsWhateverTheProgramOffersForTrainings() async throws {
        let (env, horseId, _) = try await seeded(.light)
        var note = NoteInput()
        note.horseId = horseId
        note.noteDate = LocalDate(year: 2026, month: 10, day: 3)
        note.title = "Kuleje"
        let input = note
        let created = try await env.entries.perform { $0.createNote(input) }
        let noteId = try XCTUnwrap(created.saved?.record?.id)
        let loaded = try await env.entries.record(.note, id: noteId)
        let record = try XCTUnwrap(loaded)

        XCTAssertEqual(
            EntryDetailView.attachmentOwner(record, mode: .online, capabilities: .none), AttachmentOwner(type: .note, id: noteId, horseId: horseId)
        )
    }
}
