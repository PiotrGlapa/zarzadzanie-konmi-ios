# Feature Specification: Poprawki 2.0.2 — blokada aplikacji, zdjęcia koni z programu, czytelny raport treningów

**Feature Branch**: `002-poprawki-2-0-2`

**Created**: 2026-10-17

**Status**: Draft

**Input**: User description: "Poprawka 2.0.2 aplikacji iOS — trzy błędy zgłoszone przez właściciela po testach 2.0.1 w TestFlight: (1) po włączeniu blokady i odblokowaniu kodem aplikacja od razu blokuje się ponownie i nie da się do niej wejść; (2) po pobraniu danych z programu koń nie ma miniaturki zdjęcia, choć zdjęcie jest w programie i w aplikacji na Androida; (3) raport treningów wygląda jak menu Treningi — lista wszystkich treningów i podsumowanie dopiero na końcu, bez wykresu, nieczytelny."

## Kontekst

Wydanie 2.0.1 (kompilacja 23, TestFlight 2026-10-16) ma trzy błędy widoczne dla testerki. Normatywne pozostają wymagania
[SPECYFIKACJA_MOBILE_IOS.md](../../SPECYFIKACJA_MOBILE_IOS.md): FR-TRB-09 (blokada aplikacji), FR-ZDK-04…06 (miniatury
zdjęć koni, także bez połączenia), historia „Raporty” scenariusz 5 i układ ekranu raportu „filtry → sumy → wykresy →
wiersze” (tabela ekranów, sekcja 5) oraz FR-M-RAP-03/04. Błędy 1 i 2 oraz kolejność „sumy → wiersze” w raporcie
„Treningi jeźdźca” to **niezgodności z istniejącą specyfikacją** (aplikacja na Androida 2.0.1 działa poprawnie).
Wykres w raporcie „Treningi jeźdźca” i zwijana lista treningów to **zmiana zakresu** — zgodnie z zasadą VIII konstytucji
wymaga wpisu w obu specyfikacjach (iOS i Android) i odpowiednika w aplikacji na Androida.

Ustalone przyczyny (dla planu, nie normatywne):

- Blokada: znacznik „ostatnie przejście w tło” nie jest zerowany po udanym odblokowaniu. Okno uwierzytelniania systemu
  chwilowo dezaktywuje aplikację; po jego zamknięciu aplikacja ponownie sprawdza stary znacznik (sprzed ponad 5 minut)
  i blokuje się od nowa — w pętli.
- Zdjęcia: miniatura zdjęcia konia jest odczytywana tylko z plików w telefonie; dla zdjęć pochodzących z programu nikt
  jej nie pobiera (siatka załączników pobiera miniatury, ale lista koni, Pulpit i karta konia — nie).
- Raport: „Treningi jeźdźca” pokazuje tylko tabelę (wiersze, a sumy na końcu), bez kart podsumowania i bez wykresu.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Wejście do aplikacji po odblokowaniu (Priority: P1)

Użytkowniczka ma włączoną „Blokadę aplikacji”. Otwiera aplikację (albo wraca do niej po ponad 5 minutach), widzi ekran
„Aplikacja zablokowana”, odblokowuje Face ID albo kodem telefonu i normalnie korzysta z aplikacji — bez ponownej blokady.

**Why this priority**: Obecnie włączenie blokady odcina dostęp do wszystkich danych; jedyne wyjście to usunięcie
aplikacji (utrata danych w trybie samodzielnym). To błąd krytyczny.

**Independent Test**: Włączyć blokadę, zamknąć aplikację, otworzyć ponownie, odblokować kodem — aplikacja pozostaje
odblokowana; logika stanu blokady sprawdzana testem automatycznym na sekwencjach zmian stanu aplikacji.

**Acceptance Scenarios**:

1. **Given** blokada włączona i aplikacja uruchomiona od zera, **When** odblokowuję kodem telefonu, **Then** widzę
   Pulpit i aplikacja nie blokuje się ponownie, dopóki nie przejdzie w tło na ponad 5 minut albo nie zostanie zamknięta.
2. **Given** blokada włączona i aplikacja w tle ponad 5 minut, **When** wracam i odblokowuję Face ID, **Then** widzę
   ekran, na którym byłam, bez ponownej blokady.
3. **Given** aplikacja w tle krócej niż 5 minut, **When** wracam, **Then** nie widzę ekranu blokady (tylko zasłona
   w przełączniku aplikacji, jak dotąd).
4. **Given** ekran blokady, **When** anuluję okno uwierzytelniania albo się ono nie powiedzie, **Then** zostaje ekran
   „Aplikacja zablokowana” z przyciskiem „Odblokuj”, a okno uwierzytelniania nie otwiera się samo ponownie w kółko.
