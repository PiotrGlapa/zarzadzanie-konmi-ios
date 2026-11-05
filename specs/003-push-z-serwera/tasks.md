# Tasks: Powiadomienia push z serwera (tryb z serwerem) — iOS 2.1.0

**Input**: Design documents from `specs/003-push-z-serwera/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: wymagane — konstytucja, zasada VI, oraz FR-035 (zaślepka serwera, dekodowanie tolerancyjne) i FR-028 (dziennik bez
tokenu potwierdzony testem). Testy piszemy przed implementacją; najpierw muszą nie przechodzić. Bez Maca — testy uruchamia CI.

**Organization**: zadania pogrupowane według historii użytkownika ze spec.md: US6 (bramka dokumentów i konfiguracji, P1 przed
kodem), US1 (rejestracja i odbiór, P1), US2 (tryb awaryjny, P1), US3 (wyrejestrowanie, P1), US4 (ekran „Powiadomienia”, P2),
US5 (dotknięcie powiadomienia, P2).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: można wykonać równolegle (inne pliki, brak zależności od nieukończonych zadań)
- **[Story]**: historia użytkownika (US1–US6)

## Zasady przebiegu (obowiązują w fazach 1–8)

- Praca na gałęzi `003-push-z-serwera`. Każda faza kończy się commitem, pushem gałęzi i zielonym `ci.yml` w szkicu PR
  (`gh pr checks --watch`). CI uruchamia się dla pull requestów, nie dla pushu na gałąź.
- **Zabronione przed fazą 9**: tag `v*` i zmiana `MARKETING_VERSION`. Dozwolona kompilacja częściowa do grupy „Deweloper”
  (`gh workflow run release.yml -f group=Deweloper --ref 003-push-z-serwera`) — push wymaga prawdziwego iPhone'a (faza 4).
- **Testy ręczne wyłącznie na serwerze uruchomionym lokalnie na tym komputerze. Serwer `192.168.18.33` jest produkcyjny — nie
  paruj z nim telefonu testowego, nie wysyłaj z niego testów i nie przypisuj na nim reguł** (research R18).
- Migawki: referencje powstają w CI — pobierz artefakt `snapshots-*`, przejrzyj zrzuty (jasny, ciemny, 200 %) i zacommituj do
  `Tests/AppSnapshotTests/__Snapshots__/`.

---

## Phase 1: Setup (teksty, zależność, szkic PR)

**Purpose**: teksty ze `strings.xml` Androida (zasada VIII, research R14), Firebase w projekcie (R1), szkic PR do przebiegów CI.

- [X] T001 Dopisz w ../zarzadzanie_konmi_android/app/src/main/res/values/strings.xml (sekcja `push_`) dwa teksty tylko dla iOS z komentarzem `<!-- tylko iOS (Horsely iOS 2.1.0) -->` i `tools:ignore="UnusedResources"`: `push_state_no_apns` = „Telefon nie może odbierać powiadomień z serwera — powiadomienia planuje telefon.” oraz `push_hide_previews_hint` = „Aby ukryć treść także dla nich, wybierz w Ustawieniach iOS → Powiadomienia → Pokazuj podglądy: Gdy odblokowany.”; zacommituj i wypchnij w repozytorium Androida (tylko teksty, bez kodu)
- [X] T002 Uruchom `scripts\sync-strings.ps1 -AndroidRepo ..\zarzadzanie_konmi_android` — przenosi teksty `push_*`, `dashboard_notifications_off_*` i dwa nowe do App/Resources/android/ i App/Resources/Localizable.xcstrings; sprawdź `scripts\sync-strings.ps1 -Check` bez różnic i że Tests/AppSnapshotTests/StringsParityTests.swift nie wymaga zmian
- [X] T003 Dodaj pakiet Firebase w project.yml: `packages.Firebase` z `url: https://github.com/firebase/firebase-ios-sdk` i `exactVersion` = najnowsze wydanie 12.x (sprawdź na stronie wydań i wpisz numer w komentarzu), zależność `- package: Firebase` `product: FirebaseMessaging` **tylko** w celu `Horsely` (nie w `HorselyShare`, testach ani pakietach) — research R1, contracts/ci-push.md
- [X] T004 Dodaj w App/Info.plist klucze `FirebaseAppDelegateProxyEnabled` = false, `FirebaseMessagingAutoInitEnabled` = false, `FIREBASE_ANALYTICS_COLLECTION_ENABLED` = false oraz `remote-notification` w `UIBackgroundModes` (obok `fetch`, `processing`); zaktualizuj Tests/AppSnapshotTests/InfoPlistPolicyTests.swift tak, by sprawdzał te wartości i brak Firebase w ShareExtension/Info.plist
- [ ] T005 Commit, push gałęzi, otwórz szkic PR „Push z serwera (iOS 2.1.0)” do `main` (`gh pr create --draft`), zielony `ci.yml` (kompilacja z Firebase, zgodność tekstów)

**Checkpoint**: Firebase się kompiluje, teksty są w aplikacji; zachowanie aplikacji bez zmian.

---

## Phase 2: Foundational (rdzeń push bez Firebase — blokuje US1–US5)

