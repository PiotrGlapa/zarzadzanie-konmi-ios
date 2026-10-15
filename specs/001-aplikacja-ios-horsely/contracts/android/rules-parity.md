# Kontrakt: zgodność reguł telefonu z programem

Wymagania: FR-SAM-02/03/04/05, FR-SYN2-08, SC-2-03. Konstytucja I i VI. Decyzja: research R8.

## 1. Zakres portu

| Reguła | Źródło w programie (`../zarzadzanie_konmi/src/ZarzadzanieKonmi.Application`) | Moduł w telefonie (`core/…/rules`) |
|---|---|---|
| Walidacja pól, komunikaty | `**/*Validator.cs`, `Resources/*` | `validation/` |
| Unikalność (np. numer paszportu, UELN, chip, wartości słowników) | walidatory + `Infrastructure/Persistence/Configurations/*` | `validation/Uniqueness` |
| Termin z daty następnej wizyty; zamknięcie pasującego terminu (≤ 14 dni przed) | `Visits/*Registrations.cs`, `Reminders/ReminderRegistrations.cs`, `Reminders/ReminderService.cs` | `ReminderAutomation` |
| Termin z zawodów w przyszłości | `Competitions/CompetitionRegistrations.cs` | `ReminderAutomation` |
| Podział zakupu na konie | `Purchases/PurchaseService.cs` | `PurchaseSplit` |
| Status „Padł” → cena sprzedaży 0 | `Horses/HorseService.cs` | `HorseRules` |
| Kontakt użyty jako trener/jeździec — `InUse` | `Contacts/ContactService.cs` | `ContactRules` (rozszerzenie istniejącego) |
| Kosz: partie, zależności, przywracanie, trwałe usunięcie | `Trash/TrashService.cs`, `ISoftDeleteDependencyProvider`, `IRestoreGuard` | `TrashRules` |
| Słowniki: domyślne wartości, systemowe, „używane” | `Infrastructure/Persistence/DatabaseInitializer.cs`, `Dictionaries/DictionaryService.cs` | `DefaultDictionaries`, `DictionaryRules` |
| Pulpit | `Reminders/DashboardQuery.cs`, `Reports/CostEntriesQuery.cs` | `LocalDashboard` |
| Oś czasu konia | `Timeline/TimelineQuery.cs` | `LocalTimeline` |
| Raporty: Koszty, Bilans konia, Podsumowanie treningów, Treningi jeźdźca, Zawody jeźdźca | `Reports/CostReportQuery.cs`, `HorseBalanceQuery.cs`, `Trainings/TrainingSummaryQuery.cs`, `Reports/RiderTrainingsReportQuery.cs`, `RiderCompetitionsReportQuery.cs` | `LocalReports` → istniejące `ToTabular` + `CsvReportWriter` |
| Sumy działów (Treningi, Zakupy, Zawody) | odpowiedzi list z `totalCost`/sumami | `LocalSections` |

Kolejność i porównywanie tekstów (sortowanie po imieniu z polskimi znakami) — jak w programie (`StringComparer` z kulturą
`pl-PL`); w Kotlinie `Collator.getInstance(Locale("pl", "PL"))` z testem na przypadkach brzegowych (ą, ł, ż, wielkość liter).

## 2. Pliki wzorcowe (dostarcza program)

W repozytorium programu narzędzie testowe (np. `tools/ParityFixtures`) na bazie testowej z ustalonymi danymi zapisuje
do `core/src/test/resources/parity/<zestaw>/`:

| Plik | Zawartość |
|---|---|
| `export.json` | `GET /export?scope=full` |
| `dashboard@<data>.json` | `GET /dashboard` z zegarem ustawionym na `<data>` |
| `timeline/<horseId>.json` | `GET /horses/{id}/timeline` (wszystkie strony) |
| `reports/<raport>@<filtry>.json` i `.csv` | 5 raportów dla zestawu filtrów (rok, miesiąc, koń, jeździec, kategoria) |
| `scenarios/<nazwa>.json` | scenariusz reguły: `before` (eksport), `operation` (żądanie API), `after` (eksport) lub `error` (problem z polami) |

Minimalne zestawy: `maly` (2 konie, po 1 rekordzie każdego rodzaju), `brzegowy` (grosze przy podziale zakupu, terminy
na granicy 14 dni, koń „Padł”, kontakt `InUse`, źrebak bez paszportu, polskie znaki), `duzy` (≥ 10 koni, ≥ 1 000
rekordów — SC-2-03).

## 3. Testy w `:core`

- `ParityTest` dla każdego pliku: silnik na `export.json` (+ zegar z nazwy pliku) → wynik porównany z odpowiedzią
  programu po normalizacji (kolejność pól nieistotna, kwoty `BigDecimal` co do grosza, czas co do minuty).
- CSV — porównanie bajt w bajt.
- Scenariusze — `before` + operacja w silniku → `after` (identyczne rekordy poza `id` nowych rekordów
  i znacznikami czasu) albo identyczny błąd przy tych samych polach z tym samym tekstem.

## 4. Aktualizacja

Zmiana reguły w programie → nowe pliki wzorcowe → czerwony test w telefonie → port zmiany. Wersja programu, z której
pochodzą pliki, zapisana w `parity/VERSION`.