5. **Given** odblokowana aplikacja, **When** pojawi się systemowe okno (powiadomienie, Centrum sterowania, okno
   uwierzytelniania) i zniknie, **Then** aplikacja nie blokuje się.

---

### User Story 2 — Miniatury zdjęć koni z programu (Priority: P2)

Użytkowniczka łączy telefon z programem na komputerze. Konie, które mają zdjęcie w programie, pokazują jego miniaturę na
liście koni, na Pulpicie, w karcie konia i przy wyborze konia w nowym wpisie — tak jak w aplikacji na Androida.
Pełne zdjęcie otwiera się z karty konia („Pokaż zdjęcie”).

**Why this priority**: Brak zdjęć to wyraźna różnica względem Androida i programu, ale nie blokuje pracy.

**Independent Test**: Połączyć czysty telefon z programem, w którym koń ma zdjęcie — miniatura pojawia się bez
restartu aplikacji; po wyłączeniu sieci miniatura nadal jest widoczna.

**Acceptance Scenarios**:

1. **Given** program z koniem mającym zdjęcie i telefon świeżo połączony, **When** dane zostaną pobrane, **Then**
   miniatura konia pojawia się na liście koni, Pulpicie, karcie konia i w wyborze konia — bez ponownego uruchamiania.
2. **Given** miniatury pobrane, **When** telefon traci połączenie albo aplikacja zostaje uruchomiona bez sieci,
   **Then** miniatury są nadal widoczne (FR-ZDK-06).
3. **Given** pobranie miniatury się nie udało (brak sieci, program niedostępny), **When** przy kolejnym odświeżeniu
   program jest dostępny, **Then** miniatura zostaje pobrana; do tego czasu widać zwykły awatar bez komunikatu błędu.
4. **Given** zdjęcie konia zmienione w programie, **When** telefon pobierze zmiany, **Then** widać nową miniaturę.
5. **Given** koń ze zdjęciem z programu, **When** wybieram „Pokaż zdjęcie”, **Then** pełne zdjęcie zostaje pobrane
   i pokazane (jak otwarcie załącznika).
6. **Given** przejście z programu na tryb samodzielny („Pobieram dane i pliki z programu…”), **When** przejście się
   zakończy, **Then** zdjęcia koni są w telefonie i miniatury działają bez programu.

---

### User Story 3 — Czytelny raport „Treningi jeźdźca” (Priority: P3)

Użytkowniczka otwiera Raporty → „Treningi jeźdźca”, wybiera jeźdźca (albo „Wszyscy jeźdźcy”), konia i okres. Na górze
widzi podsumowanie i wykres, niżej sumy w podziale na konie albo jeźdźców, a listę pojedynczych treningów rozwija
dopiero, gdy jej potrzebuje.

**Why this priority**: Raport działa i ma poprawne liczby, ale jest nieczytelny — to jakość, nie utrata funkcji.

**Independent Test**: Otworzyć raport z danymi z kilku miesięcy — na pierwszym ekranie, bez przewijania, widać sumy
i wykres; eksport CSV/PDF daje te same wartości co dotąd.

**Acceptance Scenarios**:

1. **Given** raport z wynikami, **When** go otwieram, **Then** na górze widzę podsumowanie: liczba treningów, łączny
   czas („X h Y min”), średnia ocena (z ocenionych treningów), koszt.
2. **Given** raport z wynikami, **When** patrzę pod podsumowanie, **Then** widzę wykres słupkowy w podziale na konie
   (jeden jeździec) albo na jeźdźców („Wszyscy jeźdźcy”) z przełącznikiem „Liczba treningów / Łączny czas”, z opisem
   dla czytnika ekranu.
3. **Given** raport z wynikami, **When** przewijam niżej, **Then** widzę karty grup (koń albo jeździec) z liczbą,
   łącznym czasem, średnią oceną i kosztem.
4. **Given** raport z wynikami, **When** patrzę na koniec, **Then** lista pojedynczych treningów jest zwinięta pod
   „Pokaż treningi (N)”; po dotknięciu rozwija się z dotychczasowymi danymi wiersza.
5. **Given** raport, **When** eksportuję PDF, **Then** PDF zawiera podsumowanie, wykres z opisem tekstowym i pełną
   listę treningów; CSV ma te same wartości co w 2.0.1.
6. **Given** „Podsumowanie treningów” konia, **When** raport ma dane, **Then** sumy „Razem” są nad wierszami rodzajów
   treningu, a wykres postępu jest pokazany zawsze, gdy jest z czego go narysować.

---

### Edge Cases