**Purpose**: modele, polityka stanu, klient API i zaślepka serwera ([data-model.md](data-model.md), [contracts/push-api-client.md](contracts/push-api-client.md)).

### Testy (najpierw czerwone)

- [X] T006 [P] Testy `push` w Packages/HorselyCore/Tests/HorselyCoreTests/CapabilitiesTests.swift (utwórz, jeśli brak): `push` rozpoznany, `pushAdmin` i nieznane pominięte, `serialized`; `CapabilitiesChange.pushAppeared` / `pushVanished`
- [X] T007 [P] Testy modeli w Packages/HorselyCore/Tests/HorselyCoreTests/PushModelsTests.swift z plikami JSON w Packages/HorselyCore/Tests/HorselyCoreTests/Resources/push/ (`device.json`, `rules.json`, `problem-400.json` — przykłady z contracts/push-api-client.md): `PushDevice` z datą `"2026-11-04T10:15:00.0000000Z"` (7 cyfr ułamka), `lastDeliveredAt: null`, nieznane pola pominięte; `ClientPushRule` z nieznanym `type` i bez pól opcjonalnych; element bez `description` pominięty bez błędu listy; `DeviceRegistration` koduje dokładnie `{"platform":"Ios","token":…}`; walidacja tokenu „1–4096 znaków, bez białych znaków”
- [X] T008 [P] Testy polityki w Packages/HorselyCore/Tests/HorselyCoreTests/PushPolicyTests.swift: każdy stan z tabeli data-model §2 i **kolejność warunków** (np. brak `push` wygrywa z brakiem zgody, `apnsRefused` przed `permanentFailure`), `notDetermined` → `noPermission(asked: false)`, `denied` → `noPermission(asked: true)`, `localRemindersActive == false` tylko dla `registered`, `registrationAllowed`
- [X] T009 [P] Testy klienta w Packages/HorselyKit/Tests/HorselyKitTests/ApiClientPushTests.swift: `PUT push/device` przy `FixedNetwork.cellular` + `wifiOnly = true` + jedyny adres zdalny → żądanie wysłane (nie `noUsableAddress`); transport zrywający połączenie po wysłaniu ciała 2 razy → trzecia próba udana przy `retryOnDrop: 2`; 3 zerwania → błąd sieci; `GET` bez zmian (jedno ponowienie); `ConnectionLog` dla `PUT push/device` zawiera metodę, ścieżkę i wynik, a **nie** zawiera tokenu
- [X] T010 [P] Test treści podsumowania w Packages/HorselyCore/Tests/HorselyCoreTests/ReminderDigestTests.swift: „Przeterminowane: 2, na dziś i jutro: 3”, same przeterminowane „Przeterminowane: 2”, same bliskie „Na dziś i jutro: 3” (jak Android `ReminderDigest.kt`: części „przeterminowane: X”, „na dziś i jutro: Y” łączone „, ”, pierwsza litera wielka), dopisek o starych danych zachowany

### Implementacja

