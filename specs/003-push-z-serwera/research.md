# Research: Powiadomienia push z serwera (iOS 2.1.0)

Decyzje fazy 0 dla [spec.md](spec.md). Odpowiedniki Androida: `../zarzadzanie_konmi_android/specs/006-push-z-serwera/research.md`
(R1–R13) — iOS przejmuje je, a różnice wynikają tylko z platformy. Kontrakty serwera:
`../zarzadzanie_konmi_java/specs/008-push-mobilny/contracts/api-push.md` §1, `fcm.md` §2.

## R1. Biblioteka: Firebase iOS SDK przez SPM, tylko `FirebaseMessaging`, wersja przypięta

- **Decision**: pakiet `https://github.com/firebase/firebase-ios-sdk` w `project.yml` z `exactVersion` (najnowsze wydanie 12.x
  w dniu implementacji, zapisane w planie zadań), produkt **wyłącznie** `FirebaseMessaging` (ciągnie `FirebaseCore`,
  `FirebaseInstallations`, `GoogleUtilities`, `GoogleDataTransport`, `nanopb`, `Promises`). Zależność ma **tylko cel aplikacji
  `Horsely`** — nie `HorselyKit` ani `HorselyCore` (z nich korzysta rozszerzenie `HorselyShare`, FR-030b). W `Info.plist`:
  `FirebaseAppDelegateProxyEnabled = NO`, `FirebaseMessagingAutoInitEnabled = NO`, `FIREBASE_ANALYTICS_COLLECTION_ENABLED = NO`
  (Analytics i tak nie jest dołączony — zabezpieczenie na przyszłość).
- **Rationale**: konstytucja II 2.1.0 dopuszcza tylko moduł Messaging; `exactVersion`, bo `Package.resolved` aplikacji powstaje
  w generowanym `.xcodeproj` (nie w repozytorium) — bez przypięcia każdy przebieg CI mógłby wziąć inną wersję (konstytucja VII).
- **Alternatives considered**: CocoaPods (osobne narzędzie, XcodeGen + SPM już w projekcie); zależność w `HorselyKit` (wciągnęłaby
  Firebase do rozszerzenia udostępniania i testów pakietu); `from:` zamiast `exactVersion` (niepowtarzalne kompilacje).

## R2. Granica Firebase: protokół w HorselyKit, implementacja w aplikacji

- **Decision**: `HorselyKit` dostaje protokół `PushTokenSource` (`configureIfNeeded()`, `token() async throws -> String`,
  `deleteToken() async`, `setAutoInit(Bool)`, `tokenChanges: AsyncStream<String>`); jedyna implementacja z `import FirebaseMessaging`
  to `App/Push/FirebasePushTokenSource.swift`. Logika (decyzja, rejestracja, ponowienia, wyrejestrowanie) jest w `HorselyKit`
  (`PushRegistrar`) i `HorselyCore` (`PushPolicy`, modele, mapowanie wiadomości) i testowana `swift test` z zaślepką źródła tokenu.
- **Rationale**: testy bez Firebase i bez symulatora (konstytucja VI); rozszerzenie i pakiety nie linkują Firebase (FR-030b);
  odpowiednik androidowego podziału `:core` / `PushRuntime`.
- **Alternatives considered**: wywołania `Messaging.messaging()` wprost w `AppEnvironment` (nietestowalne poza symulatorem).

## R3. Bez method swizzlingu; token APNs przekazywany ręcznie

- **Decision**: `FirebaseAppDelegateProxyEnabled = NO`. Istniejący `AppDelegate` (`App/Shell/QuickActions.swift`) dostaje
  `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` → `Messaging.messaging().apnsToken = token` (przez
  `FirebasePushTokenSource`) i `application(_:didFailToRegisterForRemoteNotificationsWithError:)` → zdarzenie „APNs odmówił”
  (R5). `UNUserNotificationCenterDelegate` zostaje istniejącym `NotificationDelegate` (bez podmiany przez Firebase).
  Wywołanie `Messaging.messaging().appDidReceiveMessage` pomijamy — służy tylko metrykom dostarczenia Firebase.
