# Kontrakt: wspólne komponenty interfejsu 1.2

Decyzje: [research.md R4–R7](../research.md). Wszystkie w `app/src/main/kotlin/pl/glapa/zk/app/ui/components/` (odstępy
w `ui/theme/Spacing.kt`). Teksty w `strings.xml`.

## 1. Ocena — `StarRating.kt`

| Komponent | Zachowanie |
|---|---|
| `StarRatingDisplay(rating: Int?)` | Tekst `Stars.format(rating)` („★★★☆☆”), wypełnione gwiazdki w kolorze `extraColors.warning`, puste `onSurfaceVariant`; brak oceny → „—”. `contentDescription` „Ocena: N z 5” / „Brak oceny” (cały element jeden węzeł dla czytnika). |
| `StarRatingInput(value: Int?, onChange: (Int?) -> Unit, label)` | Etykieta pola + 5 `IconButton` (≥ 48 dp, `Icons.Filled.Star` / `Icons.Outlined.StarOutline`), każdy z `contentDescription` „N z 5” i `selected` dla wypełnionych; dotknięcie N → `onChange(N)`; przycisk „Wyczyść” (widoczny, gdy jest ocena) → `onChange(null)`. Błąd walidacji pod gwiazdkami. |

Użycie: `FieldType.Rating` w formularzach treningu (`rating`) i startu (`subjectiveRating`); szczegóły wpisu
(`EntryDisplay`); wiersz treningu (`TrainingComponents`); wiersz raportu „Treningi jeźdźca” (pojedyncza ocena). Średnie —
liczby, bez gwiazdek.

## 2. Obszary — `InfoCard.kt`, `ReminderCard`

| Komponent | Zachowanie |
|---|---|
| `InfoCard(tone: InfoTone, modifier, onClick: (() -> Unit)? = null, content)` | Zaokrąglenie 12 dp, wewnętrzny odstęp 12 dp, tło wg tonu ([data-model §3](../data-model.md)); `Warning` z ramką 1 dp `extraColors.warning`; klikalna, gdy `onClick` (ripple, etykieta akcji). |
| `ReminderCard(item: ReminderItem, horseName, today, onClick)` | `InfoCard` z tonem wg stanu terminu; treść: rodzaj (ikona + nazwa), data (`dd.MM.yyyy`, przy przeterminowanych „N dni temu”), tytuł/opis, etykieta stanu („Przeterminowany” / „czeka na wysłanie”) jako tekst — nie tylko kolor. |
| `InfoGroup(title, tone, items)` (Pulpit) | `InfoCard` z nagłówkiem `SectionHeader` i wierszami terminów w środku rozdzielonymi `DividedColumn`; niewidoczna dla pustej listy. |

Karta bilansu konia i koszty konia oraz koszty miesiąca na Pulpicie — `InfoCard(Neutral)`.

## 3. Listy — `DividedList.kt`

| API | Zachowanie |
|---|---|
| `LazyListScope.dividedItems(items, key, content)` | Wiersze z `HorizontalDivider(1 dp, outlineVariant, startIndent = 16 dp)` **między** wierszami (n − 1); `Modifier.testTag("list-divider")`. |
| `DividedColumn(items, content)` | To samo w zwykłej `Column` (zakładki karty konia, wnętrze `InfoGroup`). |

Nie używać dla kafli koni ani `ReminderCard` (rozdziela odstęp 8 dp).

## 4. Nagłówki i odstępy — `SectionHeader.kt`, `Spacing.kt`

- `SectionHeader(text, color = primary)` — `titleSmall`, odstęp górny 16 dp, dolny 4 dp, `heading()` dla czytnika;
  zastępuje lokalne `SectionTitle` (Pulpit, karta konia, formularze, ustawienia).
- `Spacing.screen = 16.dp` (krawędź), `Spacing.section = 16.dp`, `Spacing.item = 8.dp`, `Spacing.card = 12.dp`.

## 4a. Dolny przycisk zapisu — `FormSaveBar.kt`

`FormSaveBar(onSave, enabled, busy)` — `Scaffold.bottomBar` formularza: szeroki `Button` „Zapisz” (wysokość ≥ 48 dp,
odstęp `Spacing.screen`), nad klawiaturą (`imePadding`), w trakcie zapisu wskaźnik postępu i `enabled = false`; ta sama
akcja co „Zapisz” w pasku tytułu (który zostaje). Użycie: `EntryFormScaffold`, `ReminderFormScreen`, `HorseFormScreen`,
`ContactFormScreen` (wszystkie formularze, także formularz zawodów oparty na `EntryFormScaffold`).

## 5. Sekcje formularzy — `FieldSpec.section`

`enum class FormSection { Basic, Details, Costs, NextVisit, Notes }` — nagłówki: „Podstawowe”, „Szczegóły”, „Koszty”,
„Następna wizyta”, „Uwagi”. Reguła przypisania pól (wszystkie rodzaje wpisów, trening, zakup, start, zawody, termin):

| Sekcja | Pola (przykłady kluczy) |
|---|---|
| Podstawowe | koń/konie, data, rodzaj/typ, kontakt (weterynarz, kowal, trener, jeździec), zawody |
| Szczegóły | pola merytoryczne rodzaju (diagnoza, leki, usługa, czas, intensywność, ocena, klasa, wynik, produkt, ilość) |
| Koszty | kwota, waluta, koszt dostawy, wpisowe, pozostałe koszty, nagroda |
| Następna wizyta | data następnej wizyty / przypomnienie |
| Uwagi | opis, uwagi |

Pola „więcej” (`advanced`) zostają w swojej sekcji pod przełącznikiem „Pokaż więcej pól”. Formularze konia i kontaktu —
te same nagłówki w ich ekranach (`HorseFormScreen`, `ContactFormScreen`).
