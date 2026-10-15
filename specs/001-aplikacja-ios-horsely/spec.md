# Feature Specification: Horsely na iOS — pełny zakres aplikacji na Androida 2.0.1

**Feature Branch**: `001-aplikacja-ios-horsely`

**Created**: 2026-10-15

**Status**: Draft

**Input**: User description: "@SPECYFIKACJA_MOBILE_IOS.md — aplikacja Horsely na iOS (iPhone, iOS 18+), pełny zakres aplikacji na Androida 2.0.1 zgodnie z tym dokumentem (wersja 1.5)."

## Kontekst

Źródłem wymagań jest [SPECYFIKACJA_MOBILE_IOS.md](../../SPECYFIKACJA_MOBILE_IOS.md) w wersji 1.5 (dalej: **specyfikacja główna**).
Ta specyfikacja funkcji porządkuje jej treść w przyrosty do realizacji i nie powtarza szczegółów: każde wymaganie poniżej
odsyła do identyfikatorów specyfikacji głównej (FR-M-*, FR-TRB-*, FR-SYN2-*, FR-SAM-*, FR-KOP-*, FR-KOL-*, FR-ZDK-*,
FR-001…FR-033, NFR-M-*, SC-*), które są **normatywne** — ich treść, teksty komunikatów i wartości obowiązują w całości.

Aplikacja ma być **tą samą aplikacją co Horsely na Androida 2.0.1** (repozytorium `zarzadzanie_konmi_android`): te same
funkcje, ekrany, teksty, kolory, ikony i zachowanie; różnice wynikają wyłącznie z mechanizmów iOS (sekcja 9 specyfikacji
głównej). Projekt iOS nie ma wydań 1.x — pierwsze wydanie ma numer 2.0.1.

Ustalenia z sesji wyjaśniającej 2026-10-15 (specyfikacja główna, wersja dokumentu 1.5): dystrybucja wyłącznie przez
TestFlight dla testerów wewnętrznych; urządzenie docelowe iPhone 15 Pro (telefon córki właściciela, jej Apple ID jest
testerem); poprawne działanie na każdym iPhonie z iOS 18+, bez iPada; natywne komponenty iOS z ikonami Material jak na
Androidzie; plik kopii zapasowej wymienny z Androidem; szybkie akcje ikony, udostępnianie do aplikacji i import kontaktu
obowiązkowe; budowanie bez Maca.

## Clarifications

### Session 2026-10-15

- Q: Sposób dystrybucji? → A: Tylko TestFlight, testerzy wewnętrzni (bez App Store).
- Q: Zakres urządzeń? → A: iPhone 15 Pro docelowo; poprawnie na każdym iPhonie z iOS 18+; iPad poza zakresem.
- Q: Styl interfejsu? → A: Natywne komponenty iOS, a kolory, teksty, kolejność elementów i ikony jak na Androidzie.
- Q: Ikony? → A: Te same ikony Material (Outlined) co na Androidzie; ikony systemowe iOS tylko dla elementów systemowych.
- Q: Kopia zapasowa wymienna z Androidem? → A: Tak, obowiązkowo (FR-KOP-09).
- Q: Ograniczenia pracy w tle na iOS? → A: Akceptowane — „w miarę możliwości systemu”, z nadrabianiem przy otwarciu.
- Q: Numer pierwszej wersji? → A: 2.0.1.
- Q: Szybkie akcje, udostępnianie, import kontaktu? → A: Wszystkie obowiązkowe.
- Q: Kto używa iPhone'a 15 Pro? → A: Córka właściciela, własnym Apple ID — ono jest testerem wewnętrznym.

## User Scenarios & Testing *(mandatory)*

Historie są przyrostami realizacji. Każda opiera się na scenariuszach akceptacyjnych specyfikacji głównej (odwołania
w nawiasach), które obowiązują w całości; poniżej tylko scenariusze kluczowe dla przyrostu. Kolejność: najpierw tryb
samodzielny (działa bez komputera i bez sieci, więc daje używalną aplikację najszybciej), potem tryb online.

### User Story 1 - Pierwsze uruchomienie i konie w trybie samodzielnym (Priority: P1)