- Blokada włączona, a użytkownik w międzyczasie usunął kod telefonu — jak dotąd: blokada wyłącza się z informacją.
- Zimny start z blokadą przy znaczniku tła sprzed wielu dni — jedno odblokowanie wystarcza.
- Aplikacja zablokowana przechodzi w tło i wraca — nadal zablokowana, jedno odblokowanie wystarcza.
- Wiele koni ze zdjęciami (np. 30) — miniatury pobierane bez blokowania listy; kolejność dowolna.
- Koń ma wskazane zdjęcie, którego nie ma już w programie (usunięte) — zwykły awatar, bez komunikatu i bez ponawiania
  przy każdym rysowaniu.
- Tryb samodzielny bez wcześniejszego połączenia — bez zmian (zdjęcia tylko lokalne).
- Raport z jednym treningiem lub jedną grupą — podsumowanie i wykres z jednym słupkiem; bez wyników — dotychczasowy
  stan pusty.
- Raport z bardzo wieloma grupami (np. 20 koni) — wykres czytelny (przewijany lub ograniczony do najważniejszych
  z pozycją „pozostałe”), dane w kartach grup kompletne.
- Treningi bez oceny — średnia ocena „—”; treningi bez czasu — czas „—” zgodnie z FR-M-RAP-04.

## Requirements *(mandatory)*

### Functional Requirements

**Blokada aplikacji (FR-TRB-09)**

- **FR-001**: Po udanym odblokowaniu aplikacja MUST pozostać odblokowana do najbliższego przejścia w tło dłuższego niż
  5 minut albo do zamknięcia aplikacji.
- **FR-002**: Chwilowe dezaktywowanie aplikacji bez przejścia w tło (okno uwierzytelniania, powiadomienie, Centrum
  sterowania, przełącznik aplikacji) MUST NOT powodować blokady.
- **FR-003**: Czas spędzony w tle MUST być liczony od ostatniego przejścia w tło po odblokowaniu; znacznik sprzed
  odblokowania MUST NOT mieć wpływu na kolejne sprawdzenia.
- **FR-004**: Anulowane lub nieudane uwierzytelnienie MUST zostawić ekran blokady z przyciskiem „Odblokuj”; okno
  uwierzytelniania otwiera się samo co najwyżej raz po pokazaniu ekranu blokady, kolejne próby — przyciskiem.
- **FR-005**: Reguły FR-001…FR-004 MUST być sprawdzane testem automatycznym uruchamianym w CI na sekwencjach: zimny
  start → odblokowanie → dezaktywacja → aktywacja; tło < 5 min; tło > 5 min; anulowanie; tło w stanie zablokowanym.

**Zdjęcia koni (FR-ZDK-04…06)**

- **FR-006**: W trybie z programem brakująca miniatura zdjęcia konia MUST być pobierana z programu i zapisywana trwale
  w telefonie (z ochroną przed czyszczeniem pamięci podręcznej), a widoki koni MUST ją pokazać bez ponownego
  uruchamiania aplikacji.
- **FR-007**: Miniatury wszystkich koni ze zdjęciem MUST być pobierane po pobraniu danych z programu (także po pierwszym
  połączeniu), nie dopiero przy otwarciu karty konia.
- **FR-008**: Nieudane pobranie miniatury MUST NOT pokazywać błędu ani blokować widoku; MUST być ponawiane przy
  kolejnym odświeżeniu danych.
- **FR-009**: „Pokaż zdjęcie” MUST pobrać pełne zdjęcie z programu, gdy nie ma go w telefonie.
- **FR-010**: Zmiana zdjęcia konia w programie MUST skutkować pokazaniem nowej miniatury po pobraniu zmian.
- **FR-011**: Przejście z programu na tryb samodzielny MUST zostawić w telefonie zdjęcia koni (miniatury i oryginały),
  tak by działały bez programu.

**Raport „Treningi jeźdźca” (scenariusz 5 historii „Raporty”, FR-M-RAP-03/04)**

- **FR-012**: Raport MUST pokazywać w kolejności: podsumowanie → wykres → karty grup → lista treningów.
- **FR-012a**: We wszystkich raportach (Koszty, Bilans konia, Podsumowanie treningów, Treningi jeźdźca, Zawody jeźdźca)
  karta sum MUST być nad wykresami i wierszami — zgodnie z tabelą ekranów specyfikacji głównej („filtry → sumy →
  wykresy → wiersze”) i z aplikacją na Androida 2.0.1; wartości sum bez zmian.
- **FR-013**: Podsumowanie MUST zawierać liczbę treningów, łączny czas, średnią ocenę z ocenionych treningów i koszt —
  wartości te same co w dotychczasowym wierszu „Razem”.
- **FR-014**: Wykres MUST być słupkowy w podziale na grupy raportu (konie przy jednym jeźdźcu, jeźdźcy przy „Wszyscy
  jeźdźcy”), z przełącznikiem wartości „Liczba treningów” / „Łączny czas”, czytelny w obu motywach, z opisem dla czytnika
  ekranu i nie tylko kolorem; wartości wykresu MUST pochodzić z danych raportu bez zmiany.
