# Research: Horsely na iOS

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

Każda decyzja: **Decision** / **Rationale** / **Alternatives considered**. Punkty oznaczone „⚠ do potwierdzenia w CI”
opierają się na dokumentacji i wiedzy o narzędziach, ale nie zostały jeszcze sprawdzone w tym repozytorium — pierwszy
przebieg CI je potwierdzi albo obali (wtedy aktualizacja tego dokumentu).

## R1. Architektura — port modelu Androida

- **Decision**: Odwzorować architekturę Androida 2.0.1: magazyn rekordów w kształcie eksportu programu (`local_record`
  z treścią JSON, wersją i stanem), trwała kolejka operacji z łączeniem, tabela konfliktów, rdzeń reguł i raportów bez
  zależności od platformy. Kod pisany od nowa w Swift (decyzja Q17), z tymi samymi nazwami pojęć (`RecordType`,
  `SyncState`, `OperationKind`) co w Kotlinie.
- **Rationale**: model jest sprawdzony testami zgodności i scenariuszami offline; te same pojęcia ułatwiają porównywanie
  zachowania i przenoszenie poprawek między repozytoriami; magazyn w kształcie eksportu daje kopię zapasową i pełne
  pobranie bez mapowania.
- **Alternatives considered**: osobne tabele na każdy rodzaj rekordu (więcej migracji, rozjazd z Androidem); Kotlin
  Multiplatform (odrzucone w sesji 2026-10-15).

## R2. Warstwy i pakiety

- **Decision**: `HorselyCore` (czysty Swift + Foundation; model, reguły, raporty, CSV, logika synchronizacji, format kopii),
  `HorselyKit` (SQLite, sieć, pliki, system), cele `Horsely` (SwiftUI) i `HorselyShare` (rozszerzenie). Interfejs w MVVM
  z `@Observable` modelami ekranów; magazyn wystawia obserwowalne zapytania (GRDB `ValueObservation`) jako `AsyncSequence`.
- **Rationale**: testy `HorselyCore` nie wymagają symulatora (szybkie, tanie minuty CI); rozszerzenie korzysta z `HorselyKit`
  bez UI aplikacji.
- **Alternatives considered**: TCA (zbędna zależność i krzywa nauki), jeden moduł (wolne testy).

## R3. Magazyn danych — GRDB.swift na SQLite

- **Decision**: GRDB.swift (licencja MIT), baza w kontenerze App Group, WAL, `DatabasePool` (odczyty równoległe, jeden
  zapis), migracje `DatabaseMigrator`, `isExcludedFromBackup` na katalogu, ochrona plików `completeUntilFirstUserAuthentication`.
- **Rationale**: transakcje obejmujące rekord + operację kolejki + licznik zmian (zasada IV), indeksy jak w Androidzie,
  przewidywalne migracje, dostęp z rozszerzenia i z zadań w tle, dojrzałość (od 2015, aktywnie utrzymywana).
- **Alternatives considered**: SwiftData (brak kontroli transakcji wielotabelowych, kłopotliwe migracje, ograniczenia
  współbieżności w Swift 6); Core Data (więcej kodu, model nie pasuje do rekordów JSON); surowe SQLite C API (koszt utrzymania).

## R4. Sieć, przypinanie certyfikatów, limity

- **Decision**: `URLSession` z własnym delegatem: tryb „przypięty odcisk” (SHA‑256 certyfikatu liścia z `SecTrust`
  porównany z odciskiem z QR; nazwa hosta pomijana), tryb „zaufany wystawca” (`SecTrustEvaluateWithError`); ATS:
  `NSAllowsLocalNetworking = YES`, bez `NSAllowsArbitraryLoads`. Ogranicznik tempa (100 żądań / 10 s, `Retry-After`)
  i wstrzymania adresów jako `actor`. Limity: połączenie ≤ 3 s na adres (`timeoutIntervalForRequest` + osobny pomiar
  nawiązania), odpowiedź 30 s, pliki — przerwanie po 60 s bez postępu. IP połączenia do dziennika z `URLSessionTaskMetrics`.
