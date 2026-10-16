---

description: "Lista zadań: Horsely na iOS — pełny zakres aplikacji na Androida 2.0.1"
---

# Tasks: Horsely na iOS — pełny zakres aplikacji na Androida 2.0.1

**Input**: `specs/001-aplikacja-ios-horsely/` — [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md); normatywnie
[SPECYFIKACJA_MOBILE_IOS.md](../../SPECYFIKACJA_MOBILE_IOS.md) 1.5 (dalej „SG”) i `contracts/android/`.

**Tests**: obowiązkowe (konstytucja VI — niepodlegające negocjacji): testy jednostkowe `HorselyCore`/`HorselyKit`, pliki
wzorcowe programu, zaślepka API, testy migawkowe i UI. Testy piszemy przed implementacją danego elementu i muszą najpierw
nie przechodzić.

**Organization**: fazy wg historii użytkownika ze spec.md. Na Windows nie ma kompilacji — każde zadanie kończy się
zielonym przebiegiem CI (`gh run watch`), nie lokalnym uruchomieniem.

## Format: `[ID] [P?] [Story] Opis ze ścieżką`

- **[P]**: można równolegle (inne pliki, brak zależności od nieukończonych zadań)
- **[USn]**: historia ze spec.md
- Ścieżki wg struktury z plan.md: `project.yml`, `Packages/HorselyCore/…`, `Packages/HorselyKit/…`, `App/…`,
  `ShareExtension/…`, `Tests/…`, `scripts/…`, `.github/workflows/…`

---

## Phase 1: Setup (infrastruktura projektu)

**Purpose**: projekt generowany XcodeGen, pakiety, CI i pierwsza kompilacja w TestFlight (wczesne potwierdzenie R19).

- [X] T001 Utwórz `project.yml` (XcodeGen): cele `Horsely` (iOS 18.0, iPhone, `pl.glapa.horsely`, `MARKETING_VERSION` 2.0.1, `CURRENT_PROJECT_VERSION` z ustawienia), `HorselyShare` (`pl.glapa.horsely.ShareExtension`), `AppUITests`, `AppSnapshotTests`; uprawnienia App Group `group.pl.glapa.horsely` i współdzielona grupa pęku kluczy; Swift 6, ostrzeżenia jako błędy; `DEVELOPMENT_TEAM` z `$(APPLE_TEAM_ID)`
- [X] T002 [P] Utwórz pakiet `Packages/HorselyCore/Package.swift` (Swift 6, iOS 18 / macOS 15, bez zależności) z celami `HorselyCore` i `HorselyCoreTests` (zasoby testowe `Resources/`)
- [X] T003 [P] Utwórz pakiet `Packages/HorselyKit/Package.swift` zależny od `HorselyCore`, GRDB.swift (najnowsza wersja 7.x), ZIPFoundation (najnowsza 0.9.x) z celem testów `HorselyKitTests`
- [X] T004 [P] Dodaj szkielet aplikacji `App/HorselyApp.swift` (pusty `TabView`), `App/Info.plist` (klucze z contracts/app-entry-points-ios.md: `CFBundleDisplayName` „Horsely”, `CFBundleURLTypes` `horsely`, `NSCameraUsageDescription`, `NSLocalNetworkUsageDescription`, `NSFaceIDUsageDescription`, `BGTaskSchedulerPermittedIdentifiers`, `UIApplicationShortcutItems`, `NSAppTransportSecurity`→`NSAllowsLocalNetworking`), `App/Horsely.entitlements`
- [X] T005 [P] Dodaj szkielet rozszerzenia `ShareExtension/ShareViewController.swift`, `ShareExtension/Info.plist` (`NSExtensionActivationRule` z contracts/app-entry-points-ios.md), `ShareExtension/HorselyShare.entitlements`
- [X] T006 [P] Uzupełnij `.gitignore` o `*.xcodeproj/`, `fixtures/*.local`, `screenshots/`
- [X] T007 Utwórz `.github/workflows/ci.yml` wg contracts/ci-release.md §2 (PR: `xcodegen generate`, `swift test` obu pakietów, kompilacja symulatora, testy migawkowe; `main`: + testy UI iPhone 15 Pro iOS 18 + artefakty `screenshots/ios`, `.xcresult`; pamięć podręczna SPM; jawny wybór Xcode)
- [X] T008 Utwórz `.github/workflows/release.yml` i `scripts/ci/ExportOptions.plist` wg contracts/ci-release.md §3 (krok „Sprawdź sekrety” z listą brakujących nazw, zapis `ASC_KEY_P8` do `$RUNNER_TEMP/AuthKey.p8` i usunięcie w `always()`, `xcodebuild archive` z `-allowProvisioningUpdates -authenticationKeyPath/-ID/-IssuerID`, `CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`, `-exportArchive` z `destination=upload`, podsumowanie przebiegu z wersją, numerem i wynikiem)
- [X] T009 Uruchom `release.yml` ręcznie (`gh workflow run release.yml -f group=Deweloper`) na szkielecie aplikacji i potwierdź kompilację w TestFlight „Deweloper”; wynik (działa podpisywanie w chmurze albo przejście na fastlane `match`) zapisz w `specs/001-aplikacja-ios-horsely/research.md` R19
- [X] T010 [P] Napisz `scripts/sync-strings.ps1` (Windows PowerShell 5.1 i `pwsh`): kopiuje `strings.xml`/`plurals.xml` z `-AndroidRepo` do `App/Resources/android/`, generuje `App/Resources/Localizable.xcstrings` (klucze z Androida, `%1$s`→`%1$@`, `%1$d`→`%1$lld`, liczba mnoga PL one/few/many/other, apostrofy i `\n` jak w Androidzie) — research R10
- [X] T011 Uruchom `scripts/sync-strings.ps1 -AndroidRepo ..\zarzadzanie_konmi_android` i zatwierdź `App/Resources/Localizable.xcstrings` oraz kopie w `App/Resources/android/`
- [X] T012 [P] Pobierz ikony Material (Outlined, SVG 24 px, repozytorium Google `material-design-icons`) z tabeli SG 5.4 do `App/Resources/Assets.xcassets/Icons/<nazwa>.imageset` (szablonowe, zachowane wektory) i dopisz licencję Apache 2.0 do `App/Resources/Licenses.md`
- [X] T013 [P] Przenieś głowę konia (`ic_horse_head.xml` → `App/Resources/Assets.xcassets/Icons/horse_head.imageset/horse_head.svg`) i ikonę aplikacji (podkowa z 6 otworami na gradiencie `#2C7756`→`#1D553E`, 1024 px, wariant ciemny i barwiony) do `App/Resources/Assets.xcassets/AppIcon.appiconset/` wg SG 5.4
- [X] T014 [P] Skopiuj pliki wzorcowe z Androida: `core/src/test/resources/parity/` → `Packages/HorselyCore/Tests/HorselyCoreTests/Resources/parity/`, `golden/` → `…/Resources/golden/` (z plikiem `SOURCE.md`: commit `c4a869d`, wersja programu 2.0.0)

**Checkpoint**: CI zielone na pustym projekcie, pierwsza kompilacja w TestFlight „Deweloper”.

---

## Phase 2: Foundational (wspólne podstawy wszystkich historii)

**Purpose**: model danych, magazyn, formaty, system projektowy i powłoka aplikacji.

**⚠️ CRITICAL**: żadna historia nie zaczyna się przed ukończeniem tej fazy.

### Testy podstaw