- **Rationale**: przy leniwej inicjalizacji (R6) proxy podmieniałoby metody delegata dopiero po `configure()`, czyli w trakcie
  działania aplikacji — trudne do przewidzenia; jawne przekazanie tokenu jest przewidywalne i testowalne. Clarifications: decyzja
  techniczna pozostawiona planowi.
- **Alternatives considered**: proxy włączone (domyślne w Firebase) — konflikt z istniejącym `NotificationDelegate` i z leniwą
  konfiguracją.

## R4. Model stanu push i jedna funkcja decyzji (jak Android R4)

- **Decision**: czysta funkcja w `HorselyCore` `PushPolicy.decide(_ input: PushInput) -> PushState`. Wejście: `workMode`,
  `serverHasPush`, `authorization` (`notDetermined` | `denied` | `allowed` — `provisional`/`ephemeral` liczone jako `allowed`),
  `apnsRefused` (Bool, R5), `registration: PushRegistration`, `now`. Kolejność warunków i stany: data-model §2. Z niej
  `localRemindersActive = state != .registered`. `AppEnvironment.rescheduleNotificationsNow()` dziś liczy
  `settings.notificationsEnabled && workMode != .unset`; po zmianie: `… && pushState.localRemindersActive` dla powiadomień o
  terminach i podsumowaniu (inne powiadomienia aplikacji — kolejka, kopia — bez zmian, FR-013).
- **Rationale**: jedno miejsce reguł brak dubli / tryb awaryjny; ekran i planowanie czytają ten sam stan (FR-008a).
- **Alternatives considered**: flagi rozproszone po `AppEnvironment` (ryzyko dubli lub utraty).

## R5. Kiedy „APNs niedostępny” (Clarifications Q1)

- **Decision**: `didFailToRegisterForRemoteNotificationsWithError` ustawia trwałe `apnsRefused = true` → od razu
  `Fallback(.apnsUnavailable)`; każda późniejsza udana rejestracja APNs (`didRegister…`) je czyści. Symulator w CI nie dostaje tokenu
  APNs, więc tryb awaryjny przy testach UI wymusza argument `-UITestPush apnsRefused` (contracts/test-fixtures). Brak tokenu FCM
  po udanej rejestracji APNs (`token()` rzuca lub limit 30 s) to **błąd chwilowy** → R7.
- **Rationale**: odmowa systemu jest jednoznaczna (odpowiednik „brak Usług Google Play”); brak tokenu FCM bywa siecią.
- **Alternatives considered**: tryb awaryjny po kilku startach (stan „Rejestruję…” bez końca na urządzeniu bez APNs).

## R6. Leniwa konfiguracja Firebase i znacznik „push aktywny” (lekcja Androida R2)

- **Decision**: `FirebaseApp.configure()` wywołuje `FirebasePushTokenSource.configureIfNeeded()` dopiero, gdy `PushPolicy` daje
  stan inny niż `standalone`, `fallback(.serverHasNoPush)` i `noPermission` (czyli: tryb z serwerem + `push` + zgoda). Wtedy
  zapisuje w `SettingsStore` znacznik `push.active = true`, włącza auto-init FCM i wywołuje
  `UIApplication.shared.registerForRemoteNotifications()`. W `HorselyApp.init` (przed końcem uruchamiania) przy `push.active == true`
  konfiguracja jest synchroniczna — po restarcie procesu SDK obsługuje zmianę tokenu. Wyrejestrowanie (R9) usuwa znacznik.
  Tryb samodzielny i serwer bez `push`: żadnego wywołania Firebase ani `registerForRemoteNotifications` (FR-027).
