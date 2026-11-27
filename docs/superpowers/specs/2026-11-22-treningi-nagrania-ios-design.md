# iOS 3.0: załączniki treningów i nagrywanie jazdy — zakres aplikacji iOS

| | |
|---|---|
| Data | 2026-11-22 |
| Status | Projekt do akceptacji |
| Gałąź | `004-treningi-nagrania` (z `fix/push-czekam-na-zgode`, commit `a355b44`) |
| Wymagania całości | `../zarzadzanie_konmi_android/docs/superpowers/specs/2026-11-14-treningi-nagrania-zalaczniki-design.md` (dalej **[WYM]**) — źródło wszystkich wymagań użytkowych |
| Wzorzec | Android **3.0.2** (`../zarzadzanie_konmi_android`, gałąź `007-treningi-nagrania`): projekt `…/2026-11-14-treningi-nagrania-android-design.md`, plan `…/plans/2026-11-15-treningi-nagrania-android.md` (dalej **[PLAN-A]**), `CHANGELOG.md` 3.0.0–3.0.2, `specs/007-treningi-nagrania/acceptance-results.md` |
| Kontrakt serwera | `../zarzadzanie_konmi_java/specs/012-treningi-nagrania/contracts/api-v3-recordings.md` (dalej **[K]**) |
| Kolejność | 1) serwer 3.0.0 ✔ → 2) Android 3.0 ✔ (sprawdzony na serwerze i na telefonie) → **3) iOS 3.0 (ten dokument)** → 4) UI webowe |

Oznaczenia: **[U]** — ustalone z właścicielem, **[A]** — decyzja przejęta 1:1 z Androida, **[P]** — propozycja
projektanta dla iOS (do sprawdzenia przy czytaniu), **[W]** — pozostawione wykonawcy.

---

## 1. Cel

Aplikacja iOS ma dostać **ten sam zakres co Android 3.0.2** (zasada VIII konstytucji, `.claude/CLAUDE.md` p. 5):
załączniki treningów, nagrywanie jazdy (GPS, akcelerometr), statystyki i chody, mapę, GPX, pogodę, progi chodów
i parametry obciążenia, raport „Analiza jazd” oraz synchronizację, kopię i przejścia trybów — w obu trybach pracy.
Cel i uzasadnienie użytkowe są w [WYM] 1; nie powtarzamy ich tutaj.

Dlaczego teraz: Android 3.0 jest wydany i sprawdzony na prawdziwym serwerze 3.0 i na telefonie **[U]**, więc jego
decyzje są już potwierdzone w praktyce, a właściciele z iPhone'ami (grupa TestFlight „Właściciele”) nie mają tych funkcji.

## 2. Źródła prawdy (w kolejności)

1. **[K]** — nazwy pól, kody błędów (RFC 9457, rozpoznanie po końcówce `type`), limity.
2. **[WYM]** rozdz. 5–7, 10, 13 — wymagania użytkowe; rozdz. 8 — różnice iOS (z poprawką z p. 5.1 tego dokumentu).
3. **Pliki wzorcowe Androida** `core/src/test/resources/golden/{zk-track,ride-stats,ride-analysis}/` wraz z README
   (reguły, których kontrakt nie mówi wprost — wiążące dla iOS).
4. **[PLAN-A]** „Decyzje planu” A1–A13 i „Global Constraints” — stałe, walidacja, bezpieczniki, kolory chodów.
5. Zachowanie Androida 3.0.2 i teksty z jego `strings.xml`.

Przy rozbieżności między 2. a 3.–5. obowiązuje to, co zrobił i sprawdził Android (jest nowsze i przeszło odbiór), a
rozbieżność zapisujemy w specyfikacji iOS.

## 3. Cele, nie-cele, anty-cele

**Cele** — jak [WYM] 2, a ponadto:
- Kopia `.zkkopia` z nagraniami jest wymienna z Androidem 3.0 w obie strony; te same dane dają te same statystyki,
  ten sam raport i ten sam CSV (bajt w bajt).
- Nagrywanie przeżywa wygaszony ekran i wyjście z aplikacji do innej; po zamknięciu aplikacji przez system wznawia się
  albo zostawia „Zapisz / Odrzuć” bez utraty punktów zapisanych ≥ 10 s wcześniej.

**Nie-cele** — jak [WYM] 2, a ponadto: Apple Watch, CarPlay, widżety ekranu głównego, iPad, import z aplikacji Zdrowie.

