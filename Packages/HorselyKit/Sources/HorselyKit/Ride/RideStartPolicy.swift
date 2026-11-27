import Foundation
import HorselyCore

// Start nagrywania, pasek NAG-01 i odzyskiwanie (Task 17 = Android 3.0.2 `RideStartFlow.kt` — `RideStartViewModel`, `RideBanner.kt`,
// `RideRecoveryDialog.kt`): czysta logika bez interfejsu, testowana w `RideStartPolicyTests`. Ekrany aplikacji (`App/Features/Ride/`) tylko
// pokazują to, co tu wynika, i wołają system (zgody, kontroler nagrywania).
//
// Różnica względem Androida (SPECYFIKACJA_MOBILE_IOS.md 9.3, plan iOS Task 17): bez kroku optymalizacji baterii (nie dotyczy iOS) i bez
// osobnego ekranu powiadomień — o zgodę na powiadomienia aplikacja pyta systemem tuż przed startem, tylko gdy jeszcze nie pytała (tekst
// kroku Androida opisuje stałe powiadomienie usługi, którego na iOS nie ma — jego rolę pełni Live Activity).

/// Krok ekranu startu (Android `RideStartStep`). `opened` — jazda już trwa (ekran przechodzi do nagrywania, jedno nagrywanie naraz),
/// `pending` — czeka niezakończona sesja („Zapisz / Odrzuć” zamiast drugiej sesji).
public enum RideStartStep: String, Sendable, Hashable, CaseIterable {
    case checking
    case horse
    case wearHint
    case location
    case locationDenied
    case starting
    case opened
    case pending
}

/// Co pokazuje krok ekranu startu — klucze tekstów z katalogu (`strings.xml` Androida), bez podstawiania.
public struct RideStartStepContent: Sendable, Hashable {
    /// Nagłówek kroku (np. `ride_wear_title`).
    public var titleKey: String?
    /// Treść pod nagłówkiem (np. `ride_wear_text` — NAG-03 dosłownie).
    public var textKey: String?
    /// Główny przycisk (np. `common_next`, `ride_allow`, `ride_open_settings`).
    public var buttonKey: String?
    /// Wskaźnik postępu z opisem (`ride_start_checking`, `ride_start_starting`).
    public var progressKey: String?
    /// Pole „Nie pokazuj więcej” (`ride_wear_dont_show`).
    public var doNotShowAgainKey: String?
    /// Nagłówek w kolorze błędu (odmowa lokalizacji).
    public var titleIsError: Bool

    public init(
        titleKey: String? = nil, textKey: String? = nil, buttonKey: String? = nil, progressKey: String? = nil, doNotShowAgainKey: String? = nil,
        titleIsError: Bool = false
    ) {
        self.titleKey = titleKey
        self.textKey = textKey
        self.buttonKey = buttonKey
        self.progressKey = progressKey
        self.doNotShowAgainKey = doNotShowAgainKey
        self.titleIsError = titleIsError
    }
}

/// Wybór konia przy otwarciu startu: z karty konia przychodzi ten koń (z przyciskiem „Zmień” zamiast listy).
public struct RideHorseSelection: Sendable, Hashable {
    public var horseId: String?
    /// Koń przyszedł z karty konia i jest w stajni.
    public var fromCard: Bool

    public init(horseId: String?, fromCard: Bool) {
        self.horseId = horseId
        self.fromCard = fromCard
    }
}

/// Pasek NAG-01: „Trwa nagrywanie — Grom · 24 min · 3,2 km” (wstrzymana i przerwana jazda mają własne brzmienie).
public struct RideBannerContent: Sendable, Hashable {
    /// `ride_banner`, `ride_banner_paused` albo `ride_banner_interrupted` (`%1$@` koń, `%2$@` czas, `%3$@` dystans).
    public var textKey: String
    public var horseName: String
    public var activeSeconds: Int
    public var distanceMeters: Int
    /// Etykieta dotknięcia dla czytnika ekranu — „Otwórz ekran nagrywania”.
    public let openLabelKey = "ride_banner_open"

    public init(textKey: String, horseName: String, activeSeconds: Int, distanceMeters: Int) {
        self.textKey = textKey
        self.horseName = horseName
        self.activeSeconds = activeSeconds
        self.distanceMeters = distanceMeters
    }
}