- **Rationale**: FR-027a, konstytucja II (brak połączeń do Google poza trybem z serwerem z `push`).
- **Alternatives considered**: `configure()` zawsze przy starcie (połączenia z Google w trybie samodzielnym — zakazane).

## R7. Rejestracja i ponowienia bez WorkManagera (Clarifications Q3)

- **Decision**: `PushRegistrar` (actor w `HorselyKit`) z metodą `reconcile(trigger:)`; wyzwalacze (FR-003): start aplikacji,
  wejście na pierwszy plan (`scenePhase == .active` w `RootView`), udane parowanie (`completePairing`), synchronizacja, w której
  `push` pojawił się w `capabilities` (`SyncService.record(_:)` zwraca `CapabilitiesChange` — nowa właściwość `pushAppeared`),
  stale obecny `push` — najwyżej raz na dobę według `registeredAt`, zmiana tokenu FCM (`tokenChanges`), zadanie
  `BGAppRefreshTask` (`BackgroundTasks.refresh`). Przebieg: `token()` → `PUT /push/device` → zapis rejestracji.
  - Sukces `200`: `registered = true`, `registeredAt` (z odpowiedzi), `tokenPrefix` (8 znaków), `failingSince = nil`,
    `permanentFailure = false`; potem przeliczenie powiadomień (lokalne o terminach znikają, FR-009).
  - `400`: `permanentFailure = true` (FR-005), ponowienia dalej (serwer mógł zostać poprawiony).
  - Sieć / 5xx / brak tokenu: `failingSince` ustawiane przy pierwszym błędzie serii (trwale, `SettingsStore`); gdy
    `now − failingSince ≥ 24 h` → `permanentFailure = true`. W otwartej aplikacji ponowienie przez `Task.sleep` z odstępami
    30 s, 60 s, 120 s, 240 s, 480 s, 900 s (dalej 900 s), anulowane przy przejściu w tło i przy sukcesie; poza aplikacją —
    przy następnym wejściu na pierwszy plan i w `BGAppRefreshTask`.
  - `401`/`403`/`429`: istniejąca obsługa `ApiClient` (wstrzymanie adresu, stan połączenia — konstytucja III); push nie dodaje
    komunikatu, stan zostaje `pending` (lub `fallback(.registrationFailed)` po 24 h).
  Jedna rejestracja naraz (actor + flaga „w toku”); nowy wyzwalacz w trakcie jest scalany.
- **Rationale**: iOS nie gwarantuje pracy w tle (konstytucja IV: nadrabianie przy otwarciu); czas od pierwszego niepowodzenia
  zamiast licznika prób nie zależy od tego, jak często system budzi aplikację.
- **Alternatives considered**: osobne zadanie `BGProcessingTask` tylko na ponowienia (system i tak decyduje o terminie; więcej
  konfiguracji bez zysku); ponowienia tylko przy wejściu na pierwszy plan (wolniejsze wyjście z `Pending`).

## R8. Sieć: zwykła ścieżka i ponowienia `PUT`/`DELETE` (poprawki Androida 1–2)

- **Decision**: żądania push budowane jako `ApiRequest(..., forFile: false)` — `ApiClient.execute` nie pomija wtedy adresów
  zewnętrznych na danych komórkowych przy „tylko przez Wi‑Fi” (`skipRemote` dotyczy tylko `forFile`). `ApiRequest` dostaje pole
  `retryOnDrop: Int` (domyślnie `0`; dla `GET` zachowanie bez zmian — jedno ponowienie odczytu). `executeOn` dla żądań z
  `retryOnDrop > 0` ponawia natychmiast do tej liczby razy przy `.network(sentBody: true, …)`; `PUT` i `DELETE /push/device` mają
  `retryOnDrop = 2` i są oznaczone jako idempotentne (bezpieczne przejście na kolejny adres). Testy: `ApiClientPushTests` z
  `FixedNetwork.cellular`, `wifiOnly = true`, jedynym adresem zdalnym → żądanie wysłane; transport zrywający połączenie dwa razy →
  trzecia próba wysłana.
