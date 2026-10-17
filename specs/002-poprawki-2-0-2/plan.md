# Implementation Plan: Poprawki 2.0.2 — blokada aplikacji, zdjęcia koni z programu, czytelny raport treningów

**Branch**: `main` (praca bezpośrednio na `main`, bez gałęzi funkcji) | **Date**: 2026-10-17 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-poprawki-2-0-2/spec.md`

## Summary

Trzy poprawki do wydania 2.0.1 i **jedno wydanie 2.0.2 na końcu**:

1. **Blokada (P1)** — pętla po odblokowaniu wynika z trwałego, niezerowanego znacznika przejścia w tło sprawdzanego
   przy każdej aktywacji (także po zamknięciu okna uwierzytelniania). Logika trafia do czystej maszyny stanów
   `AppLockMachine` w HorselyKit z testami sekwencji; znacznik tylko w pamięci, zerowany przy aktywacji i odblokowaniu;
   samoczynne okno uwierzytelniania raz na epizod blokady ([research R1](research.md#r1-przyczyna-pętli-blokady-i-model-stanu)).
2. **Zdjęcia (P2)** — miniatura konia czytana jest tylko z lokalnego pliku. Źródło miniatury: lokalna → z lokalnego
   oryginału → z programu (istniejące `GET attachments/{id}/thumbnail`), zapis przypięty, ponawianie po synchronizacji;
   „Pokaż zdjęcie” pobiera oryginał ([R2](research.md#r2-miniatury-zdjęć-koni-z-programu)).
3. **Raport (P3)** — sumy na górze we wszystkich raportach (zgodnie ze specyfikacją główną), w „Treningach jeźdźca”
   kafelki podsumowania, wykres słupkowy grup (liczba / czas), karty grup i zwijana lista; CSV/PDF bez zmian wartości
   ([R3](research.md#r3-układ-raportów-i-wykres-treningi-jeźdźca)).

**Proces (wymóg właściciela)**: fazy pośrednie kończą się wyłącznie commitem i zielonym `ci.yml` na `main` — bez tagów,
bez `release.yml`, bez kompilacji częściowych. Tag `v2.0.2` i wysyłka do TestFlight tylko w ostatniej fazie
([contracts/release.md](contracts/release.md)). Ponieważ właściciel nie sprawdza aplikacji między fazami, każda
historia jest zabezpieczona testami automatycznymi w CI.

## Technical Context

**Language/Version**: Swift 6 (tryb ścisłej współbieżności), SwiftUI, iOS 18+

**Primary Dependencies**: wbudowane — SwiftUI, Swift Charts, LocalAuthentication, URLSession; pakiety SPM projektu
`HorselyCore` (reguły, raporty, wykresy) i `HorselyKit` (magazyn, synchronizacja, bezpieczeństwo); bez nowych zależności

**Storage**: SQLite (GRDB) + pliki załączników w `LocalFileStore` — bez zmian schematu i formatu kopii

**Testing**: XCTest — `swift test` pakietów w CI, `AppSnapshotTests` (migawki jasny/ciemny/200 %), `AppUITests`;
zaślepka programu `URLProtocol`; wstrzykiwany zegar

**Target Platform**: iPhone, iOS 18+, odniesienie iPhone 15 Pro; budowanie wyłącznie GitHub Actions (macOS)

**Project Type**: aplikacja mobilna (XcodeGen `project.yml`, aplikacja + rozszerzenie udostępniania + 2 pakiety SPM)

**Performance Goals**: miniatury koni widoczne ≤ 10 s po pobraniu danych (SC-002); raport bez zauważalnego opóźnienia
przy przełączaniu miary

**Constraints**: praca offline (miniatury trwałe, FR-ZDK-06); brak Maca; teksty tylko z `strings.xml` Androida;
CSV/PDF raportów bajt w bajt jak w 2.0.1; jedno wydanie na końcu

**Scale/Scope**: 3 historie, ~10 plików aplikacji i pakietów, ~6 nowych tekstów, nowe/zmienione migawki raportów

## Constitution Check

*GATE: przed fazą 0 i po fazie 1. Oceniane dla trybu online (O) i samodzielnego (S).*

| Zasada | Przed | Po projekcie | Uwagi |
|--------|-------|--------------|-------|
| I. Jedno źródło prawdy | ✅ | ✅ | O: zdjęcie z programu tylko pobierane, nie wysyłane; S: miniatura z lokalnego oryginału |
| II. Prywatność, brak usług zewnętrznych | ✅ | ✅ | tylko program użytkownika; Swift Charts wbudowany |
| III. Bezpieczne połączenie, klucz API | ✅ | ✅ | blokada nie słabnie: zimny start i > 5 min w tle nadal blokują; zasłona bez zmian |
| IV. Offline i synchronizacja | ✅ | ✅ | O: miniatury przypięte, nieudane pobranie ponawiane; S: bez połączeń |
| V. Kontrakt API i model danych | ✅ | ✅ | istniejące `attachments/{id}/thumbnail` i `/content`; brak zmian modelu |
| VI. Testy | ✅ | ✅ | maszyna stanów blokady (zegar wstrzyknięty), źródło miniatur z zaślepką, `GroupBarChart`, wzorce raportów, migawki, zgodność tekstów |
| VII. Prostota | ✅ | ✅ | ponowne użycie `AttachmentStore`; jeden nowy model wykresu; bez „na zapas” (wykres w czasie poza zakresem) |
| VIII. Zgodność z Androidem | ⚠️ | ✅ | wykres i zwijana lista to zmiana zakresu → wpis w obu specyfikacjach + teksty w `strings.xml` Androida + zadanie dla Androida (FR-018, FR-019) |

Bramka procesu (konstytucja, „Proces wytwórczy”): wydanie po zielonym CI na `main` i ręcznej liście na iPhone 15 Pro —
lista ręczna wykonana raz, na 2.0.2 ([quickstart.md](quickstart.md#3-lista-ręczna-dla-właściciela-iphone-15-pro-kompilacja-202)).
Wymóg „każdy przyrost uruchamialny i testowalny niezależnie” spełniony przez testy CI każdej historii, bez
osobnych kompilacji TestFlight. Weryfikacja wydajności NFR-M-01…03 przed wydaniem — **pominięta decyzją właściciela**
(uzasadnienie w „Complexity Tracking”).

## Project Structure

### Documentation (this feature)

```text
specs/002-poprawki-2-0-2/
├── spec.md
├── plan.md              # ten plik
├── research.md          # R1–R5
├── data-model.md        # AppLockMachine, źródło miniatury, GroupBarChart
├── quickstart.md        # weryfikacja CI + lista ręczna 2.0.2
├── contracts/
│   ├── ui-reports.md    # kolejność i elementy ekranów raportów
│   └── release.md       # jedno wydanie na końcu
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
Packages/HorselyKit/
├── Sources/HorselyKit/Security/AppLock.swift          # + AppLockMachine (US1)
├── Sources/HorselyKit/Files/AttachmentStore.swift     # thumbnail(attachmentId:) z kolejnością źródeł (US2)
├── Sources/HorselyKit/Repositories/HorseRepository.swift  # thumbnailData/originalData → AttachmentStore (US2)
└── Tests/HorselyKitTests/                             # AppLockMachineTests, HorsePhotoSourceTests (US1, US2)
Packages/HorselyCore/
├── Sources/HorselyCore/Reports/ChartData.swift        # GroupBarChart, ReportCharts.riderGroups, ChartDescriptions.groupBars (US3)
└── Tests/HorselyCoreTests/                            # GroupBarChartTests; wzorce golden bez zmian (US3)
App/
├── Features/Lock/LockOverlay.swift                    # AppLockState jako powłoka nad AppLockMachine (US1)
├── Shell/HorseDirectory.swift                         # źródło miniatur, failed/unavailable, retryMissingThumbnails (US2)
├── Shell/AppEnvironment.swift                         # retry po refresh; miniatury po przejściu na tryb samodzielny (US2)
├── Features/Horses/HorsePhotoSheet.swift              # „Pokaż zdjęcie” przez AttachmentStore.content (US2)
├── Features/Reports/ReportScaffold.swift              # sumy na górze, collapsibleRows (US3)
├── Features/Reports/RiderReportViews.swift            # kafelki, wykres, karty grup (US3)
├── Features/Reports/Charts/ReportChartViews.swift     # GroupBarChartView (US3)
└── Resources/…/Localizable                           # teksty z sync-strings.ps1 (US3)
Tests/AppSnapshotTests/ReportsSnapshotTests.swift      # migawki raportów (US3), StringsParityTests
../zarzadzanie_konmi_android/app/src/main/res/values/strings.xml   # nowe teksty (US3)
SPECYFIKACJA_MOBILE_IOS.md, ../zarzadzanie_konmi_android/SPECYFIKACJA_MOBILE_ANDROID.md  # zmiana zakresu
project.yml                                            # MARKETING_VERSION 2.0.2 — tylko faza końcowa
```

**Structure Decision**: istniejący układ aplikacja + pakiety SPM; logika testowalna (blokada, źródło miniatury, model
wykresu) w pakietach, aby testy działały w `swift test` w CI; widoki w `App/` tylko ją wyświetlają.

## Kolejność faz (wytyczne dla /speckit-tasks)

| Faza | Zakres | Koniec fazy |
|------|--------|-------------|
| 1. Przygotowanie | teksty w `strings.xml` Androida + `sync-strings.ps1`; wpisy zmiany zakresu w obu specyfikacjach; zielone CI Androida | commit + zielone `ci.yml` |
| 2. Foundational | brak zadań — historie są rozłączne | — |
| 3. US1 Blokada (P1) | testy `AppLockMachine` (najpierw czerwone), maszyna stanów, powłoka w aplikacji | commit + zielone `ci.yml` |
| 4. US2 Zdjęcia (P2) | testy źródła miniatury z zaślepką, `AttachmentStore`, `HorseDirectory`, scenariusz `DemoProgram` „photos”, „Pokaż zdjęcie”, tryb samodzielny | commit + zielone `ci.yml` + przegląd zrzutów |
| 5. US3 Raport (P3) | testy `GroupBarChart`, scaffold (sumy na górze we wszystkich raportach), „Treningi jeźdźca”, PDF, migawki | commit + zielone `ci.yml` + przegląd zrzutów |
| 6. Domknięcie | `README`/historia zmian, zadanie dla Androida, przegląd zgodności | commit + zielone `ci.yml` |
| 7. Bramka przed wydaniem | warunki z [contracts/release.md](contracts/release.md), brak wcześniejszych tagów i przebiegów `release.yml` | — |
| 8. **Wydanie (jedyne)** | `MARKETING_VERSION` 2.0.2 → zielone CI → tag `v2.0.2` → `release.yml` → raport → lista ręczna właściciela i zapis jej wyniku | kompilacja w TestFlight, grupa „Właściciele”; 2.0.2 wydana po pozytywnej liście |

W fazach 1–7 obowiązuje zakaz tagów `v*`, `workflow_dispatch` dla `release.yml` i zmiany `MARKETING_VERSION`.

## Complexity Tracking

| Odstępstwo | Dlaczego | Odrzucona alternatywa |
|------------|----------|-----------------------|
| Bez weryfikacji wydajności NFR-M-01…03 przed wydaniem 2.0.2 (konstytucja, „Ograniczenia technologiczne”) — **decyzja właściciela 2026-10-17** | Poprawka nie zmienia ścieżek krytycznych dla wydajności (start, listy, synchronizacja rekordów); jedyne nowe obciążenie — pobieranie miniatur — działa w tle, z limitem równoległości, i jest objęte testem T012(i) | Pomiary na iPhonie 15 Pro w obu trybach — właściciel nie przeprowadza weryfikacji ręcznej poza listą końcową i zrezygnował z testów wydajności dla tej poprawki |

Zmiana zakresu względem Androida 2.0.1 (wykres grup i zwijana lista w „Treningach jeźdźca”) jest obsłużona zgodnie
z zasadą VIII aktualizacją obu specyfikacji (FR-019) — nie jest naruszeniem.
