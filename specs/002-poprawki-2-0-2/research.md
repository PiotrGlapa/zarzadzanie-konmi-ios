# Research: Poprawki 2.0.2

Wszystkie niewiadome z „Technical Context” rozstrzygnięte poniżej. Odwołania do kodu — stan na `e885f6e` (wydanie 2.0.1).

## R1. Przyczyna pętli blokady i model stanu

**Ustalenie**: `AppLockState.sceneChanged` (`App/Features/Lock/LockOverlay.swift`) przy każdym `.active` liczy
`AppLockPolicy.requiresUnlock` od trwałego `settings.appLockLastBackgroundAt`. Znacznik jest zapisywany tylko przy
`.background` w stanie odblokowanym i nigdy nie jest zerowany. Okno `LocalAuthentication` przełącza scenę
`inactive → active`, więc po udanym uwierzytelnieniu stary znacznik (> 5 min) natychmiast blokuje aplikację; na nowym
ekranie blokady `.task` znowu otwiera okno uwierzytelniania — pętla. Dodatkowo `requiresUnlock(backgroundedAt: nil)`
zwraca `true`, więc samo „wyzerowanie” znacznika bez zmiany modelu też blokowałoby przy każdej aktywacji.

**Decision**: Wydzielić czystą maszynę stanów `AppLockMachine` (struct, `HorselyKit/Security/AppLock.swift`) ze
zdarzeniami `launch`, `didEnterBackground(at:)`, `willResignActive`, `didBecomeActive(at:, passcode:)`,
`authenticationStarted`, `authenticationFinished(success:)` i stanem `locked`, `covered`, `backgroundedAt` (tylko w
pamięci, ustawiane przy `.background` w stanie odblokowanym, czyszczone przy każdym `.active` i przy udanym
odblokowaniu), `autoPromptAvailable` (jedno samoczynne okno na epizod blokady). Zimny start: `locked = enabled`
(jak dotąd). `AppLockState` w aplikacji staje się cienką powłoką `@Observable` nad maszyną; czas z wstrzykiwanego
zegara (zasada VI). Klucz `appLock.lastBackgroundAt` przestaje być używany (zostaje w `SettingsStore` bez odczytu —
brak migracji, brak utraty danych).

**Rationale**: Proces zabity w tle i tak startuje zablokowany, więc trwały znacznik nic nie daje, a był źródłem błędu.
Czysta maszyna stanów jest testowalna w `swift test`/CI bez symulatora i bez `LocalAuthentication`.

**Alternatives considered**: (a) zerowanie znacznika po odblokowaniu + zmiana `requiresUnlock(nil) → false` —
minimalne, ale nadal rozproszona logika w widoku i bez testu sekwencji; (b) ignorowanie `.active` podczas
uwierzytelniania flagą — nie rozwiązuje zablokowania po `.background` w stanie zablokowanym ani starego znacznika.

## R2. Miniatury zdjęć koni z programu

**Ustalenie**: `HorseDirectory.loadMissingThumbnails` → `HorseRepository.thumbnailData(attachmentId:)` czyta tylko
plik `kind: .thumbnail` z magazynu. Dla zdjęć z programu pliku nie ma. `AttachmentStore.thumbnail(_:)` już umie pobrać
`GET attachments/{id}/thumbnail` i zapisać plik przypięty (`pinned: true`) — używa go tylko siatka załączników.
Przy przejściu na tryb samodzielny `prepareStandaloneSwitch` pobiera **oryginały** wszystkich załączników, ale nie
tworzy miniatur, więc w trybie samodzielnym awatar też byłby pusty. `HorsePhotoSheet` („Pokaż zdjęcie”) czyta tylko
lokalny oryginał.

**Decision**:
1. `AttachmentStore.thumbnail(attachmentId:)` — kolejność: lokalna miniatura → lokalny oryginał (wygenerowanie
   miniatury `ImagePreparer.thumbnail`, zapis przypięty) → w trybie online pobranie z programu (istniejąca ścieżka).
   `HorseDirectory` korzysta z tego źródła zamiast `HorseRepository.thumbnailData`.
2. Pełne zdjęcie konia: `AttachmentStore.content(_:)` (istniejąca ścieżka pobierania oryginału) zamiast
   `HorseRepository.originalData`.
3. Ponawianie: `HorseDirectory` pamięta identyfikatory nieudanych pobrań w bieżącym cyklu i nie ponawia ich przy każdej
   emisji listy; `AppEnvironment.refresh` po zakończonej synchronizacji wywołuje `horseDirectory.retryMissingThumbnails()`
   (FR-007, FR-008). Odpowiedź 404 (zdjęcia już nie ma) — oznaczenie „niedostępne” do końca sesji.
4. Przejście na tryb samodzielny: po pobraniu oryginałów miniatury zdjęć koni powstają przez punkt 1 (lokalny
   oryginał → miniatura), więc działają bez programu (FR-011); test w HorselyKit.

**Rationale**: Wykorzystuje istniejące, przetestowane ścieżki pobierania (zasada VII), bez nowych punktów API.
Zachowanie zgodne z Androidem 2.0.1 (miniatura z programu, przypięta).