- **Rationale**: na Androidzie oba błędy pojawiły się dopiero na telefonie; tu są zabezpieczone testem od początku.
- **Alternatives considered**: osobny klient HTTP dla push (duplikacja przypinania certyfikatu, klucza, ogranicznika — konstytucja III).

## R9. Wyrejestrowanie przed usunięciem klucza (jak Android R6)

- **Decision**: `PushRegistrar.unregister(reason:)` wołane **przed** `secrets.delete()` w `AppEnvironment.disconnect()`,
  `completeStandaloneSwitch()`, usuwaniu danych połączenia i przy cofniętej zgodzie (wykrytej w `reconcile` przy starcie/powrocie).
  Kolejność: `DELETE /push/device` z limitem 5 s (`withTimeout`; wynik ignorowany — `204`, `401`, brak sieci, 5xx) →
  `deleteToken()` → `setAutoInit(false)` → `UIApplication.shared.unregisterForRemoteNotifications()` → wyczyszczenie
  `PushRegistration` i znacznika `push.active`. Przy cofniętej zgodzie znacznik też znika; po przywróceniu zgody `reconcile`
  konfiguruje wszystko od nowa. Przerwane przejście trybu
  (`settings.modeChangePending`) wznawiane po restarcie wykonuje tylko część lokalną (klucza może już nie być). Zmiana serwera
  (ponowne parowanie z innym kluczem): `unregister` starego przed zapisem nowego klucza w `completePairing`, potem rejestracja
  według nowych `capabilities`. Zniknięcie `push` z `capabilities` (FR-011): **bez** `DELETE`, tylko `registered = false` i
  przeliczenie powiadomień (serwer i tak nie wysyła).
- **Rationale**: po usunięciu klucza `DELETE` nie przejdzie (`401`), a token zostałby na serwerze (FR-006, US3).
- **Alternatives considered**: wyrejestrowanie po usunięciu klucza (niemożliwe); blokowanie odparowania do potwierdzenia serwera
  (FR-007 zabrania).

## R10. Odbiór i wyświetlanie (FR-015…FR-018, Clarifications Q2)

- **Decision**: wiadomość z alertem w tle wyświetla system (serwer ustawia `apns-push-type: alert`, `apns-collapse-id`,
  `apns-expiration`). `NotificationDelegate.willPresent`: gdy `userInfo` ma klucz `type` (wiadomość z serwera) — przy
  `pushState == .registered` zwraca `[.banner, .list, .sound]` (także przy „ukryj szczegóły”; Clarifications Q2), inaczej `[]`
  (FR-016, FR-008). Dla `reminder`/`summary` zleca `refresh(force: true)` w osobnym `Task` (FR-017). Powiadomienia lokalne (klucz
  `link`) — bez zmian. Rozpoznanie w czystej funkcji `PushMessage(userInfo:)` (`HorselyCore`), która ignoruje nieznane klucze
  i klucze Firebase (`gcm.*`, `google.*`, `aps`). Dziennik: „wiadomość type=reminder” (bez treści i identyfikatorów).
- **Rationale**: system sam zastępuje powiadomienie o tym samym `apns-collapse-id`, więc aplikacja nie buduje własnego (inaczej niż
  Android).
- **Alternatives considered**: własna lokalna kopia z ukrytą treścią na pierwszym planie (odrzucone w Clarifications Q2);
  Notification Service Extension (serwer nie ustawia `mutable-content`).

## R11. Dotknięcie powiadomienia → cel nawigacji (FR-019)