- [X] T015 [P] Testy formatów w `Packages/HorselyCore/Tests/HorselyCoreTests/FormatsTests.swift`: daty `30.09.2026`, kwoty `1 250,00 zł` (spacja niełamliwa jak w Androidzie `FormatsTest`), czas „1 h 5 min” / „45 min” / „—”, gwiazdki „★★★☆☆”, wprowadzanie kwot z przecinkiem (przypadki z `MoneyInputTest`, `StarsTest`)
- [X] T016 [P] Testy modelu w `Packages/HorselyCore/Tests/HorselyCoreTests/ExportModelTests.swift`: odczyt `parity/maly/export.json` (schemat 1.4/1.5), status `Injured`, nieznane pola ignorowane, zapis i ponowny odczyt bez zmian
- [X] T017 [P] Testy magazynu w `Packages/HorselyKit/Tests/HorselyKitTests/RecordStoreTests.swift`: zapis/odczyt rekordów wszystkich `RecordType`, indeksy `horseId`/`dateKey`/`ownerId`, `record_horse` dla zakupu wielu koni, transakcja rekord + licznik zmian, obserwacja zmian
- [X] T018 [P] Test kontrastu palety w `Tests/AppSnapshotTests/PaletteContrastTests.swift` (pary z SG 5.4: tekst ≥ 4,5:1, ikony i paski ≥ 3:1, oba motywy)
- [X] T019 [P] Test zgodności tekstów w `Tests/AppSnapshotTests/StringsParityTests.swift`: każdy klucz `App/Resources/android/strings.xml` istnieje w `Localizable.xcstrings` z tą samą treścią po konwersji formatów; brak nazwy „Zarządzanie końmi” w tekstach (SC-008 SG)

### Rdzeń (`HorselyCore`)

- [X] T020 [P] `Packages/HorselyCore/Sources/HorselyCore/Model/LocalDate.swift`, `Money.swift` (`Decimal`, 2 miejsca, zaokrąglenie jak program), `Clock.swift` (wstrzykiwany zegar „dziś/teraz”)
- [X] T021 [P] `Packages/HorselyCore/Sources/HorselyCore/Model/Enums.swift`: `HorseStatus` (`Active`/`Injured`/`Sold`/`Deceased`/`Leased`), `Sex`, `ReminderKind`, `ReminderStatus`, `ContactType` (z `Trainer`, `Rider`), `Intensity`, `ResultStatus`, `PurchaseAssignment`, `MedicationMode`, `RecordType`, `SyncState`, `WorkMode`
- [X] T022 `Packages/HorselyCore/Sources/HorselyCore/Model/ExportRecords.swift`: Codable rekordy eksportu 1.5 (koń z `finance`, 4 rodzaje wizyt z lekami, zawody, start, zakup, notatka, trening z `coaching`, termin, kontakt, słownik, załącznik) wg `contracts/android/export-schema-1.4.json` + zmian 1.5; `ExportDocument` z `scope`, `trashed`, `purged`
- [X] T023 [P] `Packages/HorselyCore/Sources/HorselyCore/Format/Formats.swift`: daty, kwoty, czas, gwiazdki, imię konia w listach (bez pustych nawiasów u źrebaka)
- [X] T024 [P] `Packages/HorselyCore/Sources/HorselyCore/Model/EnumLabels.swift`: polskie nazwy wartości wyliczeniowych (klucze `strings.xml`, np. `Deworming`→„Odrobaczanie”, `Deceased`→„Padł”, `Injured`→„Kontuzjowany”)

### Magazyn (`HorselyKit`)

- [X] T025 `Packages/HorselyKit/Sources/HorselyKit/Store/Database.swift`: `DatabasePool` w App Group (WAL, `isExcludedFromBackup`, ochrona `completeUntilFirstUserAuthentication`), migracja `v1` z tabelami `local_record`, `record_horse`, `local_file`, `queue_operation`, `queue_history`, `conflict`, `local_meta`, `address` i indeksami z data-model.md §2
- [X] T026 `Packages/HorselyKit/Sources/HorselyKit/Store/RecordStore.swift`: CRUD rekordów (treść JSON, `version`, `syncState`, `baseVersion`, `deletedAt`, `deletionBatchId`), zapytania po koniu/dacie/właścicielu, `changeCounter` w każdej transakcji zapisu, `ValueObservation` jako `AsyncSequence`
- [X] T027 [P] `Packages/HorselyKit/Sources/HorselyKit/Store/SettingsStore.swift`: `UserDefaults` grupy z kluczami i wartościami domyślnymi z data-model.md §5 (`workMode` domyślnie `unset`, `notifications.dailyTime` 08:00, `data.timelineMonths` 12, `data.attachmentLimitMB` 200, `data.wifiOnly` true)
- [X] T028 [P] `Packages/HorselyKit/Sources/HorselyKit/Log/DiagnosticLog.swift`: zdarzenia bez danych osobowych, rotacja 2 × 2,5 MB w App Group (NFR-M-06)
- [X] T029 [P] `Packages/HorselyKit/Sources/HorselyKit/Security/KeychainStore.swift`: klucz API `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, grupa dostępu wspólna z rozszerzeniem

### System projektowy i powłoka (`App`)

- [X] T030 [P] `App/DesignSystem/HorselyColor.swift` + kolory w `App/Resources/Assets.xcassets/Colors/` (jasny/ciemny) — paleta motywu, ostrzeżenie, „Nadchodzące”, kolory rodzajów wpisów i działów z SG 5.4. **Odstępstwo**: paleta jest tabelą szesnastkową w Swift (`ColorPair`), a nie zestawami kolorów w katalogu zasobów — jedno źródło prawdy dla aplikacji i testu kontrastu (T018), kolory dynamiczne jasny/ciemny przez `UIColor`
- [X] T031 [P] `App/DesignSystem/Spacing.swift`, `SectionHeader.swift`, `DividedList.swift` (linia 1 pt, wcięcie 16 pt, tylko między wierszami), `InfoCard.swift` (tony Neutral/Primary/Warning, promień 12 pt, ramka 1 pt), `AccentIcon.swift` (kółko 12 %), `AccentRow.swift` (pasek 4 pt)
- [X] T032 [P] `App/DesignSystem/StarRating.swift` (wyświetlanie ★ w kolorze ostrzeżenia, „Ocena: N z 5”/„Brak oceny”; wejście 5 przycisków ≥ 44 pt + „Wyczyść”), `HorseAvatar.swift` (okrąg 40/72 pt, głowa konia), `InjuredBadge.swift` (`healing` 18 pt + „Kontuzjowany”), `FormSaveBar.swift`, `SaveBanner.swift` („Zapisano” + „Cofnij”, 4 s), `ScreenState.swift` (ładowanie/pusto/błąd z „Spróbuj ponownie”)
- [X] T033 `App/Shell/RootView.swift`: `TabView` Pulpit · Konie · Terminy · Treningi · Więcej z ikonami i kolorami działów, plakietka licznika kolejki na „Więcej”, przycisk „+” nad paskiem (Pulpit, Konie, Terminy), wybór motywu (`preferredColorScheme`)
- [X] T034 `App/Shell/MoreView.swift`: pozycje wg trybu (SG 5.2, contracts/android/ui-screens.md §3), separator pełnej szerokości, licznik/strzałka
- [X] T035 `App/Shell/DeepLinkRouter.swift`: adresy `horsely://` z contracts/app-entry-points-ios.md (nieznany → Pulpit; tryb nieustawiony → powitanie)
- [X] T036 `App/Shell/AppEnvironment.swift`: kontener zależności (magazyn, ustawienia, zegar, dziennik), tryb pracy z `SettingsStore`, argumenty testowe `-UITestFixture`/`-UITestToday` tylko w konfiguracji Debug (contracts/test-fixtures.md)
- [X] T037 Test migawkowy powłoki w `Tests/AppSnapshotTests/ShellSnapshotTests.swift` (pasek kart i „Więcej” w obu trybach, jasny/ciemny/XXXL)