**Anty-cele** — jak [WYM] 2, a ponadto:
- Statystyki iOS różne od Androida dla tego samego nagrania (choćby o skalę liczby: `5.00` ≠ `5.0`).
- Uprawnienie lokalizacji „Zawsze” albo lokalizacja używana poza nagrywaniem — ryzyko odrzucenia w App Review
  i złamanie zasady II.
- Odrzucenie kompilacji w App Review / TestFlight z powodu niespójnych opisów zgód lub manifestu prywatności.

## 4. Ograniczenia i stan wyjściowy

- **Stan kodu:** iOS 2.1.0 (TestFlight 2.1.0 (25) z 2026-11-05, commit `5ac7d9b`). Gałąź wychodzi z `a355b44`
  (push: stan „czekam na zgodę”), którego **nie ma w żadnej kompilacji TestFlight** — trafi do użytkowników
  razem z 3.0.
- **Konstytucja iOS 2.1.0, zasada II, zabrania** lokalizacji i połączeń z usługami zewnętrznymi — potrzebna zmiana
  na **3.0.0** (MAJOR, jak [PLAN-A] A1), patrz 6.1.
- **Bez Maca:** kompilacja, testy, podpis i TestFlight wyłącznie w GitHub Actions; projekt z XcodeGen (`project.yml`).
  Nagrywania w tle, Live Activity, mapy i aparatu **nie da się sprawdzić w CI** — tylko na iPhonie z kompilacji
  TestFlight (grupa „Deweloper” dla kompilacji częściowych).
- **Minimalna wersja iOS 18** — dostępne bez warunków: `CLLocationUpdate.liveUpdates`, `CLBackgroundActivitySession`,
  `CLServiceSession`, ActivityKit z App Intents, SwiftUI `Map` z `MapPolyline`, asynchroniczne `AVAssetExportSession`.
- **Stos:** Swift 6, SwiftUI, GRDB (`Packages/HorselyKit`), logika w `Packages/HorselyCore` bez współdzielenia kodu
  z Androidem. Obecnie: `BackupManifest.formatVersion = 2`, `exportSchemaVersion = "1.5"`, migracje GRDB `v1`, `v2`,
  `ProgramCapabilities` bez nazw 3.0, `ApiClient` ze ścieżkami względem `/api/v1/`, `UIBackgroundModes` = `fetch`,
  `processing`, `remote-notification`.
- **Teksty** tylko z `strings.xml` Androida 3.0.2 przez `scripts/sync-strings.ps1` z testem zgodności.
- **Serwer `192.168.18.33` jest produkcyjny** — testy z prawdziwym serwerem tylko na serwerze uruchomionym lokalnie.

## 5. Podejścia

### 5.1 Mapa — decyzja: Apple MapKit [U]

| | Opis | Za | Przeciw |
|---|---|---|---|
| **A — MapKit (wybrane [U])** | SwiftUI `Map`, `MapPolyline` w kolorach chodów, `Annotation` dla startu, mety i pinezek | Bez klucza, bez nowej zależności i sekretu CI; natywny wygląd iOS; węższy wyjątek w zasadzie II (kafle Apple) | Wygląd inny niż na Androidzie (Google); brak osobnego widoku „teren” |
| B — Google Maps SDK for iOS | jak Android | Identyczny wygląd na obu platformach | Klucz w sekretach CI i ograniczenie do bundle id, ciężki pakiet, kolejna usługa Google w aplikacji |
| C — sam ślad bez mapy (`TrackCanvas`) | rysunek śladu na pustym tle | Zero usług zewnętrznych | Nie spełnia MAP-01 („w jakim terenie”) |

Przełącznik „Satelita / Teren / Mapa” zostaje z tymi samymi tekstami **[P]**: Satelita = `.imagery`,
Teren = `.hybrid(elevation: .realistic)` (zdjęcie z nazwami i rzeźbą), Mapa = `.standard`; domyślnie Satelita.
MAP-05 (brak klucza) na iOS nie występuje; bez sieci MapKit pokazuje to, co ma w pamięci podręcznej, a ślad i
statystyki są zawsze widoczne (MAP-04). Zmienia to [WYM] MAP-01 i rozdz. 8 — patrz 9.3.

### 5.2 Nagrywanie w tle — decyzja [P]: `CLLocationUpdate.liveUpdates` + `CLBackgroundActivitySession`

