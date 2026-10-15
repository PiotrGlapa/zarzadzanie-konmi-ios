# Kontrakt: ekrany i elementy interfejsu wersji 2.0

Wymagania: US1–US7, FR-TRB, FR-SYN2-06/07, FR-SAM-04/05, FR-KOP, FR-KOL, FR-ZDK. Decyzje: research R12, R16, R17, R21.
Teksty w `strings.xml` (PL); wszystkie kontrolki z etykietami dla czytnika ekranu, cele ≥ 48 dp, tekst 200%.

## 1. Nowe i zmienione ekrany

| Ekran | Trasa | Tryb | Zawartość |
|---|---|---|---|
| Powitanie — wybór trybu | `welcome` | `Unset` | wariant B (tekst w spec. 2.0), opcje jako `RadioButton` z opisem, „Dalej”, „Zmienisz to w Ustawieniach → Tryb pracy”; po „Nie, używaj samodzielnie” — także „Odtwórz z kopii zapasowej” |
| Pobieranie danych | `sync/initial` | Online | postęp (rekordy / etap), aplikacja używalna; baner na Pulpicie do końca |
| Ustawienia → Tryb pracy | `settings/mode` | oba | bieżący tryb, opis, przycisk zmiany; ostrzeżenia §2 |
| Konflikty | `conflicts`, `conflicts/{id}` | Online | lista (rekord, rodzaj, koń, data) + „Zachowaj wszystkie moje” / „Przyjmij wszystkie z programu”; szczegóły: dwie kolumny „Moja” / „Z programu”, różnice wyróżnione (tło + ikona, nie tylko kolor) |
| Kosz | `trash` | Samodzielny | partie (opis, koń, data usunięcia, liczba zależnych), „Przywróć”, „Usuń trwale”, „Opróżnij kosz” |
| Słowniki | `dictionaries`, `dictionaries/{type}` | Samodzielny | rodzaje słowników → wartości; dodaj, zmień nazwę, przeciągnij (kolejność), ukryj |
| Kopia zapasowa | `settings/backup` | Samodzielny | data i rodzaj ostatniej kopii, „Utwórz kopię zapasową” (hasło opcjonalne ×2 + ostrzeżenie), „Odtwórz z kopii”, „Automatyczna kopia co tydzień” + folder + ostatni błąd |
| Blokada | nakładka nad `NavHost` | oba | ikona, „Odblokuj” → `BiometricPrompt`; treść ukryta |
| Kadrowanie zdjęcia | `horse/{id}/photo/crop` | oba | podgląd z kwadratową maską, gesty, „Obróć”, „Anuluj”, „Zapisz” |

## 2. Ostrzeżenia (dwa kroki)

- **Samodzielny → online**: okno 1 — tytuł „Połączyć z programem?”, treść: „Dane zapisane w telefonie (X koni, Y wpisów)
  zostaną usunięte i zastąpione danymi z programu. Ostatnia kopia zapasowa: <data | brak>.”, przyciski „Utwórz kopię
  zapasową”, „Anuluj”, „Dalej”; okno 2 — „Usuń dane i połącz” (kolor błędu, nie domyślny) / „Anuluj”.
- **Online → samodzielny**: „Dane z programu zostaną w telefonie jako punkt startowy. Od tej chwili telefon i program
  będą prowadzone osobno. Niewysłane zmiany: N — nie trafią do programu.” → „Pracuj samodzielnie” / „Anuluj”.
- **Odtwórz z kopii**: data kopii, liczby, „Obecne dane zostaną zastąpione” → „Odtwórz” / „Anuluj”.

## 3. „Więcej” wg trybu

| Pozycja | Online | Samodzielny |
|---|---|---|
| Zawody, Zakupy, Kontakty, Raporty | ✓ | ✓ |
| Kolejka wysyłki (licznik) | ✓ | — |
| Konflikty (licznik) | ✓ (gdy > 0) | — |
| Kosz | — | ✓ |
| Słowniki | — | ✓ |
| Kopia zapasowa | — | ✓ |
| Ustawienia, O aplikacji | ✓ | ✓ |

Pulpit: licznik konfliktów (online), przypomnienie o kopii (samodzielny), baner pobierania danych (online).

## 4. Paleta kolorów (FR-KOL-01/03, R17) — do akceptacji na makiecie

| Rodzaj / dział | Rodzina | Jasny motyw (ikona/akcent) | Ciemny motyw |
|---|---|---|---|
| Pulpit (dolny pasek) | indygo | `#3949AB` | `#9FA8DA` |
| Konie (dolny pasek) | kasztanowy | `#8D4A2B` | `#FFAB91` |
| Terminy (dolny pasek) | cyjan | `#00838F` | `#80DEEA` |
| Wizyta weterynaryjna, Kontakty | niebieski | `#1565C0` | `#90CAF9` |
| Kowal | brązowy | `#6D4C41` | `#BCAAA4` |
| Fizjoterapia, Kopia zapasowa | turkusowy | `#00796B` | `#80CBC4` |
| Inny specjalista, Raporty | fioletowy | `#5E35B1` | `#B39DDB` |
| Notatka | szaroniebieski | `#546E7A` | `#B0BEC5` |
| Zakup, Zakupy | bursztynowy | `#A15C00` | `#FFCC80` |
| Zawody i start, Zawody | karmazynowy | `#B71C3C` | `#F48FB1` |
| Trening, Treningi | zielony (główny programu) | kolor główny motywu | kolor główny motywu |
| Kosz | szary | `#616161` | `#BDBDBD` |
| Konflikty | pomarańczowy (ostrzeżenie) | kolor ostrzegawczy motywu | kolor ostrzegawczy motywu |
| Termin | kolor rodzaju terminu (kowal, szczepienie → weterynarz, zawody, …) | | |

Zastosowanie: tło ikony (12% krycia koloru) + ikona w kolorze; pasek 4 dp po lewej w wierszach osi czasu i „Ostatnich
wpisów”; akcent nagłówka formularza; ikony w „Więcej” i wyborze rodzaju wpisu po „+”. Test: kontrast każdej pary wobec
`surface`/`background` obu motywów ≥ 3:1 (ikony, paski) i ≥ 4,5:1 tam, gdzie kolor jest kolorem tekstu.

## 5. Zdjęcie konia (FR-ZDK)

- Karta konia: nagłówek z miniaturą 72 dp (okrąg); brak zdjęcia → ikona głowy konia + „Dodaj zdjęcie”; dotknięcie →
  arkusz: „Zrób zdjęcie”, „Wybierz z telefonu”, „Wybierz z załączników konia”, [„Pokaż zdjęcie”, „Usuń zdjęcie”].
- Formularz konia: pole „Zdjęcie” z tym samym arkuszem.
- Pulpit: miniatura 40 dp na kaflu konia; bez akcji zdjęcia.
- Lista koni: miniatura 40 dp.

## 6. Testy UI

Compose UI: wybór trybu i powrót z parowania; oba ostrzeżenia zmiany trybu (anulowanie na każdym kroku); konflikty
pojedynczo i zbiorczo; kosz; słowniki; kopia z hasłem; blokada (atrapa `BiometricPrompt`); kadrowanie (gesty, obrót);
„Więcej” w obu trybach; kontrast palety (test jednostkowy).