**Checkpoint**: aplikacja uruchamia się z pustymi kartami, magazyn i formaty przetestowane, teksty i ikony zgodne z Androidem.

---

## Phase 3: User Story 1 — Pierwsze uruchomienie i konie w trybie samodzielnym (P1) 🎯 MVP (techniczne)

**Goal**: wybór trybu, tryb samodzielny, lista/karta/formularz konia, zdjęcie z kadrowaniem, status „Kontuzjowany”.

**Independent Test**: spec.md US1 (świeża instalacja w trybie samolotowym → 2 konie + źrebak → zdjęcie → „Kontuzjowany”).

### Testy US1

- [X] T038 [P] [US1] Testy walidacji konia w `Packages/HorselyCore/Tests/HorselyCoreTests/HorseRulesTests.swift`: „Numer paszportu wymagany, chyba że zaznaczono Źrebak”, unikalność paszportu, unikalne imię źrebaka bez paszportu (`409` → błąd przy imieniu), `farrierIntervalWeeks` 1–26, `Deceased` → `salePrice = 0`, przejścia `Active`↔`Injured` — teksty komunikatów z plików `parity`
- [X] T039 [P] [US1] Test wyszukiwania koni w `Packages/HorselyCore/Tests/HorselyCoreTests/HorseSearchTests.swift` (imię, paszport, imię stajenne; bez wielkości liter i polskich znaków; domyślnie aktywne i kontuzjowane; filtry Aktywny/Kontuzjowany/Wszystkie/Źrebięta)
- [X] T040 [P] [US1] Test UI w `Tests/AppUITests/WelcomeStandaloneUITests.swift`: ekran wyboru trybu (domyślnie „Tak, połącz z programem”), „Nie, używaj samodzielnie” → Pulpit „Dodaj pierwszego konia”, ponowne uruchomienie → Pulpit
- [X] T041 [P] [US1] Test kadrowania w `Packages/HorselyKit/Tests/HorselyKitTests/PhotoCropTests.swift` (kwadrat, obrót 90°, wynik bez GPS; w pakiecie, bo ImageIO działa w `swift test` bez symulatora)

### Implementacja US1

- [X] T042 [P] [US1] `Packages/HorselyCore/Sources/HorselyCore/Rules/HorseRules.swift` (walidacja i skutki zapisu konia; komunikaty programu)
- [X] T043 [P] [US1] `Packages/HorselyCore/Sources/HorselyCore/Rules/HorseSearch.swift` (normalizacja polskich znaków jak `HorseSearch.kt`)
- [X] T044 [US1] `Packages/HorselyKit/Sources/HorselyKit/Repositories/HorseRepository.swift`: zapis konia w trybie samodzielnym (transakcja, `Local`, `version`+1), lista z filtrami, miniatury
- [X] T045 [US1] `App/Features/Welcome/ModeChoiceView.swift`: wariant B (tytuł pełna nazwa, opcje z opisami, „Dalej”, „Zmienisz to w Ustawieniach → Tryb pracy”, „Odtwórz z kopii zapasowej” po wyborze samodzielnego — akcja podpinana w US8); zgoda na powiadomienia z wyjaśnieniem
- [X] T046 [US1] `App/Features/Horses/HorsesView.swift` + `HorsesViewModel.swift`: wyszukiwanie, chipy Aktywny · Kontuzjowany · Pokaż wszystkie · Tylko źrebięta, wiersz (miniatura 40 pt, imię, „imię stajenne”, podtytuł paszportu, `InjuredBadge`), „Dodaj konia” na końcu listy, VoiceOver „<imię>, kontuzjowany”
- [X] T047 [US1] `App/Features/Horses/HorseFormView.swift` + model: sekcje Podstawowe · Szczegóły · „Kwoty konia (ocena własna)”, pola z FR-M-KON-03, status z datą i notatką (w tym „Kontuzjowany”), pole „Zdjęcie”, potwierdzenie porzucenia zmian
- [X] T048 [US1] `App/Features/Horses/HorseCardView.swift`: nagłówek (miniatura 72 pt, imię, imię stajenne, plakietka statusu, paszport, UELN, chip), przewijane zakładki Oś czasu · Terminy · Paszport · Treningi · Zawody · Zakupy · Załączniki (treść zakładek dopełniana w US2/US4/US6), „Nie znaleziono konia” z „Wróć”
- [X] T049 [P] [US1] `Packages/HorselyKit/Sources/HorselyKit/Files/ImagePreparer.swift`: zmniejszanie do 2560 px, JPEG 85 %, usuwanie GPS (ImageIO), miniatury
- [X] T050 [US1] `App/Features/Horses/HorsePhotoSheet.swift` + `PhotoCropView.swift`: „Zrób zdjęcie”, „Wybierz z telefonu” (`PhotosPicker`), „Wybierz z załączników konia” (na karcie konia; w formularzu pozostałe akcje), „Pokaż zdjęcie”, „Usuń zdjęcie” (z potwierdzeniem); kadrowanie z gestami i obrotem; poprzednie zdjęcie zostaje w załącznikach (FR-ZDK-03)
- [X] T051 [US1] `App/Features/Dashboard/DashboardView.swift` (część koni): karta „Dodaj pierwszego konia”, kafle po 2 w rzędzie (równa wysokość, treść do góry, miniatura 40 pt, imię stajenne, „bez paszportu od X mies.” z tłem ostrzegawczym od 12 mies., ikona `healing` 24 pt w prawym górnym rogu kontuzjowanego), kafel → karta konia
- [X] T052 [US1] Testy migawkowe `Tests/AppSnapshotTests/HorsesSnapshotTests.swift` (lista, karta, kafle; jasny/ciemny/XXXL; dane `zrzuty`)

**Checkpoint**: US1 działa samodzielnie bez sieci.

---

## Phase 4: User Story 2 — Wpisy, treningi, terminy i Pulpit z regułami programu (P1)

**Goal**: wszystkie formularze wpisów, terminy, Pulpit, reguły programu w telefonie (tryb samodzielny).

**Independent Test**: spec.md US2 (kowal z następną wizytą, zakup 100,01 zł dla 2 koni, trening kontuzjowanemu).

### Testy US2

- [X] T053 [P] [US2] Testy zgodności reguł na plikach `parity` (`maly`, `brzegowy`, `duzy`) w `Packages/HorselyCore/Tests/HorselyCoreTests/RulesParityTests.swift`: terminy z `nextVisitDate`, zamykanie terminu do 14 dni przed, termin z zawodów w przyszłości, podział zakupu z resztą groszową u pierwszego konia wg imienia, kafle i grupy Pulpitu (`dashboard@<data>.json`), oś czasu (`timeline/`) — wynik identyczny z programem 2.0.0
- [X] T054 [P] [US2] Testy walidacji wpisów w `Packages/HorselyCore/Tests/HorselyCoreTests/EntryValidationTests.swift`: pola wymagane z SG 6.4 (pogrubione), „data treningu nie z przyszłości”, czas 1–600, ocena 1–5, wysokość 10–200 tylko dla `training.jumping`, `deliveryCost ≥ 0`, start w dniach zawodów, trener tylko `Trainer`, jeździec tylko `Rider`
- [X] T055 [P] [US2] Testy podpowiedzi w `Packages/HorselyCore/Tests/HorselyCoreTests/SuggestionsTests.swift`: data następnej wizyty kowala z interwału, kwota = ilość × cena do ręcznej zmiany, łączny koszt z dostawą, trener/jeździec/koszt z ostatniego treningu (bez zarchiwizowanych i bez typu; nie przy edycji), mapowanie rodzaju terminu na formularz (FR-M-TER-03)
- [X] T056 [P] [US2] Test UI `Tests/AppUITests/EntryFlowUITests.swift`: „+” → rodzaj → koń (ostatnio używany na górze) → formularz z dzisiejszą datą → „Zapisano” + „Cofnij”; błąd walidacji przy polu z zachowaniem danych; pytanie „Koń jest kontuzjowany. Zapisać trening?” _Pytanie o kontuzję sprawdza test logiki `EntryFormLogicTests` (model), nie przebieg UI._