- **Rationale**: wszystko dostępne w systemie; odpowiada FR-M-POL-* i 9.3; brak zależności.
- **Alternatives considered**: Alamofire (zbędne), Swift OpenAPI Generator (generowany kod trudniejszy do dopasowania do
  kolejki, idempotencji i licznika przed i po; dopuszczalny tylko do modeli — odrzucony dla prostoty, modele ręczne Codable
  zgodne ze schematem eksportu).
- ⚠ do potwierdzenia w CI/na urządzeniu: zgoda „Sieć lokalna” pojawia się przy pierwszym połączeniu z adresem prywatnym —
  ekran wyjaśnienia przed nią (9.2).

## R5. Kopia zapasowa — ZIPFoundation + CryptoKit

- **Decision**: format `.zkkopia` **2** jak w Androidzie 2.0.1 ([contracts/android/backup-format.md](contracts/android/backup-format.md)
  opisuje format 1; format 2 = schemat eksportu 1.5 w `export.json`, `formatVersion: 2`); ZIP przez ZIPFoundation (MIT;
  DEFLATE, STORED dla jpg/png/mp4/pdf), szyfrowanie AES-256-GCM (CryptoKit) porcjami ≤ 1 MiB z AAD jak w kontrakcie,
  PBKDF2-HMAC-SHA256 310 000 iteracji (`CCKeyDerivationPBKDF`). Odtwarzanie: format 1 i 2, schematy 1.3–1.5, dopisanie
  rodzajów treningów (FR-002/003).
- **Rationale**: FR-KOP-09 wymaga wymienności z Androidem; iOS nie ma publicznego API ZIP.
- **Alternatives considered**: Apple Archive (inny format); własny ZIP (ryzyko błędów zgodności).
- Test: plik z Androida (z hasłem i bez) w zasobach testów odtwarza się na iOS; plik z iOS odtwarza się w teście Androida
  (zadanie w repozytorium Androida, jak R18).

## R6. Testy migawkowe i zrzuty — swift-snapshot-testing + XCUITest

- **Decision**: swift-snapshot-testing (MIT, tylko cel testów) dla kluczowych ekranów w trzech wariantach (jasny, ciemny,
  tekst „accessibility XXXL”); wzorce w repozytorium, generowane w CI przy pierwszym przebiegu i zatwierdzane świadomie
  (artefakt → commit). Zrzuty do porównania z Androidem — XCUITest na symulatorze iPhone 15 Pro, zapisywane jako artefakt CI.
- **Rationale**: bez Maca jedyną weryfikacją wyglądu są obrazy z CI; testy migawkowe łapią regresje, zrzuty służą porównaniu.
- **Alternatives considered**: tylko oględziny na telefonie (odrzucone w Q16).

## R7. Interfejs — SwiftUI i komponenty

- **Decision**: SwiftUI, `TabView` (5 kart), `NavigationStack` w każdej karcie, arkusze (`.sheet`, `.presentationDetents`)
  dla filtrów i wyboru, `List` z własnymi separatorami (linie tylko między wierszami, wcięcie 16 pt), przycisk „+” jako
  nakładka nad paskiem kart, formularze jako `Form`/`ScrollView` z sekcjami i przypiętym „Zapisz” (`safeAreaInset(edge: .bottom)`),
  `.interactiveDismissDisabled` + potwierdzenie przy niezapisanych zmianach. Komponenty projektu odpowiadają komponentom
  Androida 1:1 ([contracts/ui-screens-ios.md](contracts/ui-screens-ios.md)).
- **Rationale**: natywne zachowanie iOS (decyzja Q3) przy identycznej treści i kolorach.
- **Alternatives considered**: UIKit (więcej kodu), odwzorowanie Material (odrzucone w Q3).

## R8. Ikony — Material Icons Outlined jako SVG w katalogu zasobów

- **Decision**: pliki SVG z oficjalnego repozytorium Google `material-design-icons` (Apache 2.0, wariant Outlined, 24 px)
  dla ikon z tabeli 5.4, dodane do `Assets.xcassets` jako obrazy wektorowe szablonowe („Preserve Vector Data”, „Render As:
  Template”); głowa konia i podkowa przeniesione z wektorów Androida do SVG (ścieżki z 5.4); licencja w „O aplikacji”.
- **Rationale**: identyczne ikony jak na Androidzie (Q4); katalog zasobów obsługuje SVG bez konwersji.
- **Alternatives considered**: SF Symbols (odrzucone w Q4), czcionka ikon (trudniejsza dostępność i barwienie).

