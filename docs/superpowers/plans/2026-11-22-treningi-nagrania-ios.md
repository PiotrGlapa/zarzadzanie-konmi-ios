# iOS 3.0 — załączniki treningów i nagrywanie jazdy: plan wdrożenia

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aplikacja iOS 3.0.0 z zakresem Androida 3.0.2 — załączniki treningów, nagrywanie jazdy z GPS i akcelerometrem, statystyki chodów, mapa MapKit, GPX, pogoda, progi i obciążenie, raport „Analiza jazd”, synchronizacja `/api/v3`, kopia formatu 3 — w obu trybach pracy.

**Architecture:** Czyste obliczenia (format trasy, rytm, maszyna stanów, statystyki, przycinanie, GPX, pogoda, raport, polityka filmów, model mapy) w `HorselyCore` — każde jest portem typu Androida o tej samej nazwie i sprawdzane **tymi samymi** plikami wzorcowymi. Wejście/wyjście (GRDB, sieć, lokalizacja, Core Motion, AVFoundation, Live Activity) w `HorselyKit` i w aplikacji. Nagranie to osobny rekord zależny od treningu, trasa w osobnej tabeli — jak Android (A4).

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, GRDB 7, Core Location (`CLLocationUpdate.liveUpdates`, `CLBackgroundActivitySession`, `CLServiceSession`), Core Motion, MapKit dla SwiftUI, AVFoundation, ActivityKit + App Intents, XcodeGen, GitHub Actions.

**Spec:** [`docs/superpowers/specs/2026-11-22-treningi-nagrania-ios-design.md`](../specs/2026-11-22-treningi-nagrania-ios-design.md) (dalej **[ZAK]**). Razem z nim czytaj **[WYM]** (`../zarzadzanie_konmi_android/docs/superpowers/specs/2026-11-14-treningi-nagrania-zalaczniki-design.md`), **[PLAN-A]** (`../zarzadzanie_konmi_android/docs/superpowers/plans/2026-11-15-treningi-nagrania-android.md`) i **[K]** (`../zarzadzanie_konmi_java/specs/012-treningi-nagrania/contracts/api-v3-recordings.md`).

**Zasada portu:** zadanie z dopiskiem „= [PLAN-A] Task N” przenosi do Swifta **interfejs, reguły, teksty i listę testów** tego zadania Androida (nazwy typów i pól 1:1, `camelCase`, `BigDecimal` → `Decimal`, `Instant` → `Date`, `Flow` → `AsyncStream`, `suspend` → `async`). Plan iOS wypisuje tylko to, co się różni, i ścieżki plików. W razie sprzeczności rozstrzyga kod Androida 3.0.2 (sprawdzony), a różnica trafia do `SPECYFIKACJA_MOBILE_IOS.md`.

## Global Constraints

- Wszystkie teksty UI, komentarze, komunikaty commitów — po polsku; teksty UI wyłącznie z `strings.xml` Androida 3.0.2 przez `scripts/sync-strings.ps1` (CI: `-Check`).
- iOS 18.0, Swift 6 (ścisła współbieżność), `MARKETING_VERSION "3.0.0"`; `CURRENT_PROJECT_VERSION` nadaje CI.
- Bez nowych zależności SPM poza istniejącymi (GRDB, Firebase Messaging, SnapshotTesting); gzip przez `Compression`/`zlib` systemu.
- Zgody (`Info.plist`): `NSLocationWhenInUseUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription`; `UIBackgroundModes` + `location`; `NSSupportsLiveActivities = YES`. **Nigdy** `NSLocationAlwaysAndWhenInUseUsageDescription`.
- Lokalizacja tylko w czasie nagrywania uruchomionego przez użytkownika; współrzędne nigdy w dzienniku diagnostycznym.
- API: `/api/v3`, gdy `apiVersions` zawiera `"3"`, inaczej `/api/v1` z ukryciem funkcji serwerowych; `system/info` zawsze `/api/v1`; kopia `formatVersion 3`, `exportSchemaVersion "1.6"`, `dataSchemaVersion "3.0"`.
- Stałe, walidacja, bezpieczniki, limity i kolory chodów — dokładnie jak [PLAN-A] „Global Constraints” i A11 (progi 1,5/7/15 km/h; wagi 1/2/3; podjazd 1 pkt/10 m; ostrzeżenie 30 %; ciężka jazda 60 pkt; 15 % baterii; 8 h; < 1 min lub < 100 m; słaby GPS > 25 m przez > 30 s; zapis ≤ 10 s; 100 MB; miniatura ≤ 1 MB; `pointCount ≥ 2`; ≤ 20 000 odcinków; `#9E9E9E` `#43A047` `#FB8C00` `#E53935`).
- Zaokrąglanie HALF_UP „od zera” na `Decimal` (`.plain` / `NSDecimalNumber.RoundingMode` „od zera”, odpowiednik `.toNearestOrAwayFromZero`), nigdy w `Double`; liczby w JSON porównywane ze skalą zapisu (jak `ReportsParityTests`).
- **Bez Swifta na Windows:** testy uruchamia wyłącznie CI. „Uruchom” w krokach = `git push` gałęzi `004-treningi-nagrania` i `gh run watch` przebiegu `CI` (zadania „Testy HorselyCore”, „Testy HorselyKit”, kompilacja i `AppSnapshotTests`). Faza czerwona potwierdzana w CI tylko w zadaniach z plikami wzorcowymi (5, 11, 18, 28); w pozostałych test jest pisany przed kodem i oba idą jednym przebiegiem.
- Testy na serwerze tylko lokalnym (nigdy `192.168.18.33`). Funkcje niesprawdzalne w CI — kompilacja częściowa `gh workflow run release.yml -f group=Deweloper` i lista do sprawdzenia przez właściciela.

## Review Focus

1. **Kopia z Androida 3.0 otwarta na iPhonie** — te same statystyki, odcinki, trasa i CSV raportu; kopia z iPhone'a otwiera się na Androidzie (Task 7: `androidBackupWithRidesRestoresIdentically`).
2. **Zamknięcie aplikacji przez system i przesunięciem w trakcie jazdy** — po ponownym uruchomieniu w tle nagrywanie trwa; po przesunięciu przy starcie „Zapisz / Odrzuć” z punktami zapisanymi ≥ 10 s wcześniej (Task 14: `flushedPointsSurviveNewStore`, Task 15: `relaunchWithActiveSessionResumesUpdates`).
3. **Przybliżona lokalizacja albo odmowa w trakcie jazdy** — start zablokowany z wyjaśnieniem; cofnięcie zgody w trakcie zamyka sesję jako przerwaną bez utraty punktów (Task 15: `reducedAccuracyBlocksStart`, `authorizationRevokedMarksInterrupted`).
4. **Kolejność zapisu jazdy względem transakcji** — przygotowanie filmów z jazdy rusza dopiero po zatwierdzeniu transakcji zapisującej trening, nagranie i załączniki; nieudany zapis nie zostawia osieroconych operacji (Task 21: `videoPrepareScheduledAfterCommit`).
5. **Serwer 2.x po nagraniu jazdy** — pełne pobranie nie usuwa nagrania, trasy, profilu i ustawień; operacje czekają z „Czeka na aktualizację programu” (Task 30: `syncMergerKeepsRecordingsOnV1Server`).

---

## Struktura plików