### Implementacja US2

- [X] T057 [P] [US2] `Packages/HorselyCore/Sources/HorselyCore/Rules/EntryValidation.swift` (wszystkie rodzaje wpisów, trening, termin; komunikaty programu)
- [X] T058 [P] [US2] `Packages/HorselyCore/Sources/HorselyCore/Rules/ReminderAutomation.swift` (terminy z dat następnych wizyt i zawodów, zamykanie z tolerancją 14 dni)
- [X] T059 [P] [US2] `Packages/HorselyCore/Sources/HorselyCore/Rules/PurchaseSplit.swift` (podział po równo, reszta groszowa do pierwszego konia wg imienia, porządek imion jak w programie)
- [X] T060 [P] [US2] `Packages/HorselyCore/Sources/HorselyCore/Rules/LocalViews.swift` (Pulpit: przeterminowane, nadchodzące `horizonDays`, później w miesiącu, ostatnie wpisy, koszty miesiąca i poprzedniego, kafle; oś czasu stronicowana z filtrem rodzaju)
- [X] T061 [P] [US2] `Packages/HorselyCore/Sources/HorselyCore/Suggest/` (`FarrierNextDate.swift`, `PurchaseAmount.swift`, `TrainingDefaults.swift`, `ReminderFormMapping.swift`)
- [X] T062 [US2] `Packages/HorselyKit/Sources/HorselyKit/Repositories/EntryRepository.swift`, `ReminderRepository.swift`, `TrainingRepository.swift`: zapis w jednej transakcji z regułami (rekord + skutki), „Cofnij” przez kosz lub poprzednią wersję (FR-SAM-06)
- [X] T063 [US2] `App/Features/Entries/NewEntryView.swift`: wybór rodzaju (ikony i kolory rodzajów, linie) i konia (ostatnio używane na górze); „Kilka koni” dla kowala
- [X] T064 [US2] `App/Features/Entries/EntryFormView.swift` + `FormSpec.swift`: 9 formularzy (weterynarz z lekami i szczepieniem, kowal, fizjoterapia, specjalista, notatka, zakup z „Razem” i przypisaniem, zawody, start z jeźdźcem-kontaktem, trening z wysokością dla skoków) wg SG 5.3; sekcje Podstawowe · Szczegóły · Koszty · Następna wizyta · Uwagi, „Pokaż więcej pól”, „*”, akcent koloru rodzaju w nagłówku, `FormSaveBar`, potwierdzenie porzucenia (także gest wstecz i zamknięcie arkusza) _Przełącznik nazywa się „Więcej szczegółów” (tekst z `strings.xml` Androida)._
- [X] T065 [P] [US2] `App/Components/ContactPicker.swift`, `DictionaryPicker.swift`, `HorsePicker.swift`, `MoneyField.swift`, `DateField.swift`, `MultiSelect.swift` (lista z wyszukiwaniem, „Dodaj kontakt” bez opuszczania formularza z typem; tylko aktywne pozycje słownika w nowych wpisach) _`MoneyField.swift` zawiera też `IntegerField` i `TextRow`; „Dodaj kontakt” tworzy kontakt o nazwie i typie (pełny formularz kontaktu — US8); wyszukiwanie jest w `MultiSelect`._
- [X] T066 [US2] `App/Features/Entries/EntryDetailView.swift`: sekcje jak w formularzu, gwiazdki, „Edytuj”, „Usuń” (z potwierdzeniem)
- [X] T067 [US2] `App/Features/Reminders/RemindersView.swift`, `ReminderDetailView.swift`, `ReminderFormView.swift`: filtry koń/rodzaj/status (domyślnie Otwarty)/zakres dat, linie między wierszami, akcje Zarejestruj wizytę · Zrealizowany · Odrzuć · Przełóż · Edytuj · Usuń
- [X] T068 [US2] `App/Features/Dashboard/DashboardView.swift` (pełny): szybkie dodawanie (8 chipów w kolejności z SG 5.4), obszary Przeterminowane (ostrzegawczy) / Nadchodzące (zielony) / Później w tym miesiącu (neutralny), „Brak terminów do wykonania”, Koszty (dwa obszary), Ostatnie wpisy (pasek i ikona rodzaju), zapas 96 pt dla „+”
- [X] T069 [US2] Zakładki karty konia w `App/Features/Horses/HorseTabs/`: `TimelineTab.swift` (chipy filtra, „Pokaż starsze”), `RemindersTab.swift` (obszary terminów), `PassportTab.swift` (dane i szczepienia), `TrainingsTab.swift` (filtry, „Treningów: N · Razem: kwota”), `CompetitionsTab.swift` (statystyki i starty), `PurchasesTab.swift`; „Najbliższe terminy”, „Koszty <rok>”, skrót bilansu z „Pełny bilans” _Zakładka „Załączniki” — treść w US6; „Pełny bilans” — raporty (US9)._
- [X] T070 [US2] Testy migawkowe `Tests/AppSnapshotTests/EntriesSnapshotTests.swift` (Pulpit, formularz weterynarza, Terminy, zakładki karty konia; dane `zrzuty`, dziś 2026-10-05)

**Checkpoint**: tryb samodzielny w pełni używalny dla koni, wpisów, treningów i terminów.

---

## Phase 5: User Story 3 — Połączenie z programem i pełna praca offline (P1)

**Goal**: parowanie, połączenie w domu i spoza domu, magazyn programu, kolejka, konflikty, możliwości programu 2.0.0.
Po tej fazie — pierwsza kompilacja dla grupy „Właściciele” (quickstart §7).

**Independent Test**: spec.md US3 (skan QR, praca offline z konfliktem, połączenie przez dane komórkowe).

### Testy US3

- [X] T071 [P] [US3] Testy reguł adresów i kodu QR w `Packages/HorselyCore/Tests/HorselyCoreTests/ConnectionRulesTests.swift` (przypadki z `AddressRulesTest`, `PairingCodeTest`: `http` tylko IP prywatne i `.local`, `remoteUrl` jako drugi adres, nieznane pola QR ignorowane, minimalna wersja 1.5.0, wersja testowana 2.0.0)
- [X] T072 [P] [US3] Testy łączenia operacji w `Packages/HorselyCore/Tests/HorselyCoreTests/OperationCoalescerTests.swift` (tabela FR-SYN2-04: dodanie+edycja, dodanie+usunięcie z zależnymi, edycja+edycja z `baseVersion` pierwszej, edycja+usunięcie; operacje `Sending`/`Unknown`/`Conflict` nie są łączone)
- [X] T073 [P] [US3] Testy scalania eksportu w `Packages/HorselyCore/Tests/HorselyCoreTests/SyncMergerTests.swift` (pełne i przyrostowe: `Pending`/`Conflict` nienadpisywane, nieobecność = usunięcie, `trashed`/`purged`, `fullRequired`, `Projected` usuwane; przypadki z `ExportCursorIncrementalTest`, `ConflictFlowTest`)
- [X] T074 [P] [US3] Testy klienta z zaślepką `URLProtocol` w `Packages/HorselyKit/Tests/HorselyKitTests/ApiClientTests.swift`: `X-Api-Key` w każdym żądaniu, `401`/`403` z treścią i bez (wstrzymanie adresu), `429` z `Retry-After` (bez pętli, komunikat blokady > 1 min), `409` z rekordem, `413`/`415`, przerwane połączenie (odczyt ponawiany raz i na kolejnych adresach, zapis nie), `X-Client-Features` tylko przy `horseStatusInjured`, brak nowych nagłówków dla programu 1.6.1
- [X] T075 [P] [US3] Testy przypinania certyfikatu w `Packages/HorselyKit/Tests/HorselyKitTests/TrustEvaluatorTests.swift` (zgodny odcisk, inny odcisk → odmowa bez wysłania klucza, zaufany wystawca, samopodpisany bez odcisku → odmowa)
- [X] T076 [P] [US3] Testy kolejki w `Packages/HorselyKit/Tests/HorselyKitTests/OutboxProcessorTests.swift` (scenariusze `OfflineScenarioTest`, `OutboxIdempotencyTest`, `BeforeAfterCountTest`, `DeleteIfMatchTest`, `SendNowTest`: kolejność i zależności, „Wymaga poprawy” 400/404/409/413/415, „już załatwione”, licznik przed i po z kluczami dopasowania, `Idempotency-Key` i `Idempotent-Replayed`, „żądanie w toku”, „klucz z inną treścią”, odpowiedź ≤ 1 s → „Zapisano”, później → „Zapisano — wyślę po połączeniu z komputerem”, `400` w tym czasie → formularz)
- [X] T077 [P] [US3] Test rozpoznania tej samej stajni w `Packages/HorselyKit/Tests/HorselyKitTests/StableIdentityTests.swift` (FR-M-POL-08, `StableIdentityCheckTest`)