| | Opis | Za | Przeciw |
|---|---|---|---|
| **A (proponowane)** | asynchroniczny strumień `liveUpdates(.fitness)` + sesja aktywności w tle i `CLServiceSession(authorization: .whenInUse)` | Uprawnienie „Podczas używania” wystarcza w tle; po zamknięciu aplikacji przez system (nie przesunięciem) iOS uruchamia ją ponownie w tle, jeśli sesja była aktywna — odpowiednik `START_STICKY`; Swift concurrency pasuje do Swift 6 | Wznowienie trzeba obsłużyć przy starcie aplikacji (odtworzyć sesję przed zakończeniem `didFinishLaunching`) |
| B | klasyczny `CLLocationManager` z `allowsBackgroundLocationUpdates` | Znany od lat | Brak ponownego uruchomienia po zamknięciu przez system; delegaty i wątki w Swift 6 trudniejsze |

Akcelerometr: `CMMotionManager` (`deviceMotion.userAcceleration`, ~50 Hz) działa w tle, dopóki aplikacja żyje dzięki
nagrywaniu lokalizacji; nie wymaga zgody (to nie `CMMotionActivityManager`). Surowe dane nie są zapisywane — tylko rytm
i intensywność z okien 5 s, jak na Androidzie.

### 5.3 Podgląd podczas jazdy — decyzja [P]: Live Activity z przyciskami

Live Activity (ekran blokady, Dynamic Island) z koniem, czasem, dystansem, chodem i ostrzeżeniem „Słaby sygnał GPS”;
przyciski „Pauza / Wznów” i „Zakończ” jako `LiveActivityIntent` (odpowiednik przycisków w powiadomieniu Androida;
„Zakończ” otwiera aplikację na ekranie zakończenia). Wymaga nowego celu rozszerzenia widżetów w `project.yml`
(np. `HorselyRideActivity`) i `NSSupportsLiveActivities`. Alternatywa bez Live Activity (tylko niebieski wskaźnik
lokalizacji) odpada — [WYM] NAG-05 i brak sterowania bez odblokowania telefonu.

## 6. Różnice iOS względem Androida

| Obszar | Android 3.0.2 | iOS 3.0 |
|---|---|---|
| Uprawnienia | `ACCESS_FINE/COARSE_LOCATION`, `FOREGROUND_SERVICE_LOCATION` | `NSLocationWhenInUseUsageDescription`, `UIBackgroundModes` + `location`, `NSSupportsLiveActivities`; dokładna lokalizacja wymagana — przy „przybliżonej” prośba o dokładną (`requestTemporaryFullAccuracyAuthorization`) albo wyjaśnienie **[P]**; bez „Zawsze” |
| Praca w tle | usługa pierwszoplanowa `location` | 5.2 |
| Zabicie procesu | `START_STICKY`, stan `Interrupted` (A13) | zamknięcie przez system → ponowne uruchomienie w tle i wznowienie; zamknięcie przesunięciem → koniec, przy starcie „Zapisz / Odrzuć” (NAG-09); otwarcie aplikacji przez użytkownika (pierwszy plan) z niezakończoną jazdą = przerwana, „Zapisz / Odrzuć” — wznawia tylko uruchomienie w tle |
| Powiadomienie w trakcie | stałe powiadomienie | Live Activity (5.3); ostrzeżenia (bateria 15 %, 8 h, słaby GPS) jako powiadomienia lokalne |
| Optymalizacja baterii | prośba o wyłączenie | nie dotyczy |
| Bateria | `BatteryManager` | `UIDevice.isBatteryMonitoringEnabled` tylko w trakcie nagrywania |
| Mapa | Google Maps / `TrackCanvas` | MapKit (5.1) |
| Przekodowanie filmów | Media3 Transformer w `VideoPrepareWorker` | `AVAssetExportSession` (H.264/AAC, krótszy bok 720 — preset 1280×720 z zachowaniem orientacji), reguła kiedy przekodować jak A10; operacja `Held` do końca przygotowania; przerwane przygotowanie (zamknięcie aplikacji) wznawiane przy następnym starcie i w `BGProcessingTask` **[P]** |
| Miniatura filmu | pierwsza klatka | `AVAssetImageGenerator`, JPEG ≤ 1 MB |
| Film z aparatu | arkusz „Dodaj” bez filmu z aparatu (aparat zdjęcie, galeria zdjęć i filmów); film z aparatu tylko przyciskiem „Zdjęcie / film” podczas jazdy (ZAT-05) | tak samo: arkusz „Dodaj” bez zmian; podczas jazdy `UIImagePickerController` ze zdjęciem i filmem — nowa zgoda `NSMicrophoneUsageDescription` (dźwięk filmu) |
| Położenie zdjęć z galerii (ZAT-05) | EXIF / QuickTime | z metadanych pliku przekazanego przez `PhotosPicker` (bez pełnego dostępu do biblioteki); gdy system usunie położenie — bez pinezki **[W]** sprawdzić na urządzeniu |
| Zdjęcia z odrzuconej jazdy | kopia do galerii (Android 10+) | zapis do galerii wymaga `NSPhotoLibraryAddUsageDescription` (tylko dodawanie) — **[P]** zapisujemy do galerii; gdy zgoda odmówiona, plik zostaje w prywatnym katalogu z komunikatem, jak Android `ride-media/kept/` |
| Udostępnianie GPX | systemowe „Udostępnij” | `ShareLink` / `UIActivityViewController`, ta sama nazwa pliku |
| Wybór `/api/v3` | `ApiVersionInterceptor` (A2) | przepisanie prefiksu w `ApiClient`, pseudo-możliwość `apiV3` z `apiVersions`; `system/info` zawsze pod `/api/v1`; zmiana `apiV3` wymusza pełne pobranie |
| Baza lokalna | Room 4 | GRDB: migracja `v3`; trasy w osobnej tabeli (odpowiednik `local_track`), nie w treści rekordu (A4) |

