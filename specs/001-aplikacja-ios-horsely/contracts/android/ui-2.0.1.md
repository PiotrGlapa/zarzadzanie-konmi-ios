# Kontrakt UI: wersja 2.0.1

Teksty po polsku, dokładnie jak niżej (zasoby `strings.xml`; teksty raportów w `ReportTexts` — jak w programie). Wymagania dostępności 2.0
bez zmian: kontrast tekstu ≥ 4,5:1, elementów graficznych ≥ 3:1, cele dotyku ≥ 48 dp, tekst 200 % bez obcinania, informacja nigdy tylko kolorem.

## 1. Nazwa (FR-021…FR-023)

| Miejsce | Tekst |
|---|---|
| Etykieta pod ikoną, ostatnie aplikacje, powiadomienia, udostępnianie (`app_name`) | Horsely |
| Ekran powitalny (wybór trybu) — tytuł, „O aplikacji” — nagłówek (`app_full_name`) | Horsely – Zarządzanie Koniem, Trening i Budżet |
| Teksty o programie na komputerze | „program Horsely”, „program Horsely na komputerze” (zamiast „program Zarządzanie końmi”) |
| Temat logu diagnostycznego | Log diagnostyczny — Horsely |

## 2. Status „Kontuzjowany” (FR-005…FR-011, FR-007a)

Ikona: `Icons.Outlined.Healing` (plaster), kolor `extraColors.warning` (jasny `#B45309`, ciemny `#FFB77C`).

| Miejsce | Wygląd | Czytnik ekranu |
|---|---|---|
| Kafel konia na Pulpicie | ikona 24 dp w prawym górnym rogu kafla, nie zasłania zdjęcia ani imienia | „<imię>, kontuzjowany” (jeden opis kafla) |
| Wiersz listy koni | pod imieniem plakietka: ikona 18 dp + „Kontuzjowany” (tekst w kolorze ostrzegawczym) | „<imię>, kontuzjowany” |
| Karta konia — nagłówek | plakietka jak w wierszu listy, obok statusu | „Status: Kontuzjowany” |
| Lista koni — filtr statusu | chip „Kontuzjowany” z ikoną; domyślny widok: aktywne i kontuzjowane; chip „Aktywny” — tylko aktywne | „Kontuzjowany, filtr” |
| Formularz konia — status | opcja „Kontuzjowany” (data statusu wymagana, notatka) — w trybie online tylko przy `horseStatusInjured` | — |
| Raport „Bilans konia” — filtr statusu, podtytuł karty, CSV | „Kontuzjowany” | — |

Ostrzeżenie przy treningu (formularz treningu, szybki wpis z Pulpitu), gdy wybrany koń jest kontuzjowany:

| Element | Tekst |
|---|---|
| Tytuł | Koń jest kontuzjowany |
| Treść | Koń jest kontuzjowany. Zapisać trening? |
| Przyciski | „Zapisz” (zapisuje) · „Anuluj” (wraca do formularza z danymi) |

## 3. Wiersz raportu „etykieta — wartość” (FR-027, FR-028)

```text
szeroko / krótka wartość:          wąsko albo długa wartość:
┌──────────────────────────────┐   ┌──────────────────────────────┐
│ Wynik            -1 250,00 zł │   │ Uwagi                        │
│ Uwagi        strata; brak ceny│   │ strata; brak ceny zakupu;    │
│               zakupu; koń nie │   │ koń nie sprzedany (wynik     │
│                   sprzedany … │   │ bieżący)                     │
└──────────────────────────────┘   └──────────────────────────────┘
```

Reguła: etykieta ma co najmniej szerokość swojego najdłuższego słowa; jeśli dla wartości zostaje < 40 % szerokości albo jej najdłuższe słowo się nie
mieści — wartość pod etykietą, wyrównana do lewej. Dotyczy kart wszystkich raportów, „Więcej szczegółów” i podsumowań.

## 4. Dziennik diagnostyczny (FR-029…FR-033)

**Ustawienia → Połączenie** (tryb online):

| Element | Tekst |
|---|---|
| Przełącznik | Szczegółowy dziennik połączeń |
| Opis (wyłączony) | Zapisuje adres, IP i wynik każdego połączenia z programem. Wyłącza się sam po 7 dniach. |
| Opis (włączony) | Włączony do 22.10.2026, 18:29 |

W trybie samodzielnym przełącznika nie ma (Ustawienia nie mają sekcji Połączenie).

**Ustawienia → O aplikacji → Dziennik diagnostyczny** (oba tryby):

| Element | Tekst / zachowanie |
|---|---|
| Tytuł ekranu | Dziennik diagnostyczny |
| Nagłówek | Rozmiar: 124 KB · szczegółowy dziennik połączeń: włączony do 22.10.2026, 18:29 / wyłączony |
| Lista | wpisy od najnowszych, czcionka o stałej szerokości, zawijanie wierszy, przewijanie; długie listy leniwie |
| Pusty | Dziennik jest pusty. |
| Akcje | „Wyślij” (dotychczasowe udostępnianie), „Wyczyść” |
| Potwierdzenie „Wyczyść” | Wyczyścić dziennik diagnostyczny? Wpisy zostaną usunięte z telefonu. · „Wyczyść” / „Anuluj” |

Dotychczasowy przycisk „Wyślij log diagnostyczny” w „O aplikacji” zostaje zastąpiony pozycją „Dziennik diagnostyczny”.

## 5. Ostrzeżenie „nowszy niż testowany” (FR-024)

Bez zmian w treści; pokazywane dla programu nowszego niż **2.0.0**.