Nowy użytkownik otwiera aplikację, wybiera „Nie, używaj samodzielnie”, dodaje konie (także źrebaka bez paszportu),
przegląda listę koni i kartę konia, ustawia zdjęcie konia z aparatu lub telefonu z kadrowaniem i zmienia status konia
(także „Kontuzjowany”). Wszystko działa bez sieci.

**Why this priority**: bez wyboru trybu i koni żadna inna funkcja nie ma sensu; tryb samodzielny nie wymaga komputera,
więc jest najszybszą drogą do używalnej aplikacji na telefonie córki.

**Independent Test**: świeża instalacja w trybie samolotowym → „Nie, używaj samodzielnie” → „Dalej” → pusty Pulpit
„Dodaj pierwszego konia” → dodać 2 konie i źrebaka bez paszportu → ustawić zdjęcie z kadrowaniem → zmienić status na
„Kontuzjowany” → lista, karta konia i kafle Pulpitu wyglądają jak na Androidzie 2.0.1 dla tych samych danych.

**Acceptance Scenarios** (specyfikacja główna: US2.0-1, US2.0-7, US6/1–2, US6/6, US2.0.1-2, FR-M-KON-*, FR-ZDK-*, FR-005…FR-010):

1. **Given** pierwsze uruchomienie, **When** aplikacja się otwiera, **Then** widzę ekran wyboru trybu z tytułem
   „Horsely – Zarządzanie Koniem, Trening i Budżet”, domyślnie zaznaczonym „Tak, połącz z programem” i „Zmienisz to
   w Ustawieniach → Tryb pracy”.
2. **Given** wybrany tryb samodzielny, **When** dodaję konia bez numeru paszportu i bez „Źrebak”, **Then** widzę przy polu
   komunikat programu, a koń nie jest zapisany.
3. **Given** karta konia, **When** ustawiam zdjęcie, **Then** przechodzę przez kwadratowe kadrowanie, a miniatura pojawia się
   na karcie, liście i kaflu Pulpitu; poprzednie zdjęcie zostaje w załącznikach.
4. **Given** koń kontuzjowany, **When** oglądam Pulpit i listę koni, **Then** widzę pomarańczową ikonę plastra (kafel) i
   plakietkę „Kontuzjowany” (wiersz), a VoiceOver czyta „<imię>, kontuzjowany”.
5. **Given** ponowne uruchomienie, **When** aplikacja się otwiera, **Then** od razu widzę Pulpit (tryb zapamiętany).

---

### User Story 2 - Wpisy, treningi, terminy i Pulpit z regułami programu (Priority: P1)

Właściciel zapisuje w telefonie wizyty (weterynarz z lekami, kowal także dla kilku koni, fizjoterapia, specjalista),
notatki, zakupy (z podziałem na konie), zawody i starty, treningi (z podpowiedzią trenera, jeźdźca i kosztu) oraz
terminy; Pulpit pokazuje przeterminowane i nadchodzące terminy, koszty miesiąca, ostatnie wpisy i kafle koni. Telefon sam
stosuje reguły programu: terminy z daty następnej wizyty, zamykanie terminów, podział kosztów, cena sprzedaży przy „Padł”.

**Why this priority**: to codzienna praca w stajni — sens aplikacji; reguły programu muszą działać, zanim dołączy tryb online.

**Independent Test**: tryb samodzielny bez sieci → wizyta kowala z datą następnej wizyty, zakup paszy dla 2 koni za
100,01 zł, trening koniowi kontuzjowanemu (z potwierdzeniem) → na Pulpicie termin kowala, w kosztach 50,01 zł i 50,00 zł
(różnica u pierwszego konia wg imienia), oś czasu i treningi konia jak w programie dla tych samych danych.

**Acceptance Scenarios** (US2, US3, US10, US2.0-2, FR-M-PUL-*, FR-M-TER-*, FR-M-WPI-*, FR-M-TRN-*, FR-SAM-01/02/06, FR-011):

1. **Given** formularz dowolnego rodzaju wpisu, **When** go otwieram, **Then** data = dziś, sekcje Podstawowe · Szczegóły ·
   Koszty · Następna wizyta · Uwagi, pola wymagane z „*”, „Zapisz” w pasku nawigacji i u dołu ekranu.
