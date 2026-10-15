# Kontrakt: nawigacja, działy i ikony (US2, US3)

Zmienia tabelę „5.2 Struktura” z wersji 1.0. Decyzje: [research.md R2–R4](../research.md).

## 1. Dolna nawigacja

| Kolejność | Etykieta | Ikona | Trasa | Zaznaczona także dla |
|---|---|---|---|---|
| 1 | Pulpit | `Icons.Outlined.Home` | `DashboardRoute` | — |
| 2 | Konie | `R.drawable.ic_horse_head` (głowa konia z programu) | `HorsesRoute` | — |
| 3 | Terminy | `Icons.Outlined.Event` | `RemindersRoute` | — |
| 4 | Treningi | `Icons.Outlined.DirectionsRun` | `TrainingsRoute` (**nowa**) | — |
| 5 | Więcej (licznik kolejki) | `Icons.Outlined.MoreHoriz` | `MoreRoute` | wszystkie trasy z §2 i ich ekrany podrzędne |

## 2. Ekran „Więcej”

| Kolejność | Pozycja | Ikona | Trasa |
|---|---|---|---|
| 1 | Zawody | `Icons.Outlined.EmojiEvents` | `CompetitionsRoute` (**nowa**) → `CompetitionDetailRoute`, `CompetitionFormRoute` (**nowe**) |
| 2 | Zakupy | `Icons.Outlined.ShoppingCart` | `PurchasesRoute` (**nowa**) |
| 3 | Kontakty | `Icons.Outlined.Contacts` | `ContactsRoute` (przeniesiona z dolnej nawigacji) → `ContactDetailRoute`, `ContactFormRoute` |
| 4 | Raporty | `Icons.Outlined.Assessment` | `ReportsRoute` (bez zmian) |
| — | *separator* | | |
| 5 | Kolejka wysyłki (licznik) | `Icons.Outlined.CloudSync` | `QueueRoute` |
| 6 | Ustawienia | `Icons.Outlined.Settings` | `SettingsRoute` |
| 7 | O aplikacji | `Icons.Outlined.Info` | `AboutRoute` |

Nie ma pozycji: Słowniki, Kosz, Ustawienia programu (FR-MENU-02).

## 3. Ekrany nowych działów

| Ekran | Zawartość | Akcje |
|---|---|---|
| Treningi | filtry (arkusz u dołu: okres, koń, rodzaj, trener, jeździec) · lista (data, koń, rodzaj, czas, wysokość przy skokach, trener, koszt) · stopka: liczba, łączny koszt | „+” → wybór konia → formularz treningu; wiersz → szczegóły/edycja (jak w 1.0) |
| Zakupy | filtry (okres, kategoria, dostawca, przypisanie: wszystkie / koń / ogólne) · lista (data, produkt, kategoria, dostawca, konie lub „Ogólne (stajnia)”, łączna kwota) · stopka: liczba, „Razem” | „+” → formularz zakupu (przypisanie w formularzu); wiersz → edycja; menu wiersza: „Powtórz zakup”, „Usuń” |
| Zawody | filtry (okres, dyscyplina, koń) · lista (nazwa, data od–do, miejscowość, dyscyplina, liczba startów, najlepsze miejsce) | „+” → formularz zawodów; wiersz → szczegóły |
| Szczegóły zawodów | dane zawodów · lista startów (koń, jeździec, klasa, wynik/miejsce, wpisowe, pozostałe koszty, nagroda) | „Dodaj start”, „Edytuj”, „Usuń” (online); start → edycja startu; koń → karta konia |

Wspólne stany (jak w 1.0): szkielety przy ładowaniu; „pusto” z podpowiedzią („Wyczyść filtry” / „Dodaj”); pozycje
z kolejki na górze z oznaczeniem „czeka na wysłanie”; offline — „Dane z …” i podliczenie „z pamięci”; okres poza
pamięcią — „Starsze dane wymagają połączenia z komputerem”. Akcje tylko z połączeniem — `OnlineOnlyAction` (nieaktywne
z wyjaśnieniem).

Dostępność: każda pozycja menu i wiersz z etykietą dla czytnika ekranu (z licznikiem kolejki w etykiecie „Więcej”),
cele dotyku ≥ 48 dp, tekst 200 % bez obcinania nazw działów (etykiety dolnej nawigacji jednowierszowe).

## 4. Ikony aplikacji

| Zasób | Treść | Użycie |
|---|---|---|
| `mipmap/ic_launcher.xml` | `adaptive-icon`: background = `drawable/ic_launcher_background`, foreground = `drawable/ic_launcher_foreground`, monochrome = `drawable/ic_launcher_monochrome` | `android:icon`, `android:roundIcon` |
| `drawable/ic_launcher_background.xml` | wektor 108×108, gradient liniowy #2C7756 (lewy górny) → #1D553E (prawy dolny) | tło ikony |
| `drawable/ic_launcher_foreground.xml` | biała podkowa (łuk + nogi, zaokrąglone końce) w strefie bezpiecznej 66 dp | ikona aplikacji |
| `drawable/ic_launcher_monochrome.xml` | ta sama podkowa, jednokolorowa | ikony tematyczne (Android 13+) |
| `drawable/ic_stat_horseshoe.xml` | biała podkowa 24×24 na przezroczystym | mała ikona powiadomień (terminy, kolejka) |
| `drawable/ic_horse_head.xml` | głowa konia z `HorseHeadGeometry` + `HorseHeadDotsGeometry` programu (kontur 1,5 / 1,6, zaokrąglone) | nawigacja „Konie”, kafle i karta konia bez zdjęcia, wybór konia |
| `color/ic_launcher_background` | usunięty (zastąpiony wektorem z gradientem) | — |

Ekran powitalny parowania i „O aplikacji”: podkowa (foreground na tle background, kształt koła). `Icons.Outlined.Pets`
nie występuje w kodzie aplikacji (test źródeł).