- **Decision**: czysta funkcja `PushDeepLink.url(for: PushMessage) -> URL` w `HorselyCore`, zwracająca istniejące adresy
  `horsely://` obsługiwane przez `DeepLinkRouter` (`DeepLinkTarget` `.reminder(id:)`, `.reminders`, `.dashboard`):
  `reminder` z `reminderId` → `horsely://reminders/{id}`; `summary` → `horsely://reminders`; `backup` → nowy host
  `horsely://server-backup` (nowy przypadek `.serverBackup`, karta „Więcej”); reszta i `reminder` bez `reminderId` →
  `horsely://dashboard`.
  `NotificationDelegate.didReceive`: najpierw klucz `link` (powiadomienia lokalne jak dziś), inaczej `PushMessage` → link.
  Brak terminu lokalnie: `DeepLinkRouter` przy `reminders/{id}` sprawdza magazyn; gdy rekordu nie ma, uruchamia
  `refresh(force: true)` i ponownie sprawdza; dalej brak → lista terminów. `horseId`, `targetDate` parsowane tolerancyjnie
  (`LocalDate(_:)`), nieużywane. Nowy widok `ServerBackupInfoView` (tylko tekst i „Wróć”, bez sieci).
- **Rationale**: jedna ścieżka nawigacji dla powiadomień lokalnych i z serwera; mapowanie testowane bez UI.
- **Alternatives considered**: `click_action`/kategorie z serwera (wymaga zmiany serwera).

## R12. Zgoda (FR-014, FR-014a, FR-012a)

- **Decision**: stan zgody z `UNUserNotificationCenter.notificationSettings().authorizationStatus` odczytywany przy starcie
  i każdym wejściu na pierwszy plan (wejście `PushPolicy`). Pytanie o zgodę: `DashboardView` przy pojawieniu się, gdy tryb z
  serwerem, `capabilities.push`, `authorizationStatus == .notDetermined` i `settings.pushPermissionAsked == false` → okno
  wyjaśnienia (`push_permission_text`) → `requestAuthorization` → `pushPermissionAsked = true` (odmowa szanowana). Cofnięta zgoda
  po rejestracji → `unregister` (R9). Poprawki 2.1.0 z Androida: `completePairing` włącza `notificationsEnabled`, gdy zgoda jest
  `allowed`; `NotificationSettingsView` już dziś pokazuje „brak zgody” tylko przy `.denied && enabled`, więc `notDetermined` nie
  jest odmową — zostaje to potwierdzone migawką stanu „zgoda nieustalona”; `ReminderDigest.dailySummary` → „Przeterminowane: X, na dziś i jutro: Y”.
- **Rationale**: odpowiada Androidowi 2.1.0 (rozstrzygnięcie 3, poprawki 3).
- **Alternatives considered**: pytanie przy każdym starcie (natarczywe; odrzucone na Androidzie).

## R13. Ekran „Powiadomienia” i karta Pulpitu (FR-020…FR-026, FR-012a, Clarifications Q4)

- **Decision**: `NotificationSettingsView` dostaje sekcję „Powiadomienia z serwera” sterowaną `PushState` (contracts/ui-push-ios.md);
  `GET /push/device` i `GET /push/rules` tylko w `.task` ekranu i po „Odśwież”. Karta Pulpitu „Powiadomienia o terminach są
  wyłączone” w `DashboardView` (oba tryby): widoczna, gdy `!settings.notificationsEnabled`, stan ≠ `registered` i
  `!settings.notificationsOffCardDismissed`; „Włącz” → ta sama ścieżka co przełącznik w ustawieniach (wyjaśnienie + zgoda),
  „Nie pokazuj” → trwałe ukrycie. Migawki: jasny, ciemny, tekst 200 % dla stanów `registered` (z regułami i bez), `pending`,
  `fallback`, `noPermission` oraz Pulpitu z kartą.
- **Rationale**: jedno miejsce ustawień (konstytucja VII), zgodność z Androidem (VIII).

## R14. Teksty: z `strings.xml` Androida, plus dwa teksty iOS dopisane w Androidzie