2. **Given** zapis z błędem walidacji, **When** zapisuję, **Then** widzę ten sam komunikat co w programie przy właściwym polu,
   a wpisane dane zostają.
3. **Given** nowy trening konia z wcześniejszymi treningami, **When** otwieram formularz, **Then** trener, jeździec i koszt są
   podpowiedziane z ostatniego treningu.
4. **Given** termin na Pulpicie, **When** wybieram „Zarejestruj wizytę”, „Zrealizowany”, „Odrzuć” albo „Przełóż”, **Then**
   termin zmienia się jak w programie (mapowanie rodzaju terminu na formularz z FR-M-TER-03).
5. **Given** zapis, **When** się powiedzie, **Then** widzę „Zapisano” z „Cofnij”.

---

### User Story 3 - Połączenie z programem i pełna praca offline w trybie online (Priority: P1)

Właściciel z programem Horsely na komputerze paruje telefon kodem QR (albo ręcznie), aplikacja pobiera wszystkie dane
programu i pozwala bez połączenia dodawać, poprawiać i usuwać; zmiany wychodzą przez kolejkę bez duplikatów, a konflikty
rozstrzyga użytkownik. Stan połączenia jest stabilny (komunikat zwijany do ikonki), a z programem 2.0.0 aplikacja korzysta
z jego możliwości (zmiany przyrostowe, `If-Match`, `Idempotency-Key`, zdjęcie konia, status „Kontuzjowany”).

**Why this priority**: tryb online jest głównym trybem dla właściciela z programem na komputerze; bez niego aplikacja nie
współpracuje z ewidencją stajni.

**Independent Test**: program 2.0.0 z API → skan kodu QR → dane jak w programie; tryb samolotowy → edycja wizyty, usunięcie
treningu, „Przełóż” termin, nowy koń; w programie zmiana tej samej wizyty → powrót sieci → wszystko w programie, dla wizyty
konflikt do rozstrzygnięcia, kolejka pusta po decyzji; ten sam scenariusz z programem 1.6.1 działa bez nowych nagłówków.

**Acceptance Scenarios** (US1, US5, US2.0-3, US2.0.1-4, FR-M-POL-*, FR-M-SYN-*, FR-SYN2-*, FR-014…FR-020):

1. **Given** kod QR z odciskiem certyfikatu, **When** program przedstawia inny certyfikat, **Then** aplikacja odmawia
   połączenia i nie wysyła klucza.
2. **Given** program starszy niż 1.5.0, **When** paruję, **Then** widzę prośbę o aktualizację programu, a parowanie się nie kończy.
3. **Given** brak połączenia, **When** edytuję, usuwam, przekładam termin albo dodaję konia, **Then** zmiana jest od razu
   widoczna z oznaczeniem „czeka na wysłanie”, a po powrocie sieci trafia do programu w stanie końcowym, bez duplikatów.
4. **Given** konflikt, **When** otwieram „Konflikty”, **Then** porównuję „Moja” / „Z programu” i wybieram „Zachowaj moją” albo
   „Przyjmij z programu”, także zbiorczo z potwierdzeniem i liczbą.
5. **Given** odpowiedź `401`/`403`/`429`, **When** aplikacja ją dostaje, **Then** wstrzymuje żądania do tego adresu według
   FR-M-POL-11…13 i nigdy sama nie doprowadza do zablokowania adresu telefonu.

---

### User Story 4 - Działy Treningi, Zakupy, Zawody i kontakty (Priority: P2)

Właściciel przegląda treningi wszystkich koni, zakupy (z „Powtórz zakup”) i zawody ze startami, z filtrami domyślnie na
bieżący rok i stopką z liczbą i sumą; zarządza kontaktami (trenerzy, jeźdźcy, weterynarze), dzwoni, pisze SMS i e‑mail,
nawiguje do adresu i dodaje kontakt z książki adresowej telefonu.

**Why this priority**: działy z programu porządkują dane stajni; ważne, ale wpisy da się robić bez nich.

**Independent Test**: dane testowe z treningami 2 koni, zakupem ogólnym i zawodami z 2 startami → każdy dział pokazuje te same
rekordy, liczby i sumy co program/Android dla tych samych filtrów; kontakt-trener użyty w treningu nie daje się usunąć.