/// Pytanie „Masz niezakończone nagranie (Grom, 14:05, 6,1 km).” z „Zapisz / Odrzuć” i drugim pytaniem przed odrzuceniem (NAG-09).
public struct RideRecoveryContent: Sendable, Hashable {
    public let titleKey = "ride_recovery_title"
    /// `%1$@` koń, `%2$@` godzina startu, `%3$@` dystans.
    public let textKey = "ride_recovery_text"
    public let saveKey = "ride_recovery_save"
    public let discardKey = "ride_recovery_discard"
    public let discardTitleKey = "ride_recovery_discard_title"
    /// Odrzucenie usuwa trasę i zdjęcia z aplikacji (kopia do galerii przy odrzuceniu — Task 21, wtedy `ride_recovery_discard_text_gallery`).
    public let discardTextKey = "ride_recovery_discard_text"
    public let discardConfirmKey = "ride_recovery_discard_confirm"
    public let discardBackKey = "ride_recovery_discard_back"

    public var sessionId: String
    public var horseName: String
    /// Godzina startu „HH:mm” w strefie telefonu.
    public var startTime: String
    public var distanceMeters: Int

    public init(sessionId: String, horseName: String, startTime: String, distanceMeters: Int) {
        self.sessionId = sessionId
        self.horseName = horseName
        self.startTime = startTime
        self.distanceMeters = distanceMeters
    }
}

/// Reguły startu nagrywania, paska i odzyskiwania.
public enum RideStartPolicy {
    /// Koń z karty konia (`preselectedHorseId`) jest wybrany od razu — o ile jest w stajni (`horseIds` to konie, na których można jechać).
    public static func initialSelection(preselectedHorseId: String?, horseIds: [String]) -> RideHorseSelection {
        guard let id = preselectedHorseId, horseIds.contains(id) else { return RideHorseSelection(horseId: nil, fromCard: false) }
        return RideHorseSelection(horseId: id, fromCard: true)
    }

    /// Jedno nagrywanie naraz: trwająca jazda → ekran nagrywania, niezakończona → odzyskiwanie, inaczej wybór konia.
    public static func gate(_ check: RideRecoveryCheck) -> RideStartStep {
        switch check {
        case .none: .horse
        case .recording: .opened
        case .pending: .pending
        }
    }

    /// Następny krok po „Dalej” (albo po powrocie z ustawień) — kroki, których nie trzeba pokazywać, są pomijane: instrukcja po „Nie pokazuj
    /// więcej”, pytanie o lokalizację przy zgodzie już udzielonej. Odmowa i przybliżona lokalizacja dają wyjaśnienie z „Otwórz ustawienia”
    /// (FR-NAG-09); `.starting` — można zakładać sesję.
    public static func next(after step: RideStartStep, wearHintHidden: Bool, location: LocationAuthorization) -> RideStartStep {
        switch step {
        case .horse:
            return wearHintHidden ? locationStep(location) : .wearHint
        case .wearHint, .location, .locationDenied:
            return locationStep(location)
        case .checking, .starting, .opened, .pending:
            return step
        }
    }

    /// Krok po odpowiedzi systemu na pytanie o lokalizację.
    public static func afterLocationAnswer(_ authorization: LocationAuthorization) -> RideStartStep {
        locationStep(authorization)
    }

    /// Krok po odmowie startu przez kontroler nagrywania (zgoda mogła się zmienić między krokiem a startem); `nil` — inny błąd (komunikat
    /// „Nie udało się rozpocząć nagrywania” na kroku konia).
    public static func step(for error: RideStartError) -> RideStartStep? {
        switch error {
        case .locationNotDetermined: .location
        case .locationDenied, .reducedAccuracy: .locationDenied
        case .alreadyRecording: .opened
        case .locationUnavailable: nil
        }
    }

    private static func locationStep(_ location: LocationAuthorization) -> RideStartStep {
        switch location {
        case .notDetermined: .location
        case .denied, .reducedAccuracy: .locationDenied
        case .whenInUse: .starting
        }
    }

