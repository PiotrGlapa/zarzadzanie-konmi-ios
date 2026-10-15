import Foundation
import HorselyCore
import Observation

/// Karty dolnego paska.
enum AppTab: Hashable, Sendable, CaseIterable {
    case dashboard, horses, reminders, trainings, more
}

/// Cel wejścia z powiadomienia, szybkiej akcji ikony albo adresu `horsely://` (contracts/app-entry-points-ios.md).
enum AppDestination: Equatable, Sendable {
    case dashboard
    case reminders
    case reminder(id: String)
    case newEntry(kind: String)
    case queue

    /// Karta, na której ląduje cel.
    var tab: AppTab {
        switch self {
        case .dashboard, .newEntry: .dashboard
        case .reminders, .reminder: .reminders
        case .queue: .more
        }
    }
}

/// Nawigacja z zewnątrz. Adres z innej aplikacji lub Safari otwiera najwyżej Pulpit i niczego nie zmienia: rozpoznawany jest tylko
/// schemat `horsely://` i znane hosty; nieznany adres → Pulpit. Tryb nieustawiony odkłada cel do czasu wyboru trybu (ekran powitalny).
@MainActor
@Observable
final class DeepLinkRouter {
    var selectedTab: AppTab = .dashboard
    /// Cel do otwarcia przez ekran karty (ekrany reagują na zmianę i zerują wartość po obsłużeniu).
    var pendingDestination: AppDestination?
    /// Cel odłożony do czasu wyboru trybu pracy.
    private(set) var deferredDestination: AppDestination?

    func handle(url: URL, mode: WorkMode) {
        route(Self.destination(for: url), mode: mode)
    }

    func route(_ destination: AppDestination, mode: WorkMode) {
        guard mode != .unset else {
            deferredDestination = destination
            selectedTab = .dashboard
            return
        }
        selectedTab = destination.tab
        pendingDestination = destination
    }

    /// Po wyborze trybu pracy: otwiera cel odłożony wcześniej.
    func resumeDeferred(mode: WorkMode) {
        guard let destination = deferredDestination, mode != .unset else { return }
        deferredDestination = nil
        route(destination, mode: mode)
    }

    /// Czysta funkcja rozpoznająca adres (testowana bez interfejsu).
    nonisolated static func destination(for url: URL) -> AppDestination {
        guard url.scheme?.lowercased() == AppIdentity.urlScheme, let host = url.host?.lowercased() else { return .dashboard }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "dashboard":
            return .dashboard
        case "reminders":
            if let id = parts.first, !id.isEmpty { return .reminder(id: id) }
            return .reminders
        case "queue":
            return .queue
        case "entry":
            guard parts.first == "new" else { return .dashboard }
            let kind = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "kind" }?.value
            switch kind {
            case "note", "farrier": return .newEntry(kind: kind!)
            default: return .dashboard
            }
        default:
            return .dashboard
        }
    }

    /// Szybkie akcje ikony (`UIApplicationShortcutItems`, FR-023) → adresy wewnętrzne.
    nonisolated static func destination(forShortcut type: String) -> AppDestination? {
        switch type {
        case "pl.glapa.horsely.shortcut.note": .newEntry(kind: "note")
        case "pl.glapa.horsely.shortcut.farrier": .newEntry(kind: "farrier")
        case "pl.glapa.horsely.shortcut.reminders": .reminders
        default: nil
        }
    }
}