### Implementacja US3

- [X] T078 [P] [US3] `Packages/HorselyCore/Sources/HorselyCore/Connection/` (`AddressRules.swift`, `PairingCode.swift`, `ProgramVersion.swift`, `Capabilities.swift`)
- [X] T079 [P] [US3] `Packages/HorselyCore/Sources/HorselyCore/Sync/` (`OperationCoalescer.swift`, `SyncMerger.swift`, `RefreshPlan.swift` — pełne/przyrostowe/stempel/24 h, `ConflictModel.swift`, `MatchQueries.swift` — klucze licznika przed i po z contracts/android/outbox-operations.md)
- [X] T080 [US3] `Packages/HorselyKit/Sources/HorselyKit/Network/TrustEvaluator.swift` i `URLSessionFactory.swift` (delegat z trybami zaufania, ATS lokalny, limity 3 s / 30 s / 60 s bez postępu, metryki IP)
- [X] T081 [US3] `Packages/HorselyKit/Sources/HorselyKit/Network/ApiClient.swift` (zasoby SG 6.3, `If-Match`, `Idempotency-Key`, `X-Client-Features`, błędy RFC 9457 → komunikaty przy polach), `RateLimiter.swift` (actor; 100/10 s, `Retry-After`), `AddressSelector.swift` (po kolei, zapamiętanie działającego, wstrzymania 401/403/429) _Ogranicznik: 80 żądań / 10 s (zapas wobec limitu programu 100 / 10 s, jak w Androidzie i contracts/android/pairing-and-connection.md)._
- [X] T082 [US3] `Packages/HorselyKit/Sources/HorselyKit/Network/ConnectionStatus.swift` (jeden stan dla aplikacji, aktualizowany każdym żądaniem; „Odśwież” — jedno sprawdzanie naraz; sprawdzanie co 30 s na pierwszym planie, po zmianie sieci `NWPathMonitor`; „Telefon nie ma połączenia z siecią”)
- [X] T083 [US3] `Packages/HorselyKit/Sources/HorselyKit/Sync/SyncService.swift`: pierwsze pełne pobranie strumieniowe z postępem i wznawianiem, odświeżenia (start, powrót po ≥ 15 min, ręcznie), stempel, przyrostowe, pełne raz na dobę, ochrona kolejki i konfliktów, dopasowanie wyników „z pamięci” (FR-SYN2-08) _Eksport pobierany do pliku z postępem bajtów, potem uzgadniany paczkami po 500 w osobnych transakcjach; przerwanie nie przesuwa punktu ani stempla (kolejne pobranie jest idempotentne)._
- [X] T084 [US3] `Packages/HorselyKit/Sources/HorselyKit/Outbox/OutboxProcessor.swift` (actor): wysyłka w kolejności z zależnościami, ponawianie z rosnącymi odstępami, stany z data-model.md §4, licznik przed i po / `Idempotency-Key`, `If-Match` przy `DELETE` lub odczyt kontrolny, konflikty → tabela `conflict`, historia 30 dni
- [X] T085 [US3] Ścieżka zapisu trybu online w repozytoriach (`Packages/HorselyKit/Sources/HorselyKit/Repositories/*.swift`): zapis lokalny `Pending` + operacja w jednej transakcji, natychmiastowa wysyłka z oczekiwaniem ≤ 1 s, `Projected` dla skutków reguł _Zdjęcie konia w trybie online zostaje na razie w telefonie — wysyłka załączników i `horsePhotoField` w US6 (T114)._
- [X] T086 [US3] `App/Features/Pairing/`: `LocalNetworkExplainerView.swift`, `QrScannerView.swift` (VisionKit, zasłona w przełączniku aplikacji), `ManualPairingView.swift` (adres, klucz, odcisk; zasłona), `PairingResultView.swift` (wersja programu, liczba koni, ostrzeżenia `http`, wersja < 1.5.0, nowszy niż testowany), `StableMismatchView.swift` („Wyślij mimo to” / „Usuń kolejkę”)
- [X] T087 [US3] `App/Features/Connection/ConnectionOverlay.swift` + `ConnectionStatusButton.swift` + podtytuł „Dane z …”: komunikaty z US1/8–8e, zwijanie po 3 s (dłużej przy VoiceOver), ikonka pomarańczowa/czerwona w pasku nawigacji, „Odśwież”; baner pierwszego pobrania na Pulpicie
- [X] T088 [US3] `App/Features/Queue/QueueView.swift`: operacje czekające / wysyłane / wymagające poprawy, edycja i usunięcie operacji czekających, „Wyślij teraz”, historia 30 dni, licznik w „Więcej” i na karcie
- [X] T089 [US3] `App/Features/Conflicts/ConflictsView.swift`, `ConflictDetailView.swift`: lista, karta „Konflikty do rozstrzygnięcia: N” na Pulpicie, kolumny „Moja” / „Z programu” z wyróżnieniem różnic (tło + ikona), „Zachowaj moją” / „Przyjmij z programu”, zbiorczo z potwierdzeniem i liczbą, oznaczenie „konflikt” na rekordzie
- [X] T090 [US3] Oznaczenia „czeka na wysłanie” / „wymaga poprawy” / „konflikt” na osi czasu, w „Ostatnich wpisach”, na terminach (wszystkie listy w `App/Features/**`)
- [X] T091 [US3] `App/Features/Settings/ConnectionSettingsView.swift`, `AddressEditView.swift`: program i wersja, adresy (dodaj, popraw, usuń, kolejność), szyfrowanie i tryb zaufania (potwierdzenie wystawcy i nazwy), „Sprawdź połączenie”, „Połącz ponownie (nowy kod QR)”, „Rozłącz” z przypomnieniem o unieważnieniu klucza
- [X] T092 [US3] `App/Features/Settings/WorkModeView.swift` (kierunek samodzielny → online): dwa ostrzeżenia z liczbą koni i wpisów i datą kopii, „Usuń dane i połącz” (niszczący, nie domyślny), usunięcie danych dopiero po udanym parowaniu, wznowienie przerwanej zmiany
- [X] T093 [US3] `Packages/HorselyKit/Sources/HorselyKit/Background/BackgroundTasks.swift`: rejestracja `pl.glapa.horsely.refresh` (60 min / 15 min z `dataStamp`) i `pl.glapa.horsely.sync`, reguła „tylko przez Wi‑Fi” (`isExpensive`), nadrabianie przy aktywacji
- [X] T094 [US3] Szczegółowy dziennik połączeń w `Packages/HorselyKit/Sources/HorselyKit/Log/ConnectionLog.swift` (FR-030: metoda, ścieżka bez zapytania, host:port, IP z metryk, lokalny/zewnętrzny, sieć, wynik, czas; wynik każdego adresu przy sprawdzaniu)
- [X] T095 [US3] Test UI `Tests/AppUITests/PairingUITests.swift` z zaślepką programu w procesie testowym (wpis ręczny, wynik parowania, komunikat zwinięty do ikonki, konflikt rozstrzygnięty) _Zaślepka programu w aplikacji: `-UITestProgram paired/offline/conflict` (tylko Debug, `App/Shell/DemoProgram.swift`)._
- [ ] T096 [US3] Walidacja na prawdziwym programie 2.0.0 i 1.6.1 wg quickstart.md §5 (US3: domowe Wi‑Fi i dane komórkowe przez adres publiczny z HTTPS); wynik zapisz w `specs/001-aplikacja-ios-horsely/checklists/validation.md`; potem kompilacja do grupy „Właściciele” (quickstart §7)