- [X] T011 [P] Dodaj `pushName = "push"` do `known`, `var push: Bool`, oraz `pushAppeared`/`pushVanished` w `CapabilitiesChange` w Packages/HorselyCore/Sources/HorselyCore/Connection/Capabilities.swift
- [X] T012 [P] Utwórz Packages/HorselyCore/Sources/HorselyCore/Push/PushModels.swift: `DeviceRegistration` (`platform` = "Ios", walidacja tokenu), `PushDevice` (daty przez `SyncMerger.parseInstant`; jeśli nie przyjmuje 7 cyfr ułamka — obetnij ułamek do 3 cyfr przed parsowaniem, research R17), `ClientPushRule`, `[ClientPushRule]` dekodowane z pominięciem elementów bez `description`
- [X] T013 [P] Utwórz Packages/HorselyCore/Sources/HorselyCore/Push/PushPolicy.swift: `PushAuthorization`, `PushRegistration` (pola z data-model §1), `PushFallbackReason` (`serverHasNoPush`, `apnsUnavailable`, `registrationFailed`), `PushState`, `PushInput`, `PushPolicy.decide` i pochodne `localRemindersActive`, `registrationAllowed`
- [X] T014 [P] Zmień `ReminderDigest.dailySummary` w Packages/HorselyCore/Sources/HorselyCore/Notify/ReminderDigest.swift na format bez odmiany liczebników jak w Androidzie (`../zarzadzanie_konmi_android/core/src/main/kotlin/pl/glapa/zk/core/notify/ReminderDigest.kt`)
- [X] T015 [P] Utwórz Packages/HorselyCore/Sources/HorselyCore/Push/PushMessage.swift z `PushKind` (`reminder` | `summary` | `backup` | `analytic` | `test` | `other(String)`) i `PushMessage(userInfo: [AnyHashable: Any])` — `nil` bez klucza `type`; pola `reminderId`, `horseId` (napisy niepuste albo `nil`), `targetDate` (`LocalDate` albo `nil`); klucze `aps`, `gcm.*`, `google.*` i nieznane pominięte (data-model §6) — bez `PushDeepLink` (dochodzi w US5); test podstawowy w Packages/HorselyCore/Tests/HorselyCoreTests/PushMessageTests.swift (rozpoznanie `type`, brak `type` → `nil`)
- [X] T016 Dodaj `retryOnDrop: Int = 0` do `ApiRequest` w Packages/HorselyKit/Sources/HorselyKit/Network/ApiResult.swift i obsłuż w `ApiClient.executeOn` (Packages/HorselyKit/Sources/HorselyKit/Network/ApiClient.swift): do `retryOnDrop` natychmiastowych ponowień przy `.network(sentBody: true, …)` z wpisem „ponowienie zapisu idempotentnego” w dzienniku połączeń; żądanie z `retryOnDrop > 0` traktowane jako idempotentne przy przechodzeniu na kolejny adres
- [X] T017 Dodaj metody API push w nowym pliku Packages/HorselyKit/Sources/HorselyKit/Push/PushApi.swift: `registerDevice(token:)` (`PUT push/device`, `forFile: false`, `retryOnDrop: 2`), `unregisterDevice()` (`DELETE push/device`, `retryOnDrop: 2`), `device()` (`GET push/device`, `404` → `.notRegistered`), `rules()` (`GET push/rules`) — wynik jako enum z rozróżnieniem `ok`, `invalid(400)`, `notRegistered(404)`, `transient` (sieć, 5xx, brak adresu), `access` (401/403/429 — już obsłużone przez `ApiClient`)
- [X] T018 Rozszerz zaślepkę Packages/HorselyKit/Tests/HorselyKitTests/FakeProgram.swift: przełącznik `pushCapability` (dopisuje `push` i `pushAdmin` do `capabilities` w `system/info`), gałęzie `PUT/DELETE/GET push/device` i `GET push/rules` ze stanem (token, `registeredAt`, reguły), wymuszanie `400` / `404` / `503` / zerwania połączenia N razy; kształty z contracts/push-api-client.md
- [X] T019 Skopiuj specs/003-push-z-serwera/contracts/openapi-server-push.json do Packages/HorselyKit/Tests/HorselyKitTests/Resources/openapi-server-push.json (sprawdź, że `Resources` jest zasobem celu testów w Packages/HorselyKit/Package.swift) i dodaj Packages/HorselyKit/Tests/HorselyKitTests/PushOpenApiContractTests.swift: każda para metoda + ścieżka używana przez `PushApi` i obsługiwana przez zaślepkę (`PUT`/`GET`/`DELETE /api/v1/push/device`, `GET /api/v1/push/rules`) istnieje w kopii OpenAPI; ciało `PUT` z `PushApi.registerDevice` ma wyłącznie pola schematu `DeviceRegistration` (`platform`, `token`); odstępstwo dla kształtu odpowiedzi opisane w plan.md „Complexity Tracking” (konstytucja V/VI)
- [X] T020 Dodaj klucze push w Packages/HorselyKit/Sources/HorselyKit/Store/SettingsStore.swift: `push.registered`, `push.tokenPrefix`, `push.registeredAt`, `push.failingSince`, `push.permanentFailure`, `push.deviceRemovedNotice`, `push.apnsRefused`, `push.active`, `push.permissionAsked`, `notifications.offCardDismissed`; właściwość `pushRegistration: PushRegistration` (odczyt/zapis całości) i `clearPushConnectionState()` czyszcząca wszystkie `push.*` poza `push.permissionAsked`; test w Packages/HorselyKit/Tests/HorselyKitTests/SettingsAndLogTests.swift (wartości domyślne = niezarejestrowany, czyszczenie)
- [ ] T021 Commit, push, zielony `ci.yml` (testy T006–T010 przechodzą)

**Checkpoint**: rdzeń push gotowy i przetestowany; aplikacja zachowuje się jak 2.0.2 (poza treścią podsumowania).

---

## Phase 3: User Story 6 — konfiguracja wydania dopuszcza push (Priority: P1, przed kodem rejestracji)

**Goal**: podpisana aplikacja ma uprawnienie do powiadomień zdalnych, rozszerzenie nie; manifest prywatności (FR-030a, FR-030b, FR-032b).
Dokumenty (konstytucja 2.1.0, `SPECYFIKACJA_MOBILE_IOS.md` 1.6, README) są już w commicie `c299130`.

**Independent Test**: kompilacja częściowa do „Deweloper” przechodzi krok „Uprawnienia push” (`aps-environment = production` w
aplikacji, brak w rozszerzeniu, plist Firebase tylko w aplikacji).

