import HorselyCore
import HorselyKit
import Observation
import UIKit

/// Konie w pamięci aplikacji: jedna obserwacja magazynu zasila listę, kafle Pulpitu i kartę konia, a miniatury zdjęć są wczytywane
/// raz (FR-ZDK-06: miniatury wszystkich koni są w telefonie, widoczne bez połączenia). Brakującą miniaturę zdjęcia z programu
/// pobiera `ThumbnailFetcher` (równolegle, najwyżej 4 naraz); nieudane pobrania wracają po kolejnej synchronizacji (FR-008).
@MainActor
@Observable
final class HorseDirectory {
    private(set) var horses: [LocalHorse] = []
    /// `true` po pierwszym odczycie magazynu (odróżnia „jeszcze ładuję” od „brak koni”).
    private(set) var isLoaded = false
    /// Miniatury po identyfikatorze załącznika zdjęcia.
    private(set) var thumbnails: [String: UIImage] = [:]

    @ObservationIgnored let repository: HorseRepository
    @ObservationIgnored private var fetcher: ThumbnailFetcher?
    /// Identyfikatory, dla których trwa już pobieranie (kolejne emisje listy ich nie powtarzają).
    @ObservationIgnored private var loadingThumbnails: Set<String> = []

    init(repository: HorseRepository) {
        self.repository = repository
    }

    /// Źródło miniatur (załączniki aplikacji); ustawiane po zbudowaniu `AppEnvironment`.
    func useThumbnailSource(_ attachments: AttachmentStore) {
        fetcher = ThumbnailFetcher(attachments: attachments)
    }

    /// Pętla obserwacji; uruchamiana raz z `RootView.task`.
    func run() async {
        do {
            for try await list in repository.observeHorses() {
                horses = list
                isLoaded = true
                // Pobieranie miniatur z programu nie wstrzymuje obserwacji listy.
                Task { await loadMissingThumbnails() }
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

    /// Po zakończonej synchronizacji, powrocie na pierwszy plan i przejściu na tryb samodzielny: ponawia pobranie miniatur,
    /// które wcześniej się nie udały (FR-008, FR-011).
    func retryMissingThumbnails() async {
        await fetcher?.forgetFailures()
        await loadMissingThumbnails()
    }

    private func loadMissingThumbnails() async {
        let wanted = Set(horses.compactMap(\.photoAttachmentId))
        thumbnails = thumbnails.filter { wanted.contains($0.key) }
        guard let fetcher else { return }
        let missing = wanted.filter { thumbnails[$0] == nil && !loadingThumbnails.contains($0) }.sorted()
        guard !missing.isEmpty else { return }
        loadingThumbnails.formUnion(missing)
        // Każda gotowa miniatura trafia na listę od razu, nie dopiero po całej serii.
        await fetcher.fetch(missing) { [weak self] id, data in
            await self?.received(id, data)
        }
        loadingThumbnails.subtract(missing)
    }

    private func received(_ id: String, _ data: Data) {
        guard let image = UIImage(data: data) else { return }
        thumbnails[id] = image
    }
}
