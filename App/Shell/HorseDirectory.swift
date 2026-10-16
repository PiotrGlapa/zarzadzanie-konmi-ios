import HorselyCore
import HorselyKit
import Observation
import UIKit

/// Konie w pamięci aplikacji: jedna obserwacja magazynu zasila listę, kafle Pulpitu i kartę konia, a miniatury zdjęć są wczytywane
/// raz (FR-ZDK-06: miniatury wszystkich koni są w telefonie, widoczne bez połączenia).
@MainActor
@Observable
final class HorseDirectory {
    private(set) var horses: [LocalHorse] = []
    /// `true` po pierwszym odczycie magazynu (odróżnia „jeszcze ładuję” od „brak koni”).
    private(set) var isLoaded = false
    /// Miniatury po identyfikatorze załącznika zdjęcia.
    private(set) var thumbnails: [String: UIImage] = [:]

    @ObservationIgnored let repository: HorseRepository
    @ObservationIgnored private var loadingThumbnails: Set<String> = []

    init(repository: HorseRepository) {
        self.repository = repository
    }

    /// Pętla obserwacji; uruchamiana raz z `RootView.task`.
    func run() async {
        do {
            for try await list in repository.observeHorses() {
                horses = list
                isLoaded = true
                await loadMissingThumbnails()
            }
        } catch {
            isLoaded = true
        }
    }

    /// Jednorazowy odczyt (testy, odświeżenie po zmianie bez czekania na obserwację).
    func refresh() async {
        horses = (try? await repository.horses()) ?? horses
        isLoaded = true
        await loadMissingThumbnails()
    }

    func horse(id: String) -> LocalHorse? {
        horses.first { $0.id == id }
    }

    func thumbnail(for horse: LocalHorse) -> UIImage? {
        horse.photoAttachmentId.flatMap { thumbnails[$0] }
    }

    private func loadMissingThumbnails() async {
        let wanted = Set(horses.compactMap(\.photoAttachmentId))
        thumbnails = thumbnails.filter { wanted.contains($0.key) }
        for id in wanted where thumbnails[id] == nil && !loadingThumbnails.contains(id) {
            loadingThumbnails.insert(id)
            if let data = await repository.thumbnailData(attachmentId: id), let image = UIImage(data: data) {
                thumbnails[id] = image
            }
            loadingThumbnails.remove(id)
        }
    }
}
