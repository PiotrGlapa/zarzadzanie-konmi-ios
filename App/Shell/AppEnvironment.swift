import Foundation
import HorselyCore
import HorselyKit
import Observation
import SwiftUI

/// Argumenty uruchomienia dla testów (contracts/test-fixtures.md): `-UITestFixture <nazwa>`, `-UITestToday <yyyy-MM-dd>`,
/// `-UITestMode <unset|online|standalone>`. Obsługiwane tylko w konfiguracji Debug; w Release ignorowane.
struct LaunchOptions: Equatable, Sendable {
    var fixture: String?
    var today: LocalDate?
    var mode: WorkMode?
    /// `-UITestProgram <paired|offline|conflict>`: zaślepka programu w procesie (testy UI parowania i połączenia).
    var program: String?
    /// `-UITestReset`: wyczyść zapamiętane ustawienia przed startem (świeża instalacja).
    var reset = false

    init(arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        fixture = value(after: "-UITestFixture")
        today = value(after: "-UITestToday").flatMap { LocalDate($0) }
        mode = value(after: "-UITestMode").flatMap { WorkMode(rawValue: $0) }
        program = value(after: "-UITestProgram")
        reset = arguments.contains("-UITestReset")
    }

    var isTestRun: Bool { fixture != nil || today != nil || mode != nil || program != nil || reset }
}

/// Kontener zależności aplikacji: magazyn, ustawienia, zegar, dziennik, router, tryb pracy i motyw.
@MainActor
@Observable
final class AppEnvironment {
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let dates: any DateProvider
    @ObservationIgnored let log: DiagnosticLog
    @ObservationIgnored let store: RecordStore
    @ObservationIgnored let launchOptions: LaunchOptions
    @ObservationIgnored let files: LocalFileStore
    @ObservationIgnored let horses: HorseRepository
    @ObservationIgnored let entries: EntryRepository
    @ObservationIgnored let reminders: ReminderRepository
    @ObservationIgnored let trainings: TrainingRepository
    let router = DeepLinkRouter()
    /// Licznik zmian magazynu — widoki z danymi złożonymi z wielu rekordów (Pulpit, terminy, oś czasu) odświeżają się, gdy rośnie.
    private(set) var dataRevision: Int64 = 0
    /// Konie w pamięci aplikacji (lista, kafle, karta) razem z miniaturami zdjęć; uruchamia go `RootView`.
    let horseDirectory: HorseDirectory

    /// Tryb pracy (FR-TRB-01); zapisywany w ustawieniach przy każdej zmianie.
    var workMode: WorkMode {
        didSet {
            settings.workMode = workMode
            if workMode == .standalone, oldValue != .standalone { Task { await prepareStore() } }
        }
    }

    var theme: ThemeSetting {
        didSet { settings.theme = theme }
    }

    /// Liczba niewysłanych operacji kolejki (plakietka na karcie „Więcej”) i konfliktów do rozstrzygnięcia.
    var queueCount = 0
    var conflictCount = 0
    /// Kolejka i konflikty (oznaczenia „czeka na wysłanie” / „wymaga poprawy” / „konflikt” na listach).
    private(set) var queue = QueueSnapshot()

    // MARK: Tryb online (faza 5)

    @ObservationIgnored let secrets: SecretStore
    @ObservationIgnored let network: NetworkMonitor
    @ObservationIgnored let client: ApiClient
    @ObservationIgnored let sync: SyncService
    @ObservationIgnored let outbox: OutboxProcessor
    @ObservationIgnored let resolver: ConflictResolver
    @ObservationIgnored let pairing: PairingService
    @ObservationIgnored let connectionLog: ConnectionLog
    /// Jeden stan połączenia dla całej aplikacji (pasek, ikonka, podtytuł „Dane z …”).
    let connection: ConnectionStatus
    /// Rozwinięcie i zwinięcie komunikatu o połączeniu — wspólne dla wszystkich ekranów.
    let indicator = ConnectionIndicator()
    /// Możliwości programu (np. status „Kontuzjowany” w trybie online).
    private(set) var capabilities: ProgramCapabilities = .none
    private(set) var programVersion: String?
    /// Pierwsze pobranie danych po parowaniu — baner na Pulpicie.
    private(set) var initialSync: SyncProgress?
    private(set) var initialSyncRunning = false
    @ObservationIgnored private var onlineStarted = false
    /// Filtry działów Treningi, Zakupy i Zawody — zapamiętane do zamknięcia aplikacji (US11/5).
    let sectionFilters: SectionFilters

