# Kontrakt: przegląd ekranów (FR-EST-01…05, FR-LIS-01…03, FR-BLD-03)

Zakres: wszystkie ekrany (Clarifications 2026-10-09, opcja B). Każdy ekran sprawdzany w jasnym i ciemnym motywie oraz
przy tekście 200 %. Kolumna „Wynik” wypełniana podczas wdrożenia: **OK** (spełnia) · **POPR** (poprawiono — co) ·
**WYJ** (wyjątek — uzasadnienie).

> **Podstawa wyników (wersja 1.2.0):** przegląd kodu źródłowego ekran po ekranie oraz testy Robolectric (linie między wierszami, sekcje formularzy, tony obszarów, kontrast par kolorów, brak jawnego ucięcia tekstu 200 %). Oględziny na urządzeniu — TalkBack, prawdziwe zawijanie tekstu przy 200 %, jasny i ciemny motyw — to zadanie T048 i wymagają telefonu lub emulatora.

## 1. Zasady (lista kontrolna dla każdego ekranu)

| Kod | Zasada |
|---|---|
| E1 | Odstępy z `Spacing` (krawędź 16 dp, sekcje 16 dp, elementy 8 dp); nagłówki sekcji przez `SectionHeader` |
| E2 | Listy: linie między wierszami (`dividedItems` / `DividedColumn`); obszary i kafle bez linii |
| E3 | Każdy wiersz/kafel wyglądający na klikalny coś otwiera; informacyjne — bez efektu dotknięcia |
| E4 | Główna akcja w dolnej części ekranu (FAB / dolny przycisk); cele dotyku ≥ 48 dp |
| E5 | Tekst 200 % bez obcinania; kontrast tekstu ≥ 4,5:1, elementów graficznych ≥ 3:1 |
| E6 | Kolor: zieleń — główny, pomarańcz — ostrzeżenia, czerwień — błędy; tła obszarów z `InfoCard` |
| E7 | Formularze: sekcje z nagłówkami (`FormSection`), pola wymagane oznaczone „*”, „Zapisz” w pasku tytułu i w `FormSaveBar` na dole (nad klawiaturą) |
| E8 | Stany: ładowanie, pusto (z podpowiedzią), błąd — spójne komponenty z `ScreenState` |

## 2. Ekrany