## R9. Kolory i motyw

- **Decision**: paleta z 5.4 jako kolory w katalogu zasobów z wariantem jasnym i ciemnym (`Any`/`Dark`), dostęp przez
  typ `HorselyColor`; wybór motywu w aplikacji przez `preferredColorScheme` (systemowy = `nil`); `AccentColor` = kolor główny.
  Test jednostkowy kontrastu par (≥ 4,5:1 tekst, ≥ 3:1 ikony) jak `AccentColorsContrastTest` w Androidzie.
- **Rationale**: FR-KOL-04, zgodność z Androidem.

## R10. Teksty — `strings.xml` → `Localizable.xcstrings`

- **Decision**: kopie `strings.xml` i `plurals.xml` z Androida w `App/Resources/android/`; skrypt `scripts/sync-strings.ps1`
  (zgodny z Windows PowerShell 5.1 i `pwsh` na macOS) generuje `Localizable.xcstrings` (klucze = nazwy z Androida, formaty
  `%1$s`/`%1$d` → `%1$@`/`%1$lld`, liczba mnoga PL: one/few/many/other); test w CI regeneruje plik i porównuje z
  zatwierdzonym (różnica = błąd) oraz sprawdza, że każdy klucz używany w kodzie istnieje. Teksty w kodzie wyłącznie przez
  klucze (`String(localized: "nav_dashboard")`).
- **Rationale**: decyzja Q13; jedna prawda o tekstach; skrypt działa na Windows właściciela i w CI.
- **Alternatives considered**: ręczne kopiowanie (rozjazd), narzędzie w Swift (nie uruchomi się na Windows).

## R11. Skaner QR

- **Decision**: VisionKit `DataScannerViewController` (kody QR, `recognizesMultipleItems = false`) w `UIViewControllerRepresentable`;
  gdy `isSupported`/`isAvailable` = false — od razu „Wpisz ręcznie”.
- **Rationale**: wszystkie iPhone'y z iOS 18 mają procesor A12+ wymagany przez VisionKit; bez usług zewnętrznych.
- **Alternatives considered**: AVFoundation `AVCaptureMetadataOutput` (więcej kodu; zapasowe, jeśli DataScanner sprawi kłopot).

## R12. Praca w tle

- **Decision**: `BGAppRefreshTask` `pl.glapa.horsely.refresh` (wcześniej niż 60 min / 15 min z `dataStamp`), `BGProcessingTask`
  `pl.glapa.horsely.sync` (pełne pobranie raz na dobę, wysyłka kolejki, `requiresNetworkConnectivity`) i
  `pl.glapa.horsely.backup` (kopia automatyczna co 7 dni); wysyłka plików przez sesję `URLSession` w tle
  (`background(withIdentifier:)`, zadania z plików w App Group); nadrabianie przy `scenePhase == .active`. Reguła „tylko
  przez Wi‑Fi” przez `allowsExpensiveNetworkAccess`/`NWPath.isExpensive`.
- **Rationale**: decyzja Q6; 9.4.
- ⚠ do potwierdzenia na urządzeniu: częstotliwość wybudzeń zależy od iOS; kryteria czasowe są celem.

## R13. Powiadomienia

- **Decision**: `UNUserNotificationCenter`, `UNCalendarNotificationTrigger`; planowanie: podsumowania dzienne na 14 dni
  + powiadomienia w dniu terminu dla najbliższych, łącznie ≤ 60; identyfikatory deterministyczne (`daily-RRRR-MM-DD`,
  `due-<reminderId>`); przeliczenie po każdym odświeżeniu i akcji na terminie; dotknięcie → adres `horsely://` (contracts).
- **Rationale**: limit 64 powiadomień iOS; FR-M-POW-*.

## R14. Rozszerzenie udostępniania i App Group

- **Decision**: cel `HorselyShare` (Share Extension) z SwiftUI w `UIHostingController`: wybór konia i wpisu (albo nowa
  notatka) z magazynu w App Group, kopia pliku do App Group, zapis operacji (tryb online — kolejka; samodzielny — rekord
  załącznika) w tej samej bazie; bez połączeń sieciowych z rozszerzenia; aplikacja wysyła kolejkę przy otwarciu i w tle.
  Limit pamięci rozszerzenia — pliki kopiowane strumieniowo, zmniejszanie zdjęć odroczone do aplikacji.