    init(
        settings: SettingsStore, dates: any DateProvider, log: DiagnosticLog, store: RecordStore, files: LocalFileStore,
        launchOptions: LaunchOptions = LaunchOptions(arguments: []), secrets: SecretStore? = nil, transport: ProgramTransport? = nil,
        probe: ConnectProbe? = nil
    ) {
        self.settings = settings
        self.dates = dates
        self.log = log
        self.store = store
        self.launchOptions = launchOptions
        self.files = files
        let currentMode: @Sendable () -> WorkMode = { settings.workMode }
        self.horses = HorseRepository(store: store, files: files, dates: dates, mode: currentMode)
        self.horseDirectory = HorseDirectory(repository: horses)
        self.entries = EntryRepository(store: store, dates: dates, mode: currentMode)
        self.reminders = ReminderRepository(entries: entries)
        self.trainings = TrainingRepository(entries: entries)
        self.workMode = settings.workMode
        self.theme = settings.theme
        self.sectionFilters = SectionFilters(today: dates.today())

        // Bez jawnej grupy: domyślna grupa to pierwsza z `keychain-access-groups` (wspólna z rozszerzeniem).
        let secretStore = secrets ?? KeychainStore()
        let monitor = NetworkMonitor()
        let status = ConnectionStatus()
        let connectionLog = ConnectionLog(log: log, enabled: { ConnectionLog.isEnabled(until: settings.connectionLogUntil) })
        let capabilitiesOf: @Sendable () async -> ProgramCapabilities = { ProgramCapabilities(serialized: try? await store.meta(SyncMetaKey.capabilities)) }
        let client = ApiClient(
            addresses: StoreAddressBook(store: store), secrets: secretStore, transport: transport ?? URLSessionTransport(), probe: probe ?? TCPConnectProbe(),
            network: { monitor.conditions }, wifiOnly: { settings.wifiOnly }, capabilities: capabilitiesOf,
            events: { [weak status] event in Task { @MainActor in status?.handle(event) } }, connectionLog: connectionLog
        )
        self.secrets = secretStore
        self.network = monitor
        self.connection = status
        self.connectionLog = connectionLog
        self.client = client
        self.sync = SyncService(client: client, store: store, log: { log.log("sync", $0) }, onRemoved: { refs in
            for ref in refs where ref.type == .attachment { files.delete(attachmentId: ref.id) }
        })
        self.outbox = OutboxProcessor(store: store, client: client, capabilities: capabilitiesOf, log: { log.log("queue", $0) })
        self.resolver = ConflictResolver(store: store, client: client, capabilities: capabilitiesOf)
        self.pairing = PairingService(store: store, client: client, secrets: secretStore, files: files)
    }

    /// Przygotowuje magazyn do pracy: w trybie samodzielnym wstawia domyślne słowniki (gdy ich jeszcze nie ma).
    func prepareStore() async {
        guard workMode == .standalone else { return }
        do {
            try await entries.seedDictionariesIfNeeded()
        } catch {
            log.log("storage", "Nie można dodać domyślnych słowników: \(error.localizedDescription)")
        }
    }

    // MARK: Tryb online

    /// Start pracy z programem: przerwane wysyłki → wynik nieznany, stan połączenia, wysyłka kolejki i odświeżenie danych.
    func startOnline() async {
        guard workMode == .online, !onlineStarted else { return }
        onlineStarted = true
        network.start()
        network.onChange { [weak self] conditions in
            Task { @MainActor in
                self?.connection.networkChanged(available: conditions.isAvailable)
                if conditions.isAvailable { await self?.sendQueue() }
            }
        }
        #if DEBUG
        if let scenario = launchOptions.program.flatMap(DemoProgramTransport.Scenario.init(rawValue:)), launchOptions.mode == .online {
            await DemoProgramTransport.seed(scenario, environment: self)
        }
        #endif
        let sync = self.sync
        connection.setChecker { await sync.checkConnection() }
        await loadPairingInfo()
        await outbox.recover()
        connection.enterForeground()
        await refresh(force: false)
    }