| Grupa | Ekran (plik w `app/src/main/kotlin/pl/glapa/zk/app/ui/`) | Zakres zmian 1.2 | Wynik |
|---|---|---|---|
| Pulpit | `dashboard/DashboardScreen.kt` | grupy terminów w `InfoGroup` (3 tony), koszty w `InfoCard`, „Ostatnie wpisy” klikalne z liniami, kafel konia → karta konia | **POPR** — grupy terminów w trzech obszarach (Warning / Primary / Neutral), koszty w `InfoCard`, „Ostatnie wpisy” klikalne i rozdzielone liniami, kafel konia otwiera kartę konia; termin przeterminowany na kaflu konia dostał słowa „po terminie” i pogrubienie zamiast samego koloru; `SectionHeader` i `Spacing` (E1–E3, E5, E6) |
| Konie | `horses/HorsesScreen.kt` | E1–E8 | **POPR** — linie między wierszami (`dividedItems`), `Spacing`; **WYJ** E4: „Dodaj konia” jest na końcu listy, bo „+” z dolnej belki dodaje wpis, nie konia |
| Karta konia | `horses/HorseDetailScreen.kt` | terminy jako `ReminderCard`, koszty i bilans w `InfoCard` | **POPR** — każdy termin osobnym `ReminderCard` (przeterminowany pomarańczowy z etykietą „Przeterminowany” i „N dni temu”), koszty i bilans w `InfoCard(Neutral)`, nagłówki przez `SectionHeader`; `Spacing` (E1, E2, E5, E6) |
| Karta konia — zakładki | `horses/HorseTabs.kt`, `horses/TrainingsTab.kt` | Zakupy i starty klikalne z liniami, ocena gwiazdkami, linie we wszystkich zakładkach | **POPR** — Zakupy i starty otwierają szczegóły (z „Edytuj”), linie w Osi czasu, Terminach, Paszporcie (szczepienia), Zawodach, Zakupach i Treningach; ocena w Treningach jako gwiazdki; Zawody: lista startów poza dopełnioną kolumną statystyk (E2, E3) |
| Formularz konia | `horses/HorseFormScreen.kt` | sekcje z nagłówkami | **POPR** — nagłówki sekcji (Podstawowe, Szczegóły, „Kwoty konia (ocena własna)”), „Zapisz” w pasku tytułu i w `FormSaveBar` nad klawiaturą, przełączniki i pola wyboru ≥ 48 dp (E1, E4, E7) |
| Terminy | `reminders/RemindersScreen.kt` | linie między wierszami | **POPR** — linie między wierszami (E2); pozostałe zasady bez uwag |
| Szczegóły terminu | `reminders/ReminderDetailScreen.kt` | E1–E8 | **OK** — stany ładowania/błędu/braku z `ScreenState`, kolor ostrzegawczy tylko z towarzyszącym słowem „po terminie”; `Spacing` zastosowane (E1, E5, E8) |
| Formularz terminu | `entry/ReminderFormScreen.kt` | sekcje | **POPR** — nagłówki sekcji (Podstawowe, Uwagi), „Zapisz” w pasku tytułu i w `FormSaveBar`, pola wymagane z „*” (E7) |
| Nowy wpis | `entry/NewEntryScreen.kt` | linie w listach wyboru | **POPR** — linie między rodzajami wpisów i na liście koni (E2) |
| Formularze wpisów | `entry/EntryFormScaffold.kt` (+ `FormSpec.kt`) | `FormSection`, `StarRatingInput` | **POPR** — `FormSection` (Podstawowe → Szczegóły → Koszty → Następna wizyta → Uwagi) z nagłówkami, ocena wybierana gwiazdkami (`StarRatingInput`), „Zapisz” w pasku tytułu i w `FormSaveBar`, przełączniki i opcje ≥ 48 dp (E1, E4, E7) |
| Szczegóły wpisu | `entry/EntryDetailScreen.kt` | sekcje jak w formularzu, gwiazdki | **POPR** — te same sekcje co w formularzu, ocena jako gwiazdki z opisem „Ocena: N z 5” (E1, E7) |
| Treningi | `trainings/TrainingsSectionScreen.kt` | gwiazdki w wierszu | **POPR** — gwiazdki w wierszu, linie, domyślny okres 1.01–31.12 (E2, E3) |
| Zakupy | `purchases/PurchasesScreen.kt` | E1–E8 | **POPR** — linie między wierszami, wiersz otwiera szczegóły, menu wiersza „Powtórz zakup”/„Usuń” (E2, E3) |
| Zawody | `competitions/CompetitionsScreen.kt`, `CompetitionDetailScreen.kt` | okres domyślny (dane), linie, gwiazdki startów | **POPR** — okres domyślny cały bieżący rok (zawody przyszłe widoczne), linie w liście i w startach zawodów, nagłówek „Starty” przez `SectionHeader` (E1, E2) |
| Kontakty | `contacts/ContactsScreen.kt`, `ContactDetailScreen.kt`, `ContactFormScreen.kt` | linie w szczegółach, sekcje formularza | **POPR** — linie w liście, w wierszach historii na karcie kontaktu, nagłówki sekcji historii i formularza przez `SectionHeader`/`FormSectionHeader`; „Zapisz” w pasku tytułu i w `FormSaveBar` (E1, E2, E7) |
| Listy wyboru | `components/HorsePicker.kt`, `ContactPicker.kt`, `DictionaryPicker.kt` | linie | **POPR** — linie w wyborze konia, kontaktu i w menu słownika; własny nagłówek wyboru konia zastąpiony `SectionHeader` (E1, E2) |
| Raporty | `reports/ReportsScreen.kt`, `ReportScaffold.kt`, `CostReportScreen.kt`, `HorseBalanceScreen.kt`, `TrainingSummaryScreen.kt`, `RiderReportScreens.kt` | linie w wierszach wyników, gwiazdki pojedynczej oceny | **POPR** — lista raportów rozdzielona liniami; gwiazdki w pojedynczej ocenie treningu jeźdźca (średnie i eksport zostają liczbami); **WYJ** E2: wyniki raportów to obszary (`Card`) rozdzielone odstępem, nie wiersze listy |
| Kolejka | `queue/QueueScreen.kt`, `StableMismatchScreen.kt` | linie (lista i historia) | **POPR** — linie w kolejce i w historii (E2) |
| Załączniki | `attachments/AttachmentViewerScreen.kt`, `AddAttachmentSheet.kt` | E1–E8 | **POPR** — tytuł podglądu z wielokropkiem przy długiej nazwie pliku (E5); reszta bez uwag |
| Więcej / Ustawienia | `settings/MoreScreen.kt`, `SettingsScreen.kt`, `ConnectionSettingsScreen.kt`, `NotificationSettingsScreen.kt`, `DataSettingsScreen.kt`, `AppearanceSettingsScreen.kt`, `AddressEditScreen.kt`, `AboutScreen.kt` | linie, nagłówki, opis zmian 1.2 w „O aplikacji” | **POPR** — linie w „Więcej” (osobno dla sekcji programu i dla telefonu) i w menu ustawień, nagłówki sekcji przez `SectionHeader`, opis zmian 1.2 w „O aplikacji”; przełączniki ≥ 48 dp (E1, E2, E4) |
| Parowanie | `pairing/WelcomeScreen.kt`, `ManualPairingScreen.kt`, `QrScannerScreen.kt`, `PairingResultScreen.kt` | E1–E8 | **OK** — przegląd kodu bez uwag (odstępy `Spacing`, przyciski pełnej szerokości, stany błędu); do sprawdzenia na urządzeniu (T048) |