- [X] T022 [P] [US6] Dodaj `<key>aps-environment</key><string>development</string>` w App/Horsely.entitlements (ShareExtension/HorselyShare.entitlements bez zmian)
- [X] T023 [P] [US6] Utwórz scripts/ci/verify-push-entitlements.sh według contracts/ci-push.md (wejście: katalog z `Payload/Horsely.app`; `codesign -d --entitlements :-`; aplikacja MUSI mieć `aps-environment` = `production`, `HorselyShare.appex` NIE MOŻE go mieć; `GoogleService-Info.plist` z `BUNDLE_ID = pl.glapa.horsely` tylko w aplikacji; błąd → `::error title=Uprawnienia push::…` i wpis w `GITHUB_STEP_SUMMARY`, kod wyjścia 1)
- [X] T024 [US6] Wywołaj skrypt w .github/workflows/release.yml po rozpakowaniu `.ipa` do `$RUNNER_TEMP/ipa`, przed `upload-build.js`; w scripts/ci/embed-entitlements.sh rozszerz końcowy `grep` o `aps-environment`
- [X] T025 [P] [US6] Utwórz App/PrivacyInfo.xcprivacy według contracts/ci-push.md (`NSPrivacyTracking` false, `NSPrivacyCollectedDataTypeDeviceID` — niepowiązany, bez śledzenia, cel App Functionality; `NSPrivacyAccessedAPICategoryUserDefaults` z powodem `CA92.1`) i dopisz go do zasobów celu `Horsely` w project.yml, jeśli XcodeGen nie dołącza go sam
- [ ] T026 [US6] Commit, push, zielony `ci.yml`; potem kompilacja częściowa `gh workflow run release.yml -f group=Deweloper --ref 003-push-z-serwera` — krok „Uprawnienia push” zielony. Jeśli eksport zgłosi brak możliwości Push Notifications dla `pl.glapa.horsely`, powiedz to wprost i poproś właściciela o włączenie jej w Apple Developer (quickstart §2) — nie pomijaj kroku

**Checkpoint**: wydanie potrafi podpisać aplikację z push; CI pilnuje uprawnień.

---

## Phase 4: User Story 1 — telefon dostaje powiadomienia z serwera (Priority: P1) 🎯 MVP

**Goal**: rejestracja tokenu FCM na serwerze po zgodzie, ponowienia, odbiór na pierwszym planie, brak dubli z powiadomieniami lokalnymi.

**Independent Test**: kompilacja „Deweloper” sparowana z **lokalnym** serwerem z `push` → telefon na liście urządzeń jako iOS;
„Wyślij test” daje powiadomienie przy zablokowanym ekranie i na pierwszym planie (quickstart §4, scenariusze 1–3).

### Testy (najpierw czerwone)

- [X] T027 [P] [US1] Testy w Packages/HorselyKit/Tests/HorselyKitTests/PushRegistrarTests.swift (zaślepka `PushTokenSource`, `FakeProgram` z T018, wstrzykiwany zegar): rejestracja przy starcie, po parowaniu, przy `pushAppeared`, przy zmianie tokenu; przy stale obecnym `push` i `registeredAt` < 24 h — brak `PUT`; sukces zapisuje `registered`, `registeredAt`, `tokenPrefix` (dokładnie 8 znaków), czyści `failingSince`; błąd sieci ustawia `failingSince` tylko przy pierwszym błędzie serii; odstępy ponowień 30, 60, 120, 240, 480, 900, 900 s; jedna rejestracja naraz (dwa wyzwalacze → jeden `PUT`); brak zgody → zero wywołań źródła tokenu i `PUT`
- [X] T028 [P] [US1] Test w Packages/HorselyKit/Tests/HorselyKitTests/NotificationSchedulerTests.swift: przy `localRemindersActive == false` plan usuwa zaplanowane `daily-`/`due-` i nie dodaje nowych; inne identyfikatory zostają (FR-013)

### Implementacja

