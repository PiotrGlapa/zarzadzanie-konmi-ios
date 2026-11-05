# Kontrakt: wspólne dane testowe i zrzuty wzorcowe z Androidem

**Wymagania**: FR-026, SC-M-12, SC-006 | **Research**: R6, R18

## 1. Dane

| Plik | Pochodzenie | Zawartość |
|---|---|---|
| `fixtures/zrzuty.zkkopia` (bez hasła, format 2) | wspólny dla obu repozytoriów; źródło prawdy w repozytorium Androida | ≥ 6 koni (aktywne, kontuzjowany, źrebak bez paszportu ≥ 12 mies., sprzedany), wpisy 8 rodzajów, terminy przeterminowane / nadchodzące / później w miesiącu, treningi z trenerem i jeźdźcem, zakup dla kilku koni, zawody ze startami, kontakty wszystkich typów, zdjęcia 2 koni |
| data „dziś” | stała: **2026-10-05** | taka sama w obu aplikacjach (wstrzykiwany zegar) |
| pliki wzorcowe reguł i CSV | `core/src/test/resources/parity`, `golden` z Androida (program 2.0.0) | kopiowane do `Packages/HorselyCore/Tests/HorselyCoreTests/Resources/` |

iOS ładuje dane argumentem uruchomienia `-UITestFixture zrzuty -UITestToday 2026-10-05` (obsługiwane tylko w konfiguracji
testowej; w Release ignorowane).

## 2. Ekrany i warianty

Ekrany: `welcome`, `dashboard`, `horses`, `horse-card` (nagłówek), `horse-timeline`, `horse-trainings`, `entry-form-vet`,
`reminders`, `trainings`, `more`, `report-balance` (z rozwiniętym „Więcej szczegółów”), `settings`.
Warianty: `light`, `dark`, `xxxl` (tekst 200 %). Nazwa pliku: `<ekran>-<wariant>.png`.

| Platforma | Generowanie | Miejsce |
|---|---|---|
| Android | test zrzutów (np. Roborazzi) na tych samych danych i dacie — **zadanie w repozytorium Androida** | `zarzadzanie_konmi_android/…/screenshots/` → kopia do `Tests/Reference/android/` w iOS |
| iOS | XCUITest na symulatorze iPhone 15 Pro w CI | artefakt `screenshots/ios/` |

Porównanie: oględziny par obrazów (te same elementy, kolejność, teksty, kolory, ikony); różnice wynikające z natywnych
komponentów iOS (pasek nawigacji, karty, przełączniki) są dozwolone (spec FR-002).

## 3. Testy migawkowe iOS

swift-snapshot-testing dla tych samych ekranów i wariantów; wzorce w `Tests/AppSnapshotTests/__Snapshots__/`; zmiana wzorca
tylko świadomym commitem (różnica z artefaktu CI przejrzana).

## 4. Argumenty testów push (spec 003, 2.1.0; tylko konfiguracja Debug)

Zaślepki i argumenty uruchomienia dla powiadomień push z serwera. W Release są ignorowane; Firebase i systemowe pytanie o zgodę
nigdy nie biorą udziału w testach UI i migawkach (`DisabledPushTokenSource`).

| Argument | Wartości | Działanie |
|---|---|---|
| `-UITestProgram push` | — | jak `paired`, a serwer ogłasza `push` (`capabilities`); `PUT`/`GET push/device` zwracają urządzenie, `GET push/rules` — dwie reguły |
| `-UITestProgram pushNoRules` | — | jak `push`, ale `GET push/rules` zwraca pustą listę (ostrzeżenie „Brak przypisanych powiadomień”) |
| `-UITestPush <stan>` | `apnsRefused` · `registered` · `pending` · `noPermission` | wymusza stan push (`fallback(.apnsUnavailable)` · `registered` · `pending` · `noPermission(asked: true)`) bez rejestratora, Firebase i zgody systemu; zaślepka serwera nadal odpowiada na `push/device` i `push/rules` |
| `-UITestOpenPush <rodzaj>` | `reminder` · `summary` · `backup` · `test` | po sekundzie symuluje dotknięcie wiadomości z serwera tego rodzaju (`type`; dla `reminder` — identyfikator terminu, którego telefon nie ma) |

Karta Pulpitu „Powiadomienia o terminach są wyłączone” jest w testach UI ukryta, chyba że podano `-UITestPush`; migawki środowiska
(`makeEnvironment`) mają ją ukrytą (`notifications.offCardDismissed`), a własną migawkę `Dashboard_notificationsOffCard` — widoczną.