**`Packages/HorselyCore/Sources/HorselyCore/`**
- `Ride/` (nowy): `Recording.swift` (modele API i lokalne), `RideParameters.swift`, `ZkTrack.swift`, `CadenceAnalyzer.swift`, `RideRecorder.swift`, `RideStatsCalculator.swift`, `TrackTrimmer.swift`, `GpxWriter.swift`, `Weather.swift`, `VideoPolicy.swift`, `RideMapModel.swift`, `HalfUp.swift` (zaokrąglenia `Decimal`).
- `Reports/`: `RideAnalysis.swift` (modele [K] 8.2), `RideAnalysisCalculator.swift`, `RideAnalysisCsv.swift`.
- Zmiany: `Connection/Capabilities.swift`, `Model/Enums.swift` (`AttachmentOwnerType.training`, nowe `RecordType`), `Model/ExportDocument.swift`, `Model/ExportRecords.swift`, `Sync/OutboxModel.swift`, `Sync/OperationCoalescer.swift`, `Sync/SyncMerger.swift`, `Sync/ApiRecordMapping.swift`, `Backup/BackupFormat.swift`, `Suggest/TrainingDefaults.swift`.

**`Packages/HorselyKit/Sources/HorselyKit/`**
- `Ride/` (nowy): `RideSessionStore.swift`, `LocationSource.swift`, `MotionSource.swift`, `RideRecordingController.swift`, `RideFinisher.swift`, `WeatherFetcher.swift`, `TrackFetcher.swift`, `RideMediaJanitor.swift`.
- `Files/`: `VideoPreparer.swift`, `VideoThumbnail.swift`, `MediaMetadataReader.swift`.
- `Repositories/`: `RecordingRepository.swift`, `RideSettingsRepository.swift`; zmiany `TrainingRepository.swift`, `ReportRepository.swift`, `HorseRepository.swift`.
- Zmiany: `Network/ApiClient.swift`, `Network/ApiResult.swift`, `Store/Database.swift` (migracja `v3`), `Store/RecordStore.swift`, `Store/SettingsStore.swift`, `Outbox/OutboxProcessor.swift`, `Backup/BackupService.swift`, `Sync/SyncService.swift`, `Background/BackgroundTasks.swift`.

**Aplikacja**
- `App/Features/Ride/` (nowy): `RideStartFlow.swift`, `RideRecordingView.swift`, `RideBanner.swift`, `RideRecoveryAlert.swift`, `RecordingCard.swift`, `TrimView.swift`, `RideStatsSection.swift`, `RideMapView.swift`, `GaitColors.swift`, `RideCameraPicker.swift`.
- `App/Features/Settings/RideSettingsView.swift`, `App/Features/Horses/HorseTabs/RidesTab.swift`, `App/Features/Reports/RideAnalysisReportView.swift`.
- `RideActivity/` (nowy cel rozszerzenia widżetów): `RideActivityBundle.swift`, `RideActivityWidget.swift`, `Info.plist`; wspólne `Shared/RideActivityAttributes.swift`, `Shared/RideActivityIntents.swift` (w celach aplikacji i rozszerzenia).
- Zmiany: `project.yml`, `App/Info.plist`, `App/PrivacyInfo.xcprivacy`, `App/HorselyApp.swift`, `App/Features/Trainings/TrainingsSectionView.swift`, `App/Features/Horses/HorseTabs/{TrainingsTab,PassportTab,HorseTabSupport}.swift`, `App/Features/Entries/{EntryDetailView,EntryFormModel,EntryFormView,FormSpec}.swift`, `App/Features/Dashboard/DashboardView.swift`, `App/Features/Settings/*`, `App/Features/Reports/*`, `.github/workflows/release.yml`, `scripts/ci/embed-entitlements.sh`.

**Zasoby testowe** (`Packages/HorselyCore/Tests/HorselyCoreTests/Resources/`): `golden/zk-track/`, `golden/ride-stats/`, `golden/ride-analysis/` (kopie 1:1 z Androida 3.0.2 z README), `v3/*.json` (przykłady z [K], kopie z `core/src/test/resources/v3/` Androida), `contracts/export-schema-1.6.json`, `weather/forecast.json`, `backup-3/` (Task 7).

---

## Część A — fundament

### Task 1: Konstytucja 3.0.0 i specyfikacja „Zakres wersji 3.0”

**Files:**
- Modify: `.specify/memory/constitution.md`, `SPECYFIKACJA_MOBILE_IOS.md`

- [x] **Step 1:** Konstytucja → 3.0.0 (raport synchronizacji na górze: MAJOR, zasady II i VIII). Zasada II: wyjątki z [ZAK] 6.1 dokładnie tymi warunkami (lokalizacja „Podczas używania" tylko w czasie nagrywania uruchomionego przez użytkownika, bez „Zawsze"; kafle Apple Maps; Open‑Meteo z położeniem zaokrąglonym do 0,01° i godziną startu, z wyłącznikiem; dziennik bez współrzędnych); zdanie „NIE MOŻE prosić o lokalizację" zastąpione powyższym; lista zgód 9.2 + lokalizacja, mikrofon, dodawanie do galerii. Zasada VIII: „Android 2.1.0" → „Android 3.0.2". `Version: 3.0.0`, `Last Amended:` data wykonania.
- [x] **Step 2:** Specyfikacja: sekcja „Zakres wersji 3.0" odsyłająca do [ZAK] i [WYM] (FR z prefiksami ZAT/NAG/STA/MAP/POG/PAR/RAJ/SYN), w US10 usunięte „Treningi nie mają załączników…" (wiersz 544), sekcja 9 z różnicami z [ZAK] 6 (MapKit, lokalizacja w tle, Live Activity), 9.2 zgody.
- [x] **Step 3: Commit** — `docs: konstytucja 3.0.0 i zakres wersji 3.0 w specyfikacji`

### Task 2: Teksty 3.0.2 z Androida

**Files:**
- Modify: `App/Resources/Localizable.xcstrings` (generowany), ewentualnie `scripts/sync-strings.ps1` (mapowanie nowych kluczy)

- [x] **Step 1:** `pwsh -NoProfile -File scripts/sync-strings.ps1` z `../zarzadzanie_konmi_android/app/src/main/res/values/strings.xml` (3.0.2) — nowe klucze jazdy, mapy, pogody, raportu, Live Activity bierze teksty powiadomienia nagrywania.
- [x] **Step 2:** `pwsh -NoProfile -File scripts/sync-strings.ps1 -Check` → bez różnic (działa lokalnie).
- [x] **Step 3: Commit** — `chore: teksty Androida 3.0.2`

### Task 3: Wersje API i nowe możliwości = [PLAN-A] Task 2

**Files:**
- Modify: `Packages/HorselyCore/Sources/HorselyCore/Connection/Capabilities.swift`
- Create: `Packages/HorselyCore/Tests/HorselyCoreTests/Resources/v3/system-info.json`
- Test: `Packages/HorselyCore/Tests/HorselyCoreTests/CapabilitiesTests.swift`

**Interfaces:**
- Produces: `ProgramInfo.apiVersions: [String]` (domyślnie `[]`), `ProgramInfo.dataSchemaVersion: String?`; `ProgramCapabilities.trainingAttachmentsName = "trainingAttachments"`, `.trainingRecordingsName = "trainingRecordings"`, `.apiV3Name = "apiV3"` (pseudo-nazwa, w `known`); właściwości `trainingAttachments`, `trainingRecordings`, `apiV3: Bool`; `static func of(_ info: ProgramInfo) -> ProgramCapabilities` (dodaje `apiV3`, gdy `info.apiVersions.contains("3")`); zmiana `apiV3` wymusza pełne pobranie (ta sama ścieżka co dziś przy zmianie możliwości wymuszającej pełne pobranie).