- [X] T029 [P] [US1] Utwórz Packages/HorselyKit/Sources/HorselyKit/Push/PushTokenSource.swift: protokół `PushTokenSource: Sendable` z `configureIfNeeded()`, `token() async throws -> String` (limit 30 s), `deleteToken() async`, `setAutoInit(_:)`, `tokenChanges: AsyncStream<String>`, oraz `registerForRemoteNotifications()` / `unregisterForRemoteNotifications()` (wywołania systemu wstrzykiwane, by testy nie dotykały `UIApplication`)
- [X] T030 [P] [US1] Utwórz Packages/HorselyKit/Sources/HorselyKit/Push/PushDiagnostics.swift: opisy słowami do dziennika kategorii `push` — „rejestracja ok token=abcd1234…”, „rejestracja nieudana: brak połączenia (zerwane połączenie)”, „rejestracja odrzucona przez serwer (400): token”, „brak tokenu FCM”, „APNs odmówił rejestracji”, „wiadomość type=<rodzaj>”, „wyrejestrowanie: <wynik>”; mapowanie `ApiFailure` → polski opis (bez nazw typów Swift); nigdy pełny token, tytuł, treść ani identyfikatory
- [X] T031 [US1] Utwórz Packages/HorselyKit/Sources/HorselyKit/Push/PushRegistrar.swift (actor): stan wejściowy (`workMode`, `capabilities`, `authorization`) → `PushPolicy.decide`; `reconcile(trigger:)` z wyzwalaczami z research R7; rejestracja `token()` → `PushApi.registerDevice` → zapis `PushRegistration` w `SettingsStore`; ponowienia w aplikacji przez `Task.sleep` (30 s → 900 s), anulowane przy `suspend()` (przejście w tło) i sukcesie; `400` → `permanentFailure`; 24 h od `failingSince` → `permanentFailure`; `didRegisterAPNs()` czyści `apnsRefused`, `didFailAPNs()` ustawia; przy pierwszej konfiguracji `push.active = true`, `setAutoInit(true)`, `registerForRemoteNotifications()`; publikuje bieżący `PushState` (`AsyncStream` lub wywołanie zwrotne) i woła przeliczenie powiadomień po każdej zmianie stanu
- [X] T032 [US1] Utwórz App/Push/FirebasePushTokenSource.swift (jedyny `import FirebaseCore`/`FirebaseMessaging` w projekcie): `configureIfNeeded()` → `FirebaseApp.configure()` raz; `setAPNSToken(_:)` → `Messaging.messaging().apnsToken`; `token()` → `Messaging.messaging().token()` z limitem 30 s; `deleteToken()`; `setAutoInit` → `isAutoInitEnabled`; `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)` → `tokenChanges`; `registerForRemoteNotifications` przez `UIApplication.shared` na głównym wątku
- [X] T033 [US1] Rozszerz `AppDelegate` w App/Shell/QuickActions.swift o `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` (→ `FirebasePushTokenSource.setAPNSToken`, `PushRegistrar.didRegisterAPNs`) i `application(_:didFailToRegisterForRemoteNotificationsWithError:)` (→ `didFailAPNs`, dziennik „APNs odmówił rejestracji”); oraz `application(_:didFinishLaunchingWithOptions:)`: przy `settings.pushActive == true` synchroniczne `configureIfNeeded()` (research R6)
- [X] T034 [US1] Podłącz rejestrator w App/Shell/AppEnvironment.swift: właściwość `pushState` (obserwowana), `PushRegistrar` tworzony z `client`, `settings`, `FirebasePushTokenSource` (w przebiegach testowych — zaślepka bez Firebase); `rescheduleNotificationsNow()` liczy `enabled = settings.notificationsEnabled && workMode != .unset && pushState.localRemindersActive && !launchOptions.isTestRun` dla powiadomień o terminach i podsumowaniu; `startOnline()` → `reconcile(.launch)`; `completePairing` → `reconcile(.paired)`; `refresh` → przekazanie `CapabilitiesChange` z `SyncService.record` do `reconcile(.capabilities(change))` (dopisz zwrot zmiany w Packages/HorselyKit/Sources/HorselyKit/Sync/SyncService.swift, jeśli dziś nie wychodzi poza serwis)
- [X] T035 [US1] Wejście na pierwszy plan i tło w App/Shell/RootView.swift: `scenePhase == .active` → odczyt `authorizationStatus` i `reconcile(.foreground)`; `.background` → `suspend()` rejestratora
- [X] T036 [US1] Zadanie w tle w App/HorselyApp.swift: w `BackgroundTasks.refresh` po `rescheduleNotificationsNow()` wywołaj `reconcile(.background)` (tylko tryb online)
- [X] T037 [US1] Odbiór na pierwszym planie w App/Shell/NotificationDelegate.swift: `willPresent` — wiadomość z kluczem `type` przy `pushState == .registered` → `[.banner, .list, .sound]` (także przy „ukryj szczegóły”, Clarifications Q2), przy innym stanie `[]`; dla `reminder`/`summary` `Task { await environment.refresh(force: true) }`; dziennik „wiadomość type=…”; powiadomienia lokalne (klucz `link`) bez zmian. Rozpoznanie przez `PushMessage(userInfo:)` z T015
- [ ] T038 [US1] Commit, push, zielony `ci.yml`; kompilacja częściowa do „Deweloper”; na iPhonie z **lokalnym** serwerem (quickstart §3) wykonaj scenariusze 1–3 z quickstart §4 i zapisz wynik w specs/003-push-z-serwera/checklists/validation.md (utwórz)

**Checkpoint**: MVP — push z lokalnego serwera dociera, brak dubli.

---

## Phase 5: User Story 2 — tryb awaryjny (Priority: P1)

**Goal**: gdy push nie działa, powiadomienia lokalne działają jak w 2.0.2 i aplikacja zna powód; poprawki powiadomień lokalnych z Androida 2.1.0.

**Independent Test**: serwer bez `push` albo symulator (`-UITestPush apnsRefused`) — powiadomienia lokalne zaplanowane, stan
`fallback` z właściwym powodem.