**Acceptance Scenarios** (US8, US11, FR-M-KTK-*, SC-M-11):

1. **Given** dowolny dział, **When** go otwieram, **Then** okres filtra to 1 stycznia – 31 grudnia bieżącego roku, a „Wyczyść
   filtry” do niego wraca.
2. **Given** zakup, **When** wybieram „Powtórz zakup”, **Then** otwiera się nowy zakup z danymi tamtego i dzisiejszą datą.
3. **Given** dodawanie kontaktu, **When** wybieram import z książki adresowej, **Then** wybieram kontakt systemowym oknem bez
   proszenia o zgodę na dostęp do kontaktów.

---

### User Story 5 - Raporty z wykresami i eksportem CSV/PDF (Priority: P2)

Właściciel korzysta z pięciu raportów programu (Koszty, Bilans konia, Podsumowanie treningów, Treningi jeźdźca, Zawody
jeźdźca) z filtrami, wykresami i eksportem CSV/PDF przez „Udostępnij” albo „Zapisz w plikach”.

**Why this priority**: raporty dają wartość finansową i treningową, ale nie blokują codziennej pracy.

**Independent Test**: zestaw testowy programu → każdy raport ma te same wartości co program co do grosza i minuty; plik CSV
jest bajt w bajt zgodny z CSV programu; wiersz „Uwagi” w Bilansie konia nie łamie się po literze przy tekście 200 %.

**Acceptance Scenarios** (US9, FR-M-RAP-*, FR-SAM-03, FR-027/028, SC-M-09):

1. **Given** raport z danymi, **When** eksportuję CSV, **Then** plik ma UTF‑8 z BOM, separator `;`, przecinek dziesiętny i te
   same kolumny co program.
2. **Given** brak danych, **When** otwieram raport, **Then** widzę informację o braku danych, zerowe sumy i nieaktywny eksport.
3. **Given** tryb online bez połączenia, **When** otwieram raport, **Then** jest wyliczony z danych w telefonie z oznaczeniem
   „z pamięci”.

---

### User Story 6 - Zdjęcia, dokumenty i udostępnianie do aplikacji (Priority: P2)

Właściciel dołącza do wpisów i koni zdjęcia z aparatu, galerii i pliki (PDF, dokumenty), ogląda je i udostępnia; z innych
aplikacji (zdjęcia, poczta) wybiera „Udostępnij → Horsely” i dołącza plik do konia lub wpisu.

**Why this priority**: dokumentacja (faktury, rany, paszport) jest ważna, ale wtórna wobec wpisów.

**Independent Test**: dodać 2 zdjęcia z aparatu do wizyty weterynaryjnej (bez sieci w trybie online) → po powrocie sieci są
w programie; udostępnić PDF z aplikacji Pliki do konia → widoczny w zakładce „Załączniki”.

**Acceptance Scenarios** (US4, FR-M-ZAL-*):

1. **Given** zdjęcie większe niż limit, **When** je dodaję, **Then** jest zmniejszane i pozbawione lokalizacji (chyba że
   ustawienia mówią inaczej).
2. **Given** plik powyżej 100 MB albo niedozwolonego typu, **When** go wybieram, **Then** widzę komunikat i plik nie jest dodany.

---

### User Story 7 - Powiadomienia o terminach (Priority: P2)

Telefon sam przypomina o przeterminowanych i dzisiejszych terminach — codzienne podsumowanie o wybranej godzinie i opcjonalne
powiadomienie w dniu terminu — także gdy komputer jest wyłączony.

**Why this priority**: przypomnienie o kowalu i szczepieniu to jedna z głównych korzyści, ale wymaga najpierw terminów.

**Independent Test**: termin na jutro → następnego dnia o 08:00 (± 15 min) jedno powiadomienie „X przeterminowanych, Y na dziś
i jutro”, bez połączenia; dotknięcie otwiera Pulpit.

**Acceptance Scenarios** (US7, FR-M-POW-*):

1. **Given** brak terminów do zgłoszenia, **When** nadchodzi godzina podsumowania, **Then** powiadomienie się nie pojawia.
2. **Given** termin zrealizowany, **When** dane się odświeżą, **Then** powiadomienia o nim znikają.