- [ ] **Step 1: Testy** — `systemInfo300IsParsed` (`["1","3"]`, `"3.0"`, wszystkie trzy możliwości), `server2xHasNoV3`, `apiV3SurvivesSerializeParse`, `switchingToV3ForcesFullSync`.
- [ ] **Step 2:** Implementacja; push → CI „Testy HorselyCore” PASS.
- [ ] **Step 3: Commit** — `feat(core): apiVersions, dataSchemaVersion i mozliwosci nagran`

### Task 4: Przełączanie `/api/v1` ↔ `/api/v3` = [PLAN-A] Task 3

**Files:**
- Modify: `Packages/HorselyKit/Sources/HorselyKit/Network/ApiClient.swift`, `Network/ApiResult.swift` (dokumentacja `ApiRequest`)
- Test: `Packages/HorselyKit/Tests/HorselyKitTests/ApiClientTests.swift`

**Interfaces:**
- Consumes: `ProgramCapabilities.apiV3` (Task 3).
- Produces: `ApiClient` buduje adres z prefiksem `api/v3/`, gdy bieżące możliwości mają `apiV3`, z wyjątkiem `system/info`; zapisane adresy parowania bez zmian. Funkcja pomocnicza `static func versionedPath(_ base: URL, apiV3: Bool, relative: String) -> URL` (zamienia **ostatnie** `api/v1` w ścieżce bazowej).

- [ ] **Step 1: Testy** — `v1PathIsRewrittenWhenServerHasV3` (`/proxy/api/v1/` + `trainings` → `/proxy/api/v3/trainings`), `systemInfoAlwaysGoesToV1`, `nothingChangesWithoutV3`, `queryAndEncodedSegmentsAreKept`.
- [ ] **Step 2:** Implementacja; push → CI „Testy HorselyKit” PASS.
- [ ] **Step 3: Commit** — `feat(api): przelaczanie na /api/v3 po apiVersions`

### Task 5: Modele nagrań, profilu i ustawień jazd = [PLAN-A] Task 4

**Files:**
- Create: `Packages/HorselyCore/Sources/HorselyCore/Ride/{Recording,RideParameters,HalfUp}.swift`, `Resources/v3/recording.json`
- Modify: `Model/Enums.swift` (`RecordType.trainingRecording = "trainingRecordings"`, `.horseRideProfile = "horseRideProfiles"`, `.rideDefaults`), `Model/ExportRecords.swift`, `Model/ExportDocument.swift`, `Sync/ApiRecordMapping.swift`, modele konia (`rideProfile: RideProfile?`, pomijane w wejściu, gdy `nil`) i treningu (`recordingSummary: RecordingSummary?`)
- Test: `Packages/HorselyCore/Tests/HorselyCoreTests/RecordingModelTests.swift`, `RideParametersTests.swift`

**Interfaces:**
- Produces (nazwy 1:1 z [PLAN-A] Task 4): `Recording`, `Gait` (`stop`, `walk`, `trot`, `canter`, wartości surowe `Stop`…), `WeatherStatus`, `GaitSegment`, `RecordingSummary`, `GaitThresholds`, `LoadParams`, `RideProfile`, `RideDefaults` + `static let builtIn` (`1.5, 7, 15, 1, 2, 3, 1, 30, 60`, `version 0`), `EffectiveRideParameters`, `enum RideParameters { static func resolve(_:_:)`, `validate`, `loadPoints(walkSeconds:trotSeconds:canterSeconds:elevationGainM:load:) -> Decimal`, `exampleText(_:) -> String }`; `extension Recording { func toInput(trackData: String) -> JSONValue }`; `enum HalfUp { static func round(_ value: Decimal, scale: Int) -> Decimal }`.

- [ ] **Step 1: Testy** — lista z [PLAN-A] Task 4 Step 1 (`recordingDtoFromContractParsesAndRoundTrips`, `inputHasNoResponseOnlyFieldsAndKeepsTrackData`, `profileInheritsFieldByField`, `exampleFromPar02Gives100Points` → `Decimal(string: "100.0")`, `walkThresholdNotAboveStopIsRejected`, `rangesFromPar05`, `exportDocumentRecordTypesMapCollections`) oraz `halfUpRoundsAwayFromZero` (`2.345`→`2.35`, `-2.345`→`-2.35`, `2.5`→`3`).
- [ ] **Step 2:** Push testów bez implementacji → CI FAIL (kompilacja testów). **Step 3:** Implementacja → push → PASS.
- [ ] **Step 4: Commit** — `feat(core): modele nagran jazdy, profilu konia i ustawien jazd`

### Task 6: Baza GRDB `v3` = [PLAN-A] Task 5

**Files:**
- Modify: `Packages/HorselyKit/Sources/HorselyKit/Store/Database.swift` (`registerMigration("v3")`), `Store/RecordStore.swift`
- Create: `Packages/HorselyKit/Sources/HorselyKit/Ride/RideSessionStore.swift` (tylko typy wierszy i zapytania; logika w Task 14)
- Test: `Packages/HorselyKit/Tests/HorselyKitTests/MigrationV3Tests.swift`

**Interfaces:**
- Produces: tabele `local_track`, `ride_session`, `ride_point`, `ride_media` z kolumnami jak [PLAN-A] Task 5 (nazwy kolumn identyczne); `RecordStore.track(recordingId:) async throws -> StoredTrack?`, `putTrack(_:)`, `deleteTrack(recordingId:)`; `struct StoredTrack: Sendable { recordingId: String; version: Int; format: String; data: Data }`; czyszczenie magazynu usuwa też trasy i sesje.

- [ ] **Step 1: Testy** — `migrationV2ToV3KeepsRecordsAndCreatesRideTables` (baza w `v2` z rekordem, migracja, rekord jest, nowe tabele puste), `trackRoundTrip`, `clearRemovesTracks`.
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(db): baza v3 - trasy, sesje nagrywania, punkty i pliki z jazdy`

### Task 7: Kopia formatu 3 i wymienność z Androidem = [PLAN-A] Task 6

**Files:**
- Modify: `Packages/HorselyCore/Sources/HorselyCore/Backup/BackupFormat.swift` (`formatVersion = 3`, `exportSchemaVersion = "1.6"`, `dataSchemaVersion = "3.0"`), `Model/ExportDocument.swift`, `Packages/HorselyKit/Sources/HorselyKit/Backup/BackupService.swift`
- Create: `Resources/contracts/export-schema-1.6.json` (kopia z `../zarzadzanie_konmi_java/src/main/resources/schemas/`), `Resources/backup-3/` (kopia `.zkkopia` bez hasła z dwiema jazdami wygenerowana przez Androida 3.0.2 — jeśli zasoby testowe Androida nie mają takiej kopii, wygeneruj ją jednorazowo testem w repozytorium Androida osobnym commitem tam; obok `expected-stats.json` z jego statystykami)
- Test: `Packages/HorselyKit/Tests/HorselyKitTests/BackupRidesTests.swift`

**Interfaces:**
- Produces: `export.json` kopii z `trainingRecordings[]` (z `segments` i `trackData` base64), `horseRideProfiles[]`, `rideDefaults`, załączniki z `capturedAt/latitude/longitude`; odczyt pełnego eksportu serwera 1.6 tymi samymi kolekcjami.

- [ ] **Step 1: Testy** — lista z [PLAN-A] Task 6 (`backupWithRecordingRoundTripsTrackBytesAndSegments`, `exportJsonValidatesAgainstExportSchema16`, `backup2xWithoutRidesRestores`, `backupNewerThan3IsRefused` z komunikatem „Kopia z nowszej wersji aplikacji (format 4) — zaktualizuj aplikację.”, `format2ManifestWithoutDataSchemaVersionIsRead`) oraz `androidBackupWithRidesRestoresIdentically` (odtworzenie `backup-3/` → rekordy, trasy i statystyki równe `expected-stats.json`).
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(backup): kopia formatu 3 ze schematem 1.6 i nagraniami, wymienna z Androidem`