- [X] T039 [P] [US2] Testy w Packages/HorselyKit/Tests/HorselyKitTests/PushRegistrarTests.swift: serwer bez `push` → `fallback(.serverHasNoPush)` i zero wywołań źródła tokenu; `pushVanished` przy `registered` → `registered = false` **bez** `DELETE`, lokalne wracają; powrót `push` → `pending` → `registered`; `didFailAPNs` → `fallback(.apnsUnavailable)`, potem `didRegisterAPNs` → `pending`; `400` → `fallback(.registrationFailed)` i dalsze ponowienia; 24 h `503` → `registrationFailed`; przejście `pending → registered` anuluje lokalne dopiero po sukcesie; aktualizacja z 2.0.2 (ustawienia bez kluczy `push.*`, `notificationsEnabled = true`, serwer z `push`) → stan `pending` i zaplanowane `daily-`/`due-` do pierwszej udanej rejestracji (FR-034)
- [X] T040 [P] [US2] Argument testów UI `-UITestPush <apnsRefused|registered|pending|noPermission>` w App/Shell/AppEnvironment.swift (`LaunchOptions`, tylko Debug) ustawiający stan rejestratora bez Firebase; scenariusze `push` i `pushNoRules` w App/Shell/DemoProgram.swift (`DemoProgramTransport`: `capabilities` z `push`, odpowiedzi `push/device`, `push/rules`)
- [X] T041 [P] [US2] Opisz nowe argumenty i scenariusze testowe w specs/001-aplikacja-ios-horsely/contracts/test-fixtures.md: `-UITestPush <apnsRefused|registered|pending|noPermission>`, `-UITestOpenPush <reminder|summary|backup|test>` (T059), scenariusze `-UITestProgram push` i `pushNoRules` (dane `capabilities`, `push/device`, `push/rules`); tylko konfiguracja Debug
- [X] T042 [US2] Poprawka 2.1.0: `completePairing` w App/Shell/AppEnvironment.swift ustawia `settings.notificationsEnabled = true`, gdy `authorizationStatus` jest `.authorized`/`.provisional`, i przelicza powiadomienia (podsumowanie planowane po parowaniu); test w Tests/AppSnapshotTests/ShellLogicTests.swift
- [X] T043 [US2] Test UI w Tests/AppUITests/SettingsUITests.swift: `-UITestProgram push -UITestPush apnsRefused` → ekran „Powiadomienia” pokazuje `push_state_no_apns` i ustawienia lokalne (włączenie, godzina, „w dniu terminu”)
- [ ] T044 [US2] Commit, push, zielony `ci.yml`

**Checkpoint**: żadne przypomnienie nie ginie, gdy push nie działa.

---

## Phase 6: User Story 3 — odparowanie wyrejestrowuje telefon (Priority: P1)

**Goal**: `DELETE /push/device` przed usunięciem klucza przy „Rozłącz”, przejściu w tryb samodzielny, usunięciu danych połączenia, cofniętej zgodzie i zmianie serwera.

**Independent Test**: „Rozłącz” na zarejestrowanym telefonie → urządzenie znika z listy w UI webowym lokalnego serwera; bez sieci
odparowanie kończy się w ≤ ~5 s dłużej niż w 2.0.2.

- [X] T045 [P] [US3] Testy w Packages/HorselyKit/Tests/HorselyKitTests/PushRegistrarTests.swift: `unregister` wysyła `DELETE` z kluczem **przed** jego usunięciem (zaślepka `SecretStore` rejestruje kolejność), potem `deleteToken`, `setAutoInit(false)`, `unregisterForRemoteNotifications`, `clearPushConnectionState` (bez `push.permissionAsked`); `401`, brak sieci, `503`, brak odpowiedzi > 5 s → odparowanie kończy się normalnie (limit 5 s, zegar testowy); cofnięta zgoda przy `reconcile(.foreground)` → `unregister`; w trybie samodzielnym i bez `push` brak jakiegokolwiek wywołania źródła tokenu
- [X] T046 [US3] Wywołaj `pushRegistrar.unregister()` przed usunięciem klucza w App/Shell/AppEnvironment.swift: na początku `disconnect()` (przed `pairing.disconnect()`), `completeStandaloneSwitch()` (przed `pairing.switchToStandalone()`), w ścieżce usuwania danych połączenia (znajdź wywołanie w App/Features/Settings/ConnectionSettingsView.swift i DataSettingsView.swift) oraz w `completePairing` przy ponownym parowaniu z innym kluczem/serwerem (stary wyrejestrowany przed zapisem nowego klucza); przerwane przejście trybu (`settings.modeChangePending`) po restarcie → tylko `clearPushConnectionState()` i `deleteToken()`
- [ ] T047 [US3] Commit, push, zielony `ci.yml`; na iPhonie z lokalnym serwerem scenariusze 8–10 z quickstart §4, wynik w checklists/validation.md

**Checkpoint**: odparowany telefon nie dostaje powiadomień.

---

## Phase 7: User Story 4 — ekran „Powiadomienia”, karta Pulpitu, zgoda (Priority: P2)

**Goal**: użytkownik widzi stan push, daty, listę reguł albo powód trybu awaryjnego; karta Pulpitu i pytanie o zgodę ([contracts/ui-push-ios.md](contracts/ui-push-ios.md)).

**Independent Test**: dwie reguły przypisane w UI webowym lokalnego serwera → „Odśwież” pokazuje dokładnie dwa opisy; migawki stanów.