---

### User Story 8 - Kosz, słowniki, kopia zapasowa i zmiana trybu (Priority: P2)

Użytkownik trybu samodzielnego przywraca usunięte dane z kosza, dopasowuje słowniki, robi kopię zapasową do pliku (z hasłem
lub bez, także automatycznie co tydzień) i odtwarza ją — również z kopii zrobionej na Androidzie; w Ustawieniach zmienia tryb
pracy z bezpiecznymi ostrzeżeniami.

**Why this priority**: zabezpiecza dane trybu samodzielnego i umożliwia przejście między telefonami i trybami.

**Independent Test**: kopia z hasłem na Androidzie 2.0.1 → odtworzenie na iPhonie → te same dane i załączniki; kopia z iPhone'a
odtwarza się na Androidzie; zmiana trybu samodzielny → online nie usuwa danych przed udanym parowaniem.

**Acceptance Scenarios** (US2.0-2/5, US2.0-4, US2.0.1-1, FR-SAM-04/05, FR-KOP-*, FR-TRB-05…07, FR-001…FR-004):

1. **Given** plik kopii z błędnym hasłem albo uszkodzony, **When** go odtwarzam, **Then** widzę „Nieprawidłowe hasło” albo
   „Plik uszkodzony lub niekompletny”, a obecne dane są bez zmian.
2. **Given** kopia ze słownikami sprzed 2.0.1 (7 rodzajów treningów), **When** ją odtwarzam, **Then** brakujące 3 rodzaje są
   dopisane bez zmiany istniejących.
3. **Given** brak kopii od 7 dni przy zmianach danych, **When** otwieram Pulpit, **Then** widzę „Zadbaj o kopię zapasową”.

---

### User Story 9 - Ustawienia, blokada, dziennik diagnostyczny i skróty (Priority: P3)

Użytkownik ustawia powiadomienia, dane, wygląd (systemowy / jasny / ciemny), blokadę aplikacji Face ID lub kodem urządzenia,
zarządza adresami komputera, przegląda i czyści dziennik diagnostyczny (ze szczegółowym dziennikiem połączeń na 7 dni),
a z ikony aplikacji otwiera „Dodaj notatkę”, „Kowal” i „Terminy”.

**Why this priority**: uzupełnia aplikację i ułatwia diagnozę, ale nie jest potrzebne do podstawowej pracy.

**Independent Test**: włączyć blokadę → po 5 min w tle aplikacja wymaga Face ID, a przełącznik aplikacji nie pokazuje danych;
włączyć szczegółowy dziennik → po odświeżeniu widać adres, IP, sieć i wynik każdego żądania, bez klucza i danych osobowych.

**Acceptance Scenarios** (FR-M-UST-*, FR-TRB-09, FR-029…FR-033, FR-M-UI-06):

1. **Given** telefon bez kodu urządzenia, **When** otwieram „Blokada aplikacji”, **Then** przełącznik jest nieaktywny z wyjaśnieniem.
2. **Given** dziennik, **When** wybieram „Wyczyść” i potwierdzam, **Then** widzę „Dziennik jest pusty.”.

---

### Edge Cases

Obowiązują przypadki brzegowe specyfikacji głównej (US1–US12 i sekcje 3.1–3.2, „Przypadki brzegowe 2.0”, edge cases 2.0.1).
Najważniejsze dla iOS:

- iOS nie uruchamia pracy w tle: odświeżenie, wysyłka kolejki i kopia automatyczna nadrabiane przy otwarciu aplikacji, bez utraty danych.
- System zamyka aplikację w trakcie zapisu, wysyłki lub odtwarzania kopii: brak danych częściowych, brak duplikatów.
- Odmowa zgody „Sieć lokalna”, aparatu albo powiadomień: aplikacja działa dalej i pokazuje, jak włączyć zgodę.
- Limit 64 zaplanowanych powiadomień iOS: planowane najbliższe (≤ 60), uzupełniane przy odświeżeniu.
- Kopia zapasowa z nowszej wersji formatu: komunikat „Kopia z nowszej wersji aplikacji”, dane bez zmian.
- Kompilacja TestFlight wygasła (90 dni): aplikacji nie da się otworzyć do czasu instalacji nowej kompilacji, dane w telefonie zostają.
- Mały ekran (320 pt szerokości) i tekst 200 %: żadne etykiety ani wartości nie są obcinane ani łamane po literze.
- Program cofnięty z 2.0.0 do 1.6.1: aplikacja przestaje używać nowych możliwości bez ponownego parowania.