---

## Część B — załączniki treningu

### Task 8: Załącznik treningu, metadane i miniatura = [PLAN-A] Task 7

**Files:**
- Modify: `Model/Enums.swift` (`AttachmentOwnerType.training = "Training"`), modele załącznika (`capturedAt: Date?`, `latitude: Decimal?`, `longitude: Decimal?`), `Sync/OutboxModel.swift` (`OutboxFile` + `thumbnailPath`, `capturedAt`, `latitude`, `longitude`), `HorselyKit/Network/ApiClient.swift` (części multipart `capturedAt`, `latitude`, `longitude`, `thumbnail` `image/jpeg`), `Outbox/OutboxProcessor.swift` (wstrzymanie A6: `ownerType=Training` bez `trainingAttachments` zostaje `pending`, kolejka pokazuje „Czeka na aktualizację programu”)
- Test: `Packages/HorselyKit/Tests/HorselyKitTests/AttachmentOperationTests.swift`

- [ ] **Step 1: Testy** — `trainingAttachmentMultipartCarriesMetadataAndThumbnail` (`FakeProgram`: `capturedAt=2026-09-01T08:15:00Z`, `latitude=52.2297000`, część `thumbnail`), `trainingAttachmentWaitsWithoutTrainingAttachments`, `attachmentDtoWithMetadataParses`.
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(attachments): zalaczniki treningu z miejscem, czasem i miniatura filmu`

### Task 9: Przekodowanie filmów 720p i miniatura = [PLAN-A] Task 8

**Files:**
- Create: `HorselyCore/Ride/VideoPolicy.swift`, `HorselyKit/Files/VideoPreparer.swift`, `HorselyKit/Files/VideoThumbnail.swift`, `HorselyKit/Tests/HorselyKitTests/Resources/sample-1s.mov`
- Modify: `HorselyKit/Files/AttachmentStore.swift` (operacja `held` do końca przygotowania, potem `pending`; tryb samodzielny — przygotowanie przed zapisem pliku), `Background/BackgroundTasks.swift` (zadanie `BGProcessingTask` „przygotowanie filmów” wznawiające przerwane), `App/Features/Attachments/AttachmentsGrid.swift` (postęp „Przygotowuję film… 45%”, przełącznik „Wyślij oryginał”), `project.yml`/`Info.plist` (`BGTaskSchedulerPermittedIdentifiers` + nowy identyfikator)
- Test: `HorselyCore/Tests/HorselyCoreTests/VideoPolicyTests.swift`, `HorselyKit/Tests/HorselyKitTests/VideoThumbnailTests.swift`

**Interfaces:**
- Produces: `enum VideoDecision: Equatable { case keepOriginal, transcode, reject(String) }`; `enum VideoPolicy { static func decide(shortSidePx:sizeBytes:sendOriginal:) -> VideoDecision; static func afterTranscode(sizeBytes:durationSeconds:) -> VideoDecision; static func canSendOriginal(sizeBytes:) -> Bool }` (reguły i komunikat odrzucenia jak [PLAN-A] Task 8); `VideoPreparer.prepare(source: URL, target: URL, progress: @Sendable (Int) -> Void) async throws -> URL` (`AVAssetExportSession` preset `AVAssetExportPreset1280x720`, `.mp4`, z zachowaniem orientacji; asynchroniczne `export(to:as:)` i `states(updateInterval:)`); `VideoThumbnail.make(video: URL) async -> Data?` (`AVAssetImageGenerator`, `appliesPreferredTrackTransform`, dłuższy bok 512, JPEG obniżany do ≤ 1 MB).

- [ ] **Step 1: Testy** — lista z [PLAN-A] Task 8 (`video4KIsTranscoded`, `video720UnderLimitIsKept`, `originalToggleOnlyBelow100MB`, `transcodedOverLimitIsRejectedWithMaxLength`, `thumbnailOfSampleIsJpegUnder1MB`) oraz `interruptedPreparationResumesOnLaunch` (operacja `held` bez pliku wynikowego → przygotowanie ponownie w kolejce).
- [ ] **Step 2:** Implementacja; push → PASS (test miniatury działa na runnerze macOS w `swift test`).
- [ ] **Step 3: Commit** — `feat(attachments): przekodowanie filmow do 720p i miniatura pierwszej klatki`

### Task 10: Sekcja „Załączniki” treningu i metadane z galerii = [PLAN-A] Task 9

**Files:**
- Create: `HorselyKit/Files/MediaMetadataReader.swift`
- Modify: `App/Features/Entries/{EntryDetailView,EntryFormModel,FormSpec}.swift` (trening: sekcja i „Dodaj zdjęcie / film / plik” tym samym `AddAttachmentSheet`), `App/Features/Attachments/AddAttachmentSheet.swift` (przekazanie metadanych pliku)
- Test: `HorselyKit/Tests/HorselyKitTests/MediaMetadataReaderTests.swift`, `Tests/AppSnapshotTests/TrainingAttachmentsSnapshotTests.swift`

**Interfaces:**
- Produces: `struct MediaMetadata: Equatable { capturedAt: Date?; latitude: Double?; longitude: Double? }`; `MediaMetadataReader.read(file: URL, contentType: String) async -> MediaMetadata` (zdjęcia: `CGImageSource` `{Exif}DateTimeOriginal`+`OffsetTimeOriginal`, `{GPS}`; filmy: `AVAsset` `commonKey.location` ISO 6709 i `creationDate`).

- [ ] **Step 1: Testy** — `exifGpsAndTimeAreRead` (mały JPEG z GPS w zasobach), `quicktimeIso6709LocationIsParsed` (`+52.2297+021.0122/`), `missingLocationGivesNil`; migawki `trainingDetailShowsAttachmentsSection`, `sectionHiddenOnlineWithoutTrainingAttachments` (ZAT-06).
- [ ] **Step 2:** Implementacja; push → PASS (w tym `AppSnapshotTests`).
- [ ] **Step 3: Commit** — `feat(trainings): zalaczniki treningu w szczegolach i formularzu`

---

## Część C — nagrywanie

### Task 11: Format trasy `zk-track/1` = [PLAN-A] Task 10

**Files:**
- Create: `HorselyCore/Ride/ZkTrack.swift`, `Resources/golden/zk-track/` (kopia 1:1 z Androida, z README)
- Test: `HorselyCore/Tests/HorselyCoreTests/ZkTrackTests.swift`

**Interfaces:**
- Produces: `struct TrackPoint`, `struct Pause`, `struct Track` (pola z [PLAN-A] Task 10, `tMillis: Int64`); `enum ZkTrack { static let format = "zk-track/1"; static func encode(_ track: Track) throws -> Data; static func decode(_ data: Data) throws -> Track }` — gzip (nagłówek gzip, nie surowy deflate) z JSON jak w README.

- [ ] **Step 1: Testy** — `roundTripKeepsValuesWithinRounding`, `goldenBytesDecodeToFixture` (`krotka.b64` → `krotka.json`), `encodedDocumentEqualsAndroidAfterGunzip` (porównanie dokumentu JSON, nie bajtów), `oneHourAt1HzIsUnder60KB`.
- [ ] **Step 2:** Push testów → CI FAIL. **Step 3:** Implementacja → PASS.
- [ ] **Step 4: Commit** — `feat(core): format trasy zk-track/1 zgodny z Androidem`

### Task 12: Rytm i intensywność z akcelerometru = [PLAN-A] Task 11

**Files:**
- Create: `HorselyCore/Ride/CadenceAnalyzer.swift`
- Test: `HorselyCore/Tests/HorselyCoreTests/CadenceAnalyzerTests.swift`

- [ ] **Step 1: Testy** — cztery testy [PLAN-A] Task 11 (sinus 2,5 Hz → 150/min ±2, szum → `nil`, spoczynek → `nil` i intensywność ≈ 0, za mało próbek → `nil`). Algorytm dosłownie z [PLAN-A] Task 11 (przepróbkowanie do 50 Hz, autokorelacja 0,3–1,5 s, próg 0,4, ≥ 150 próbek); próbki iOS z `userAcceleration` w g mnożone przez 9,80665 (m/s²) przed analizą.
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(core): rytm i intensywnosc ruchu z okien akcelerometru`