### 6.1 Konstytucja iOS 3.0.0 [A]

Zasada II dostaje wąskie wyjątki, jak Android (A1): lokalizacja „Podczas używania” **tylko** w czasie nagrywania jazdy
uruchomionego przez użytkownika (nigdy w logach, nigdy poza nagrywaniem); kafle Apple Maps; Open‑Meteo z położeniem
zaokrąglonym do 0,01° i godziną startu, z wyłącznikiem — w obu trybach pracy. Zdanie „NIE MOŻE prosić o lokalizację”
i lista zgód (specyfikacja 9.2) — do zmiany. Zasada VIII: odniesienie „Android 2.1.0” → „Android 3.0.2”.
`PrivacyInfo.xcprivacy` dostaje typ danych „precyzyjna lokalizacja” (funkcjonalność aplikacji, niepowiązana
ze śledzeniem); etykiety prywatności w App Store Connect aktualizuje właściciel.

## 7. Co musi być identyczne z Androidem [A]

Za stroną parity Androida i [PLAN-A]:

- **`zk-track/1`**: base64 → gzip → JSON z kolumnami `dt`, `lat`, `lon`, `alt`, `spd`, `acc`, `cad`, `int` i `pauses`;
  przyrosty dla `dt`/`lat`/`lon`; jednostki całkowite (10⁻⁷°, dm, cm/s); ≤ 5 242 880 B po zdekodowaniu base64.
  Porównujemy dokument po rozpakowaniu, nie bajty gzip (gzip na iOS: `Compression`/`zlib` bez nowej zależności — [W]).
- **Zaokrąglanie HALF_UP „od zera”** liczone na zapisie dziesiętnym: `Decimal` i `.toNearestOrAwayFromZero`, nigdy
  `Double` ani `.toNearestOrEven`; liczby porównywane ze skalą zapisu.
- **Statystyki i chody, algorytm v1**: haversine R = 6 371 000 m, dokładność ≤ 25 m (brak = punkt zły), filtr skoków
  > 70 km/h z regułą kotwicy (`JumpAnchorFilter`), okna 5 s domknięte z prawej `(5k, 5k+5]`, rytm koryguje chód tylko
  w pasie ±3 km/h wokół progu kłusa (A8), luka GPS > ~10 s = postój. Analizator rytmu z akcelerometru — ta sama metoda
  co `CadenceAnalyzer` Androida (wynik nie jest objęty wzorcem, więc opisać i przetestować na tych samych przypadkach) **[W]**.
- **Raport „Analiza jazd”**: te same przypadki `golden/ride-analysis` i 10 rozstrzygnięć z README; CSV bajt w bajt
  (UTF-8 z BOM, `;`, `\r\n`, przecinek dziesiętny).
