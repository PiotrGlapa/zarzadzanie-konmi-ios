# Implementation Plan: Horsely na iOS — pełny zakres aplikacji na Androida 2.0.1

**Branch**: `main` (specyfikacja `001-aplikacja-ios-horsely`) | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-aplikacja-ios-horsely/spec.md` oraz [SPECYFIKACJA_MOBILE_IOS.md](../../SPECYFIKACJA_MOBILE_IOS.md) 1.5

## Summary

Natywna aplikacja Horsely na iPhone (iOS 18+), funkcjonalnie i wizualnie równa aplikacji na Androida 2.0.1: tryb samodzielny
(telefon źródłem prawdy, reguły programu w telefonie, kosz, słowniki, kopia zapasowa) i tryb online (pełna kopia danych
programu w telefonie, kolejka zmian bez duplikatów, konflikty, możliwości programu 2.0.0). Architektura odwzorowuje
sprawdzony model Androida: **jeden magazyn rekordów w kształcie eksportu programu** (tabela rekordów z treścią JSON
i stanem synchronizacji), **trwała kolejka operacji** i **czysty rdzeń reguł** (walidacja, terminy, podział kosztów,
raporty, CSV) testowany tymi samymi plikami wzorcowymi programu co Android. Interfejs w SwiftUI z natywnymi komponentami
iOS, kolorami, tekstami i ikonami Material z Androida. Budowanie, testy, podpis i wysyłka do TestFlight wyłącznie w GitHub
Actions (rozwój na Windows, bez Maca); projekt generowany XcodeGen. Szczegóły decyzji: [research.md](research.md).

## Technical Context

**Language/Version**: Swift 6 (tryb języka 6, pełna kontrola współbieżności), najnowszy stabilny Xcode na runnerze GitHub macOS (SDK iOS 18+)

**Primary Dependencies**: SwiftUI, Observation, Foundation `URLSession`, VisionKit (`DataScannerViewController`), PhotosUI, Swift Charts, BackgroundTasks, UserNotifications, LocalAuthentication, CryptoKit + CommonCrypto, Contacts/ContactsUI, Network (`NWPathMonitor`); zewnętrzne (uzasadnione w R3–R6): **GRDB.swift** (SQLite), **ZIPFoundation** (ZIP zgodny z `java.util.zip`), **swift-snapshot-testing** (tylko testy); narzędzie: **XcodeGen**

**Storage**: SQLite przez GRDB w kontenerze App Group (`group.pl.glapa.horsely`), wyłączony z kopii iCloud; pliki załączników w kontenerze App Group; klucz API w Keychain; ustawienia w `UserDefaults` grupy

**Testing**: Swift Testing (jednostkowe, pakiety), XCTest + XCUITest (UI), `URLProtocol` jako zaślepka programu (kontrakt `openapi`), pliki wzorcowe programu (`parity`, `golden`) z repozytorium Androida, testy migawkowe (swift-snapshot-testing) i zrzuty z symulatora iPhone 15 Pro

**Target Platform**: iOS 18.0+, tylko iPhone (urządzenie odniesienia: iPhone 15 Pro); orientacja pionowa (pozioma dla podglądu zdjęć/wideo)

**Project Type**: mobile-app (aplikacja + rozszerzenie udostępniania + lokalne pakiety Swift)

**Performance Goals**: start do Pulpitu < 2 s, raport dla 2 000 treningów / 50 koni < 3 s, pierwsze pełne pobranie 50 koni / 50 000 wpisów < 3 min, informacja zwrotna po zapisie < 1 s (NFR-M-01…03, SC-2-05/06) — na iPhone 15 Pro

**Constraints**: działanie bez sieci w obu trybach; w trybie samodzielnym zero połączeń; bez telemetrii i usług zewnętrznych; kwoty jako `Decimal`; daty kalendarzowe bez strefy; tekst 200 %, VoiceOver, WCAG AA; praca w tle „w miarę możliwości iOS”; brak Maca — wszystko, co wymaga Xcode, w CI

**Scale/Scope**: do ~50 koni, ~50 000 wpisów, załączniki do 100 MB/plik (1 GB łącznie w kopii); ok. 45 ekranów (lista: [contracts/ui-screens-ios.md](contracts/ui-screens-ios.md)); 2 tryby pracy; programy 1.5.0–2.0.0

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.* Konstytucja: `.specify/memory/constitution.md` 2.0.1.

| Zasada | Tryb online | Tryb samodzielny | Wynik |
|---|---|---|---|
| I. Jedno źródło prawdy | program; wartości z programu po synchronizacji, reguły telefonu tylko dla danych niewysłanych (oznaczone „z pamięci”) | telefon; reguły z rdzenia testowane plikami wzorcowymi | ✅ |
| II. Prywatność | połączenia tylko do sparowanych adresów; brak SDK sieciowych (GRDB, ZIPFoundation — biblioteki lokalne) | zero połączeń (test SC-2-02); kopia tylko na żądanie | ✅ |
| III. Klucz i połączenie | Keychain `AfterFirstUnlockThisDeviceOnly`; przypięcie odcisku w `URLSessionDelegate`; ATS bez `NSAllowsArbitraryLoads` | nie dotyczy (brak połączeń) | ✅ |
| IV. Offline bez utraty i duplikatów | kolejka w SQLite (transakcje), stały id operacji, `Idempotency-Key` / licznik przed i po, konflikty do decyzji | zapis transakcyjny, kosz | ✅ |
| V. Kontrakt i model | kopia `openapi-2.0.0.yaml` i schematu eksportu; magazyn w kształcie eksportu; `Decimal`, daty bez strefy | ten sam model | ✅ |
| VI. Testy | zaślepka API ze scenariuszami błędów; testy kolejki, konfliktów, możliwości | pliki wzorcowe reguł i CSV, kopia (także z Androida), zmiana trybu, testy migawkowe | ✅ |
| VII. Prostota | 3 zależności zewnętrzne z uzasadnieniem (R3–R6); 2 pakiety lokalne zamiast wielu modułów | j.w. | ✅ (patrz Complexity Tracking) |
| VIII. Zgodność z Androidem | teksty z `strings.xml` (skrypt + test), ikony Material SVG, paleta i układ wg 5.4, wspólne dane do zrzutów | j.w.; kopia `.zkkopia` format 2 wymienna | ✅ |

Bramka przed Fazą 0: **zaliczona**, bez naruszeń wymagających uzasadnienia poza zależnościami (VII).

**Ponowna kontrola po Fazie 1 (projekt):** zaliczona.

- I/IV: [data-model.md](data-model.md) — stany rekordów i operacji jak w Androidzie; `Projected` nigdy w kolejce ani kopii;
  zapisy rekord + operacja + licznik w jednej transakcji GRDB.
- II/III: [contracts/app-entry-points-ios.md](contracts/app-entry-points-ios.md) — lista zgód `Info.plist` z testem, adresy
  `horsely://` bez skutków z zewnątrz, rozszerzenie bez sieci; [contracts/ci-release.md](contracts/ci-release.md) — sekrety
  tylko w GitHubie, plik klucza usuwany w `always()`.
