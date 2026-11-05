# Implementation Plan: Powiadomienia push z serwera (tryb z serwerem) — iOS 2.1.0

**Branch**: `003-push-z-serwera` | **Date**: 2026-11-05 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-push-z-serwera/spec.md`

## Summary

W trybie z serwerem, gdy serwer Horsely 2.0 ogłasza `push`, iPhone rejestruje token Firebase Cloud Messaging na serwerze
(`PUT /push/device`), pokazuje powiadomienia wysłane przez serwer (FCM → APNs) i przestaje planować własne powiadomienia
o terminach i podsumowaniu — dopiero po udanej rejestracji. Gdy push nie działa, wraca do powiadomień lokalnych i mówi
dlaczego. Tryb samodzielny bez zmian, bez żadnego połączenia z Google. Zachowanie i teksty jak w Androidzie 2.1.0.

Podejście techniczne ([research.md](research.md)):

- **Rdzeń bez Firebase**: `PushPolicy.decide` (stan push), modele API, `PushMessage` i `PushDeepLink` w `HorselyCore`;
  `PushRegistrar` (rejestracja, ponowienia 30 s → 15 min, próg 24 h, wyrejestrowanie przed usunięciem klucza) w `HorselyKit`
  za protokołem `PushTokenSource` — testy `swift test` z zaślepkami (R2, R4, R7, R9).
- **Firebase tylko w celu aplikacji**: `FirebaseMessaging` (SPM, `exactVersion`), bez swizzlingu, leniwie konfigurowany
  i ze znacznikiem „push aktywny” (R1, R3, R6). Rozszerzenie udostępniania bez Firebase.
- **Sieć**: żądania push zwykłą ścieżką `ApiClient` (działają na danych komórkowych), `PUT`/`DELETE` ponawiane do 2 razy
  po zerwanym połączeniu — poprawki z telefonu z Androidem zabezpieczone testami od początku (R8).
- **UI**: sekcja „Powiadomienia z serwera” w istniejącym ekranie, karta Pulpitu, ekran „Kopia zapasowa na serwerze”,
  pytanie o zgodę z Pulpitu (R12, R13); teksty ze `strings.xml` Androida, dwa nowe dopisane tam (R14).
- **Wydanie**: `aps-environment`, `remote-notification`, weryfikacja uprawnień `.ipa` w CI, manifest prywatności, 2.1.0 (R15, R16, R19).

## Technical Context

**Language/Version**: Swift 6 (ścisła współbieżność, ostrzeżenia jako błędy), SwiftUI, iOS 18+

**Primary Dependencies**: wbudowane — SwiftUI, UserNotifications, BackgroundTasks, URLSession; pakiety projektu `HorselyCore`,
`HorselyKit`; **nowa**: Firebase iOS SDK — wyłącznie produkt `FirebaseMessaging`, przypięta wersja 12.x, tylko cel `Horsely` (R1)

**Storage**: stan rejestracji push w `SettingsStore` (`UserDefaults` aplikacji, klucze `push.*`) jako część danych połączenia —
bez zmian schematu SQLite i formatu kopii zapasowej ([data-model.md](data-model.md) §1)

**Testing**: XCTest — `swift test` pakietów (polityka, modele, mapowanie wiadomości, rejestrator, klient API z zaślepką
`ProgramTransport`/`FakeProgram`), `AppSnapshotTests` (jasny/ciemny/200 %), `AppUITests` z `DemoProgramTransport` (scenariusz
`push`, `-UITestPush`); test zgodności tekstów; weryfikacja uprawnień `.ipa` w `release.yml`

**Target Platform**: iPhone, iOS 18+, odniesienie iPhone 15 Pro (TestFlight, `aps-environment = production`); budowanie wyłącznie
w GitHub Actions (macOS), bez Maca

**Project Type**: aplikacja mobilna (XcodeGen `project.yml`: aplikacja + rozszerzenie udostępniania + 2 pakiety SPM)

**Performance Goals**: rejestracja widoczna w UI webowym ≤ 1 min (SC-001); powiadomienie testowe ≤ 30 s (SC-002 — zależne od
FCM/APNs); obsługa wiadomości bez długiej pracy (FR-017); odparowanie bez sieci najwyżej ~5 s dłużej (SC-005)

**Constraints**: zero połączeń z Google w trybie samodzielnym i przy serwerze bez `push` (FR-027); zero dubli i zero utraconych
przypomnień przy przełączaniu (SC-003, SC-004); token nigdy w dzienniku (FR-028); testy ręczne tylko na lokalnym serwerze,
nigdy na produkcyjnym `192.168.18.33` (R18); brak Maca — kompilacje deweloperskie nie powstają (R15)

**Scale/Scope**: 6 historii; ~8 nowych plików (rdzeń, rejestrator, źródło tokenu, ekran kopii serwera, skrypt CI, manifest),
~14 zmienionych (`AppEnvironment`, `HorselyApp`, `AppDelegate`, `NotificationDelegate`, `DeepLinkRouter`, `NotificationSettingsView`,
`DashboardView`, `ApiClient`/`ApiRequest`, `SyncService`, `SettingsStore`, `Capabilities`, `ReminderDigest`, `project.yml`,
`release.yml`); ~20 nowych tekstów; 4 endpointy

## Constitution Check

*GATE: przed fazą 0 i po fazie 1. Oceniane dla trybu online (O) i samodzielnego (S). Konstytucja 2.1.0.*

| Zasada | Przed (O / S) | Po projekcie (O / S) | Uwagi |
|--------|---------------|----------------------|-------|
| I. Jedno źródło prawdy | ✅ / ✅ | ✅ / ✅ | O: serwer decyduje o regułach push, telefon pokazuje `description` bez interpretacji; S: bez zmian |
| II. Prywatność i brak usług zewnętrznych | ✅ / ✅ (wyjątek FCM w 2.1.0) | ✅ / ✅ | O: tylko `FirebaseMessaging`, auto-init wyłączony, konfiguracja wyłącznie przy `push` + zgodzie (R6), serwerowi tylko platforma i token, dziennik bez tokenu i treści (R16); S: brak Firebase i APNs; rozszerzenie bez Firebase; plist w repozytorium, `.p8` i konto usługi poza nim |
| III. Bezpieczne połączenie i klucz API | ✅ / ✅ | ✅ / ✅ | O: żądania push przez istniejący `ApiClient` (przypinanie, klucz, `401/403/429`), wyrejestrowanie przed usunięciem klucza z Keychain (R9); S: bez połączeń |
| IV. Offline i synchronizacja | ✅ / ✅ | ✅ / ✅ | O: rejestracja nadrabiana przy otwarciu i w `BGAppRefreshTask` (R7), lokalne powiadomienia działają do udanej rejestracji; S: bez zmian |
| V. Kontrakt API | ✅ / ✅ | ✅ z odstępstwem / ✅ | O: ścieżki i ciało `PUT` z OpenAPI serwera (`contracts/openapi-server-push.json`, R17); kształty odpowiedzi, `400`/`404` z `api-push.md` §1 — odstępstwo w „Complexity Tracking”; `push` tylko gdy ogłoszony; nieznane pola i typy pomijane. S: bez zmian |
| VI. Testy | ✅ / ✅ | ✅ / ✅ | zaślepka z endpointami push sprawdzana z kopią OpenAPI (ścieżki, metody, `DeviceRegistration`); polityka, rejestrator, mapowanie, klient (dane komórkowe, zerwane połączenia), dziennik bez tokenu, migawki stanów, zgodność tekstów, uprawnienia w CI; S: test braku wywołań Firebase |
| VII. Prostota | ✅ / ✅ | ✅ / ✅ | jedna nowa zależność (wyjątek z zasady VII); bez NSE, bez osobnego zadania w tle; sekcja w istniejącym ekranie |
| VIII. Zgodność z Androidem 2.1.0 | ✅ / ✅ | ✅ / ✅ | te same stany, teksty (`strings.xml`), cele nawigacji, karta Pulpitu; różnice platformy opisane (APNs zamiast Usług Google Play, pierwszy plan przy „ukryj szczegóły”, R5, R10) |
| Proces | ✅ / ✅ | ✅ / ✅ | XcodeGen, CI bez Maca, wydanie tagiem `v2.1.0`; testy ręczne tylko na serwerze lokalnym; kompilacje deweloperskie nie powstają (R15) |

Jedno uzasadnione odstępstwo (zasada V) — „Complexity Tracking” niżej.

## Project Structure

### Documentation (this feature)

```text
specs/003-push-z-serwera/
├── plan.md              # ten plik
├── research.md          # faza 0 — decyzje R1–R19
├── data-model.md        # faza 1 — stan rejestracji, PushState, modele API i wiadomości
├── quickstart.md        # faza 1 — weryfikacja (CI, lokalny serwer, TestFlight)
├── contracts/
│   ├── openapi-server-push.json # kopia OpenAPI serwera z endpointami push (repozytorium UI, dd7f142)
│   ├── push-api-client.md   # jak aplikacja używa API telefonu
│   ├── push-message.md      # wiadomość APNs/FCM → PushMessage → cel nawigacji
│   ├── ui-push-ios.md       # ekran „Powiadomienia”, karta Pulpitu, zgoda, ekran kopii serwera
│   └── ci-push.md           # uprawnienia, Info.plist, weryfikacja .ipa, manifest prywatności
├── checklists/requirements.md
└── tasks.md             # faza 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
App/
├── Horsely.entitlements                 # + aps-environment (development)
├── Info.plist                           # + remote-notification, FirebaseAppDelegateProxyEnabled/AutoInit = NO
├── PrivacyInfo.xcprivacy                # NOWY (R16)
├── Resources/GoogleService-Info.plist   # już w repozytorium (projekt horsely-41baf)
├── Push/
│   └── FirebasePushTokenSource.swift    # NOWY — jedyny import FirebaseMessaging (R2, R3, R6)
├── Shell/
│   ├── AppEnvironment.swift             # PushRegistrar, pushState, unregister przed usunięciem klucza, reschedule wg stanu
│   ├── QuickActions.swift (AppDelegate) # didRegister/didFail… RemoteNotifications
│   ├── NotificationDelegate.swift       # wiadomości z serwera: willPresent wg stanu, didReceive → PushDeepLink
│   ├── DeepLinkRouter.swift             # host server-backup, brak terminu → synchronizacja → lista
│   └── RootView.swift                   # reconcile przy wejściu na pierwszy plan
├── HorselyApp.swift                     # synchroniczna konfiguracja przy push.active, BGAppRefresh → reconcile
└── Features/
    ├── Settings/NotificationSettingsView.swift   # sekcja „Powiadomienia z serwera”
    ├── Dashboard/DashboardView.swift             # karta „Powiadomienia o terminach są wyłączone”, pytanie o zgodę
    └── Backup/ServerBackupInfoView.swift         # NOWY — „Kopia zapasowa na serwerze”

