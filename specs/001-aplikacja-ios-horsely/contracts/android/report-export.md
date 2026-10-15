# Kontrakt: eksport raportów CSV i PDF

**Wymagania**: FR-M-RAP-01…07, SC-M-09 | **Research**: [R16, R17](../research.md#r17-eksport-raportów-csv-i-pdf)

Źródło formatu: program „Zarządzanie końmi” 1.6.1 (repozytorium `zarzadzanie_konmi`):

| Element | Plik w programie |
|---|---|
| Zapis CSV | `src/ZarzadzanieKonmi.Application/Reports/CsvReportWriter.cs` |
| Model tabeli, formaty komórek | `src/ZarzadzanieKonmi.Application/Reports/TabularReport.cs` |
| Kolumny „Bilans konia” | `src/ZarzadzanieKonmi.Application/Reports/HorseBalanceQuery.cs` (`ToTabular`) |
| Kolumny „Podsumowanie treningów” | `src/ZarzadzanieKonmi.Application/Trainings/TrainingSummaryQuery.cs` (`ToTabular`) |
| Kolumny „Treningi jeźdźca” | `src/ZarzadzanieKonmi.Application/Reports/RiderTrainingsReportQuery.cs` |
| Kolumny „Zawody jeźdźca” | `src/ZarzadzanieKonmi.Application/Reports/RiderCompetitionsReportQuery.cs` |
| Nazwy plików | `FileName()` w `src/ZarzadzanieKonmi.Desktop/Features/Reports/*ViewModel*.cs` |
| Etykiety (`Csv_*`, `Duration_*`, `Report_General`) | `src/ZarzadzanieKonmi.Application/Resources/AppTexts.resx` |

Implementacja w `:core` przenosi te definicje 1:1 (kolumny, kolejność, nagłówki CSV, wiersze sum, uwagi). Zmiana w programie
wymaga zmiany tego kontraktu, plików wzorcowych i kodu (zasada V).

## CSV — reguły bajtowe

| Reguła | Wartość |
|---|---|
| Kodowanie | UTF‑8 **z BOM** (`EF BB BF`) |
| Koniec wiersza | `\r\n` (także po ostatnim wierszu) |
| Separator | `;` |
| Cudzysłowy | pole zawierające `;`, `"`, `\r` lub `\n` w `"…"`, wewnętrzne `"` podwojone (RFC 4180) |
| Kwota (`Money`) | `0.00` w `pl-PL`, bez separatora tysięcy: `1250,00` |
| Liczba z 1 miejscem (`Decimal1`) | `0.0`: `3,5` |
| Liczba całkowita, minuty | bez separatora tysięcy: `1405` (minuty jako liczba, nagłówek z jednostką, np. `Czas (min)`) |
| Data | `dd.MM.yyyy` |
| Data i czas | `dd.MM.yyyy HH:mm` |
| Brak wartości | pole puste |
| Struktura raportu tabelarycznego | nagłówek → wiersze → pusty wiersz → wiersze sum (jeśli są) → pusty wiersz → uwagi (jeśli są), każda uwaga w pierwszej kolumnie |
| Raport „Koszty” | kolumny wg `groupBy`: `horse` → Koń; Kategoria; Koszty; Przychody · `month` → Miesiąc; Kategoria; … · `category` → Kategoria; Koszty; Przychody; po wierszach: pusty wiersz, „Razem”, „Ogólne (stajnia)” (koszty = `generalPurchasesTotal`), „Saldo” (przychody = `balance`) |

## PDF — wymagane elementy (układ aplikacji)

- A4 pionowo; marginesy 36 pt; czcionka systemowa z polskimi znakami.
- Nagłówek: nazwa raportu, filtry (okres, konie, kategorie, grupowanie / jeździec / zakres), „Dane z: <data i godzina>”
  (z pamięci podręcznej — „Dane z pamięci telefonu, pobrane <data>”, FR-M-RAP-06), wersja programu.
- Tabela z tymi samymi kolumnami co CSV; wartości wg `TabularReport.Display`: kwoty `1 250,00 zł` (separator tysięcy U+00A0),
  minuty „X h Y min” / „Y min” / „—”, brak wartości „—”; łamanie stron z powtórzeniem nagłówka kolumn.
- Sumy i uwagi pod tabelą.
- Wykresy (R16): „Koszty” — słupkowy skumulowany miesięczny + kołowy kategorii; „Podsumowanie treningów” — wykres postępów
  wybranego parametru z legendą (kolor + kształt znacznika). Pozostałe raporty — bez wykresów (jak w programie).
- Stopka: „Zarządzanie końmi — aplikacja na Androida <wersja> · strona X z Y”.

## Nazwa pliku

Jak w programie: `<Tytuł raportu> <yyyy-MM-dd>` (data utworzenia pliku, czas lokalny) z rozszerzeniem `.csv` / `.pdf`;
dla danych z pamięci podręcznej dopisek ` (dane z <yyyy-MM-dd>)` (FR-M-RAP-06). Raporty, których nazwa w programie zawiera
dodatkowe elementy (np. imię konia w „Podsumowaniu treningów”), odtwarzają je wg `FileName()` z programu.

## Pliki wzorcowe i testy

- `core/src/test/resources/golden/<raport>/<przypadek>.json` — odpowiedź API (z zaślepki zgodnej z kontraktem albo zapisana
  z programu 1.6.1 dla zestawu testowego).
- `core/src/test/resources/golden/<raport>/<przypadek>.csv` — CSV wyeksportowany przez program 1.6.1 dla tych samych danych
  i filtrów.
- Test: `CsvReportWriter(TabularReport(json))` == plik `.csv` **bajt w bajt**; przypadki: dane typowe, brak danych, pola
  z `;` i `"`, kwoty ≥ 1000, czas < 60 i ≥ 60 min, wartości `null`, raport z pamięci podręcznej.
- Test PDF (`:app`): liczba stron > 0, obecność nazwy raportu, filtrów, sum i legendy (tekst z `PdfRenderer` niedostępny →
  sprawdzenie przez rejestrację wywołań `Canvas.drawText` w rendererze).