## Requirements *(mandatory)*

### Functional Requirements

Każde wymaganie obejmuje w całości wskazane wymagania specyfikacji głównej.

**Zakres i zgodność z Androidem**

- **FR-001**: Aplikacja MUST realizować wszystkie wymagania funkcjonalne specyfikacji głównej (sekcje 4.1–4.13) w obu trybach
  pracy, z identyfikatorami i treścią jak w specyfikacji głównej.
- **FR-002**: Aplikacja MUST mieć te same funkcje, ekrany, kolejność elementów, teksty, kolory i ikony co Horsely na Androida
  2.0.1 (FR-M-UI-07, wzorzec wyglądu 5.4); teksty interfejsu MUST pochodzić z zasobów tekstowych aplikacji na Androida,
  a ich zgodność MUST być sprawdzana automatycznie.
- **FR-003**: Interfejs MUST być po polsku (daty `30.09.2026`, kwoty `1 250,00 zł`, tydzień od poniedziałku) i spełniać
  wymagania dostępności NFR-M-07 (czytnik ekranu, tekst 200 %, kontrast WCAG 2.1 AA, cele dotyku ≥ 44 pt).
- **FR-004**: Nazwa pod ikoną MUST brzmieć „Horsely”, a pełna nazwa „Horsely – Zarządzanie Koniem, Trening i Budżet” MUST być
  na ekranie powitalnym i w „O aplikacji” (FR-021/022); wersja aplikacji 2.0.1 (FR-025).

**Tryby pracy (US1, US8)**

- **FR-005**: Wybór i zmiana trybu pracy MUST działać według FR-TRB-01…09 (bez FR-TRB-04, który na iOS nie dotyczy).
- **FR-006**: W trybie samodzielnym aplikacja MUST NOT nawiązywać żadnych połączeń sieciowych ani pokazywać elementów połączenia (FR-TRB-08).

**Konie (US1)**

- **FR-007**: Lista, karta, dodawanie i edycja konia, zdjęcie konia i status „Kontuzjowany” MUST działać według FR-M-KON-01…04,
  FR-ZDK-01…06 i FR-005…FR-010.

**Wpisy, treningi, terminy, Pulpit (US2)**

- **FR-008**: Formularze i podpowiedzi wpisów, treningów i terminów MUST działać według FR-M-WPI-01…07, FR-M-TRN-01…04,
  FR-M-TER-01…03 i 5.3; Pulpit — według FR-M-PUL-01/02 i układu z 5.4.
- **FR-009**: W trybie samodzielnym (i bez połączenia w trybie online) reguły programu MUST dawać wyniki identyczne z programem
  (FR-SAM-02, FR-SYN2-08), sprawdzane tymi samymi plikami wzorcowymi programu co w aplikacji na Androida.
- **FR-010**: Zapis koniowi kontuzjowanemu treningu MUST wymagać potwierdzenia (FR-011 specyfikacji głównej).

**Tryb online (US3)**

- **FR-011**: Parowanie, adresy, zaufanie certyfikatów i obsługa błędów połączenia MUST działać według FR-M-POL-01…17.
- **FR-012**: Magazyn lokalny, pełne pobranie, kolejka, łączenie zmian, konflikty i historia kolejki MUST działać według
  FR-M-SYN-01…13 i FR-SYN2-01…10.
- **FR-013**: Możliwości programu 2.0.0 MUST być wykrywane i używane według FR-014…FR-020; z programem 1.5.0–1.6.x aplikacja
  MUST NOT wysyłać związanych z nimi parametrów ani nagłówków.

**Działy i kontakty (US4)**

- **FR-014**: Działy Treningi, Zakupy i Zawody MUST działać według US11; kontakty — według FR-M-KTK-01…03, z importem z książki
  adresowej bez zgody na dostęp do kontaktów.