### Task 13: Maszyna stanów nagrywania = [PLAN-A] Task 12

**Files:**
- Create: `HorselyCore/Ride/RideRecorder.swift`
- Test: `HorselyCore/Tests/HorselyCoreTests/RideRecorderTests.swift`

- [ ] **Step 1: Testy** — sześć testów [PLAN-A] Task 12 (pauza, słaby GPS po 30 s, bateria raz przy 15 %, koniec po 8 h, zapis co ≤ 10 s, odtworzenie dystansu i czasu).
- [ ] **Step 2:** `final class RideRecorder` (bez współbieżności — używa jej aktor z Task 15), interfejs 1:1; push → PASS.
- [ ] **Step 3: Commit** — `feat(core): maszyna stanow nagrywania jazdy z bezpiecznikami`

### Task 14: Zapis sesji na bieżąco i odzyskiwanie = [PLAN-A] Task 13

**Files:**
- Modify: `HorselyKit/Ride/RideSessionStore.swift`
- Test: `HorselyKit/Tests/HorselyKitTests/RideSessionStoreTests.swift`

**Interfaces:**
- Produces: `RideSessionStore` z `start(horse:params:) throws -> String`, `flush(sessionId:points:snapshot:)` (jedna transakcja), `setState`, `addMedia`, `unfinished() -> UnfinishedRide?`, `load(sessionId:) -> LoadedSession`, `discard(sessionId:)`, `observeActive() -> AsyncStream<RideSnapshot?>` — typy jak [PLAN-A] Task 13.

- [ ] **Step 1: Testy** — `flushedPointsSurviveNewStore` (nowa instancja na tym samym pliku bazy), `unfinishedRideReportsHorseTimeAndDistance`, `discardRemovesPointsAndMedia`, `onlyOneActiveSession`.
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(ride): zapis sesji nagrywania na biezaco i odzyskiwanie`

### Task 15: Lokalizacja i ruch w tle, kontroler nagrywania

**Files:**
- Create: `HorselyKit/Ride/{LocationSource,MotionSource,RideRecordingController}.swift`
- Modify: `App/Info.plist` (zgody i `UIBackgroundModes` z Global Constraints), `App/HorselyApp.swift` (przy starcie: aktywna sesja w stanie `recording`/`paused` → `RideRecordingController.resumeAfterRelaunch()` **przed** zakończeniem uruchamiania), `Tests/AppSnapshotTests/InfoPlistPolicyTests.swift`
- Test: `HorselyKit/Tests/HorselyKitTests/RideRecordingControllerTests.swift`

**Interfaces:**
- Consumes: Task 12–14.
- Produces: `protocol LocationSource: Sendable { func updates() -> AsyncStream<LocationSample>; var authorization: LocationAuthorization { get } }` z implementacją systemową (`CLLocationUpdate.liveUpdates(.fitness)`, `CLBackgroundActivitySession()` trzymana przez cały czas nagrywania, `CLServiceSession(authorization: .whenInUse, fullAccuracyPurposeKey:)`; `LocationSample` → `TrackPoint`); `enum LocationAuthorization { notDetermined, denied, reducedAccuracy, whenInUse }`; `protocol MotionSource` (`CMMotionManager.deviceMotionUpdateInterval = 1/50`, okna 5 s → `CadenceAnalyzer`); `actor RideRecordingController { func start(horse:params:) async throws; func pause(); func resume(); func finish() async -> String /* sessionId */; func resumeAfterRelaunch() async; var snapshots: AsyncStream<RideSnapshot> }` — zdarzenia `RideEvent` → powiadomienia lokalne (teksty z [PLAN-A] Task 14) i aktualizacja Live Activity (Task 16 podłącza); `UIDevice.isBatteryMonitoringEnabled` tylko w trakcie. Utrata zgody w trakcie → stan `interrupted`, zapis bieżących punktów. Dziennik diagnostyczny (`HorselyKit/Log`) dostaje wpisy stanu (start, pauza, wznowienie, ponowne uruchomienie, słaby GPS, przerwanie, koniec — z czasem, liczbą punktów i dokładnością) **bez współrzędnych i nazwy konia**.

- [ ] **Step 1: Testy** (z udawanymi źródłami) — `pointsFlowToStoreEvery10s`, `reducedAccuracyBlocksStart`, `deniedBlocksStart`, `authorizationRevokedMarksInterrupted`, `relaunchWithActiveSessionResumesUpdates`, `finishStopsSourcesAndSetsFinished`, `diagnosticLogHasNoCoordinatesOrHorseName`; w `InfoPlistPolicyTests`: `locationWhenInUseOnly` (jest `NSLocationWhenInUseUsageDescription` i `location` w trybach tła; brak klucza „Always”).
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(ride): nagrywanie lokalizacji i ruchu w tle z wznowieniem po ponownym uruchomieniu`

### Task 16: Live Activity

**Files:**
- Create: `RideActivity/{RideActivityBundle,RideActivityWidget}.swift`, `RideActivity/Info.plist`, `Shared/RideActivityAttributes.swift`, `Shared/RideActivityIntents.swift`
- Modify: `project.yml` (cel `HorselyRideActivity`, typ `app-extension`, `PRODUCT_BUNDLE_IDENTIFIER pl.glapa.horsely.RideActivity`, osadzony w `Horsely`; `Shared/` w obu celach; `NSSupportsLiveActivities` w aplikacji), `.github/workflows/release.yml` (pętla weryfikacji podpisu + `HorselyRideActivity.appex`), `scripts/ci/embed-entitlements.sh`, `HorselyKit/Ride/RideRecordingController.swift` (start/aktualizacja/koniec aktywności przez wstrzyknięty protokół `RideActivityPresenter`)
- Test: `HorselyKit/Tests/HorselyKitTests/RideRecordingControllerTests.swift`, `Tests/AppSnapshotTests/RideActivitySnapshotTests.swift`

**Interfaces:**
- Produces: `struct RideActivityAttributes: ActivityAttributes { horseName: String; struct ContentState: Codable, Hashable { activeSeconds: Int; distanceMeters: Int; gait: String?; weakGps: Bool; paused: Bool } }`; `PauseRideIntent`, `ResumeRideIntent`, `FinishRideIntent: LiveActivityIntent` (Zakończ → `openAppWhenRun`, ekran zakończenia); `protocol RideActivityPresenter: Sendable { func start(...); func update(...); func end() }`. Treść: „Grom · 24 min · 3,2 km · kłus”, „Słaby sygnał GPS”.

- [ ] **Step 1: Testy** — `activityStartsUpdatesAndEndsWithRide` (udawany prezenter), `pauseIntentPausesController`; migawki ekranu blokady i Dynamic Island (kompaktowy, rozwinięty).
- [ ] **Step 2:** Implementacja; push → PASS (kompilacja z nowym celem).
- [ ] **Step 3:** `gh workflow run release.yml -f group=Deweloper` → przebieg zielony, oba rozszerzenia podpisane (podsumowanie przebiegu).
- [ ] **Step 4: Commit** — `feat(ride): Live Activity z pauza i zakonczeniem jazdy`