- **FR-015**: Lista pojedynczych treningów MUST być domyślnie zwinięta pod „Pokaż treningi (N)” i rozwijana dotknięciem;
  stan rozwinięcia nie musi być pamiętany między wejściami.
- **FR-016**: Eksport PDF MUST zawierać wykres z opisem tekstowym (jak w pozostałych raportach) i pełną listę treningów;
  wartości CSV i PDF MUST być identyczne z 2.0.1 (istniejące testy zgodności z wzorcami muszą przejść bez zmiany wzorców
  danych).
- **FR-017**: „Podsumowanie treningów” konia MUST pokazywać sumy „Razem” nad wierszami rodzajów treningu, a wykres
  postępu zawsze, gdy dane zawierają przynajmniej jedną wartość wybranego parametru.

**Zgodność i wydanie**

- **FR-018**: Nowe teksty (np. „Pokaż treningi (%d)”, „Liczba treningów”, tytuł i opis wykresu) MUST być dodane do
  `strings.xml` aplikacji na Androida i przeniesione do iOS skryptem; test zgodności tekstów MUST przejść.
- **FR-019**: Zmiana zakresu (FR-014, FR-015) MUST być opisana w SPECYFIKACJA_MOBILE_IOS.md i
  SPECYFIKACJA_MOBILE_ANDROID.md, a odpowiednik w aplikacji na Androida MUST być zaplanowany jako osobne zadanie
  w jej repozytorium.
- **FR-020**: Poprawka MUST być wydana jako wersja 2.0.2 (kolejny numer kompilacji po 23) do TestFlight, grupa
  „Właściciele”, przez tag `v2.0.2` w CI.

### Key Entities

- **Stan blokady**: zablokowana / odblokowana, moment ostatniego przejścia w tło po odblokowaniu, trwające
  uwierzytelnienie, ustawienie „Blokada aplikacji”.
- **Zdjęcie konia**: wskazanie załącznika konia jako zdjęcia; w telefonie miniatura (trwała) i oryginał (na żądanie,
  trwały w trybie samodzielnym).
- **Raport „Treningi jeźdźca”**: suma (liczba, czas, średnia ocena, koszt), grupy (koń albo jeździec z tymi samymi
  sumami), wiersze treningów — bez zmian w danych, zmiana tylko w prezentacji.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 10 kolejnych odblokowań (5 kodem, 5 Face ID, w tym po zimnym starcie i po > 5 min w tle) kończy się
  wejściem do aplikacji bez ponownej blokady — 10/10.
- **SC-002**: Po świeżym połączeniu z programem dostępnym w sieci miniatury wszystkich koni ze zdjęciem są widoczne
  w ciągu 10 sekund od zakończenia pobierania danych — bez restartu aplikacji.
- **SC-003**: Po pobraniu miniatur 100% z nich jest widocznych w trybie samolotowym.
- **SC-004**: Na iPhonie 15 Pro (standardowy rozmiar tekstu) raport „Treningi jeźdźca” pokazuje podsumowanie i wykres
  na pierwszym ekranie bez przewijania.
- **SC-005**: Wartości eksportu CSV/PDF raportów treningów są identyczne z wersją 2.0.1 (testy zgodności zielone).
- **SC-006**: Testerka (właścicielka iPhone'a) potwierdza w TestFlight, że trzy zgłoszone problemy nie występują.

## Assumptions

- „Import danych z serwera” oznacza pobranie danych z programu na komputerze po połączeniu telefonu (tryb z programem)
  oraz przejście z programu na tryb samodzielny; import z pliku kopii zapasowej już przenosi zdjęcia i nie jest objęty.
- Raport opisany jako „raport treningów” to „Treningi jeźdźca” (lista wszystkich treningów z sumą na końcu);
  „Podsumowanie treningów” konia dostaje tylko przesunięcie sum na górę i warunek pokazywania wykresu.
- Wykres w „Treningach jeźdźca” pokazuje podział na grupy; wykres w czasie (tygodnie/miesiące) jest poza zakresem tej
  poprawki — można go dodać później w obu aplikacjach.
- Przy bardzo wielu grupach wykres może pokazać najliczniejsze grupy i pozycję „pozostałe” — szczegół do planu.
- Program na komputerze udostępnia miniatury i oryginały załączników tak samo jak dla aplikacji na Androida (bez zmian
  po stronie programu).
- Zasłona w przełączniku aplikacji i 5-minutowy próg blokady pozostają bez zmian.
- Kompilacja, testy i wysyłka wyłącznie w GitHub Actions (brak Maca); weryfikacja ręczna na iPhonie testerki.