    func loadPairingInfo() async {
        guard let info = try? await store.read({ try $0.pairingInfo() }) else { return }
        capabilities = info.capabilities
        programVersion = info.programVersion
        connection.dataFrom = info.lastSyncAt
    }

    /// Wysyłka kolejki (po zapisie, odzyskaniu sieci, „Wyślij teraz”).
    @discardableResult
    func sendQueue() async -> ProcessSummary {
        guard workMode == .online else { return ProcessSummary() }
        return await outbox.processAll()
    }

    /// Odświeżenie: najpierw kolejka, potem dane programu. `force == false` — tylko gdy od ostatniego minęło ≥ 15 min.
    func refresh(force: Bool) async {
        guard workMode == .online else { return }
        let info = try? await store.read { try $0.pairingInfo() }
        if !force && !BackgroundWork.isRefreshDue(lastSyncAt: info?.lastSyncAt, now: Date()) { return }
        await sendQueue()
        let first = info?.lastSyncAt == nil
        if first {
            initialSyncRunning = true
            initialSync = SyncProgress(records: 0, bytes: 0, totalBytes: nil)
        }
        let outcome = await sync.refresh { progress in
            Task { @MainActor [weak self] in if self?.initialSyncRunning == true { self?.initialSync = progress } }
        }
        initialSyncRunning = false
        initialSync = nil
        if case let .done(_, _, _, at, _) = outcome { connection.dataFrom = at }
        await loadPairingInfo()
    }

    /// Po zapisie z formularza: w trybie online wysyła operacje i czeka ≤ 1 s. Zwraca tekst komunikatu
    /// („Zapisano” / „Zapisano — wyślę po połączeniu z komputerem” / konflikt).
    func messageAfterSave(_ saved: EntrySaved, edited: Bool) async -> String {
        let savedText = tr(edited ? "entry_updated" : "common_saved")
        guard workMode == .online, let last = saved.operationIds.last else { return savedText }
        let result = await outbox.sendNow(last)
        Task { await sendQueue() }
        switch result {
        case .sent, .alreadyHandled: return savedText
        case .conflict: return tr("common_saved_conflict")
        case .rejected, .queued: return tr("common_saved_queued")
        }
    }

    /// Zapis parowania (pierwsze, ponowne albo zmiana trybu samodzielny → online).
    func completePairing(_ request: PairingRequest, result: PairingResult) async throws -> StableIdentity {
        let replacing = workMode == .standalone
        let identity = try await pairing.commit(request, result: result, replacingStandaloneData: replacing)
        settings.modeChangePending = nil
        connection.reset()
        onlineStarted = false
        workMode = .online
        await startOnline()
        return identity
    }

    /// „Rozłącz”: klucz, pamięć, kolejka i adresy usunięte; aplikacja wraca do wyboru trybu.
    func disconnect() async throws {
        try await pairing.disconnect()
        connection.reset()
        connection.enterBackground()
        onlineStarted = false
        capabilities = .none
        programVersion = nil
        workMode = .unset
    }

    /// Kolejka i konflikty jako strumień (licznik „Więcej”, oznaczenia na listach).
    func observeQueue() async {
        do {
            for try await snapshot in store.queueUpdates() {
                queue = snapshot
                queueCount = snapshot.unsentCount
                conflictCount = snapshot.openConflicts.count
            }
        } catch {
            log.log("queue", "Obserwacja kolejki zatrzymana: \(error.localizedDescription)")
        }
    }

    /// Oznaczenie rekordu na listach (tryb online).
    func marker(_ type: RecordType, id: String) -> RecordMarker? {
        workMode == .online ? queue.marker(type, id: id) : nil
    }

    /// Pętla odświeżania widoków po zmianach w magazynie; uruchamia ją `RootView`.
    func observeChanges() async {
        do {
            for try await counter in entries.observeChanges() { dataRevision = counter }
        } catch {
            log.log("storage", "Obserwacja zmian zatrzymana: \(error.localizedDescription)")
        }
    }

