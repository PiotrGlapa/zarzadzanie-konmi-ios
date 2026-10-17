# Kontrakt UI: ekrany raportów (2.0.2)

Dotyczy wszystkich raportów (`ReportScaffold`), szczegóły dla „Treningi jeźdźca”.

## Kolejność elementów (wszystkie raporty)

1. Opis filtrów (bez zmian)
2. Karta sum (`report-totals`) — **przeniesiona z końca na górę**
3. Wykresy
4. Wiersze (karty)
5. Uwagi

Wartości, formaty (FR-M-RAP-04, kwoty `1 250,00 zł`), eksport CSV i PDF — bez zmian.

## „Treningi jeźdźca”

| Element | Identyfikator dostępności | Zawartość |
|---------|---------------------------|-----------|
| Kafelki podsumowania | `report-totals` | Liczba treningów · Łączny czas · Ocena (średnia) · Koszt |
| Przełącznik miary | `report-chart-metric` | „Liczba treningów” / „Łączny czas” |
| Wykres grup | `report-chart-groups` | słupki poziome: konie (jeden jeździec) albo jeźdźcy (wszyscy); etykieta VoiceOver = opis z `ChartDescriptions.groupBars` |
| Karty grup | `report-group-<n>` | „<nazwa> (treningów: N)”: czas, ocena, koszt |
| Przycisk listy | `report-rows-toggle` | „Pokaż treningi (N)” / „Ukryj treningi”; domyślnie zwinięte |
| Wiersze | jak dotąd | data · koń, rodzaj, czas, intensywność, ocena, trener, koszt (+ jeździec przy wszystkich) |

PDF: tabela jak w 2.0.1 + dwa obrazy wykresu (liczba, czas) z opisem tekstowym.

## Teksty (z `strings.xml` Androida)

`reports_show_trainings`, `reports_hide_trainings`, `reports_chart_metric_count`, `reports_chart_metric_time`,
`reports_chart_rider_groups_title`, `reports_chart_others`.