- [X] T048 [US4] Sekcja „Powiadomienia z serwera” w App/Features/Settings/NotificationSettingsView.swift według tabeli contracts/ui-push-ios.md: teksty `push_*`, `GET push/device` i `GET push/rules` w `.task` i po `push_refresh` (przez `PushRegistrar.deviceInfo()`/`rules()`), `404` → ponowna rejestracja i okno `push_device_removed` raz (`deviceRemovedNotice`), błąd reguł → `push_rules_failed`, przy `registered` ukryte włączenie/godzina/„w dniu terminu”, przy „ukryj szczegóły” dopiski `push_hide_background_note` i `push_hide_previews_hint`, przycisk „Otwórz ustawienia powiadomień” przy `noPermission(asked: true)`; identyfikatory `push-state`, `push-rules`, `push-refresh`, `push-open-settings`; daty w formacie `05.11.2026, 08:15`
- [X] T049 [US4] Karta „Powiadomienia o terminach są wyłączone” w App/Features/Dashboard/DashboardView.swift (oba tryby): widoczna przy `!notificationsEnabled`, `pushState != .registered`, `!notificationsOffCardDismissed`; „Włącz” — ta sama ścieżka zgody co w ustawieniach (wyjaśnienie przy `notDetermined`, instrukcja przy `denied`), „Nie pokazuj” → trwałe ukrycie; ikony i kolory jak karta ostrzegawcza na Pulpicie (wzorzec 5.4)
- [X] T050 [US4] Pytanie o zgodę z Pulpitu w App/Features/Dashboard/DashboardView.swift: tryb online, `capabilities.push`, `authorizationStatus == .notDetermined`, `!settings.pushPermissionAsked` → okno `notif_permission_title` + `push_permission_text` → `requestAuthorization` → `pushPermissionAsked = true` → `reconcile(.permissionChanged)`; nigdy z tła
- [X] T051 [US4] Migawki w Tests/AppSnapshotTests/ShellSnapshotTests.swift (jasny, ciemny, 200 %): `NotificationSettings_registered_rules`, `…_registered_empty`, `…_pending`, `…_fallback_noPush`, `…_fallback_apns`, `…_noPermission`, `…_notDetermined` (bez komunikatu o odmowie), `Dashboard_notificationsOffCard` — dane przez zaślepki, bez sieci
- [X] T052 [US4] Test UI w Tests/AppUITests/SettingsUITests.swift: `-UITestProgram push -UITestPush registered` → ekran pokazuje dwa opisy reguł; `pushNoRules` → `push_rules_empty_title`
- [X] T053 [US4] Commit, push; pobierz artefakt `snapshots-*`, przejrzyj i zacommituj referencje; zielony `ci.yml`

**Checkpoint**: SC-008 — stan i powód widoczne od razu.

---

## Phase 8: User Story 5 — dotknięcie powiadomienia otwiera właściwy ekran (Priority: P2)

**Goal**: mapowanie `type` → cel nawigacji, ekran „Kopia zapasowa na serwerze”, brak terminu lokalnie → synchronizacja.

**Independent Test**: po jednym powiadomieniu każdego rodzaju — dotknięcie otwiera ekran z tabeli FR-019.

- [X] T054 [P] [US5] Rozszerz testy w Packages/HorselyCore/Tests/HorselyCoreTests/PushMessageTests.swift: wszystkie wiersze tabeli contracts/push-message.md (`reminder` z i bez `reminderId`, `summary`, `backup`, `analytic`, `test`, nieznany, brak `type` → nie jest wiadomością z serwera); klucze `aps`, `gcm.message_id`, `google.c.a.e` i nieznane pominięte; `targetDate` „2026-13-01” → `nil`; `triggersSync` tylko `reminder`/`summary`
- [X] T055 [US5] Uzupełnij Packages/HorselyCore/Sources/HorselyCore/Push/PushMessage.swift (z T015) o `PushDeepLink.url(for:)` → `horsely://reminders/{id}` | `horsely://reminders` | `horsely://server-backup` | `horsely://dashboard`, `triggersSync`
- [X] T056 [US5] W App/Shell/DeepLinkRouter.swift dodaj host `server-backup` → `DeepLinkTarget.serverBackup` (karta „Więcej”); dla `.reminder(id:)` bez rekordu w magazynie — `refresh(force: true)`, ponowne sprawdzenie, dalej brak → `.reminders`; test w Tests/AppSnapshotTests/ShellLogicTests.swift
- [X] T057 [P] [US5] Utwórz App/Features/Backup/ServerBackupInfoView.swift: tytuł `push_server_backup_title`, tekst `push_server_backup_text`, ikona Material `cloud_off` (Outlined, dodaj do katalogu zasobów, jeśli brak), przycisk powrotu z tekstem jak w Androidzie (sprawdź klucz w strings.xml; domyślnie `common_back`), bez sieci; nawigacja z karty „Więcej” dla `.serverBackup`; migawka `ServerBackupInfo` (jasny, ciemny, 200 %) w Tests/AppSnapshotTests/ShellSnapshotTests.swift
- [X] T058 [US5] `didReceive` w App/Shell/NotificationDelegate.swift: najpierw klucz `link` (jak dziś), inaczej `PushMessage` → `PushDeepLink.url` → `router.handle(url:mode:)`; dla `triggersSync` — synchronizacja w tle
- [X] T059 [US5] Test UI w Tests/AppUITests/SettingsUITests.swift (lub nowy PushNavigationUITests.swift): argument `-UITestOpenPush backup` (Debug) symuluje dotknięcie wiadomości `backup` → widoczny ekran „Kopia zapasowa na serwerze”
- [ ] T060 [US5] Commit, push, referencje migawek, zielony `ci.yml`; na iPhonie z lokalnym serwerem scenariusz 4 z quickstart §4

**Checkpoint**: wszystkie historie gotowe.

---