**Checkpoint**: pierwsza wersja do codziennego użytku córki (US1–US3).

---

## Phase 6: User Story 4 — Działy Treningi, Zakupy, Zawody i kontakty (P2)

**Goal**: działy z filtrami i stopkami, kontakty z akcjami i importem.

**Independent Test**: spec.md US4.

- [X] T097 [P] [US4] Testy filtrów i stopek działów w `Packages/HorselyCore/Tests/HorselyCoreTests/SectionsTests.swift` (okres domyślny 1 stycznia – 31 grudnia, „Wyczyść filtry”, liczba i suma zgodne z programem; „Powtórz zakup” z dzisiejszą datą)
- [X] T098 [P] [US4] Testy kontaktów w `Packages/HorselyCore/Tests/HorselyCoreTests/ContactRulesTests.swift` (wyszukiwanie nazwa/telefon/e‑mail, filtr typu bez zarchiwizowanych, `InUse` → „Kontakt jest używany we wpisach — możesz go zarchiwizować”)
- [X] T099 [US4] `App/Features/Trainings/TrainingsSectionView.swift` (wszystkie konie, arkusz filtrów okres/koń/rodzaj/trener/jeździec, „Treningów: N · Razem: kwota”, gwiazdki, wysokość przy skokach, „+”)
- [X] T100 [P] [US4] `App/Features/Purchases/PurchasesView.swift` (filtry okres/kategoria/dostawca/przypisanie, „Zakupów: N · Razem: kwota”, menu wiersza „Powtórz zakup”/„Usuń”, „+” z przypisaniem „Ogólne (stajnia)”)
- [X] T101 [P] [US4] `App/Features/Competitions/CompetitionsView.swift`, `CompetitionDetailView.swift` (lista z liczbą startów i najlepszym miejscem, szczegóły ze startami, „Dodaj start”, „Edytuj”, „Usuń” z komunikatem programu)
- [X] T102 [US4] `App/Features/Contacts/ContactsView.swift`, `ContactCardView.swift`, `ContactFormView.swift`: akcje zadzwoń/SMS/e‑mail/nawigacja (Mapy)/kopiuj, historia zakupów z sumą, treningi trenera i jeźdźca, starty jeźdźca, „Archiwizuj”, import przez `CNContactPickerViewController` _Historia kontaktu i sumy działów liczone z danych w telefonie (w trybie online pełna kopia programu, FR-SYN2-08); przy braku połączenia stopka pokazuje „Podliczenie z pamięci”._
- [X] T103 [US4] Testy migawkowe `Tests/AppSnapshotTests/SectionsSnapshotTests.swift` (Treningi, Zakupy, Zawody, Kontakty)

---

## Phase 7: User Story 5 — Raporty z wykresami i eksportem (P2)

**Goal**: pięć raportów, wykresy, CSV bajt w bajt, PDF.

**Independent Test**: spec.md US5.

- [X] T104 [P] [US5] Testy raportów na plikach `parity/*/reports` i CSV `golden/` w `Packages/HorselyCore/Tests/HorselyCoreTests/ReportsParityTests.swift` (wartości co do grosza i minuty, CSV bajt w bajt: UTF‑8 z BOM, `;`, przecinek, „Łączny czas (min)”, kategorie z programu w tym „Treningi”)
- [X] T105 [P] [US5] Test układu wiersza raportu w `Tests/AppSnapshotTests/ReportRowTests.swift` (FR-027/028: „Uwagi” z tekstem „strata; brak ceny zakupu; koń nie sprzedany (wynik bieżący)”, tekst 200 %, szerokość 320 pt)
- [X] T106 [P] [US5] `Packages/HorselyCore/Sources/HorselyCore/Reports/` (`CostReport.swift`, `HorseBalance.swift`, `TrainingSummary.swift`, `RiderTrainings.swift`, `RiderCompetitions.swift`, `CsvWriter.swift`, `ReportTexts.swift`, `ChartData.swift`) — zrealizowane jako `ReportModels.swift`, `LocalReports.swift`, `ReportTables.swift` (teksty, tabele, CSV) i `ChartData.swift`
- [X] T107 [US5] `Packages/HorselyKit/Sources/HorselyKit/Repositories/ReportRepository.swift` (online: `GET /reports/*` z pamięcią ostatnich 20; samodzielny / offline: wyliczenie lokalne z oznaczeniem „z pamięci”)
- [X] T108 [US5] `App/Features/Reports/ReportsListView.swift` i pięć ekranów raportów (arkusz filtrów, sumy, karty wierszy z „Więcej szczegółów”, `ViewThatFits` dla wierszy etykieta—wartość) — lista w `ReportScaffold.swift` (`ReportsListView`), ekrany w `CostReportView.swift`, `HorseBalanceReportView.swift`, `TrainingSummaryReportView.swift`, `RiderReportViews.swift`
- [X] T109 [P] [US5] `App/Features/Reports/Charts/` (Swift Charts: słupkowy skumulowany po kategoriach, kołowy udziału, postępy z seriami wg `paletteIndex` i kształtami znaczników, legenda, opis dla VoiceOver)
- [X] T110 [US5] `App/Features/Reports/Export/PdfReportRenderer.swift` (A4, nagłówek z nazwą „Horsely”, filtrami i datą danych, tabela z sumami, wykresy przez `ImageRenderer`) i eksport CSV/PDF przez `ShareLink` / `fileExporter` z usuwaniem pliku tymczasowego; nazwa domyślna jak w programie; eksport z pamięci z datą pobrania
- [X] T111 [US5] Testy migawkowe `Tests/AppSnapshotTests/ReportsSnapshotTests.swift` (Koszty z wykresami, Bilans konia z rozwiniętym wierszem)

---

## Phase 8: User Story 6 — Zdjęcia, dokumenty i udostępnianie (P2)

**Goal**: załączniki wpisów i koni, podgląd, rozszerzenie „Udostępnij → Horsely”.

**Independent Test**: spec.md US6.