**Alternatives considered**: pobieranie miniatur w `SyncService` przy scalaniu koni — wiązałoby synchronizację rekordów
z plikami i wydłużało pierwsze pobieranie; odrzucone.

## R3. Układ raportów i wykres „Treningi jeźdźca”

**Ustalenie**: `ReportScaffold.tableContent` rysuje: wykresy → wiersze → karta sum (na końcu) → uwagi — dla wszystkich
raportów. Specyfikacja główna (tabela ekranów, „Raporty”) wymaga „filtry → sumy → wykresy → wiersze”, a Android 2.0.1
pokazuje sumy na górze. „Treningi jeźdźca” nie ma wykresu (`pdfCharts: []`).

**Decision**:
1. `ReportScaffold`: karta sum przed wykresami dla wszystkich raportów (naprawa niezgodności ze specyfikacją; zmiana
   tylko kolejności, wartości bez zmian). Nowy parametr `collapsibleRows: Bool` (domyślnie `false`) — wiersze pod
   przyciskiem „Pokaż treningi (N)” / „Ukryj treningi”.
2. „Treningi jeźdźca”: podsumowanie jako kafelki (liczba, łączny czas, średnia ocena, koszt) z `report.total`; karty
   grup jak w Androidzie (`report.groups`); `collapsibleRows: true`.
3. Wykres: nowy model `GroupBarChart` w `HorselyCore/Reports/ChartData.swift` (etykiety grup, wartości `Int`, miara
   `count | minutes`), budowany z `report.groups` bez przeliczania (`ReportCharts.riderGroups(_:metric:)`), opis dla
   czytnika `ChartDescriptions.groupBars`. Widok `GroupBarChartView` (Swift Charts, `BarMark` poziomy), przełącznik
   segmentowy „Liczba treningów / Łączny czas”. Przy > 12 grupach — 11 największych + „Pozostałe” (suma reszty), karty
   grup zawsze pełne. Do PDF trafiają oba warianty wykresu przez `ChartRendering.image`.
4. „Podsumowanie treningów”: sumy na górze dzięki punktowi 1; wykres postępu już jest pokazywany, gdy
   `ReportCharts.progress` zwraca dane — dodać test jednostkowy, że dla raportu z ≥ 1 wartością parametru wykres
   powstaje (FR-017), bez zmiany logiki, jeśli test przejdzie.
5. CSV/PDF: `ReportTables.riderTrainings` bez zmian → istniejące wzorce `golden/rider-trainings/*` przechodzą bez zmian.

**Rationale**: Swift Charts jest wbudowany (zasada VII), już używany przez pozostałe wykresy. Kolejność sum dla
wszystkich raportów przywraca zgodność ze specyfikacją i Androidem, zamiast dokładać wyjątek.

**Alternatives considered**: wykres w czasie (tygodnie/miesiące) — poza zakresem (spec, Assumptions); sumy na górze
tylko w dwóch raportach — pozostawiałoby niezgodność w pozostałych.

## R4. Teksty i zgodność z Androidem

**Decision**: Nowe klucze w `../zarzadzanie_konmi_android/app/src/main/res/values/strings.xml`:
`reports_show_trainings` („Pokaż treningi (%1$d)”), `reports_hide_trainings` („Ukryj treningi”),
`reports_chart_metric_count` („Liczba treningów”), `reports_chart_metric_time` („Łączny czas”),
`reports_chart_rider_groups_title` („Treningi według grup”), `reports_chart_others` („Pozostałe”). Przeniesienie
`scripts/sync-strings.ps1`; `StringsParityTests` musi przejść. Commit w repozytorium Androida tylko z tekstami i wpisem
w `SPECYFIKACJA_MOBILE_ANDROID.md`; implementacja w Androidzie — osobne zadanie (nie blokuje 2.0.2 na iOS).

## R5. Proces: jedno wydanie na końcu

**Ustalenie**: `ci.yml` uruchamia się na push/PR do `main` (kompilacja i wszystkie testy, bez podpisu); `release.yml` —
tylko tag `v*` lub `workflow_dispatch`. Numer kompilacji = `GITHUB_RUN_NUMBER` przebiegu `release.yml`, wersja =
`MARKETING_VERSION` z `project.yml`.

**Decision** (wymóg właściciela 2026-10-17): po każdej fazie wyłącznie commit + push do `main` i zielony `ci.yml`;
**zakaz** tagów i `workflow_dispatch` `release.yml` (także „kompilacji częściowych” dla grupy Deweloper) przed fazą
końcową. Podbicie `MARKETING_VERSION` do `2.0.2` dopiero w fazie końcowej. Wydanie `v2.0.2` jedno, po zakończeniu
wszystkich historii, aktualizacji obu specyfikacji i przejrzeniu zrzutów z CI. Właściciel weryfikuje ręcznie tylko
kompilację 2.0.2 — dlatego każda historia ma testy automatyczne (jednostkowe w pakietach, migawkowe, UI) w CI.

**Rationale**: Właściciel nie może weryfikować kompilacji pośrednich; pośrednie wysyłki zużywałyby numery kompilacji
i myliły testerkę.