- V: kontrakty normatywne Androida skopiowane z pochodzeniem (`contracts/android/`, `c4a869d`); kopia format 2 / schemat 1.5.
- VI: [quickstart.md](quickstart.md) i [contracts/test-fixtures.md](contracts/test-fixtures.md) — pliki wzorcowe, zaślepka API,
  testy migawkowe, wspólne dane z Androidem.
- VIII: [contracts/ui-screens-ios.md](contracts/ui-screens-ios.md) — odpowiedniki komponentów 1:1, teksty ze `strings.xml`.
- Otwarte zależności spoza repozytorium (nie naruszenia): test zrzutów i plik `zrzuty.zkkopia` w repozytorium Androida (R18);
  test odtwarzania kopii iOS po stronie Androida (R5); potwierdzenie podpisywania w chmurze w pierwszym przebiegu (R19).

## Project Structure

### Documentation (this feature)

```text
specs/001-aplikacja-ios-horsely/
├── spec.md
├── plan.md              # ten plik
├── research.md          # Faza 0 — decyzje R1–R20
├── data-model.md        # Faza 1 — magazyn, kolejka, stany
├── quickstart.md        # Faza 1 — scenariusze walidacji
├── contracts/
│   ├── README.md                 # spis i pochodzenie kontraktów
│   ├── ci-release.md             # proces CI/TestFlight (sekrety, wyzwalacze, grupy)
│   ├── app-entry-points-ios.md   # powiadomienia, szybkie akcje, udostępnianie, adresy URL
│   ├── ui-screens-ios.md         # lista ekranów, odpowiedniki komponentów, ikony
│   ├── test-fixtures.md          # wspólne dane testowe i zrzuty wzorcowe z Androidem
│   └── android/                  # kontrakty normatywne skopiowane z Androida 2.0.1 (c4a869d)
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
project.yml                         # XcodeGen — cele, ustawienia, App Group, Info.plist
Packages/
├── HorselyCore/                    # czysty Swift (Foundation): bez UI, bez SQLite, bez sieci
│   ├── Sources/HorselyCore/
│   │   ├── Model/                  # rekordy eksportu (Codable), enumy, Money (Decimal), LocalDate
│   │   ├── Rules/                  # walidacja, komunikaty, terminy, podział kosztów, kosz, słowniki (FR-SAM-02)
│   │   ├── Reports/                # 5 raportów, CSV (bajt w bajt), dane wykresów, formaty czasu i kwot
│   │   ├── Sync/                   # łączenie operacji, plan odświeżenia, scalanie eksportu, konflikty (logika)
│   │   ├── Connection/             # reguły adresów, kod QR, możliwości programu, wersje
│   │   ├── Backup/                 # format .zkkopia 2 (manifest, szyfrowanie porcjami)
│   │   └── Suggest/                # podpowiedzi (kowal, zakup, trening)
│   └── Tests/HorselyCoreTests/     # + Resources/parity, golden (z Androida)
└── HorselyKit/                     # zależy od HorselyCore, GRDB, ZIPFoundation
    ├── Sources/HorselyKit/
    │   ├── Store/                  # GRDB: rekordy, kolejka, konflikty, pliki, migracje
    │   ├── Network/                # klient API, przypinanie certyfikatów, ogranicznik tempa, stan połączenia
    │   ├── Outbox/                 # procesor kolejki (actor), wysyłka plików w tle
    │   ├── Sync/                   # pełne/przyrostowe pobranie, scalanie do magazynu
    │   ├── Files/                  # zdjęcia (zmniejszanie, EXIF), miniatury, kadrowanie
    │   ├── Backup/                 # zapis/odczyt pliku, kopia automatyczna
    │   ├── Notifications/          # planowanie powiadomień (≤ 60)
    │   ├── Security/               # Keychain, blokada aplikacji
    │   └── Log/                    # dziennik diagnostyczny (rotacja 5 MB)
    └── Tests/HorselyKitTests/      # zaślepka URLProtocol, baza w pamięci
App/                                # cel aplikacji (SwiftUI)
├── HorselyApp.swift
├── Features/                       # Welcome, Pairing, Dashboard, Horses, Entries, Reminders, Trainings,
│                                   # Purchases, Competitions, Contacts, Reports, Attachments, Queue,
│                                   # Conflicts, Trash, Dictionaries, Backup, Settings, About, Lock
├── DesignSystem/                   # paleta (5.4), InfoCard, ReminderCard, StarRating, DividedList,
│                                   # SectionHeader, FormSaveBar, AccentIcon, HorseAvatar, InjuredBadge
├── Resources/
│   ├── Localizable.xcstrings       # generowany z strings.xml (R11)
│   ├── Assets.xcassets             # AppIcon, ikony Material (SVG), głowa konia, kolory
│   └── android/strings.xml, plurals.xml   # kopie wzorcowe do testu zgodności
└── Info.plist / Horsely.entitlements
ShareExtension/                     # rozszerzenie „Udostępnij → Horsely”
Tests/
├── AppUITests/                     # XCUITest: przepływy, zrzuty ekranów
└── AppSnapshotTests/               # testy migawkowe kluczowych ekranów
scripts/
├── sync-strings.ps1                # strings.xml → Localizable.xcstrings (Windows PowerShell 5.1 i pwsh)
└── ci/                             # skrypty kroków CI (archiwum, eksport, wysyłka)
.github/workflows/
├── ci.yml                          # PR i main: generate, build, testy, zrzuty
└── release.yml                     # tag v* / ręcznie: + archiwum, podpis, wysyłka do TestFlight
```