    /// Treść kroku (teksty jak w Androidzie). Odmowa lokalizacji: „Bez dostępu do dokładnej lokalizacji nie da się nagrać jazdy.” w kolorze
    /// błędu i „Otwórz ustawienia”; wskazówka Androida (`ride_location_denied_hint` — „Uprawnienia → Lokalizacja”) opisuje ustawienia
    /// Androida, więc iOS jej nie pokazuje.
    public static func content(for step: RideStartStep) -> RideStartStepContent {
        switch step {
        case .checking, .opened, .pending:
            RideStartStepContent(progressKey: "ride_start_checking")
        case .starting:
            RideStartStepContent(progressKey: "ride_start_starting")
        case .horse:
            RideStartStepContent(textKey: "ride_start_pick_horse", buttonKey: "common_next")
        case .wearHint:
            RideStartStepContent(titleKey: "ride_wear_title", textKey: "ride_wear_text", buttonKey: "common_next", doNotShowAgainKey: "ride_wear_dont_show")
        case .location:
            RideStartStepContent(titleKey: "ride_location_title", textKey: "ride_location_text", buttonKey: "ride_allow")
        case .locationDenied:
            RideStartStepContent(titleKey: "ride_location_denied", buttonKey: "ride_open_settings", titleIsError: true)
        }
    }

    /// Czy sesja czeka na „Zapisz / Odrzuć”: zakończona albo przerwana — nie ta, którą właśnie nagrywa kontroler w tym procesie
    /// (Android `UnfinishedRide.needsRecovery`).
    public static func needsRecovery(state: RideState, controllerRunning: Bool) -> Bool {
        !(controllerRunning && (state == .recording || state == .paused))
    }

    /// Pasek NAG-01 dla niezakończonej jazdy z `RideSessionStore.observeActiveRide()` (sklep nie podaje jazd zakończonych); `nil` — bez paska.
    public static func banner(_ ride: ActiveRide?) -> RideBannerContent? {
        guard let ride, ride.snapshot.state != .finished else { return nil }
        let key = switch ride.snapshot.state {
        case .paused: "ride_banner_paused"
        case .interrupted: "ride_banner_interrupted"
        case .recording, .finished: "ride_banner"
        }
        return RideBannerContent(textKey: key, horseName: ride.horseName, activeSeconds: ride.snapshot.activeSeconds, distanceMeters: ride.snapshot.distanceMeters)
    }

    /// Pytanie odzyskiwania: koń, godzina startu w strefie telefonu („HH:mm”) i dystans z zapisanych punktów.
    public static func recovery(_ ride: UnfinishedRide, timeZone: TimeZone = .current) -> RideRecoveryContent {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: ride.startedAt)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        return RideRecoveryContent(sessionId: ride.sessionId, horseName: ride.horseName, startTime: time, distanceMeters: ride.distanceMeters)
    }

    /// Czas wyświetlany na ekranie nagrywania między zapisami (migawka odświeża się co 5 s): czas z migawki plus to, co upłynęło od niej —
    /// tylko w trakcie nagrywania i najwyżej 10 s (Android `RideRecordingViewModel.onTick`, `MAX_INTERPOLATION_SECONDS`).
    public static func displayedSeconds(snapshot: RideSnapshot, snapshotAt: Date, now: Date) -> Int {
        guard snapshot.state == .recording else { return snapshot.activeSeconds }
        let elapsed = Int(now.timeIntervalSince(snapshotAt).rounded(.down))
        return snapshot.activeSeconds + min(max(elapsed, 0), maxInterpolationSeconds)
    }

    static let maxInterpolationSeconds = 10

    /// Zegar ekranu nagrywania: „24:10” albo „1:02:05” (Android `rideClock`).
    public static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
    }

    /// „9,4 km/h” — prędkość z jedną cyfrą po przecinku (Android `String.format(pl-PL, "%.1f")`, połówka w górę jak w Javie);
    /// `template` to `ride_speed_kmh` („%1$@ km/h”).
    public static func speed(_ kmh: Double, template: String) -> String {
        let tenths = Int((max(0, kmh) * 10).rounded(.toNearestOrAwayFromZero))
        return String(format: template, locale: Locale(identifier: "pl_PL"), "\(tenths / 10),\(tenths % 10)" as NSString)
    }
}