- **Rationale**: 9.5; wspólna baza GRDB z koordynacją zapisów (`DatabasePool` + WAL, krótkie transakcje).

## R15. Blokada aplikacji

- **Decision**: `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`; nakładka zasłaniająca treść przy `scenePhase != .active`
  (przełącznik aplikacji); licznik 5 min od przejścia w tło; `canEvaluatePolicy` → `passcodeNotSet` = przełącznik nieaktywny.
  `NSFaceIDUsageDescription`.

## R16. Zdjęcia i kadrowanie

- **Decision**: aparat — `UIImagePickerController` (`.camera`) w `UIViewControllerRepresentable`; galeria — `PhotosPicker`
  (bez zgody); pliki — `fileImporter`; zmniejszanie do 2560 px i JPEG 85 % przez `ImageIO` z usunięciem GPS
  (`kCGImagePropertyGPSDictionary`) — HEIC wysyłany jako JPEG przy zmniejszaniu (9.5); kadrowanie — własny widok SwiftUI
  (gesty `MagnifyGesture` + `DragGesture`, obrót o 90°, kwadratowa maska), wynik renderowany `CGImage`.
- **Rationale**: bez zależności; zgodne z FR-M-ZAL-03, FR-ZDK-02.

## R17. Raporty, wykresy, PDF

- **Decision**: wartości raportów — z programu (online) albo z `HorselyCore.Reports` (samodzielny / offline); wykresy Swift
  Charts (słupkowy skumulowany, kołowy `SectorMark`, linie postępów z kształtami znaczników); PDF A4 przez
  `UIGraphicsPDFRenderer`, wykresy osadzane przez `ImageRenderer`; CSV z `HorselyCore` (UTF‑8 z BOM, `;`, przecinek
  dziesiętny) porównywany bajt w bajt z plikami `golden`; eksport przez `ShareLink` i `fileExporter`.
- **Rationale**: FR-M-RAP-*, SC-M-09.

## R18. Wspólne dane testowe i zrzuty wzorcowe (zależność od Androida)

- **Decision**: wspólny zestaw danych = plik `.zkkopia` (bez hasła) `fixtures/zrzuty.zkkopia` generowany z programu
  narzędziem `ParityFixtures` albo z Androida i trzymany w obu repozytoriach. iOS w testach UI odtwarza go przy starcie
  (argument uruchomienia `-UITestFixture zrzuty`, tylko w kompilacji testowej) i ustala datę „dziś” (wstrzykiwany zegar).
  Android dostaje test zrzutów (np. Roborazzi na Robolectric) na tych samych danych i tej samej dacie, generujący PNG
  wzorcowe (jasny, ciemny, czcionka 200 %) zapisywane w repozytorium Androida i kopiowane do `Tests/Reference/android/`.
  Szczegóły: [contracts/test-fixtures.md](contracts/test-fixtures.md).
- **Rationale**: decyzja Q3 sesji clarify; kopia zapasowa jest już wspólnym formatem obu aplikacji.
- **Alternatives considered**: ręczne zrzuty (odrzucone), wspólne JSON-y testowe (dodatkowy format do utrzymania).

## R19. CI i wydanie — GitHub Actions

- **Decision**: `ci.yml` (PR, push `main`): `brew install xcodegen` → `xcodegen generate` → `xcodebuild build-for-testing`
  → testy pakietów (`swift test` dla `HorselyCore` na macOS) → testy aplikacji, UI i migawkowe na symulatorze iPhone 15 Pro
  → artefakty (zrzuty, różnice migawek, `.xcresult`). `release.yml` (tag `v*`, `workflow_dispatch`): to samo + `xcodebuild archive`
  z `-allowProvisioningUpdates -authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` (klucz z sekretu
  `ASC_KEY_P8` zapisany do pliku tymczasowego), `CURRENT_PROJECT_VERSION = GITHUB_RUN_NUMBER`, `xcodebuild -exportArchive`
  z `ExportOptions.plist` (`method: app-store-connect`, `destination: upload`, `signingStyle: automatic`). Grupa TestFlight
  „Deweloper” z automatyczną dystrybucją; „Właściciele” — kompilacja dodawana ręcznie w App Store Connect po liście
  kontrolnej. Brak sekretów → krok kończy się błędem z komunikatem. Szczegóły: [contracts/ci-release.md](contracts/ci-release.md).