**Structure Decision**: dwa lokalne pakiety SPM odzwierciedlają podział Androida `:core` / `:app` — `HorselyCore` (czysta
logika, najszybsze testy, bez symulatora) i `HorselyKit` (wejście/wyjście: SQLite, sieć, pliki, system), a cele XcodeGen
`Horsely` (aplikacja) i `HorselyShare` (rozszerzenie) zawierają tylko interfejs i spoinę. `.xcodeproj` nie jest w repozytorium.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Zależność GRDB.swift | jeden magazyn rekordów z indeksami, transakcjami obejmującymi rekordy + kolejkę + konflikty, kontrolowane migracje i dostęp z rozszerzenia (R3) | SwiftData — brak kontroli transakcji wielotabelowych i migracji, problemy współbieżności; surowe API SQLite C — dużo kodu do utrzymania |
| Zależność ZIPFoundation | format `.zkkopia` to ZIP zgodny z `java.util.zip` (FR-KOP-09); iOS nie ma publicznego API ZIP (R5) | Apple Archive — inny format, niezgodny z Androidem |
| Zależność swift-snapshot-testing (tylko testy) | automatyczne wykrywanie zmian wyglądu bez Maca (FR-026) | własne porównywanie obrazów — więcej kodu, gorsze raporty różnic |
| Dwa pakiety + dwa cele | podział jak w Androidzie; rdzeń testowany bez symulatora; rozszerzenie dzieli magazyn | jeden cel — wolne testy, rozszerzenie musiałoby duplikować kod |