### Task 17: Start, ekran nagrywania, pasek, odzyskiwanie, aparat = [PLAN-A] Task 15

**Files:**
- Create: `App/Features/Ride/{RideStartFlow,RideRecordingView,RideBanner,RideRecoveryAlert,RideCameraPicker}.swift`
- Modify: `App/Features/Trainings/TrainingsSectionView.swift` („Nagraj jazdę” obok „+”), `App/Features/Horses/HorseTabs/TrainingsTab.swift` (koń wybrany), `App/Features/Dashboard/DashboardView.swift` (pasek), `HorselyKit/Store/SettingsStore.swift` (`rideWearHintHidden`), `App/HorselyApp.swift` (alert odzyskiwania)
- Test: `Tests/AppSnapshotTests/RideFlowSnapshotTests.swift`, `HorselyKit/Tests/HorselyKitTests/RideStartPolicyTests.swift`

**Interfaces:**
- Kolejność startu jak [PLAN-A] Task 15 bez kroków Androida (powiadomienia zgoda tylko gdy jeszcze nie zapytano; bez optymalizacji baterii): wybór konia → instrukcja noszenia (NAG-03 dosłownie, „Nie pokazuj więcej”) → zgoda lokalizacji (odmowa / przybliżona: „Bez dostępu do dokładnej lokalizacji nie da się nagrać jazdy.” + „Otwórz ustawienia”) → start. „Zdjęcie / film” — `UIImagePickerController` (zdjęcie i film) do `ride-media/` w kontenerze aplikacji, `addMedia` z czasem i ostatnim punktem.

- [ ] **Step 1: Testy** — `startFromHorseTabPreselectsHorse`, `wearHintSkippedAfterDoNotShowAgain`, `locationDeniedShowsExplanationWithSettingsButton`, `bannerVisibleWhileRecording`, `recoveryAlertShowsHorseTimeDistance` (logika w `RideStartPolicy` + migawki ekranu nagrywania i alertu).
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3:** Kompilacja częściowa „Deweloper”; lista dla właściciela: 10 min jazdy z zablokowanym ekranem, pauza z ekranu blokady, zamknięcie przesunięciem i odzyskanie.
- [ ] **Step 4: Commit** — `feat(ride): start nagrywania, ekran jazdy, pasek i odzyskiwanie`

---

## Część D — statystyki, zapis i szczegóły treningu

### Task 18: Statystyki i rozpoznanie chodów = [PLAN-A] Task 16

**Files:**
- Create: `HorselyCore/Ride/RideStatsCalculator.swift`, `Resources/golden/ride-stats/` (kopia 1:1 z Androida 3.0.2 z README i `expected.json`)
- Test: `HorselyCore/Tests/HorselyCoreTests/RideStatsCalculatorTests.swift`, `RideStatsGoldenTests.swift`

**Interfaces:**
- Produces: `struct RideStats` (pola [PLAN-A] Task 16), `enum RideStatsCalculator { static let algorithmVersion = 1; static func compute(track:endedAtMillis:params:) -> RideStats }`, `enum GaitBands`, `JumpAnchorFilter` (reguła kotwicy z README `ride-stats` / decyzji Androida). **Algorytm z README Androida, nie z [PLAN-A]**: okna domknięte z prawej `(5k, 5k+5]` (poprawka R19), luka GPS > ~10 s = postój.

- [ ] **Step 1: Testy** — ręczne asercje [PLAN-A] Task 16 Step 1 (wszystkie osiem) i `RideStatsGoldenTests` parametryzowany po katalogach `golden/ride-stats` (pole po polu, liczby ze skalą).
- [ ] **Step 2:** Push testów → CI FAIL. **Step 3:** Implementacja → PASS (wszystkie przypadki).
- [ ] **Step 4: Commit** — `feat(core): statystyki jazdy i rozpoznanie chodow v1 zgodne z Androidem`

### Task 19: Przycinanie i przeliczenie = [PLAN-A] Task 17

**Files:**
- Create: `HorselyCore/Ride/TrackTrimmer.swift`
- Test: `HorselyCore/Tests/HorselyCoreTests/TrackTrimmerTests.swift`

- [ ] **Step 1: Testy** — cztery testy [PLAN-A] Task 17 (`trimRemovesCarTail`, `trimmedPointsAreGoneFromEncodedTrack`, `secondTrimAddsToTrimmedSeconds`, `recalculateWithNewWalkThresholdChangesSplitAndKeepsWeather`).
- [ ] **Step 2:** Implementacja (`TrackTrimmer.trim`, `Recording.recalculated`, `Recording.thresholdsDiffer`); push → PASS.
- [ ] **Step 3: Commit** — `feat(core): przycinanie trasy i przeliczanie nagrania`

### Task 20: Nagranie w kolejce, trybie samodzielnym i repozytorium = [PLAN-A] Task 18

**Files:**
- Create: `HorselyKit/Repositories/RecordingRepository.swift`
- Modify: `HorselyCore/Sync/OutboxModel.swift` (`OperationKind.putRecording`, `.putRideDefaults`, `.putHorseRideProfile` — A5), `Sync/OperationCoalescer.swift`, `HorselyKit/Outbox/{OutboxProcessor,ConflictResolver}.swift` (A6, A9), mapowanie błędu `training-has-recording` → „Trening ma nagranie jazdy — usuń nagranie, aby zmienić konia lub datę.”, `Repositories/TrashRepository.swift` (kosz treningu z nagraniem)
- Test: `HorselyCore/Tests/HorselyCoreTests/RecordingQueueTests.swift`, `HorselyKit/Tests/HorselyKitTests/RecordingRepositoryTests.swift`

- [ ] **Step 1: Testy** — lista [PLAN-A] Task 18 Step 1 (zależność od treningu, `If-Match`, konflikt z porównaniem podsumowań, ponowienie konfliktu samej pogody, `trainingHasRecordingMapsToNeedsFix`, wstrzymanie bez `trainingRecordings`, kosz w trybie samodzielnym).
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(trainings): nagranie jazdy w kolejce, konfliktach i trybie samodzielnym`

### Task 21: Zakończenie jazdy, formularz, przycinanie i zapis = [PLAN-A] Task 19

**Files:**
- Create: `HorselyKit/Ride/RideFinisher.swift`, `App/Features/Ride/{RecordingCard,TrimView}.swift`
- Modify: `HorselyKit/Repositories/TrainingRepository.swift` (`createWithRecording`), `App/Features/Entries/{NewEntryView,EntryFormModel,FormSpec}.swift`, `HorselyCore/Suggest/TrainingDefaults.swift` (rodzaj z `recordedRideTrainingTypeId`)
- Test: `HorselyKit/Tests/HorselyKitTests/RideFinisherTests.swift`, `Tests/AppSnapshotTests/FinishRideSnapshotTests.swift`

**Interfaces:**
- Produces: `RideFinisher.finish(sessionId:) async throws -> FinishedRide` (`tooShort` jak [PLAN-A] Task 19); `TrainingRepository.createWithRecording(_ input:, ride:) async throws -> String` — jedna transakcja GRDB: trening → nagranie → załączniki z jazdy w kolejce; przygotowanie filmów planowane **po** zatwierdzeniu transakcji. „Anuluj”: zdjęcia i filmy z jazdy zapisywane do galerii (`PHPhotoLibrary` z poziomem `.addOnly`); odmowa → plik zostaje w `ride-media/kept/` z komunikatem.

- [ ] **Step 1: Testy** — lista [PLAN-A] Task 19 Step 1 oraz `videoPrepareScheduledAfterCommit` (błąd w transakcji → brak operacji i brak zaplanowanego przygotowania) i `discardKeepsMediaWhenGalleryDenied`.
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(ride): zakonczenie jazdy, wypelniony formularz treningu, przycinanie i zapis`

