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

    init(arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        fixture = value(after: "-UITestFixture")
        today = value(after: "-UITestToday").flatMap { LocalDate($0) }
        mode = value(after: "-UITestMode").flatMap { WorkMode(rawValue: $0) }
    }

    var isTestRun: Bool { fixture != nil || today != nil || mode != nil }
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
    let router = DeepLinkRouter()

    /// Tryb pracy (FR-TRB-01); zapisywany w ustawieniach przy każdej zmianie.
    var workMode: WorkMode {
        didSet { settings.workMode = workMode }
    }

    var theme: ThemeSetting {
        didSet { settings.theme = theme }
    }

    /// Liczba operacji w kolejce wysyłki (plakietka na karcie „Więcej”) i konfliktów do rozstrzygnięcia — uzupełniane od fazy 5.
    var queueCount = 0
    var conflictCount = 0

    init(settings: SettingsStore, dates: any DateProvider, log: DiagnosticLog, store: RecordStore, launchOptions: LaunchOptions = LaunchOptions(arguments: [])) {
        self.settings = settings
        self.dates = dates
        self.log = log
        self.store = store
        self.launchOptions = launchOptions
        self.workMode = settings.workMode
        self.theme = settings.theme
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
            // Przebieg testowy: ustawienia z osobnego, czyszczonego zestawu, żeby testy nie dziedziczyły stanu.
            let suite = "horsely.uitest"
            let defaults = UserDefaults(suiteName: suite)
            defaults?.removePersistentDomain(forName: suite)
            settings = SettingsStore(defaults: defaults)
            if let mode = options.mode { settings.workMode = mode }
        } else {
            settings = SettingsStore()
        }

        let database = openDatabase(options: options, directory: directory, log: log)

        let dates: any DateProvider = options.today.map { FixedDateProvider(today: $0) } ?? SystemDateProvider()
        return AppEnvironment(settings: settings, dates: dates, log: log, store: RecordStore(database: database), launchOptions: options)
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
        let environment = AppEnvironment(settings: settings, dates: FixedDateProvider(today: today), log: log, store: RecordStore(database: database))
        environment.queueCount = queueCount
        environment.conflictCount = conflictCount
        return environment
    }
}