- [X] T112 [P] [US6] Testy polityki plików w `Packages/HorselyCore/Tests/HorselyCoreTests/FilePolicyTests.swift` (jpg, png, heic, webp, pdf, docx, xlsx, txt, mp4, mov; maks. 100 MB)
- [X] T113 [P] [US6] Testy operacji załączników w `Packages/HorselyKit/Tests/HorselyKitTests/AttachmentOperationTests.swift` (załącznik po swoim wpisie, także z kolejki; licznik przed i po z `sha256`; tryb samodzielny — plik w magazynie, `pinned`)
- [X] T114 [US6] `Packages/HorselyKit/Sources/HorselyKit/Files/AttachmentStore.swift` (pliki w App Group, LRU z limitem 200 MB w trybie online, `pinned` dla miniatur i trybu samodzielnego, ostrzeżenie < 500 MB wolnego miejsca) i `Outbox/BackgroundUploader.swift` (sesja w tle `pl.glapa.horsely.upload`, postęp, wznawianie)
- [X] T115 [US6] `App/Features/Attachments/AddAttachmentSheet.swift` (aparat, galeria — wiele, pliki; opis), `AttachmentsGrid.swift` (miniatury), `AttachmentViewer.swift` (obraz z powiększaniem, PDF, wideo z przewijaniem, „Zapisz na urządzeniu” / „Udostępnij”, „Usuń” z potwierdzeniem), zakładka „Załączniki” karty konia — sekcja i siatka w `AttachmentsGrid.swift` (także w szczegółach wpisów), podgląd przez QuickLook
- [X] T116 [US6] `ShareExtension/ShareFlowView.swift` + `ShareViewController.swift`: kopia plików do App Group strumieniowo, wybór konia i wpisu albo „Nowa notatka”, zapis operacji/rekordu w bazie App Group, komunikaty dla pliku niedozwolonego i trybu nieustawionego (contracts/app-entry-points-ios.md) — rozszerzenie czyta bazę tylko do odczytu i zapisuje pozycję skrzynki App Group (`SharedInbox`); załączniki tworzy aplikacja (T117), contracts/app-entry-points-ios.md
- [X] T117 [US6] Przetwarzanie plików z rozszerzenia przy otwarciu aplikacji (`App/Shell/SharedInboxProcessor.swift`: zmniejszanie zdjęć, wysyłka)

---

## Phase 9: User Story 7 — Powiadomienia o terminach (P2)

**Goal**: lokalne powiadomienia bez serwera.

**Independent Test**: spec.md US7.

- [X] T118 [P] [US7] Testy planu powiadomień w `Packages/HorselyCore/Tests/HorselyCoreTests/ReminderDigestTests.swift` (przypadki `ReminderDigestTest`: treść „X przeterminowanych, Y na dziś i jutro”, brak powiadomienia bez terminów, dopisek przy danych > 7 dni, „Grom — kowal, dziś”, ukrycie szczegółów, limit ≤ 60 — 14 dni podsumowań + najbliższe terminy, koń kontuzjowany jak aktywny)
- [X] T119 [US7] `Packages/HorselyCore/Sources/HorselyCore/Notify/ReminderDigest.swift` i `Packages/HorselyKit/Sources/HorselyKit/Notifications/NotificationScheduler.swift` (`UNCalendarNotificationTrigger`, identyfikatory `daily-…`/`due-…`, przeliczenie po odświeżeniu i akcjach, dotknięcie → `horsely://`) — plan: 14 podsumowań dziennych liczonych na swój dzień + najbliższe terminy (≤ 60), test planisty `NotificationSchedulerTests.swift`
- [X] T120 [US7] `App/Features/Settings/NotificationSettingsView.swift` (włącz/wyłącz z prośbą o zgodę i wyjaśnieniem, godzina, w dniu terminu, ukrywanie szczegółów, instrukcja włączenia zgody po odmowie)

---

## Phase 10: User Story 8 — Kosz, słowniki, kopia zapasowa i zmiana trybu (P2)

**Goal**: zabezpieczenie danych trybu samodzielnego i wymiana kopii z Androidem.

**Independent Test**: spec.md US8 (kopia z Androida ↔ iPhone).

- [X] T121 [P] [US8] Testy kosza w `Packages/HorselyCore/Tests/HorselyCoreTests/TrashRulesTests.swift` (partie z zależnymi, przywrócenie z kontrolą powiązań, trwałe usunięcie, opróżnienie; zgodność z `parity`)
- [X] T122 [P] [US8] Testy słowników w `Packages/HorselyCore/Tests/HorselyCoreTests/DictionaryRulesTests.swift` (domyślny zestaw programu 2.0.0 — rodzaje treningów: Ujeżdżenie, Skoki, Teren, Lonża, Karuzela, Spacer, Zajeżdżanie, Gimnastyka, Wszechstronny, Inne; jednorazowe dopisanie Zajeżdżanie/Gimnastyka/Wszechstronny bez względu na wielkość liter, spacje i polskie znaki; brak rodzajów → pełna lista; zakaz usunięcia systemowych i używanych)
- [X] T123 [P] [US8] Testy kopii w `Packages/HorselyKit/Tests/HorselyKitTests/BackupTests.swift` (przypadki `BackupRoundTripTest`, `BackupCorruptionTest`, `BackupInjuredTest`: z hasłem i bez, błędne hasło, obcięty plik, zmieniony bajt, zła suma `sha256`, `formatVersion` 3 → „Kopia z nowszej wersji aplikacji”, odtworzenie formatu 1 i 2, **plik utworzony przez Androida 2.0.1** w zasobach testu odtwarza się z identycznymi rekordami i `sha256`) — wzorcowe pliki wygenerowane kodem `BackupWriter` Androida 2.0.1 (`Resources/backup/SOURCE.md`)
- [X] T124 [P] [US8] `Packages/HorselyCore/Sources/HorselyCore/Rules/TrashRules.swift`, `DictionaryRules.swift`, `DictionaryUpgrades.swift` — zrealizowane jako `DictionaryRules.swift` (`DictionaryNames`, `DictionaryUpgrades`, operacje słowników w `RuleEngine`) i `TrashCatalog.swift` (lista, opisy, plan trwałego usunięcia — także z załącznikami usuwanych rekordów)
- [X] T125 [US8] `Packages/HorselyCore/Sources/HorselyCore/Backup/BackupFormat.swift` (manifest `formatVersion: 2`, `exportSchemaVersion: "1.5"`, nagłówek `ZKKOPIA1`, PBKDF2-HMAC-SHA256 310 000, AES-256-GCM porcjami ≤ 1 MiB z AAD z contracts/android/backup-format.md) i `Packages/HorselyKit/Sources/HorselyKit/Backup/BackupService.swift` (ZIPFoundation, DEFLATE/STORED, odtwarzanie niepodzielne przez katalog tymczasowy i jedną transakcję) — `BackupFormat.swift` w `HorselyCore/Backup`, szyfrowanie CryptoKit + CommonCrypto (PBKDF2)
- [X] T126 [US8] `App/Features/Trash/TrashView.swift`, `App/Features/Dictionaries/DictionariesView.swift`, `DictionaryValuesView.swift` (dodaj, zmień nazwę, przeciągnij, ukryj)
- [X] T127 [US8] `App/Features/Backup/BackupView.swift`: data i rodzaj ostatniej kopii, „Utwórz kopię zapasową” (hasło ×2 z ostrzeżeniem, `fileExporter`, nazwa `Zarzadzanie-konmi-kopia-RRRR-MM-DD.zkkopia`, postęp i rozmiar), „Odtwórz z kopii” (data, liczby, „Obecne dane zostaną zastąpione”), „Automatyczna kopia co tydzień” (folder przez zakładkę bezpieczeństwa, 4 najnowsze `zk-auto-*.zkkopia`, ostatni błąd i „Wskaż folder ponownie”); „Odtwórz z kopii zapasowej” na ekranie powitalnym
- [X] T128 [US8] Przypomnienie o kopii na Pulpicie („Zadbaj o kopię zapasową”, „Utwórz teraz”, „Przypomnij później” — 7 dni) i `pl.glapa.horsely.backup` w `Packages/HorselyKit/Sources/HorselyKit/Background/BackgroundTasks.swift` z nadrabianiem przy otwarciu i powiadomieniem o błędzie
- [X] T129 [US8] `App/Features/Settings/WorkModeView.swift` (kierunek online → samodzielny): ostrzeżenie z liczbą niewysłanych zmian, pobranie brakujących danych lub wskazanie braków, usunięcie połączenia i klucza