### Task 22: Szczegóły treningu z nagraniem i lista = [PLAN-A] Task 20

**Files:**
- Create: `App/Features/Ride/{RideStatsSection,GaitColors}.swift`
- Modify: `App/Features/Entries/{EntryDetailView,EntryFormView}.swift` (blokada konia i daty NAG-25), `App/Features/Entries/TimelineRow.swift` i wiersz listy treningów (ikona trasy, dystans), `App/Features/Reports/Charts/*` (wykres wysokości i prędkości — istniejące wykresy, jeśli obsługują serie liniowe; inaczej Swift Charts `LineMark`)
- Test: `Tests/AppSnapshotTests/RideStatsSnapshotTests.swift`, `HorselyKit/Tests/HorselyKitTests/TrainingWithRecordingTests.swift`

- [ ] **Step 1: Testy** — lista [PLAN-A] Task 20 Step 1 (migawki sekcji w trybie jasnym i ciemnym, Dynamic Type XXL).
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(trainings): statystyki jazdy w szczegolach treningu i blokada konia/daty`

---

## Część E — mapa i GPX

### Task 23: Mapa jazdy MapKit = [PLAN-A] Task 22 (Task 21 Androida nie dotyczy iOS)

**Files:**
- Create: `HorselyCore/Ride/RideMapModel.swift`, `App/Features/Ride/RideMapView.swift`
- Modify: `RideRecordingView` (mała mapa), `RecordingCard`, `RideStatsSection` (wejście na pełny ekran)
- Test: `HorselyCore/Tests/HorselyCoreTests/RideMapModelTests.swift`, `Tests/AppSnapshotTests/RideMapSnapshotTests.swift`

**Interfaces:**
- Produces: `struct RideMapModel { init(track:segments:pins:); var polylines: [GaitPolyline]; var start, finish: Coordinate?; func nearest(lat:lon:) -> PointInfo? }`, `struct MapPin`; widok: SwiftUI `Map` z `MapPolyline` w kolorach chodów (szerokość 5 pt), `Annotation` start/meta/pinezki (dotknięcie → `AttachmentViewer`), legenda, przełącznik „Satelita / Teren / Mapa” = `.imagery` / `.hybrid(elevation: .realistic)` / `.standard`, domyślnie Satelita; dotknięcie śladu (`MapReader` → `nearest`) pokazuje czas, prędkość i chód.

- [ ] **Step 1: Testy** — cztery testy [PLAN-A] Task 22 Step 1 (`polylinesBreakAtPauses`, `consecutiveSameGaitPointsShareOnePolyline`, `nearestPointInfo`, `pinsOnlyForMediaWithLocationInsideRideTime`); migawka legendy i przełącznika (sama mapa nie jest migawkowana — kafle z sieci).
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3:** Kompilacja częściowa „Deweloper”; właściciel sprawdza ślad na satelicie ([WYM] 10.2).
- [ ] **Step 4: Commit** — `feat(map): mapa jazdy MapKit z chodami, pinezkami i przelacznikiem widoku`

### Task 24: Eksport GPX = [PLAN-A] Task 23

**Files:**
- Create: `HorselyCore/Ride/GpxWriter.swift`
- Modify: `RideMapView`/`RideStatsSection` („Udostępnij trasę (GPX)” przez `ShareLink` z plikiem tymczasowym `application/gpx+xml`)
- Test: `HorselyCore/Tests/HorselyCoreTests/GpxWriterTests.swift`

- [ ] **Step 1: Testy** — trzy testy [PLAN-A] Task 23 (`XMLParser`), w tym `fileNameFromHorseDateAndType` → `Grom_2026-11-12_Teren.gpx`, oraz `gpxEqualsAndroidForSameTrack` (ten sam `krotka.json` → ten sam tekst co Android, jeśli Android ma plik wzorcowy GPX; inaczej porównanie punktów).
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(map): udostepnianie trasy jako GPX 1.1`

---

## Część F — pogoda

### Task 25: Pogoda Open‑Meteo = [PLAN-A] Task 24

**Files:**
- Create: `HorselyCore/Ride/Weather.swift`, `HorselyKit/Ride/WeatherFetcher.swift`, `Resources/weather/forecast.json` (kopia z Androida)
- Modify: `HorselyKit/Store/SettingsStore.swift` (`rideWeatherEnabled = true`), `Background/BackgroundTasks.swift` (pobranie oczekujących przy odświeżaniu w tle i po odzyskaniu sieci — `NWPathMonitor`)
- Test: `HorselyCore/Tests/HorselyCoreTests/WeatherTests.swift`, `HorselyKit/Tests/HorselyKitTests/WeatherFetcherTests.swift`

- [ ] **Step 1: Testy** — lista [PLAN-A] Task 24 Step 1 (zaokrąglenie do 0,01°, archiwum dla starych jazd, wartości godziny startu, średnia długich jazd, brak godziny → `nil`, oczekujące → `fetched`, wyłączone → `disabled`, offline zostaje `pending`).
- [ ] **Step 2:** Implementacja (żądanie bez identyfikatorów, `User-Agent: zarzadzanie-konmi`, sesja bez ciasteczek i pamięci podręcznej); push → PASS.
- [ ] **Step 3: Commit** — `feat(ride): pogoda do jazd z Open-Meteo, takze po odzyskaniu zasiegu`

---

## Część G — progi i obciążenie

### Task 26: Ustawienia jazd i profil konia — dane i synchronizacja = [PLAN-A] Task 25

**Files:**
- Create: `HorselyKit/Repositories/RideSettingsRepository.swift`
- Modify: `HorselyKit/Network/ApiClient.swift` (`settings/ride-defaults` GET/PUT), `Repositories/HorseRepository.swift` (wejście konia z `rideProfile`), `HorselyKit/Sync/SyncService.swift` (odświeżenie przy zmianie `dataStamp`)
- Test: `HorselyKit/Tests/HorselyKitTests/RideSettingsRepositoryTests.swift`

- [ ] **Step 1: Testy** — lista [PLAN-A] Task 25 Step 1 (wartości wbudowane z „Teren” po nazwie, `If-Match` przy zapisie ustawień i `"0"` za pierwszym razem, profil z pełnym wejściem konia i jego wersją, odświeżenie po `dataStamp`, profil lokalny zostaje po pełnym pobraniu z serwera v1).
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(rides): ustawienia domyslne jazd i profil konia z synchronizacja`

### Task 27: Ekrany „Jazdy: chody i obciążenie” i zakładka „Jazdy” konia = [PLAN-A] Task 26 + Android 3.0.1–3.0.2

**Files:**
- Create: `App/Features/Settings/RideSettingsView.swift`, `App/Features/Horses/HorseTabs/RidesTab.swift`
- Modify: `App/Features/Horses/HorseCardView.swift` i `HorseTabs/HorseTabSupport.swift` (zakładka „Jazdy” zaraz po „Treningach”), `HorseTabs/PassportTab.swift` (bez parametrów jazdy), ekran ustawień (pozycja „Jazdy: chody i obciążenie”)
- Test: `Tests/AppSnapshotTests/RideSettingsSnapshotTests.swift`, `HorselyCore/Tests/HorselyCoreTests/RideParametersTests.swift` (logika etykiet)

**Interfaces:**
- Produces: Ustawienia jak [PLAN-A] Task 26 (opisy PAR-02 dosłownie, przykład na żywo, „Rodzaj treningu dla nagranych jazd”, „Pobieraj pogodę do jazd”, „Pokazuj instrukcję noszenia telefonu”). Zakładka „Jazdy” (Android 3.0.2): wiersze tabeli — nazwa po lewej, wartość po prawej, linie rozdzielające (`DividedList`); wartość własna pogrubiona, odziedziczona przygaszona z dopiskiem „domyślne”; „Ustaw własne” otwiera formularz, „Przywróć domyślne”.

- [ ] **Step 1: Testy** — lista [PLAN-A] Task 26 Step 1 oraz migawki `ridesTabTableOwnBoldInheritedDimmed`, `passportHasNoRideParameters`.
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(rides): ekrany progow chodow i parametrow obciazenia, zakladka Jazdy konia`