- **Rationale**: decyzje Q8–Q10, Q14, Q19, sesja clarify (grupy).
- **Wynik potwierdzenia (T009, 2026-10-15)**: podpisywanie w chmurze **działa bez fastlane `match`**, ale proces różni się od pierwotnego
  założenia:
  1. Runner `macos-15`, **Xcode 26** (`scripts/ci/select-xcode.sh`): App Store Connect odrzuca SDK starsze niż iOS 26
     (błąd 90725 przy Xcode 16.4); cel wdrożenia pozostaje iOS 18.0.
  2. Obraz runnera nie ma symulatora „iPhone 15 Pro” — `scripts/ci/create-simulator.sh` tworzy go z najnowszym środowiskiem iOS 18.
  3. Archiwum **bez podpisu** (`CODE_SIGNING_ALLOWED=NO`): zespół nie ma zarejestrowanych urządzeń, więc podpis deweloperski
     w archiwum kończy się „Your team has no devices”, a podpis doraźny jest zabroniony dla SDK urządzenia. Uprawnienia (App Group,
     pęk kluczy) wstawia `scripts/ci/embed-entitlements.sh` (podpis doraźny `codesign` z plikami `.entitlements`), a eksport
     (`-exportArchive -allowProvisioningUpdates` z kluczem API) nadaje podpis dystrybucyjny z chmury Apple i zachowuje uprawnienia
     (sprawdzane w przebiegu: `codesign -d --entitlements` na aplikacji i rozszerzeniu).
  4. Wysyłka: `xcodebuild -exportArchive` z `destination = upload` oraz `altool` kończą się błędem 3004 „Cannot verify client’s JWT headers”
     (usługa dostarczania nie uwierzytelnia klucza), choć ten sam klucz działa w REST API i przy podpisywaniu. Wysyłkę wykonuje
     `scripts/ci/upload-build.js` przez API „build uploads” (`POST /v1/buildUploads`, `buildUploadFiles`) i czeka na stan `VALID`.
     Sam eksport ma więc `destination = export` (`scripts/ci/ExportOptions.plist`).
  5. Przetwarzanie w App Store Connect wykryło 2 prawdziwe błędy pakietu (naprawione): brak `TARGETED_DEVICE_FAMILY = 1` na poziomie celów
     (wymóg orientacji iPada, błąd 90474) i stary SDK (pkt 1).
  - Kompilacja 2.0.1 (…) jest w TestFlight w stanie `VALID`; stan dla testerów wewnętrznych `MISSING_EXPORT_COMPLIANCE` — właściciel musi raz
    odpowiedzieć na pytanie o szyfrowanie w App Store Connect (albo ustalić wartość `ITSAppUsesNonExemptEncryption` w `Info.plist`; zob. uwagi w T009).
- Koszt: minuty macOS ×10; `HorselyCore` testowany `swift test` (bez symulatora) dla krótszych przebiegów; testy UI tylko
  na `main` i w wydaniu, na PR — testy jednostkowe i migawkowe.

## R20. Zegar, formaty, kwoty

- **Decision**: wstrzykiwany `Clock`/`DateProvider` (dziś, teraz) wszędzie w logice; `LocalDate` (rok, miesiąc, dzień)
  zamiast `Date` dla dat kalendarzowych; `Money` oparte na `Decimal` z zaokrągleniem bankowym/handlowym dokładnie jak
  program (zgodność sprawdzana plikami wzorcowymi); formaty `30.09.2026`, `1 250,00 zł` (spacja niełamliwa jak w Androidzie —
  bajt w bajt w CSV), czas „X h Y min”.
- **Rationale**: zasada V konstytucji; testowalność.

## Rozstrzygnięte niewiadome z Technical Context

Brak pozostałych „NEEDS CLARIFICATION”. Trzy punkty ⚠ (R4, R12, R19) wymagają potwierdzenia w praktyce, nie decyzji.