    /// Środowisko produkcyjne: baza w kontenerze App Group (a bez niego — w Application Support), dziennik obok.
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        #if DEBUG
        let options = LaunchOptions(arguments: arguments)
        #else
        let options = LaunchOptions(arguments: [])
        #endif

        let directory = AppDatabase.appGroupDirectory(identifier: AppIdentity.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let log = DiagnosticLog(directory: directory.appendingPathComponent("Logs", isDirectory: true))

        let settings: SettingsStore
        if options.isTestRun {
            // Przebieg testowy: ustawienia z osobnego zestawu (czyszczonego przy `-UITestReset`), żeby testy nie dziedziczyły stanu.
            let suite = "horsely.uitest"
            let defaults = UserDefaults(suiteName: suite)
            if options.reset { defaults?.removePersistentDomain(forName: suite) }
            settings = SettingsStore(defaults: defaults)
            if let mode = options.mode { settings.workMode = mode }
        } else {
            settings = SettingsStore()
        }

        let database = openDatabase(options: options, directory: directory, log: log)

        let dates: any DateProvider = options.today.map { FixedDateProvider(today: $0) } ?? SystemDateProvider()
        let files = makeFileStore(directory: directory, log: log)
        #if DEBUG
        if let scenario = options.program.flatMap(DemoProgramTransport.Scenario.init(rawValue:)) {
            return AppEnvironment(
                settings: settings, dates: dates, log: log, store: RecordStore(database: database), files: files, launchOptions: options,
                secrets: InMemorySecretStore(), transport: DemoProgramTransport(scenario: scenario), probe: AlwaysReachable()
            )
        }
        #endif
        return AppEnvironment(settings: settings, dates: dates, log: log, store: RecordStore(database: database), files: files, launchOptions: options)
    }
}

/// Pliki załączników w kontenerze App Group; gdy katalog jest niedostępny — w katalogu tymczasowym (dane nie przetrwają).
private func makeFileStore(directory: URL, log: DiagnosticLog) -> LocalFileStore {
    do {
        return try LocalFileStore(root: directory.appendingPathComponent("Files", isDirectory: true))
    } catch {
        log.log("storage", "Nie można otworzyć katalogu plików: \(error.localizedDescription)")
    }
    do {
        return try LocalFileStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("horsely-files-\(UUID().uuidString)"))
    } catch {
        fatalError("Katalog tymczasowy musi być dostępny: \(error)")
    }
}

private func openDatabase(options: LaunchOptions, directory: URL, log: DiagnosticLog) -> AppDatabase {
    do {
        return options.isTestRun ? try AppDatabase.inMemory() : try AppDatabase.open(in: directory)
    } catch {
        log.log("storage", "Nie można otworzyć bazy: \(error.localizedDescription)")
    }
    // Aplikacja nie powinna się zawieszać na starcie; bez trwałej bazy dane nie przetrwają zamknięcia.
    do {
        return try AppDatabase.inMemory()
    } catch {
        fatalError("Baza w pamięci musi się otworzyć: \(error)")
    }
}

extension ThemeSetting {
    /// `nil` = zgodnie z systemem.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension AppEnvironment {
    /// Środowisko do testów i migawek: baza w pamięci, dziennik w katalogu tymczasowym, stały dzień (domyślnie 2026-10-05).
    static func testing(
        settings: SettingsStore,
        today: LocalDate = LocalDate(year: 2026, month: 10, day: 5)!,
        queueCount: Int = 0,
        conflictCount: Int = 0
    ) -> AppEnvironment {
        let log = DiagnosticLog(directory: FileManager.default.temporaryDirectory.appendingPathComponent("horsely-test-log-\(UUID().uuidString)"))
        let database = try! AppDatabase.inMemory()
        let files = try! LocalFileStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("horsely-test-files-\(UUID().uuidString)"))
        let environment = AppEnvironment(settings: settings, dates: FixedDateProvider(today: today), log: log, store: RecordStore(database: database), files: files)
        environment.queueCount = queueCount
        environment.conflictCount = conflictCount
        return environment
    }
}
