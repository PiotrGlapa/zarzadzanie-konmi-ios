# Kontrakt: ekrany i komponenty interfejsu (iOS)

**Wymagania**: FR-002, FR-M-UI-*, specyfikacja główna 5.1–5.4 | **Research**: R7–R10 | **Androidowe odpowiedniki**:
[android/ui-components.md](android/ui-components.md), [android/screen-review.md](android/screen-review.md),
[android/ui-screens.md](android/ui-screens.md), [android/ui-2.0.1.md](android/ui-2.0.1.md)

Teksty: klucze z `strings.xml` Androida (nazwy kluczy podane przy elementach w kodzie, nie tutaj). Kolory i ikony: 5.4.

## 1. Ekrany

| Grupa | Ekran (iOS) | Android (plik / trasa) | Tryb |
|---|---|---|---|
| Start | Wybór trybu, Odtwórz z kopii | `welcome/*` | nieustawiony |
| Parowanie | Wyjaśnienie „Sieć lokalna”, Skaner QR, Wpis ręczny, Wynik, Inna stajnia | `pairing/*`, `StableMismatchRoute` | online |
| Karty | Pulpit, Konie, Terminy, Treningi, Więcej | `DashboardRoute`, `HorsesRoute`, `RemindersRoute`, `TrainingsRoute`, `MoreRoute` | oba |
| Konie | Karta konia (7 zakładek), Formularz konia, Arkusz zdjęcia, Kadrowanie | `horses/*` | oba |
| Wpisy | Wybór rodzaju i konia („+”), Formularz wpisu (8 rodzajów + zawody), Szczegóły wpisu, Formularz terminu, Szczegóły terminu | `entry/*`, `reminders/*` | oba |
| Działy | Zakupy, Zawody, Szczegóły zawodów, Kontakty, Karta kontaktu, Formularz kontaktu | `purchases`, `competitions`, `contacts` | oba |
| Raporty | Lista, Koszty, Bilans konia, Podsumowanie treningów, Treningi jeźdźca, Zawody jeźdźca (+ arkusz filtrów) | `reports/*` | oba |
| Załączniki | Podgląd (obraz, PDF, wideo), Arkusz „Dodaj” | `attachments/*` | oba |
| Telefon (online) | Kolejka wysyłki, Konflikty, Szczegóły konfliktu | `queue`, `conflicts` | online |
| Telefon (samodzielny) | Kosz, Słowniki, Wartości słownika, Kopia zapasowa | `trash`, `dictionaries`, `backup` | samodzielny |
| Ustawienia | Ustawienia, Połączenie z programem, Edycja adresu, Tryb pracy, Powiadomienia, Blokada aplikacji, Dane, Wygląd | `settings/*` | wg FR-M-UST-00 |
| O aplikacji | O aplikacji, Dziennik diagnostyczny | `AboutRoute` | oba |
| Nakładki | Blokada, Komunikat połączenia (zwijany do ikonki), Baner pierwszego pobrania | `lock/*`, `ConnectionOverlay` | — |

## 2. Komponenty (Android → iOS)

| Android (Compose) | iOS (SwiftUI) | Zachowanie wspólne |
|---|---|---|
| `NavigationBar` + `FloatingActionButton` | `TabView` + nakładka „+” nad paskiem (Pulpit, Konie, Terminy, karta konia) | plakietka licznika kolejki na „Więcej” |
| `TopAppBar` + `ScreenTitle` (podtytuł „Dane z …”) | `.navigationTitle` + podtytuł w `ToolbarItem(.principal)` | ikonka połączenia w prawym górnym rogu |
| `InfoCard(tone)` / `InfoGroup` / `ReminderCard` | `InfoCard` (12 pt promień, 12 pt wnętrze, ramka 1 pt dla Primary/Warning) | tony Neutral / Primary / Warning |
| `dividedItems` / `DividedColumn` | `DividedList` (linia 1 pt, wcięcie 16 pt, tylko między wierszami) | brak linii po ostatnim wierszu |
| `SectionHeader` | `SectionHeader` (subheadline półgruby, kolor główny, `.isHeader`) | odstęp 16/4 pt |
| `FormSaveBar` | `safeAreaInset(.bottom)` z szerokim „Zapisz” | także „Zapisz” w pasku |
| `StarRatingDisplay` / `StarRatingInput` | `StarRating` (tekst ★, `accessibilityLabel` „Ocena: N z 5”) / 5 przycisków ≥ 44 pt + „Wyczyść” | — |
| `AccentIcon`, `AccentRow` | `AccentIcon` (kółko 12 % koloru), pasek 4 pt | kolory rodzajów |
| `HorseAvatar` | `HorseAvatar` (okrąg 40/72 pt, głowa konia bez zdjęcia) | — |
| `InjuredBadge` / `InjuryIcon` | `InjuredBadge` (ikona `healing` 18 pt + „Kontuzjowany”), ikona 24 pt na kaflu | VoiceOver „<imię>, kontuzjowany” |
| `FilterChip` / `AssistChip` | przyciski kapsułowe (`.buttonStyle(.bordered)` z ikoną) w przewijanym wierszu | — |
| `ModalBottomSheet` | `.sheet` z `.presentationDetents([.medium, .large])` | filtry, wybór, arkusz zdjęcia |
| `AlertDialog` (2 kroki przy zmianie trybu) | `.alert` / `.confirmationDialog`, przycisk usuwający z rolą `.destructive`, nie domyślny | — |
| `Snackbar` „Zapisano” + „Cofnij” | własny baner u dołu (`.transition(.move)`), 4 s, z akcją | — |
| `ConnectionOverlay` | nakładka u góry treści, zwijana po 3 s (dłużej przy VoiceOver) do ikonki | pomarańczowa / czerwona |

## 3. Ikony

Ikony Material (Outlined) wg 5.4 jako obrazy szablonowe `Assets.xcassets/Icons/<nazwa>.imageset` (SVG); głowa konia
`horse_head`, podkowa w `AppIcon`. SF Symbols tylko: wstecz, zamknij, udostępnij, menu, wyszukiwanie, ikonki połączenia.

## 4. Dostępność

Każda kontrolka z etykietą VoiceOver (teksty z `strings.xml` jak `contentDescription` w Androidzie); Dynamic Type do
`accessibility5` bez obcinania (wiersze raportów wg FR-027: `ViewThatFits` — etykieta i wartość obok siebie albo wartość
pod etykietą); cele dotyku ≥ 44 pt; informacja nigdy tylko kolorem.