---

## Część H — raport „Analiza jazd”

### Task 28: Obliczenia raportu = [PLAN-A] Task 27

**Files:**
- Create: `HorselyCore/Reports/{RideAnalysis,RideAnalysisCalculator,RideAnalysisCsv}.swift`, `Resources/golden/ride-analysis/` (kopia 1:1 z Androida 3.0.2 z README — te same pliki co serwer)
- Test: `HorselyCore/Tests/HorselyCoreTests/RideAnalysisGoldenTests.swift`

- [ ] **Step 1:** Skopiuj wzorce; `RideAnalysisGoldenTests` parametryzowany po pięciu katalogach (JSON pole po polu w kolejności, `podstawowy` — CSV bajt w bajt: UTF-8 z BOM, `;`, `\r\n`, przecinek dziesiętny), 10 rozstrzygnięć z README jako osobne asercje tam, gdzie wzorce ich nie pokrywają.
- [ ] **Step 2:** Push → CI FAIL. **Step 3:** Implementacja (polska kolejność nazw — istniejące porównanie z `LocalReports`) → PASS.
- [ ] **Step 4: Commit** — `feat(reports): raport Analiza jazd w telefonie, zgodny z wzorcami`

### Task 29: Raport w aplikacji = [PLAN-A] Task 28

**Files:**
- Create: `App/Features/Reports/RideAnalysisReportView.swift`
- Modify: `HorselyKit/Repositories/ReportRepository.swift` (`rideAnalysis(_:)` — serwer przy `trainingRecordings` i połączeniu, inaczej lokalnie), `HorselyKit/Network/ApiClient.swift` (`reports/ride-analysis`, `format=csv`), lista raportów (pozycja po „Zawody jeźdźca”), `App/Features/Reports/Export/*` (CSV, PDF), `TrainingSummaryReportView.swift` i `RiderReportViews.swift` (wzmianka „Z nagraniem: N z M treningów · X km”)
- Test: `HorselyKit/Tests/HorselyKitTests/ReportRepositoryRideTests.swift`, `Tests/AppSnapshotTests/RideAnalysisSnapshotTests.swift`

- [ ] **Step 1: Testy** — lista [PLAN-A] Task 28 Step 1; mapa tras jako `Map` z wieloma `MapPolyline` (przezroczystość 0,5).
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(reports): ekran Analiza jazd z mapa tras, CSV i PDF`

---

## Część I — synchronizacja, przejścia trybów i wydanie

### Task 30: Pobieranie nagrań i tras z serwera = [PLAN-A] Task 29

**Files:**
- Create: `HorselyKit/Ride/TrackFetcher.swift`
- Modify: `HorselyKit/Sync/SyncService.swift`, `HorselyCore/Sync/SyncMerger.swift`, `Background/BackgroundTasks.swift`
- Test: `HorselyKit/Tests/HorselyKitTests/RecordingSyncTests.swift`, `HorselyCore/Tests/HorselyCoreTests/SyncMergerTests.swift`

- [ ] **Step 1: Testy** — lista [PLAN-A] Task 29 Step 1, w tym `syncMergerKeepsRecordingsOnV1Server` (pełne pobranie bez kolekcji → nagranie, trasa, profil, ustawienia zostają) i `trackFetcherDownloadsMissingTracks`.
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3: Commit** — `feat(sync): pobieranie nagran, tras, profili i ustawien jazd`

### Task 31: Przejścia trybów, blokady, sprzątanie i scenariusze odbioru = [PLAN-A] Task 30

**Files:**
- Create: `HorselyKit/Ride/RideMediaJanitor.swift`, `specs/004-treningi-nagrania/acceptance-results.md`
- Modify: przejścia trybów i „Rozłącz” (`App/Features/Settings/WorkModeView.swift`, `ConnectionSettingsView.swift`, logika w `HorselyKit`), przywracanie kopii (`BackupService`), ostrzeżenia o jedynej kopii (jazdy z trasą wymienione w oknach przejścia, przywracania i braku hasła kopii)
- Test: `HorselyKit/Tests/HorselyKitTests/ModeSwitchRideTests.swift`, `RideAcceptanceTests.swift`

- [ ] **Step 1: Testy** — lista [PLAN-A] Task 30 Step 1 oraz `unsavedRideBlocksModeSwitchRestoreAndDisconnect` (komunikaty „Zakończ nagrywanie jazdy, zanim …” / „Zapisz lub odrzuć nagraną jazdę, zanim …” z `strings.xml`), `janitorRemovesUnreferencedRideFilesOlderThanHour`, `RideAcceptanceTests` — [WYM] 10.1, 10.4–10.7 i [ZAK] 10.1 na `FakeProgram`.
- [ ] **Step 2:** Implementacja; push → PASS.
- [ ] **Step 3:** Kompilacja częściowa „Deweloper”; właściciel z lokalnym serwerem 3.0 (nie `192.168.18.33`): [WYM] 10.1–10.3, 10.8 i [ZAK] 10.2–10.5. Wyniki i to, czego nie sprawdzono, do `acceptance-results.md`.
- [ ] **Step 4: Commit** — `test: scenariusze odbioru 3.0 i przejscia trybow z nagraniami`

### Task 32: Dokumentacja i wydanie 3.0.0

**Files:**
- Modify: `project.yml` (`MARKETING_VERSION: "3.0.0"`), `App/PrivacyInfo.xcprivacy` (precyzyjna lokalizacja: funkcjonalność aplikacji, bez śledzenia), `CHANGELOG.md` (sekcja 3.0.0 na wzór Androida 3.0.0–3.0.2, z „Prywatność”, „Wymaga”, „Znane ograniczenia”; zmiana push „czekam na zgodę” z `a355b44`), `README.md`, test pakietu z oczekiwaną wersją (`3.0.0`)

- [ ] **Step 1:** Zmiany dokumentów i wersji; push → CI na gałęzi zielone.
- [ ] **Step 2:** PR do `main` i scalenie po zielonym CI na `main` (zgoda właściciela).
- [ ] **Step 3:** Tag `v3.0.0` → przebieg `Release`; podaj wersję, numer kompilacji i wynik wysyłki (link `gh run view`). Brak sekretów podpisu / klucza ASC → powiedz wprost. Przypomnij właścicielowi o etykietach prywatności w App Store Connect.
- [ ] **Step 4:** Zaktualizuj pamięć `testflight-last-build.md` (wersja, numer, data, przypomnienie po 80 dniach).
- [ ] **Step 5: Commit** — `chore: wydanie 3.0.0 - zalaczniki treningow i nagrywanie jazdy`

### Task 33 (gdy Android dostroi chody — [PLAN-A] Task 32)

- [ ] **Step 1:** Skopiuj nowe wzorce `golden/ride-stats` i zmiany `GaitBands` / `algorithmVersion = 2` z Androida; `RideStatsGoldenTests` → PASS.
- [ ] **Step 2: Commit** — `feat(core): algorytm chodow v2 zgodny z Androidem`