- **Stałe**: progi 1,5 / 7 / 15 km/h, wagi 1 / 2 / 3, podjazd 1 pkt / 10 m, ostrzeżenie 30 %, ciężka jazda 60 pkt,
  walidacja PAR-05, wzór punktów jazdy z [PLAN-A], bezpieczniki (15 % baterii, 8 h, < 1 min lub < 100 m, słaby GPS
  > 25 m przez > 30 s, zapis co ≤ 10 s), limity (100 MB plik, miniatura ≤ 1 MB, `pointCount ≥ 2`, ≤ 20 000 odcinków),
  kolory chodów `#9E9E9E` / `#43A047` / `#FB8C00` / `#E53935` (A11).
- **Dane i kolejka**: rekordy nagrania, profilu jazdy konia i ustawień jazd (A4), operacje kolejki (A5), zachowanie
  na serwerze bez `trainingRecordings` — operacje czekają z „Czeka na aktualizację programu”, `SyncMerger` nie usuwa
  tych rekordów (A6), pogoda bez konfliktu (A9), `409 training-has-recording` → „Do poprawy” z czytelnym komunikatem.
- **Kopia**: `formatVersion` 3, `exportSchemaVersion` „1.6”, `dataSchemaVersion` „3.0” (A3); iOS 2.1.0 już dziś odrzuca
  nowszy format komunikatem „Kopia z nowszej wersji aplikacji (format 3) — zaktualizuj aplikację.” (`BackupService`),
  zgodnie z Androidem; testowana wersja programu 3.0.0.
- **Zachowanie i ekrany z 3.0.1–3.0.2**: zakładka „Jazdy” na karcie konia zaraz po „Treningach”, widok tabeli (wartość
  własna pogrubiona, odziedziczona przygaszona z dopiskiem „domyślne”); „Paszport” bez parametrów jazdy.
- **Niezapisana jazda blokuje** zmianę trybu, przywrócenie kopii i „Rozłącz”; zapis jazdy w jednej transakcji, a
  przygotowanie filmów planowane dopiero po jej zatwierdzeniu; sprzątanie niereferowanych plików z jazd starszych
  niż godzina przy starcie i po „Rozłącz”.
- **Ostrzeżenia o jedynej kopii**: przejście z trybu samodzielnego do trybu z serwerem, przywracanie kopii i brak hasła
  kopii wymieniają jazdy z trasą.

Pliki wzorcowe `zk-track`, `ride-stats`, `ride-analysis` kopiujemy 1:1 do
`Packages/HorselyCore/Tests/HorselyCoreTests/Resources/golden/` (jak obecne `parity`/`golden`) i porównujemy pole po
polu. Dodatkowo test zgodności kopii: kopia `.zkkopia` z nagraniem wygenerowana przez Androida (plik wzorcowy)
odtwarza się na iOS z tymi samymi statystykami **[P]**.

## 8. Podział na etapy (dla planu) [P]

Kolejność jak [WYM] 9 / projekt Androida p. 3. Każdy etap kończy się zielonym CI na gałęzi; etapy z elementami
niesprawdzalnymi w CI (2, 3, 5) — kompilacja częściowa do grupy TestFlight „Deweloper”.

1. **Fundament**: konstytucja 3.0.0, specyfikacja „Zakres wersji 3.0”, `MARKETING_VERSION 3.0.0`, migracja GRDB `v3`,
   kopia formatu 3, `/api/v3` po `apiVersions`, możliwości `trainingAttachments` i `trainingRecordings`, teksty z
   `strings.xml` 3.0.2.
2. **Załączniki treningu** (ZAT-01…06) z przekodowaniem 720p i miniaturą dla wszystkich filmów.
3. **Nagrywanie i zapis** (NAG): lokalizacja w tle (5.2), Core Motion, maszyna stanów, zapis na bieżąco
   i odzyskiwanie, Live Activity (5.3), ekran nagrywania, pasek „Trwa nagrywanie”, formularz po jeździe, przycinanie.
4. **Statystyki i chody** (STA) w `HorselyCore` z plikami wzorcowymi (może iść równolegle z 2–3 — czyste funkcje).
5. **Mapa i GPX** (MAP) — MapKit.
6. **Pogoda** (POG) — Open‑Meteo.
7. **Progi i obciążenie** (PAR) — Ustawienia i zakładka „Jazdy” konia.
8. **Raport „Analiza jazd”** (RAJ) + wzmianki w raportach treningów.
9. **Synchronizacja, kopia, przejścia trybów** (SYN) — przekrojowo w 2–8, domknięcie scenariuszy, wydanie 3.0.0 do
   TestFlight (tag `v3.0.0`, numer kompilacji kolejny po 25).