Packages/HorselyCore/Sources/HorselyCore/
├── Connection/Capabilities.swift        # + push; CapabilitiesChange.pushAppeared/pushVanished
├── Notify/ReminderDigest.swift          # „Przeterminowane: X, na dziś i jutro: Y”
└── Push/                                # NOWY
    ├── PushPolicy.swift                 # PushInput, PushState, decide
    ├── PushModels.swift                 # DeviceRegistration, PushDevice, ClientPushRule
    └── PushMessage.swift                # PushMessage(userInfo:), PushDeepLink

Packages/HorselyKit/Sources/HorselyKit/
├── Network/ApiResult.swift, ApiClient.swift   # retryOnDrop dla PUT/DELETE push (R8)
├── Push/                                       # NOWY
│   ├── PushTokenSource.swift            # protokół
│   ├── PushRegistrar.swift              # reconcile, ponowienia, unregister, deviceInfo, rules
│   └── PushDiagnostics.swift            # opisy słowami do dziennika
├── Store/SettingsStore.swift            # klucze push.*, pushPermissionAsked, notificationsOffCardDismissed
└── Sync/SyncService.swift               # zwrot zmiany capabilities do rejestratora

Packages/*/Tests/…                       # PushPolicyTests, PushModelsTests, PushMessageTests, PushRegistrarTests,
                                         # ApiClientPushTests, ReminderDigestTests (podsumowanie), FakeProgram + push
Tests/AppSnapshotTests, Tests/AppUITests # migawki stanów push i Pulpitu; UI: tryb awaryjny w symulatorze, nawigacja z wiadomości
scripts/ci/verify-push-entitlements.sh   # NOWY (R15)
project.yml                              # firebase-ios-sdk (exactVersion), FirebaseMessaging tylko dla Horsely, 2.1.0
.github/workflows/release.yml            # krok weryfikacji uprawnień po eksporcie
CHANGELOG.md                             # [2.1.0]
```

**Structure Decision**: istniejący układ (aplikacja + `HorselyCore` + `HorselyKit`). Logika push w pakietach (testowalna bez
symulatora i bez Firebase), jedyny kod Firebase w `App/Push/`. Poza repozytorium iOS: dwa teksty dopisane w `strings.xml`
repozytorium Androida (R14) — osobny commit tam, przed synchronizacją tekstów.

## Fazy realizacji (wejście do /speckit-tasks)

1. **Fundament (bez widocznych zmian)**: `push` w `ProgramCapabilities`, modele i `PushPolicy` z testami, `retryOnDrop` w
   `ApiClient` z testami na danych komórkowych, zaślepka serwera z endpointami push, teksty (Android → sync).
2. **US6 bramka konfiguracji** (dokumenty już zrobione w commicie c299130): Firebase w `project.yml`, uprawnienia, `Info.plist`,
   manifest prywatności, `verify-push-entitlements.sh` w `release.yml` — zielone CI.
3. **US1 + US2 (P1)**: `PushRegistrar`, `FirebasePushTokenSource`, `AppDelegate`, wyzwalacze, `reschedule` wg stanu, tryb awaryjny,
   poprawki powiadomień lokalnych (parowanie włącza, treść podsumowania).
4. **US3 (P1)**: wyrejestrowanie w „Rozłącz”, przejściu w tryb samodzielny, cofniętej zgodzie, zmianie serwera.
5. **US4 (P2)**: ekran „Powiadomienia”, karta Pulpitu, pytanie o zgodę; migawki.
6. **US5 (P2)**: `NotificationDelegate`, `PushDeepLink`, `DeepLinkRouter`, ekran „Kopia zapasowa na serwerze”; testy UI.
7. **Wydanie 2.1.0**: wersja, CHANGELOG, zielone CI na `main`, tag `v2.1.0` → TestFlight („Deweloper”); lista kontrolna z
   [quickstart.md](quickstart.md) na lokalnym serwerze; potem „Właściciele”.

## Complexity Tracking

| Odstępstwo | Dlaczego potrzebne | Prostsza alternatywa odrzucona, bo |
|------------|--------------------|-------------------------------------|
| Zasada V/VI — OpenAPI serwera (`GET /openapi/v1.json`, kopia `contracts/openapi-server-push.json` z repozytorium `zarzadzanie_konmi_ui`, `api/openapi.json`, commit `dd7f142`) zawiera ścieżki `push/device` (`PUT`/`GET`/`DELETE`), `push/rules` (`GET`) i schemat `DeviceRegistration`, ale odpowiedzi `200` opisuje jako `type: object`, bez `PushDevice`/`ClientPushRule`, i nie wymienia `400`/`404`. Kształty odpowiedzi i kody błędów aplikacja bierze z `../zarzadzanie_konmi_java/specs/008-push-mobilny/contracts/api-push.md` §1 (kontrakt serwera, zgodny z testem `PushOpenApiIT` i testami API serwera) | bez tych pól nie da się pokazać dat rejestracji ani listy reguł (FR-022, FR-023), a bez `404` — wykryć usunięcia urządzenia (FR-025) | zakładanie pól tylko z OpenAPI: brak pól; czekanie na typowane schematy w OpenAPI serwera: blokuje wydanie bez zysku — pola są ustalone w kontrakcie serwera i wdrożone na produkcji. Ograniczenia ryzyka: dekodowanie tolerancyjne (R17), test zgodności zaślepki z kopią OpenAPI (ścieżki, metody, `DeviceRegistration`), a gdy serwer otypuje odpowiedzi — kopia zostanie odświeżona i test rozszerzony o schematy |

Jedyna nowa zależność zewnętrzna (Firebase Messaging) jest wprost dopuszczona przez zasady II i VII konstytucji 2.1.0.
