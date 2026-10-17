# Tasks: Poprawki 2.0.2 — blokada aplikacji, zdjęcia koni z programu, czytelny raport treningów

**Input**: Design documents from `specs/002-poprawki-2-0-2/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: wymagane — konstytucja, zasada VI, oraz FR-005, FR-016; właściciel nie weryfikuje aplikacji między fazami,
więc testy w CI są jedyną bramką faz 1–5. Testy piszemy przed implementacją i najpierw muszą nie przechodzić.

**Organization**: zadania pogrupowane według historii użytkownika (US1 blokada, US2 zdjęcia, US3 raport).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: można wykonać równolegle (inne pliki, brak zależności od nieukończonych zadań)
- **[Story]**: historia użytkownika (US1, US2, US3)

## Zasada jednego wydania (obowiązuje w fazach 1–7)

Fazy 1–7 kończą się **wyłącznie** commitem i pushem na `main` oraz zielonym `ci.yml`
(`gh run watch --exit-status <id>`). **Zabronione przed fazą 8**: tag `v*`, `workflow_dispatch` dla `release.yml`
(także kompilacja częściowa dla grupy „Deweloper”), zmiana `MARKETING_VERSION` w `project.yml`. Jedyna wysyłka
do TestFlight — faza 8 ([contracts/release.md](contracts/release.md)).

---

## Phase 1: Setup (teksty i specyfikacje)

**Purpose**: teksty z `strings.xml` Androida i zapis zmiany zakresu (zasada VIII, FR-018, FR-019) — potrzebne US3,
nie blokują US1 i US2.

- [X] T001 Dodaj teksty `reports_show_trainings` („Pokaż treningi (%1$d)”), `reports_hide_trainings` („Ukryj treningi”), `reports_chart_metric_count` („Liczba treningów”), `reports_chart_metric_time` („Łączny czas”), `reports_chart_rider_groups_title` („Treningi według grup”), `reports_chart_others` („Pozostałe”) w ../zarzadzanie_konmi_android/app/src/main/res/values/strings.xml (sekcja raportów) i zacommituj w repozytorium Androida (tylko teksty, bez kodu); jeśli lint Androida zgłasza `UnusedResources`, oznacz nowe wpisy `tools:ignore="UnusedResources"` do czasu zadania T031 i potwierdź zielone CI Androida po pushu — _wykonano: commit 808e3c8 na gałęzi 005-horsely-2-0-1 (push przez schannel); Android nie ma CI w GitHub Actions, a lokalnie brak JDK, więc lint nie został uruchomiony — wpisy mają `tools:ignore="UnusedResources"`_
- [X] T002 Uruchom scripts/sync-strings.ps1, aby przenieść nowe teksty do zasobów aplikacji iOS (App/Resources), i sprawdź, że Tests/AppSnapshotTests/StringsParityTests.swift nie wymaga zmian
- [X] T003 [P] Opisz zmianę zakresu w SPECYFIKACJA_MOBILE_IOS.md: historia „Raporty” scenariusz 5 i FR-M-RAP-03 — wykres słupkowy grup (liczba / łączny czas, > 12 grup → 11 + „Pozostałe”), lista treningów zwinięta pod „Pokaż treningi (N)”; wpis w historii wersji dokumentu (2.0.2)
- [X] T004 [P] Opisz tę samą zmianę zakresu w ../zarzadzanie_konmi_android/SPECYFIKACJA_MOBILE_ANDROID.md (scenariusz 5 „Treningi jeźdźca”, FR-M-RAP-03) i zacommituj w repozytorium Androida
- [ ] T005 Commit i push na `main` (iOS), poczekaj na zielony `ci.yml` — bez taga

**Checkpoint**: teksty i specyfikacje gotowe; CI zielone.

---

## Phase 2: Foundational

Brak zadań blokujących wszystkie historie — US1, US2 i US3 dotykają rozłącznych plików i mogą iść po kolei albo równolegle.

---

## Phase 3: User Story 1 — Wejście do aplikacji po odblokowaniu (Priority: P1) 🎯 MVP

**Goal**: po udanym odblokowaniu aplikacja nie blokuje się ponownie; blokada wraca tylko po zimnym starcie albo > 5 min w tle (FR-001…FR-005).

**Independent Test**: `AppLockMachineTests` w `swift test` HorselyKit (CI) przechodzą dla wszystkich sekwencji z [data-model.md](data-model.md#applockmachine-horselykit-w-pamięci); kompilacja aplikacji zielona.

### Tests for User Story 1 ⚠️ (najpierw czerwone)

- [X] T006 [US1] Napisz Packages/HorselyKit/Tests/HorselyKitTests/AppLockMachineTests.swift z wstrzykiwanym czasem: (a) `launch` z `enabled` → `locked`; `authenticationStarted`; `willResignActive`; `didBecomeActive(t)`; `authenticationFinished(true)`; `didBecomeActive(t+1s)` → `locked == false` (regresja pętli); (b) tło 4 min 59 s → brak blokady; (c) tło 5 min 1 s → `locked` i `autoPromptAvailable`; (d) `authenticationFinished(false)` → zostaje `locked`, `autoPromptAvailable == false` (okno nie otwiera się samo drugi raz); (e) `didEnterBackground` w stanie zablokowanym, powrót po 10 min → jedno odblokowanie wystarcza; (f) `didBecomeActive` bez wcześniejszego `didEnterBackground` nigdy nie blokuje; (g) `didBecomeActive(passcode: false)` → blokada wyłączona i komunikat; (h) `willResignActive` podczas `authenticating` nie ustawia `covered`; (i) `enabled == false` → nigdy `locked` ani `covered`

### Implementation for User Story 1

- [X] T007 [US1] Dodaj `public struct AppLockMachine` w Packages/HorselyKit/Sources/HorselyKit/Security/AppLock.swift z polami `enabled`, `locked`, `covered`, `backgroundedAt: Date?` (tylko w pamięci, ustawiane przy `didEnterBackground` tylko gdy `!locked`, czyszczone przy każdym `didBecomeActive` i przy udanym odblokowaniu), `authenticating`, `autoPromptAvailable` (raz na epizod blokady) oraz metodami zdarzeń wg tabeli przejść w data-model.md; próg z `AppLockPolicy.timeout`; T006 musi przejść
- [X] T008 [US1] Przebuduj `AppLockState` w App/Features/Lock/LockOverlay.swift na cienką powłokę `@Observable` nad `AppLockMachine`: `sceneChanged` mapuje `ScenePhase` na zdarzenia z `Date()`, `unlock()` woła `authenticationStarted`/`authenticationFinished`; usuń odczyt i zapis `settings.appLockLastBackgroundAt`; zachowaj wyłączenie blokady w testach (`settings.appLockEnabled && !launchOptions.isTestRun` w App/Shell/AppEnvironment.swift:126)
- [X] T009 [US1] W `LockOverlay` (App/Features/Lock/LockOverlay.swift) zmień `.task` tak, aby samoczynne uwierzytelnienie startowało tylko gdy `autoPromptAvailable` (nowa metoda `AppLockState.autoUnlock()`), a przycisk „Odblokuj” zawsze wywoływał `unlock()`
- [X] T010 [US1] Oznacz `appLockLastBackgroundAt` w Packages/HorselyKit/Sources/HorselyKit/Store/SettingsStore.swift jako nieużywany (komentarz, bez usuwania klucza — brak migracji) i zaktualizuj ewentualne odwołania w Packages/HorselyKit/Tests/HorselyKitTests/SettingsMaintenanceTests.swift
- [ ] T011 [US1] Commit i push na `main`, zielony `ci.yml` (testy pakietów, migawkowe, UI) — bez taga

**Checkpoint**: blokada naprawiona i zabezpieczona testem sekwencji.

---

## Phase 4: User Story 2 — Miniatury zdjęć koni z programu (Priority: P2)

**Goal**: miniatury zdjęć koni z programu widoczne bez restartu i bez połączenia; „Pokaż zdjęcie” pobiera oryginał; tryb samodzielny po przejściu ma miniatury (FR-006…FR-011).

**Independent Test**: testy HorselyKit ze zaślepką programu (`FakeProgram`) i test UI listy koni z miniaturą przechodzą w CI.

### Tests for User Story 2 ⚠️ (najpierw czerwone)

- [X] T012 [P] [US2] Napisz Packages/HorselyKit/Tests/HorselyKitTests/HorsePhotoSourceTests.swift (zaślepka `FakeProgram` / `URLProtocol`): (a) lokalna miniatura → zwrócona bez żądania; (b) brak miniatury, jest lokalny oryginał → miniatura wygenerowana i zapisana jako przypięta, bez żądania; (c) tryb online, brak plików → `GET attachments/{id}/thumbnail`, plik zapisany jako przypięty, drugi odczyt bez żądania; (d) brak sieci → `nil` bez błędu; (e) 404 → wynik „niedostępne”; (f) tryb samodzielny, brak plików → `nil` bez żądania; (g) pełne zdjęcie: brak oryginału online → pobranie `attachments/{id}/content`; (h) zmiana zdjęcia konia w programie (nowy `photoAttachmentId` po synchronizacji) → `HorseDirectory.thumbnail(for:)` zwraca nową miniaturę (FR-010); (i) 30 koni ze zdjęciami, zaślepka z opóźnieniem 300 ms na żądanie → wszystkie miniatury załadowane w < 10 s czasu testu i nie więcej niż 4 żądania jednocześnie (SC-002)
- [X] T013 [P] [US2] Dodaj test w Packages/HorselyKit/Tests/HorselyKitTests/HorseRepositoryTests.swift lub nowym pliku: po scenariuszu przejścia na tryb samodzielny (oryginał zdjęcia konia pobrany, brak miniatury) źródło miniatury zwraca obraz bez programu (FR-011)

### Implementation for User Story 2

- [X] T014 [US2] Dodaj `AttachmentStore.thumbnail(attachmentId:) async -> ThumbnailResult` (`.image(Data)`, `.unavailable`, `.failed`) w Packages/HorselyKit/Sources/HorselyKit/Files/AttachmentStore.swift z kolejnością: plik `thumbnail` → plik `original` (`ImagePreparer.thumbnail`, `files.write(..., kind: .thumbnail, pinned: true)`, `upsertFile`) → online `GET attachments/{id}/thumbnail` (istniejąca ścieżka z `thumbnail(_:)`, 404 → `.unavailable`); `thumbnail(_ attachment:)` korzysta z tej samej ścieżki; T012(a–f) muszą przejść
- [X] T015 [US2] W Packages/HorselyKit/Sources/HorselyKit/Repositories/HorseRepository.swift przekieruj `thumbnailData(attachmentId:)` i `originalData(attachmentId:)` na `AttachmentStore` (oryginał przez `content(_:)` z rekordu `LocalAttachment`) — decyzja: jeśli `grep` w App/ i Packages/ nie pokaże innych wywołań niż HorseDirectory i HorsePhotoSheet, **usuń** obie metody (wywołujący przechodzą na `AttachmentStore`), w przeciwnym razie przekieruj; T012(g) i T013 muszą przejść
- [X] T016 [US2] W App/Shell/HorseDirectory.swift używaj źródła z T014; dodaj `failed: Set<String>` (bez ponawiania przy każdej emisji listy) i `unavailable: Set<String>` (404, do końca sesji) oraz `func retryMissingThumbnails() async` czyszczącą `failed` i doładowującą brakujące; pobieranie brakujących miniatur równoległe (`withTaskGroup`) z limitem 4 jednocześnie, aktualizacja `thumbnails` po każdej gotowej; T012(h, i) muszą przejść
- [X] T017 [US2] W App/Shell/AppEnvironment.swift wywołaj `horseDirectory.retryMissingThumbnails()` po zakończonej synchronizacji w `refresh(force:)` (także pierwszej i wymuszonej przeciągnięciem w dół), przy powrocie aplikacji na pierwszy plan (`.active` w `RootView.onChange(of: scenePhase)`, także gdy `refresh(force: false)` kończy się wcześniej, bo odświeżenie nie jest należne) oraz po `prepareStandaloneSwitch` (miniatury z pobranych oryginałów, FR-011) — tak rozumiemy „kolejne odświeżenie” z FR-008
- [X] T018 [US2] W App/Features/Horses/HorsePhotoSheet.swift (podgląd „Pokaż zdjęcie”) pobieraj oryginał przez `environment.attachments.content(_:)`, z dotychczasowym wskaźnikiem ładowania i komunikatem jak przy otwieraniu załącznika, gdy program niedostępny
- [X] T019 [US2] Dodaj scenariusz `photos` do zaślepki programu w App/Shell/DemoProgram.swift (`-UITestProgram photos`: sparowany program z koniem, który ma `photoAttachmentId`, rekord załącznika obrazu oraz odpowiedzi `attachments/{id}/thumbnail` i `attachments/{id}/content` z małym PNG w kodzie) i dodaj test UI w Tests/AppUITests/HorsesFlowUITests.swift (`-UITestMode online -UITestProgram photos`): na liście koni awatar konia ma obraz (identyfikator dostępności awatara, np. `horse-avatar-photo`) w ≤ 10 s; jeśli brak identyfikatora, dodaj go w `HorseAvatar`
- [ ] T020 [US2] Commit i push na `main`, zielony `ci.yml` — bez taga; jeśli zmieniły się migawki koni lub Pulpitu (Tests/AppSnapshotTests/HorsesSnapshotTests.swift, ShellSnapshotTests.swift), pobierz artefakt `snapshots-*`, przejrzyj zrzuty i zacommituj referencje

**Checkpoint**: miniatury działają online, offline i po przejściu na tryb samodzielny.

---

## Phase 5: User Story 3 — Czytelny raport „Treningi jeźdźca” (Priority: P3)

**Goal**: sumy na górze we wszystkich raportach; w „Treningach jeźdźca” kafelki podsumowania, wykres grup, karty grup, zwinięta lista; CSV/PDF bez zmian wartości (FR-012, FR-012a…FR-017, [contracts/ui-reports.md](contracts/ui-reports.md)).

**Independent Test**: testy HorselyCore (`GroupBarChartTests`, wzorce `golden/rider-trainings/*` i `training-summary/*` bez zmian) i migawki raportów w CI.

**Zależność**: Phase 1 (teksty T001–T002).

### Tests for User Story 3 ⚠️ (najpierw czerwone)

- [X] T021 [P] [US3] Napisz Packages/HorselyCore/Tests/HorselyCoreTests/GroupBarChartTests.swift: `ReportCharts.riderGroups(_:metric:)` — miara `count` i `minutes` równa `groups[].count` / `groups[].totalMinutes` w kolejności raportu; pusty raport → `nil`; 13 grup → 11 + „Pozostałe” z sumą reszty; `ChartDescriptions.groupBars` zawiera każdą etykietę i wartość (czas w formacie FR-M-RAP-04)
- [X] T022 [P] [US3] Dodaj test w Packages/HorselyCore/Tests/HorselyCoreTests/ReportsParityTests.swift: dla raportu „Podsumowanie treningów” z ≥ 1 wartością parametru `ReportCharts.progress` zwraca wykres, a `availableParameters` zawiera ten parametr (FR-017); potwierdź, że wzorce `golden/rider-trainings/*` przechodzą bez zmian plików

### Implementation for User Story 3

- [X] T023 [US3] Dodaj w Packages/HorselyCore/Sources/HorselyCore/Reports/ChartData.swift: `public enum GroupMetric { case count, minutes }`, `public struct GroupBarChart` (`metric`, `bars: [(label, value: Int)]` — w praktyce struktura `GroupBar`), `ReportCharts.riderGroups(_ report: RiderTrainingsReport, metric:) -> GroupBarChart?` (bez przeliczania, > 12 grup → 11 + „Pozostałe”) i `ChartDescriptions.groupBars(_:)`; T021 musi przejść
- [X] T024 [US3] W App/Features/Reports/ReportScaffold.swift przenieś kartę sum (`report-totals`) przed `charts()` (kolejność: sumy → wykresy → wiersze → uwagi, dla wszystkich raportów — FR-012a, jak w Androidzie: CostReportScreen.kt, HorseBalanceScreen.kt, TrainingSummaryScreen.kt) i dodaj parametr `collapsibleRows: Bool = false` — wiersze pod przyciskiem `report-rows-toggle` „Pokaż treningi (N)” / „Ukryj treningi” (teksty z T001), domyślnie zwinięte
- [X] T025 [US3] Dodaj `GroupBarChartView` w App/Features/Reports/Charts/ReportChartViews.swift (Swift Charts, `BarMark` poziomy, kolor `HorselyColor.primary`, wartości przy słupkach, czas „X h Y min”, etykieta dostępności z `ChartDescriptions.groupBars`, identyfikator `report-chart-groups`, czytelny przy tekście 200 %)
- [X] T026 [US3] W App/Features/Reports/RiderReportViews.swift (`RiderTrainingsReportView`): kafelki podsumowania z `report.total` (liczba, łączny czas, średnia ocena „—” bez ocen, koszt) w slocie sum, przełącznik segmentowy `report-chart-metric` „Liczba treningów / Łączny czas” + `GroupBarChartView`, karty grup `report-group-<n>` jak w Androidzie, `collapsibleRows: true`; `pdfCharts` — oba warianty wykresu przez `ChartRendering.image` z tytułem `reports_chart_rider_groups_title` i opisem `ChartDescriptions.groupBars`
- [X] T027 [US3] Sprawdź App/Features/Reports/TrainingSummaryReportView.swift po zmianie scaffoldu: sumy „Razem” nad wierszami rodzajów, wykres postępu widoczny przy danych; popraw tylko, jeśli test T022 lub migawka wykazuje problem
- [X] T028 [US3] Dodaj migawki w Tests/AppSnapshotTests/ReportsSnapshotTests.swift: `testRiderTrainingsSummaryAndChart` (jeden jeździec, kilka koni) i `testRiderTrainingsAllRiders` (wszyscy jeźdźcy) — jasny, ciemny, tekst 200 %; istniejące migawki raportów zmienią się przez sumy na górze
- [ ] T029 [US3] Commit i push na `main`; z przebiegu `ci.yml` pobierz artefakt `snapshots-*`, przejrzyj nowe i zmienione zrzuty raportów (sumy i wykres widoczne bez przewijania na iPhone 15 Pro, SC-004), zacommituj referencje do Tests/AppSnapshotTests/__Snapshots__/ i doprowadź `ci.yml` do zielonego — bez taga

**Checkpoint**: raporty czytelne, eksport bez zmian wartości.

---

## Phase 6: Polish & Cross-Cutting

- [X] T030 [P] Zaktualizuj README.md (sekcja „Status”: wydanie 2.0.2 z trzema poprawkami) i wpis historii zmian w SPECYFIKACJA_MOBILE_IOS.md
- [ ] T031 [P] Utwórz zadanie dla repozytorium Androida (osobna sesja lub issue w `zarzadzanie_konmi_android`): wykres grup i zwijana lista w `RiderReportScreens.kt` zgodnie z T004 — nie blokuje wydania iOS
- [ ] T032 Przegląd zgodności z [spec.md](spec.md): każdy FR-001…FR-019 ma zadanie i test; przejrzyj ostrzeżenia kompilacji w logu `ci.yml` (ostrzeżenia jako błędy)
- [ ] T033 Commit i push na `main`, zielony `ci.yml` — bez taga

---

## Phase 7: Bramka przed wydaniem

- [ ] T034 Potwierdź warunki wejścia z [contracts/release.md](contracts/release.md): T001–T033 ukończone, ostatni `ci.yml` na `main` zielony, zrzuty przejrzane, obie specyfikacje zaktualizowane; potwierdź, że weryfikacja wydajności jest świadomie pominięta (plan.md, „Complexity Tracking”); sprawdź, że w fazach 1–6 nie powstał tag `v*` ani przebieg `release.yml` (`gh run list --workflow release.yml --limit 3`)

---

## Phase 8: Wydanie 2.0.2 (jedyna wysyłka do TestFlight)

- [ ] T035 Ustaw `MARKETING_VERSION: "2.0.2"` w project.yml, commit „Wydanie 2.0.2”, push na `main`, zielony `ci.yml`
- [ ] T036 Utwórz tag `v2.0.2` na tym commicie i wypchnij go; obserwuj `release.yml` (`gh run watch --exit-status`) — archiwum, podpis, wysyłka do TestFlight, grupa „Właściciele”; przy braku sekretów podpisywania lub klucza App Store Connect zgłoś to wprost
- [ ] T037 Raport dla właściciela: wersja 2.0.2, numer kompilacji (`GITHUB_RUN_NUMBER`), wynik wysyłki, link do przebiegu `gh run`; przekaż listę ręczną z [quickstart.md](quickstart.md#3-lista-ręczna-dla-właściciela-iphone-15-pro-kompilacja-202); zaktualizuj pamięć „ostatnia kompilacja TestFlight” (data + przypomnienie po 80 dniach)
- [ ] T038 Po odpowiedzi właściciela zapisz wynik listy ręcznej (punkty 1–3 quickstart.md: zaliczony / niezaliczony z opisem) w specs/002-poprawki-2-0-2/quickstart.md, sekcja „Wynik listy ręcznej 2.0.2”; dopiero przy wyniku pozytywnym oznacz 2.0.2 jako wydaną w README.md (konstytucja: „wersja jest wydana po ręcznej liście kontrolnej”); przy wyniku negatywnym — nowa specyfikacja poprawki 2.0.3, bez ponownego tagowania 2.0.2. Weryfikacja wydajności NFR-M-01…03 pominięta decyzją właściciela (plan.md, „Complexity Tracking”)

---

## Dependencies & Execution Order

- **Phase 1** → wymagana przez US3 (teksty); US1 i US2 mogą startować od razu.
- **US1 (Phase 3)**, **US2 (Phase 4)**, **US3 (Phase 5)** — rozłączne pliki, niezależne; zalecana kolejność priorytetów P1 → P2 → P3, każda zakończona zielonym CI.
- **Phase 6** po wszystkich historiach; **Phase 7** po Phase 6; **Phase 8** wyłącznie po Phase 7.
- W historii: testy (czerwone) → model/logika w pakiecie → aplikacja → commit + CI.

```text
Phase 1 ──────────────┐
Phase 3 (US1) ────────┤
Phase 4 (US2) ────────┼──► Phase 6 ──► Phase 7 ──► Phase 8 (tag v2.0.2, TestFlight)
Phase 5 (US3, po P1) ─┘
```

## Parallel Example

```text
# US2 — testy równolegle:
T012 HorsePhotoSourceTests.swift
T013 test trybu samodzielnego

# US3 — testy równolegle:
T021 GroupBarChartTests.swift
T022 ReportsParityTests.swift (FR-017)

# Phase 1:
T003 SPECYFIKACJA_MOBILE_IOS.md  |  T004 SPECYFIKACJA_MOBILE_ANDROID.md
```

## Implementation Strategy

- **MVP = US1** (blokada) — krytyczny błąd odcinający dostęp do danych; mimo to **nie** jest wydawany osobno: zgodnie
  z wymogiem właściciela wszystkie historie trafiają do jednej kompilacji 2.0.2.
- Przyrosty: każda historia kończy się zielonym CI na `main`, co jest dowodem działania zamiast ręcznej weryfikacji.
- Jedno wydanie: Phase 8 po bramce Phase 7; ręczna lista kontrolna wykonywana raz przez właściciela na 2.0.2.