## Phase 9: Polish i wydanie 2.1.0

- [X] T061 [P] Test prywatności dziennika w Packages/HorselyKit/Tests/HorselyKitTests/PushRegistrarTests.swift: po scenariuszu rejestracja → wiadomość → wyrejestrowanie (`FakeProgram`, włączony dziennik połączeń) żaden plik dziennika nie zawiera pełnego tokenu, tytułu ani treści; są tylko prefiksy 8 znaków i opisy słowami (FR-028, SC-009)
- [X] T062 [P] Test w Tests/AppSnapshotTests/InfoPlistPolicyTests.swift (`testStandaloneWorkMakesNoNetworkRequests` lub nowy): tryb samodzielny i serwer bez `push` nie wywołują `PushTokenSource` ani `registerForRemoteNotifications` (FR-027, SC-006)
- [ ] T063 Ustaw `MARKETING_VERSION: "2.1.0"` w project.yml i zaktualizuj domyślną wersję w `AppEnvironment` (`"2.0.2"` → `"2.1.0"` przy `BackupService`); utwórz CHANGELOG.md (jeśli brak) z sekcją `[2.1.0]` — Dodano: powiadomienia push z serwera w trybie z serwerem, ekran „Powiadomienia” z listą reguł, karta Pulpitu, ekran „Kopia zapasowa na serwerze”; Zmieniono: powiadomienia lokalne o terminach w trybie z serwerem z działającym push, treść dziennego podsumowania; zaktualizuj README.md (status 2.1.0)
- [ ] T064 Oznacz PR jako gotowy, zielony `ci.yml`, scal do `main` (po zgodzie właściciela), zielony `ci.yml` na `main` (z testami UI)
- [ ] T065 Tag `v2.1.0` na `main` → `release.yml`: krok „Uprawnienia push” zielony, wysyłka do TestFlight; podaj wersję, numer kompilacji i link do przebiegu `gh run`; brak sekretów lub klucza ASC → powiedz wprost (konstytucja)
- [ ] T066 Lista kontrolna quickstart §4 (scenariusze 1–12) na iPhonie 15 Pro z **lokalnym** serwerem, wynik w checklists/validation.md; App Privacy w App Store Connect (krok właściciela, quickstart §2); po zaliczeniu — kompilacja dla grupy „Właściciele”
- [ ] T067 Zaktualizuj pamięć projektu (`testflight-last-build.md`: 2.1.0, numer kompilacji, data, przypomnienie po 80 dniach) i zaznacz zadania w tasks.md

---

## Dependencies & Execution Order

- **Phase 1 → Phase 2 → Phase 3 (US6)** — kolejno; US6 to bramka wydania, ale nie blokuje kodu US1 (można robić równolegle z Phase 4, jeśli kompilacja częściowa w T038 poczeka na T026).
- **Phase 4 (US1)** zależy od Phase 2 i (dla testu na telefonie) od US6.
- **Phase 5 (US2)** i **Phase 6 (US3)** zależą od `PushRegistrar` (T031) i `AppEnvironment` (T034); między sobą niezależne (różne metody w `AppEnvironment` — robić kolejno, bo ten sam plik).
- **Phase 7 (US4)** zależy od stanu push (T034) i API ekranu (T017); **Phase 8 (US5)** — od T037 (wiadomości na pierwszym planie).
- **Phase 9** po wszystkich historiach.

Kolejność historii: US6 → US1 (MVP) → US2 → US3 → US4 → US5 → wydanie.

## Parallel Opportunities

- Phase 2: T006–T010 (testy w różnych plikach) razem; potem T011–T015 razem; T016–T020 kolejno (wspólne pliki HorselyKit, zaślepka, test zgodności z OpenAPI w T019).
- Phase 3: T022, T023, T025 razem.
- Phase 4: T027, T028, T029, T030 razem; potem T031 → T032/T033 → T034 → T035–T037.
- Phase 8: T054 i T057 razem.
- Phase 9: T061 i T062 razem.

### Przykład (Phase 2)

```text
Równolegle: T006 CapabilitiesTests, T007 PushModelsTests, T008 PushPolicyTests, T009 ApiClientPushTests, T010 ReminderDigestTests
Potem równolegle: T011 Capabilities.swift, T012 PushModels.swift, T013 PushPolicy.swift, T014 ReminderDigest.swift, T015 PushMessage.swift
```

## Implementation Strategy

1. **MVP = Phase 1–4** (fundament, uprawnienia, rejestracja i odbiór): po T038 push z lokalnego serwera działa na iPhonie z
   kompilacji „Deweloper”, a lokalne przypomnienia znikają dopiero po udanej rejestracji.
2. **Bezpieczeństwo przed wygodą**: US2 (tryb awaryjny) i US3 (wyrejestrowanie) przed ekranem i nawigacją — bez nich wydanie jest
   ryzykowne (utracone przypomnienia, prywatność).
3. **US4, US5** — wygoda i zrozumiałość; każda kończy się zielonym CI i referencjami migawek.
4. **Jedno wydanie 2.1.0** na końcu (Phase 9); kompilacje częściowe tylko do „Deweloper” i tylko do testów z lokalnym serwerem.