- **Decision**: teksty `push_*` i `dashboard_notifications_off_*` są już w `strings.xml` Androida 2.1.0 → `scripts/sync-strings.ps1
  -AndroidRepo ..\zarzadzanie_konmi_android` je przenosi. iOS potrzebuje dwóch tekstów, których Android nie ma:
  `push_state_no_apns` („Telefon nie może odbierać powiadomień z serwera — powiadomienia planuje telefon.”) i
  `push_hide_previews_hint` (wskazanie systemowego „Pokazuj podglądy”). Zgodnie z zasadą VIII (teksty tylko ze `strings.xml`)
  dopisujemy je w `strings.xml` **repozytorium Androida** z komentarzem „tylko iOS” (Android ich nie używa; lint `UnusedResources`
  w Androidzie wyłączony dla tych kluczy przez `tools:ignore`), commit w repozytorium Androida, potem synchronizacja w iOS.
  `push_state_no_play` w iOS nie jest używany.
- **Rationale**: jedno źródło tekstów i istniejący test zgodności; brak osobnego mechanizmu tekstów iOS.
- **Alternatives considered**: plik tekstów tylko dla iOS (łamie zasadę VIII i test zgodności); tekst wpisany w kod (łamie zasadę VIII).

## R15. Uprawnienia aplikacji i podpis w CI (FR-032b)

- **Decision**: `App/Horsely.entitlements` dostaje `aps-environment = development` (kompilacje deweloperskie); `App/Info.plist`
  `UIBackgroundModes` dostaje `remote-notification` (obok `fetch`, `processing`). Wydanie: `embed-entitlements.sh` podpisuje
  archiwum doraźnie z tym plikiem, a eksport z `-allowProvisioningUpdates` podpisuje profilem dystrybucyjnym, który ustawia
  `aps-environment = production` (identyfikator `pl.glapa.horsely` musi mieć włączoną możliwość Push Notifications w Apple Developer —
  automatyczne podpisywanie z kluczem API ASC ją włącza; quickstart §2 sprawdza). Nowy skrypt `scripts/ci/verify-push-entitlements.sh`
  po eksporcie: rozpakowuje `.ipa`, `codesign -d --entitlements` → aplikacja MUSI mieć `aps-environment = production`, a
  `HorselyShare.appex` NIE MOŻE mieć `aps-environment`; inaczej przebieg kończy się błędem z opisem (konstytucja: brak cichego
  pominięcia). `embed-entitlements.sh` dodatkowo wypisuje `aps` przy weryfikacji. Rozszerzenie: `HorselyShare.entitlements` bez zmian.
- **Rationale**: błąd w uprawnieniach wychodzi dopiero na telefonie (brak tokenu APNs) — weryfikacja w CI łapie go wcześniej.
- **Alternatives considered**: zmiana pliku uprawnień na `production` na czas wydania (ręczny krok; profil i tak decyduje).
- **Uwaga**: kryterium „kompilacja z Xcode (development) dostaje test” (spec, US1/8) nie da się sprawdzić bez Maca; kompilacje
  deweloperskie nie powstają. Środowisko `development` pokrywa tylko konfiguracja Firebase (klucz `.p8` obsługuje oba). Weryfikacja
  ręczna obejmuje TestFlight (`production`).

## R16. Prywatność: manifest, dziennik, App Privacy (FR-028…FR-030a)