**Raporty (US5)**

- **FR-015**: Pięć raportów z wykresami i eksportem MUST działać według FR-M-RAP-01…07, FR-SAM-03 i FR-027/028; CSV MUST być
  bajt w bajt zgodny z CSV programu.

**Załączniki (US6)**

- **FR-016**: Załączniki MUST działać według FR-M-ZAL-01…06; udostępnianie z innych aplikacji do Horsely MUST działać także
  wtedy, gdy aplikacja jest zamknięta (plik trafia do kolejki albo magazynu, zgodnie z trybem).

**Powiadomienia (US7)**

- **FR-017**: Powiadomienia MUST działać według FR-M-POW-01…04, planowane lokalnie z wyprzedzeniem, w limicie systemu (≤ 60).

**Kosz, słowniki, kopia (US8)**

- **FR-018**: Kosz i słowniki MUST działać według FR-SAM-04/05 i FR-001…FR-004 specyfikacji głównej.
- **FR-019**: Kopia zapasowa MUST działać według FR-KOP-01…09; plik MUST być wymienny z aplikacją na Androida 2.0.1
  w obie strony (z hasłem i bez).

**Ustawienia, blokada, diagnostyka, skróty (US9)**

- **FR-020**: Ustawienia MUST mieć pozycje i kolejność z FR-M-UST-00 i działać według FR-M-UST-01…09.
- **FR-021**: Blokada aplikacji MUST działać według FR-TRB-09 (zabezpieczenie telefonu, 5 min w tle, ukryta treść w przełączniku aplikacji).
- **FR-022**: Dziennik diagnostyczny i szczegółowy dziennik połączeń MUST działać według FR-029…FR-033.
- **FR-023**: Szybkie akcje ikony aplikacji „Dodaj notatkę”, „Kowal”, „Terminy” MUST otwierać odpowiednie ekrany (FR-M-UI-06).

**Prywatność i bezpieczeństwo**

- **FR-024**: Klucz API, dane i logi MUST być chronione według NFR-M-04…06, 9.2 i 9.3 specyfikacji głównej (bez lokalizacji,
  bez dostępu do kontaktów i pełnej biblioteki zdjęć, dane poza kopią w chmurze, brak telemetrii).

**Dostarczanie**

- **FR-025**: Każde wydanie MUST trafiać do testerów wewnętrznych przez TestFlight według 9.6 i 9.8 (wydanie z tagu wersji po
  zielonych testach, nowa kompilacja co najmniej raz na 80 dni, jawna informacja o braku danych do podpisu); wersja jest
  wydana po ręcznej liście kontrolnej na iPhone 15 Pro.
- **FR-026**: Wygląd MUST być sprawdzany automatycznie zrzutami kluczowych ekranów (motyw jasny i ciemny, tekst 200 %)
  porównywanymi z wzorcami (SC-M-12).

### Key Entities *(include if feature involves data)*

Model danych odwzorowuje program (schemat eksportu 1.5) — jak w specyfikacji głównej, sekcje 2 i 6.4:

- **Koń**: dane paszportowe, status (Aktywny, Kontuzjowany, Sprzedany, Padł, Wydzierżawiony), imię stajenne, kwoty konia, zdjęcie.
- **Wpis**: wizyta weterynaryjna (z lekami), kowalska, fizjoterapii, specjalisty, notatka, zakup (z przypisaniem do koni),
  start w zawodach; każdy z wersją rekordu.
- **Trening**: koń, dzień, rodzaj, czas, intensywność, ocena, trener, jeździec, koszt, wysokość przeszkód.
- **Zawody**: dane zawodów i ich starty.
- **Termin**: koń, rodzaj, data, tytuł, status (Otwarty / Zrealizowany / Odrzucony).
- **Kontakt**: typy (m.in. Trener, Jeździec), dane teleadresowe, archiwizacja.
- **Załącznik**: plik przypisany do konia lub wpisu, miniatura.
- **Słownik**: wartości (aktywne/ukryte, systemowe), np. rodzaje treningów.
- **Operacja kolejki**: zmiana czekająca na wysłanie (tryb online) ze stałym identyfikatorem i wersją bazową.
- **Konflikt**: para wersji rekordu z rodzajem i rozstrzygnięciem.
- **Element kosza**: partia usuniętych rekordów (tryb samodzielny).
- **Kopia zapasowa**: plik z danymi, koszem, słownikami i załącznikami, format wspólny z Androidem.
- **Połączenie**: adresy komputera z trybem zaufania, możliwości programu, stan pobierania.
- **Wpis dziennika diagnostycznego**: zdarzenie bez danych osobowych.