---

## Phase 11: User Story 9 — Ustawienia, blokada, dziennik diagnostyczny i skróty (P3)

**Goal**: pozostałe ustawienia i narzędzia.

**Independent Test**: spec.md US9.

- [X] T130 [P] [US9] Test UI `Tests/AppUITests/SettingsUITests.swift` (kolejność pozycji FR-M-UST-00 w obu trybach, brak „Połączenie z programem” w trybie samodzielnym, szybkie akcje otwierają właściwe ekrany)
- [X] T131 [US9] `App/Features/Settings/SettingsView.swift`, `DataSettingsView.swift` (zakres osi czasu, limit załączników, oryginały, lokalizacja zdjęć, „Wyczyść pamięć podręczną” tylko online, zajętość, „tylko przez Wi‑Fi”, „Pobieraj wszystkie załączniki” tylko online), `AppearanceSettingsView.swift` — ekran Ustawień w `ConnectionSettingsView.swift` (`SettingsHubView`); Android 2.0.1 nie ma już zakresu osi czasu na ekranie Dane, więc go nie dodano
- [X] T132 [US9] `Packages/HorselyKit/Sources/HorselyKit/Security/AppLock.swift` + `App/Features/Lock/LockOverlay.swift` (Face ID / kod, 5 min w tle, zasłona w przełączniku aplikacji, przełącznik nieaktywny bez kodu urządzenia z wyjaśnieniem, wyłączenie po usunięciu kodu z informacją) i `App/Features/Settings/AppLockSettingsView.swift` — blokada i zasłona w osobnym oknie nad arkuszami (`LockWindowHost`)
- [X] T133 [US9] `App/Features/About/AboutView.swift` (pełna nazwa, wersja 2.0.1 i kompilacja, autor „Piotr Glapa”, wersja programu, ostrzeżenie „Program <wersja> — aplikacja testowana z 2.0.0…”, tryb zgodności, licencje) i `DiagnosticLogView.swift` (rozmiar, wpisy od najnowszych, czcionka o stałej szerokości, „Wyślij” z tematem „Log diagnostyczny — Horsely”, „Wyczyść” z potwierdzeniem, „Dziennik jest pusty.”); przełącznik „Szczegółowy dziennik połączeń” z „Włączony do …” w `ConnectionSettingsView.swift`
- [X] T134 [US9] Szybkie akcje: obsługa `UIApplicationShortcutItem` w `App/Shell/DeepLinkRouter.swift` (Dodaj notatkę, Kowal, Terminy)

---

## Phase 12: Polish & Cross-Cutting

- [X] T135 [P] Przegląd dostępności wszystkich ekranów (VoiceOver, Dynamic Type do `accessibility5`, kontrast, cele ≥ 44 pt) wg contracts/android/screen-review.md (zasady E1–E8) — wynik w `specs/001-aplikacja-ios-horsely/checklists/accessibility.md`
- [X] T136 [P] Test listy zgód `Info.plist` w `Tests/AppSnapshotTests/InfoPlistPolicyTests.swift` (brak lokalizacji, kontaktów, biblioteki zdjęć, `NSAllowsArbitraryLoads`) i test „0 połączeń w trybie samodzielnym” (zaślepka `URLProtocol` zgłasza każde żądanie)
- [ ] T137 Pomiary wydajności na iPhone 15 Pro wg quickstart.md §6 (dane `parity/duzy`, znaczniki w dzienniku) — wynik w `checklists/validation.md` — **do wykonania na telefonie** (bez Maca nie ma Instruments); procedura w `checklists/validation.md`
- [X] T138 Zależność zewnętrzna (repozytorium `zarzadzanie_konmi_android`): plik `fixtures/zrzuty.zkkopia` i test zrzutów Androida na tych samych danych i dacie 2026-10-05; skopiuj PNG do `Tests/Reference/android/` i plik do `fixtures/zrzuty.zkkopia` (contracts/test-fixtures.md) — **pominięte na prośbę właściciela** (2026-10-16): funkcjonalność sprawdzana na zainstalowanej aplikacji, rozbieżności — wydanie poprawkowe
- [X] T139 Zależność zewnętrzna (repozytorium `zarzadzanie_konmi_android`): test odtwarzania kopii utworzonej przez iOS (plik z artefaktu CI iOS) — FR-KOP-09 w obie strony — kopie z artefaktu CI odtworzone kodem `BackupReader` Androida 2.0.1 (jednorazowy test JVM), wynik w `checklists/validation.md`
- [X] T140 Porównanie zrzutów iOS z Androidem dla wszystkich ekranów z contracts/test-fixtures.md §2; rozbieżności poprawione albo uzasadnione natywnym komponentem — wynik w `checklists/validation.md` — **pominięte na prośbę właściciela** (2026-10-16), patrz `checklists/validation.md`
- [X] T141 Lista kontrolna wydania z quickstart.md §7, tag `v2.0.1`, kompilacja w grupie „Właściciele”, zapis daty (przypomnienie po 80 dniach) — tag `v2.0.1` → kompilacja 23 w TestFlight 2026-10-16 (przebieg 38969761212); przypomnienie od 2027-01-04; punkty listy §7 wymagające telefonu sprawdza właściciel

---

## Dependencies & Execution Order

- **Setup (Ph1)** → **Foundational (Ph2)** → historie.
- **US1 → US2 → US3** sekwencyjnie (US2 korzysta z magazynu i ekranów konia; US3 z repozytoriów i reguł US1–US2 — praca offline w trybie online używa tych samych reguł). Po US3 — pierwsza kompilacja dla córki.
- **US4, US5, US6, US7, US8** zależą od US2 (dane wpisów); każda niezależna od pozostałych z tej grupy; części online każdej z nich korzystają z US3 (`ApiClient`, kolejka) — można je robić po US3 albo najpierw w trybie samodzielnym i dopiąć online.
- **US9** po US3 (ustawienia połączenia, dziennik połączeń) i US8 (tryb pracy).
- **Polish** na końcu; T138/T139 (Android) można zacząć równolegle po Ph2 — blokują tylko T140 i T123 (część „plik z Androida”).

## Parallel Execution Examples

- Ph1: T002, T003, T004, T005, T006, T010, T012, T013, T014 równolegle; T007 → T008 → T009 sekwencyjnie.
- Ph2: testy T015–T019 równolegle; T020, T021, T023, T024 równolegle, potem T022; T027–T032 równolegle.
- US1: T038–T041 równolegle; T042, T043, T049 równolegle.
- US2: T053–T056 równolegle; T057–T061 równolegle, potem T062.
- US3: T071–T077 równolegle; T078, T079 równolegle, potem T080 → T081 → T082–T085.
- US4–US8: po US3 każda historia w osobnym przebiegu (różne katalogi `App/Features/*`).

## Implementation Strategy

1. **MVP techniczne**: Ph1 + Ph2 + US1 — kompilacja w grupie „Deweloper” (tylko właściciel; dane testowe).
2. **Pierwsza wersja dla córki**: + US2 + US3, walidacja w domu i spoza domu (T096) → grupa „Właściciele”.
3. **Przyrosty**: US4 → US5 → US6 → US7 → US8 → US9, każdy jako kompilacja „Deweloper”, a po liście kontrolnej — „Właściciele”.
4. **Wydanie 2.0.1**: Polish (T135–T141) i tag `v2.0.1`.
5. Każde zadanie kończy się zielonym CI; kompilacja w TestFlight co najmniej raz na 80 dni.