## 9. Pliki do aktualizacji

1. `.specify/memory/constitution.md` → 3.0.0 (6.1).
2. `SPECYFIKACJA_MOBILE_IOS.md`: wpis „Zakres wersji 3.0”, usunięcie „Treningi nie mają załączników” (US10), nowe FR
   z prefiksami [WYM], sekcja 9 (różnice: MapKit, lokalizacja w tle, Live Activity, zgody 9.2), `CHANGELOG.md`.
3. **Zasada V — druga specyfikacja**: w repozytorium Androida [WYM] MAP-01 i rozdz. 8 dostają „iOS: MapKit” zamiast
   „Google Maps SDK for iOS”, a strona ai-memory `parity/android-3-0-nagrania-jazd-kontrakt` — „dostawca map: MapKit”
   i usunięcie „niezweryfikowane na serwerze 3.0” (Android sprawdzony **[U]**). Zmiany w drugim repozytorium
   wprowadzamy osobnym commitem tam, po akceptacji tego dokumentu.
4. `project.yml` (cel Live Activity, `UIBackgroundModes` `location`), `App/Info.plist` (opisy zgód: lokalizacja,
   mikrofon, dodawanie do galerii; Live Activity), `PrivacyInfo.xcprivacy`.

## 10. Kryteria akceptacji

[WYM] 10 (scenariusze 1–8, w scenariuszu 2 mapa MapKit, w scenariuszu 3 wariant iOS) oraz:

1. Kopia `.zkkopia` z Androida 3.0 z dwiema jazdami → odtworzenie na iPhonie → te same dystanse, chody, punkty
   obciążenia i ten sam CSV „Analizy jazd”; kopia z iPhone'a otwiera się na Androidzie.
2. 30 min jazdy z zablokowanym ekranem → Live Activity pokazuje czas i dystans; „Pauza” z ekranu blokady działa.
3. Zamknięcie aplikacji przesunięciem w trakcie jazdy → przy starcie „Masz niezakończone nagranie … — Zapisz / Odrzuć”
   z dystansem z zapisanych punktów.
4. Odmowa lokalizacji albo „przybliżona” → nagrywanie się nie zaczyna, jest wyjaśnienie i przejście do Ustawień.
5. Lokalny serwer 3.0 (nie produkcyjny): jazda nagrana na iPhonie widoczna z trasą na Androidzie po synchronizacji.

## 11. Ryzyka

- **App Review**: tryb `location` w tle wymaga jasnego opisu zgody i widocznej funkcji — opis w `Info.plist` i notatka
  dla recenzenta przy pierwszej wysyłce poza TestFlight.
- **Brak urządzenia w CI**: błędy nagrywania w tle wyjdą dopiero na telefonie; dziennik diagnostyczny (bez położeń)
  dostaje wpisy stanu nagrywania, jak wpisy stanu push.
- **Ponowne uruchomienie po zamknięciu przez system** (5.2) — zachowanie do potwierdzenia na urządzeniu; gdy zawiedzie,
  zostaje „Zapisz / Odrzuć” (bez utraty danych).
- **Położenie w plikach z `PhotosPicker`** — może być usuwane przez system; skutkiem jest tylko brak pinezki.

## 12. Pozostawione wykonawcy [W]

Implementacja gzip; dokładna metoda rytmu zgodna z Androidem; położenie z `PhotosPicker`; nazwa celu Live Activity;
podział na kompilacje częściowe; nazwy plików i typów w Swifcie.

## 13. Decyzje projektanta do sprawdzenia [P]

Wersja iOS **3.0.0** z całym zakresem Androida do 3.0.2 (bez osobnych 3.0.1/3.0.2 na iOS); `liveUpdates`
+ `CLBackgroundActivitySession` zamiast klasycznego `CLLocationManager`; Live Activity z przyciskami „Pauza” i
„Zakończ”; mapowanie „Satelita / Teren / Mapa” na style MapKit; wymagana dokładna lokalizacja; zdjęcia z odrzuconej
jazdy zapisywane do galerii (zgoda tylko na dodawanie); przerwane przekodowanie wznawiane przy starcie i w
`BGProcessingTask`; plik wzorcowy kopii z Androida jako test wymienności.