- **Decision**: nowy `App/PrivacyInfo.xcprivacy`: `NSPrivacyTracking = false`, bez domen śledzących; `NSPrivacyCollectedDataTypes`:
  „Device ID” (identyfikator instalacji/token FCM) — cel „App Functionality”, niepowiązany z tożsamością, bez śledzenia;
  `NSPrivacyAccessedAPITypes` — `UserDefaults` (CA92.1), na które aplikacja już się powołuje przez `SettingsStore`. Pakiety Firebase
  mają własne manifesty (agregowane przez Xcode). App Store Connect → App Privacy: „Identyfikatory → Identyfikator urządzenia,
  Funkcjonalność aplikacji, niepowiązane, bez śledzenia” — krok ręczny właściciela (quickstart §2), bo App Privacy wymagany jest
  tylko dla App Store, a dystrybucja to TestFlight (9.6) — mimo to uzupełniamy dla spójności. Dziennik: kategoria `push`
  (`DiagnosticLog.log("push", …)`), komunikaty słowami z `PushDiagnostics` (np. „rejestracja nieudana: brak połączenia
  (zerwane połączenie)” z `ApiFailure` → opis), bez tokenu (prefiks 8 znaków), tytułów, treści, identyfikatorów. Test:
  dziennik połączeń zapisuje dla `PUT /push/device` tylko metodę, ścieżkę i wynik (już tak działa — `ConnectionLog.request` nie
  dostaje ciała), a pełny token nie występuje w żadnym pliku dziennika po scenariuszu rejestracja–wiadomość–wyrejestrowanie.
- **Rationale**: FR-028, konstytucja II; nazwy błędów czytelne (na Androidzie zaciemnione nazwy klas dawały „ik”).

## R17. Daty z serwera i modele (FR-035)

- **Decision**: `PushDevice`, `ClientPushRule`, `DeviceRegistration` w `HorselyCore` (`Codable`, dekodowanie tolerancyjne:
  nieznane pola pomijane, `lastSeenAt`/`lastDeliveredAt` mogą być `null`, nieznany `type` reguły to zwykły napis). Daty
  `registeredAt` itd. przez istniejące `SyncMerger.parseInstant` — test z przykładem serwera o 7 cyfrach ułamka
  (`2026-11-04T10:15:00.0000000Z`); gdyby `ISO8601DateFormatter` go nie przyjął, parser obcina ułamek do 3 cyfr. Przykłady JSON
  z `api-push.md` w `Packages/HorselyCore/Tests/HorselyCoreTests/Resources/push/`. `ProgramCapabilities.pushName = "push"`
  dodane do `known`; `pushAdmin` dalej pomijane.

## R18. Środowisko testów (wymóg właściciela)

- **Decision**: testy automatyczne w CI wyłącznie z zaślepką (`URLProtocol`/`ProgramTransport`) — w tym nowe gałęzie
  `push/device` i `push/rules` w zaślepce testowej i `DemoProgramTransport` (scenariusz `push` dla testów UI). Testy ręczne
  z prawdziwym serwerem: serwer Java uruchomiony lokalnie na komputerze dewelopera (Windows) według
  `../zarzadzanie_konmi_java/specs/008-push-mobilny/quickstart.md` z własną bazą i plikiem konta usługi Firebase, iPhone w tej samej
  sieci Wi‑Fi sparowany z lokalnym serwerem. **Serwer `192.168.18.33` (produkcja) jest wykluczony z testów** — nie wolno na nim
  rejestrować telefonu testowego, wysyłać testów ani przypisywać reguł.
- **Rationale**: polecenie właściciela; produkcyjne reguły i lista urządzeń nie mogą się zmieniać przez testy.

## R19. Wersja i wydanie

- **Decision**: `MARKETING_VERSION: "2.1.0"` w `project.yml`; numer kompilacji z CI (`GITHUB_RUN_NUMBER`). `CHANGELOG.md` (tworzony,
  jeśli go nie ma) z sekcją `[2.1.0]`. Wydanie: po zielonym CI na `main` tag `v2.1.0` → TestFlight do grupy „Deweloper”, po liście
  kontrolnej — do „Właściciele” (pamięć projektu). Aktualizacja z 2.0.2: nowe klucze `push.*` w `SettingsStore` z wartościami
  domyślnymi „niezarejestrowany” → do pierwszej udanej rejestracji działają powiadomienia lokalne (FR-034); brak migracji bazy.