## Success Criteria *(mandatory)*

### Measurable Outcomes

Obowiązują kryteria sukcesu specyfikacji głównej (SC-M-01…13, SC-2-01…11, SC-001…010 wersji 2.0.1), mierzone na iPhone 15 Pro.
Kluczowe:

- **SC-001**: Nowy użytkownik w trybie samodzielnym dodaje pierwszego konia w < 1 min od pierwszego otwarcia, bez sieci (SC-2-01).
- **SC-002**: Notatkę ze zdjęciem z aparatu da się dodać w < 30 s, a trening z podpowiedzianym trenerem, jeźdźcem i kosztem
  w < 30 s (SC-M-02).
- **SC-003**: Dla zestawu testowego 100 % zgodności z programem: terminy automatyczne, podział kosztów, sumy pięciu raportów co do
  grosza i minuty, CSV bajt w bajt (SC-2-03, SC-M-09).
- **SC-004**: Scenariusz offline w trybie online (10 nowych, 20 edycji, 5 usunięć, 3 „Przełóż”, 1 nowy koń, 5 konfliktów,
  przerwanie wysyłania, ponowne uruchomienie telefonu) kończy się 0 utraconych zmian i 0 duplikatów (SC-2-04).
- **SC-005**: Pulpit otwiera się w < 2 s z danych w telefonie, a każdy raport dla 2 000 treningów albo 50 koni w < 3 s (SC-2-06).
- **SC-006**: Każdy ekran z listy wzorca wyglądu pokazuje na tych samych danych te same elementy, teksty, kolory i ikony co
  Android 2.0.1, w motywie jasnym i ciemnym (SC-M-12).
- **SC-007**: Kopia zapasowa z Androida odtwarza się na iPhonie i odwrotnie ze 100 % rekordów i zgodnymi sumami kontrolnymi
  załączników (SC-M-13).
- **SC-008**: W trybie samodzielnym 0 połączeń sieciowych podczas 30 min pracy obejmującej wszystkie funkcje (SC-2-02).
- **SC-009**: Wszystkie ekrany przechodzą przegląd dostępności (VoiceOver, tekst 200 %, kontrast) bez błędów krytycznych (SC-M-07).
- **SC-010**: Córka instaluje każdą wydaną wersję z TestFlight na iPhonie 15 Pro bez pomocy technicznej, a dane w telefonie
  przetrwają aktualizację w 100 %.

## Assumptions

- Normatywne szczegóły (teksty komunikatów, wartości, kolory, ikony, formaty plików) są w specyfikacji głównej i w materiałach
  wzorcowych repozytorium Androida wskazanych w jej wstępie; ta specyfikacja ich nie powtarza.
- Program Horsely (≥ 1.5.0, testowany 2.0.0) jest dostępny do testów trybu online; pliki wzorcowe reguł i CSV pochodzą z programu.
- Właściciel ma aktywne konto Apple Developer Program, rekord aplikacji w App Store Connect (`pl.glapa.horsely`), App Group
  i sekrety repozytorium do podpisu i wysyłki (skonfigurowane 2026-10-15); córka jest testerką wewnętrzną.
- Nie ma Maca — budowanie, testy i wysyłka odbywają się wyłącznie zdalnie (specyfikacja główna 9.8); weryfikacja na urządzeniu
  — przez kompilacje TestFlight i ręczną listę kontrolną.
- Praca w tle na iOS działa „w miarę możliwości systemu”; kryteria czasowe odświeżania w tle z Androida są celem, nie wymaganiem.
- Poza zakresem jak w sekcji 10 specyfikacji głównej oraz: iPad, App Store, testerzy zewnętrzni, przenoszenie danych trybu
  samodzielnego do programu.
