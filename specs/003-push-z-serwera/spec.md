# Feature Specification: Powiadomienia push z serwera (tryb z serwerem)

**Feature Branch**: `003-push-z-serwera`

**Created**: 2026-11-05

**Status**: Draft

**Input**: User description: "Nowe wymagania dla realizacji push masz a pliku zmiana_push.md. Jeżeli czegoś nie będziesz
wiedział zobacz do projektu zarzadzanie_konmi_android. Pliki wymagana do komunikacji push znajdziesz w katalogu
c:\Users\desan\Downloads\ przenieś je sobie do projektu tam gdzie będziesz chciał. Aplikacja na androida jest już napisana
i działa poprawnie. Serwer też już wspiera wysyłanie push - Uwaga serwer na ip 192.168.18.33 jest już produkcyjny zanim nie
testuj na nim aplikacji jeżeli potrzebujesz serwera do testów uruchom go sobie lokalnie na tym komputerze"

## Kontekst

Serwer Horsely (program Java 2.0, specyfikacja serwera `008-push-mobilny`) wysyła powiadomienia push na telefony
(wdrożone na produkcji 2026-11-05). O tym, **które** powiadomienia, **kiedy** i **na który telefon** trafiają, decyduje
właściciel w UI webowym (reguły push przypisywane do kluczy API telefonów). Dziś aplikacja iOS 2.0.2 sama planuje
powiadomienia lokalne o terminach i dziennym podsumowaniu, także w trybie z serwerem.

Ta zmiana sprawia, że aplikacja w **trybie z serwerem**, gdy serwer ogłasza możliwość `push`, przestaje planować własne
powiadomienia o terminach i podsumowaniu, a zamiast tego: rejestruje się na serwerze jako odbiorca, pokazuje powiadomienia
przysłane przez serwer i pokazuje, jakie powiadomienia ma przypisane. Gdy push nie działa z jakiegokolwiek powodu,
aplikacja wraca do powiadomień lokalnych jak dziś. **Tryb samodzielny nie zmienia się w ogóle.**

Android zrealizował to **jako pierwszy** (wersja 2.1.0, spec `../zarzadzanie_konmi_android/specs/006-push-z-serwera/`)
i działa poprawnie na telefonie. Aplikacja iOS ma działać tak samo (konstytucja, zasada VIII): ta specyfikacja przejmuje
rozstrzygnięcia Androida i poprawki z jego wdrożenia, a różnice techniczne iOS opisuje wprost.

Źródła: `zmiana_push.md` (katalog główny repozytorium); po stronie serwera (`../zarzadzanie_konmi_java`):
`specs/008-push-mobilny/spec.md` (US21–US26, US47–US50), `contracts/api-push.md` §1 i „Capabilities”, `contracts/fcm.md` §2,
`docs/adr/0001-push-mobilny-przez-fcm.md`; po stronie Androida: `spec.md`, `research.md` R1–R13, `data-model.md` §2,
`contracts/ui-push.md` w `specs/006-push-z-serwera/`.

**Pliki konfiguracji push** (przejęte z katalogu Pobrane 2026-11-05): do repozytorium trafia wyłącznie plik konfiguracyjny
usługi dostarczania dla aplikacji iOS (`App/Resources/GoogleService-Info.plist`, identyfikator pakietu `pl.glapa.horsely`,
projekt `horsely-41baf`). Pozostałe pliki z tego katalogu **nie** należą do aplikacji iOS i nie trafiają do repozytorium:
klucz APNs `.p8` (już wgrany do usługi dostarczania), konto serwisowe usługi dostarczania (sekret serwera) i plik
konfiguracyjny Androida.

**Środowisko testów**: serwer pod adresem `192.168.18.33` jest **produkcyjny** — nie wolno na nim testować aplikacji
(rejestracji, wysyłki testów, przypisywania reguł). Testy ręczne i integracyjne z prawdziwym serwerem odbywają się na
serwerze uruchomionym lokalnie na komputerze dewelopera (Windows); testy automatyczne w CI używają zaślepki serwera.

## Clarifications

### Session 2026-11-05

- Q: Kiedy aplikacja ma uznać, że iPhone nie może odbierać powiadomień z serwera (tryb awaryjny „APNs niedostępny”)? → A: Odmowa rejestracji do powiadomień zdalnych przez system → od razu `Fallback(apnsUnavailable)`; brak tokenu FCM po udanej rejestracji APNs → zwykłe ponowienia, a po 24 h `Fallback(registrationFailed)`.
- Q: Jak pokazać powiadomienie z serwera odebrane na pierwszym planie przy włączonym „ukryj szczegóły na ekranie blokady”? → A: Jak każde inne — baner, wpis w centrum powiadomień i dźwięk z treścią z serwera; ekran ustawień wyjaśnia ograniczenie i wskazuje systemowe „Pokazuj podglądy” (świadoma różnica wobec Androida, który na pierwszym planie buduje powiadomienie sam).
- Q: Kiedy ponawiać nieudaną rejestrację na serwerze (iOS nie ma odpowiednika WorkManagera)? → A: W otwartej aplikacji z rosnącym odstępem (30 s, 1 min, 2 min…, maks. 15 min); poza tym przy każdym wejściu na pierwszy plan i w istniejącym zadaniu odświeżania w tle; próg 24 h liczony od zapisanego czasu pierwszego niepowodzenia.
- Q: Czy w tej zmianie dodać na Pulpicie kartę „Powiadomienia o terminach są wyłączone” (jest w Androidzie 2.1.0, brak w iOS 2.0.2)? → A: Tak — w tej zmianie, teksty z `strings.xml` Androida, ukryta przy `Registered`, wybór „Nie pokazuj” zapamiętany.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Telefon dostaje powiadomienia wysłane przez serwer (Priority: P1)

Użytkownik ma iPhone'a sparowanego z serwerem, który ogłasza `push`. Po wyrażeniu zgody na powiadomienia telefon sam
zgłasza się serwerowi jako odbiorca. Od tej chwili powiadomienia o terminach, dzienne podsumowanie, awarie kopii zapasowej
i powiadomienie testowe przychodzą z serwera — gdy aplikacja jest zamknięta, w tle, przy zablokowanym ekranie i na ekranie.

**Why this priority**: To jest istota zmiany — właściciel ustawia powiadomienia w jednym miejscu (UI webowe), a telefon je
dostaje. Bez tego pozostałe historie nie mają sensu.

**Independent Test**: Sparować iPhone'a (kompilacja z TestFlight) z lokalnym serwerem testowym z `push`, wyrazić zgodę,
w UI webowym kliknąć „Wyślij test” dla tego telefonu — powiadomienie „Test powiadomień Horsely” pojawia się raz przy
zablokowanym ekranie i raz przy aplikacji na ekranie.

**Acceptance Scenarios**:

1. **Given** telefon sparowany z serwerem ogłaszającym `push` i zgoda na powiadomienia, **When** aplikacja startuje,
   **Then** telefon jest zarejestrowany na serwerze i widać go na liście urządzeń w UI webowym jako iOS.
2. **Given** zarejestrowany telefon i aplikacja w tle, zamknięta lub ekran zablokowany, **When** właściciel wysyła test
   z UI webowego, **Then** w ciągu kilku sekund pojawia się powiadomienie „Horsely” z treścią „Test powiadomień Horsely”.
3. **Given** zarejestrowany telefon i aplikacja na ekranie, **When** serwer przysyła powiadomienie, **Then** aplikacja
   pokazuje je jako baner z dźwiękiem i wpisem w centrum powiadomień, tak jak powiadomienia lokalne.
4. **Given** zarejestrowany telefon z przypisaną regułą „Kowal: dzień przed o 08:00”, **When** nadchodzi termin kowala
   na jutro, **Then** o 08:00 przychodzi jedno powiadomienie z serwera i **nie** pojawia się powiadomienie lokalne (brak
   dubli).
5. **Given** zarejestrowany telefon, **When** usługa dostarczania odnowi identyfikator odbiorcy, **Then** aplikacja
   samoczynnie zgłasza nowy identyfikator serwerowi, a przypisane reguły dalej działają.
6. **Given** pojedynczy błąd sieci przy rejestracji, **When** aplikacja próbuje się zarejestrować, **Then** użytkownik
   nie widzi komunikatu, a rejestracja zostaje ponowiona później.
7. **Given** iPhone na danych komórkowych (Wi-Fi wyłączone), włączone „tylko przez Wi-Fi” dla plików i publiczny adres
   serwera, **When** aplikacja rejestruje telefon, **Then** rejestracja się udaje, a test z UI webowego dociera (błąd
   znaleziony na Androidzie).
8. **Given** kompilacja deweloperska (środowisko APNs „development”), **When** właściciel wysyła test, **Then** telefon
   także go dostaje.

---

### User Story 2 - Powiadomienia nie giną, gdy push nie działa (tryb awaryjny) (Priority: P1)

Gdy push nie może działać — stary serwer bez `push`, push wyłączony przez administratora lub właściciela, telefon nie może
zarejestrować się w systemowej usłudze powiadomień Apple, nieudane pobranie identyfikatora odbiorcy albo trwale nieudana
rejestracja — aplikacja dalej planuje powiadomienia lokalne jak dziś i mówi użytkownikowi dlaczego.

**Why this priority**: Użytkownik nie może stracić przypomnień o kowalu czy weterynarzu z powodu konfiguracji serwera albo
telefonu. To warunek bezpiecznego wdrożenia P1.

**Independent Test**: Sparować telefon z serwerem bez `push` albo uruchomić aplikację w symulatorze (bez rejestracji
w usłudze Apple) — powiadomienia lokalne działają jak w 2.0.2, a ekran powiadomień pokazuje ostrzeżenie z powodem.

**Acceptance Scenarios**:

1. **Given** serwer bez `push` w `capabilities`, **When** aplikacja działa w trybie z serwerem, **Then** planuje
   powiadomienia lokalne jak w wersji 2.0.2 i nie kontaktuje się z usługą dostarczania push.
2. **Given** zarejestrowany telefon, **When** właściciel wyłącza wysyłanie w UI webowym i telefon się synchronizuje,
   **Then** aplikacja bez udziału użytkownika wraca do powiadomień lokalnych.
3. **Given** tryb awaryjny po zniknięciu `push`, **When** `push` wraca w `capabilities` przy kolejnej synchronizacji,
   **Then** aplikacja rejestruje się ponownie i po udanej rejestracji wyłącza powiadomienia lokalne o terminach
   i podsumowaniu.
4. **Given** telefon (lub symulator), którego system odmówił rejestracji do powiadomień zdalnych, **When** użytkownik otwiera
   ekran powiadomień, **Then** widzi ostrzeżenie „Telefon nie może odbierać powiadomień z serwera — powiadomienia planuje
   telefon.”
5. **Given** serwer ogłasza `push`, ale rejestracja jeszcze się nie udała, **When** zbliża się termin, **Then** użytkownik
   dostaje powiadomienie lokalne (powiadomienia lokalne są wyłączane dopiero po udanej rejestracji).
6. **Given** tryb z serwerem w trybie awaryjnym i zgoda na powiadomienia, **When** zbliża się termin lub godzina
   podsumowania, **Then** powiadomienie lokalne naprawdę przychodzi (także po świeżym sparowaniu).

---

### User Story 3 - Odparowanie wyrejestrowuje telefon (Priority: P1)

Gdy użytkownik odparowuje telefon, przełącza aplikację w tryb samodzielny, usuwa dane połączenia albo cofa zgodę na
powiadomienia, telefon wypisuje się z serwera jako odbiorca i zapomina swój identyfikator odbiorcy. Serwer przestaje
wysyłać na ten telefon.

**Why this priority**: Bez tego odparowany telefon nadal dostawałby powiadomienia o koniach — problem prywatności.

**Independent Test**: Odparować zarejestrowany telefon — urządzenie znika z listy w UI webowym, a „Wyślij test” nie jest
już możliwy dla tego klucza.

**Acceptance Scenarios**:

1. **Given** zarejestrowany telefon, **When** użytkownik odparowuje telefon, **Then** urządzenie znika z listy urządzeń
   w UI webowym i telefon nie dostaje już powiadomień z serwera.
2. **Given** zarejestrowany telefon, **When** użytkownik przełącza się na tryb samodzielny, **Then** telefon wyrejestrowuje
   się z serwera, a powiadomienia lokalne działają jak w trybie samodzielnym.
3. **Given** klucz API już unieważniony na serwerze, **When** użytkownik odparowuje telefon, **Then** odparowanie kończy
   się normalnie (odrzucenie klucza nie jest błędem tego kroku), a lokalny stan push jest usunięty.
4. **Given** brak sieci przy odparowaniu, **When** użytkownik odparowuje telefon, **Then** odparowanie nie jest blokowane
   dłużej niż kilka sekund, a lokalny stan push jest usunięty.
5. **Given** zarejestrowany telefon, **When** użytkownik cofa zgodę na powiadomienia w Ustawieniach iOS i wraca do
   aplikacji, **Then** urządzenie znika z listy w UI webowym, a ekran pokazuje „Brak zgody”; przywrócenie zgody uruchamia
   ponowną rejestrację.

---

### User Story 4 - Ekran „Powiadomienia” pokazuje, co dostaję i dlaczego (Priority: P2)

W trybie z serwerem ekran ustawień powiadomień pokazuje stan push (zarejestrowany / rejestracja w toku / tryb awaryjny
z powodem / brak zgody), datę rejestracji i ostatniej dostawy oraz listę „Jakie powiadomienia dostaję” z opisami reguł
przysłanymi przez serwer. Ustawienia, którymi teraz steruje serwer, są ukryte.

**Why this priority**: Użytkownik musi rozumieć, skąd przychodzą powiadomienia i co zrobić, gdy ich nie ma. Funkcja działa
bez tego ekranu, więc P2.

**Independent Test**: Przypisać w UI webowym lokalnego serwera testowego dwie reguły do telefonu, otworzyć ekran
„Powiadomienia”, nacisnąć „Odśwież” — lista pokazuje dokładnie dwa opisy z serwera, np. „Kowal: dzień przed o 08:00,
powtórka o 07:00”.

**Acceptance Scenarios**:

1. **Given** tryb z serwerem i działający push, **When** użytkownik otwiera ekran „Powiadomienia”, **Then** nie widzi
   przełącznika włączenia powiadomień, godziny podsumowania ani opcji „w dniu terminu”, a widzi opcję „ukryj szczegóły na
   ekranie blokady”, „Powiadomienia z serwera: włączone”, datę rejestracji i ostatniej dostawy oraz listę reguł.
2. **Given** brak przypisanych reguł, **When** użytkownik otwiera ekran, **Then** widzi ostrzeżenie „Brak przypisanych
   powiadomień” i wyjaśnienie, że reguły przypisuje właściciel w UI webowym (Administracja → Serwer → Powiadomienia)
   i że po wdrożeniu wszystkie są domyślnie wyłączone.
3. **Given** brak zgody na powiadomienia (po odmowie), **When** użytkownik otwiera ekran, **Then** widzi stan „Brak zgody
   na powiadomienia” i przycisk „Otwórz ustawienia powiadomień” prowadzący do ustawień powiadomień aplikacji w systemie.
4. **Given** właściciel usunął urządzenie w UI webowym, **When** użytkownik otwiera ekran, **Then** aplikacja rejestruje
   się ponownie i jednorazowo informuje, że reguły trzeba znów przypisać w UI webowym.
5. **Given** tryb awaryjny, **When** użytkownik otwiera ekran, **Then** widzi powód trybu awaryjnego oraz dotychczasowe
   ustawienia powiadomień lokalnych (włączenie, godzina podsumowania, „w dniu terminu”).
6. **Given** rejestracja w toku, **When** użytkownik otwiera ekran, **Then** widzi „Rejestruję telefon na serwerze…”
   oraz dotychczasowe ustawienia lokalne.
7. **Given** tryb samodzielny, **When** użytkownik otwiera ekran, **Then** ekran wygląda i działa jak w wersji 2.0.2.
8. **Given** błąd pobrania listy reguł, **When** użytkownik naciska „Odśwież”, **Then** widzi „Nie udało się pobrać listy —
   spróbuj później”, a stan push się nie zmienia.

---

### User Story 5 - Dotknięcie powiadomienia otwiera właściwy ekran (Priority: P2)

Dotknięcie powiadomienia z serwera prowadzi tam, gdzie użytkownik może coś z nim zrobić: do szczegółów terminu, listy
terminów, informacji o kopiach zapasowych programu albo na ekran główny.

**Why this priority**: Wygoda; samo powiadomienie spełnia rolę przypomnienia także bez nawigacji.

**Independent Test**: Wywołać po jednym powiadomieniu każdego rodzaju i dotknąć każdego — otwiera się ekran z tabeli
w FR-019.

**Acceptance Scenarios**:

1. **Given** powiadomienie o terminie, którego dane są w telefonie, **When** użytkownik je dotyka, **Then** otwierają się
   szczegóły tego terminu.
2. **Given** powiadomienie o terminie, którego jeszcze nie ma w telefonie, **When** użytkownik je dotyka, **Then** aplikacja
   pobiera zmiany i otwiera szczegóły terminu, a gdy po synchronizacji termin dalej nie istnieje — listę terminów.
3. **Given** dzienne podsumowanie, **When** użytkownik je dotyka, **Then** otwiera się lista terminów (przeterminowane /
   dziś / jutro).
4. **Given** powiadomienie o awarii kopii zapasowej, **When** użytkownik je dotyka, **Then** otwiera się ekran „Kopia
   zapasowa na serwerze” z informacją, gdzie sprawdzić kopie.
5. **Given** powiadomienie testowe, analityczne albo nieznanego rodzaju (albo o terminie bez identyfikatora terminu),
   **When** użytkownik je dotyka, **Then** otwiera się ekran główny.

---

### User Story 6 - Dokumenty projektu i konfiguracja dopuszczają push z serwera (Priority: P1, przed kodem)

Konstytucja (zasada II) zakazuje dziś SDK łączących się z usługami zewnętrznymi, a specyfikacja mobilna wymienia
„powiadomienia push z serwera” jako poza zakresem. Przed realizacją dokumenty muszą to dopuścić w wąskim, opisanym zakresie,
spójnie z konstytucją Androida 2.1.0, a wydanie (podpis, uprawnienia aplikacji, manifest prywatności) musi obsługiwać push.

**Why this priority**: Bez zmiany konstytucji realizacja łamałaby zasadę projektu; bez uprawnienia do powiadomień zdalnych
w podpisanej kompilacji push nie zadziała z TestFlight. To bramka przed kodem.

**Independent Test**: Przeczytać konstytucję i specyfikację mobilną — wyjątek dla usługi dostarczania push jest opisany
z ograniczeniami, push nie ma na liście „Poza zakresem”; przebieg wydania w CI weryfikuje, że podpisana aplikacja ma
środowisko powiadomień „production”, a rozszerzenie udostępniania go nie ma.

**Acceptance Scenarios**:

1. **Given** obecna konstytucja, **When** zmiana jest gotowa do planu, **Then** konstytucja ma nową wersję z wyjątkiem:
   usługa dostarczania push wyłącznie do odbioru powiadomień z serwera użytkownika, tylko w trybie z serwerem, bez analityki
   i raportowania awarii, z notatką, że plik konfiguracyjny usługi nie jest sekretem.
2. **Given** specyfikacja mobilna, **When** zmiana jest gotowa, **Then** ma rozdział o push z serwera (uprawnienia
   aplikacji, tryb awaryjny, ekran ustawień), push nie figuruje w „Poza zakresem”, a lista zgód (sekcja 9.2) jest aktualna.
3. **Given** wydanie przez tag, **When** CI podpisuje aplikację, **Then** weryfikuje obecność właściwego środowiska
   powiadomień zdalnych w aplikacji i jego brak w rozszerzeniu udostępniania; brak → przebieg kończy się błędem.

---

### Edge Cases

- Serwer ogłasza `push`, ale użytkownik odmówił zgody: telefon się nie rejestruje; ekran pokazuje „Brak zgody” z przyciskiem
  do ustawień systemu. Po udzieleniu zgody (wykrytym przy powrocie do aplikacji) rejestracja rusza samoczynnie.
- Zgoda jeszcze nie była pytana (stan „nieustalona”): ekran nie mówi o odmowie; pytanie pada przy pierwszym otwarciu
  aplikacji (Pulpit) po pojawieniu się `push`, nigdy z tła.
- Zgoda cofnięta w Ustawieniach iOS po rejestracji: przy najbliższym starcie lub powrocie do aplikacji telefon
  wyrejestrowuje się z serwera i pokazuje „Brak zgody”; przywrócenie zgody uruchamia ponowną rejestrację (reguły przypisane
  do klucza zostają).
- Zmiana adresu serwera lub klucza na inny serwer: stary serwer zostaje wyrejestrowany (jeśli osiągalny), nowy
  zarejestrowany według jego `capabilities`.
- Przerwane przejście trybu (np. aplikacja zamknięta w trakcie „Rozłącz”) wznawiane po restarcie: wykonywana jest tylko
  część lokalna (klucza może już nie być).
- Dwa telefony z tym samym kluczem API: ostatnia rejestracja wygrywa; aplikacja nie musi tego wykrywać.
- Serwer odrzuca rejestrację błędem walidacji (`400`): trwały błąd rejestracji → tryb awaryjny z powodem.
- Klucz unieważniony (`401`), brak uprawnień (`403`) lub ograniczenie (`429`) przy rejestracji: obsługa jak dziś dla każdego
  żądania, bez osobnego komunikatu push; powiadomienia lokalne działają.
- Powiadomienie z nieznanym `type` lub dodatkowymi polami: wyświetlane normalnie, dotknięcie otwiera ekran główny; brak
  awarii. Zła data `targetDate` → pole pominięte.
- Powiadomienie odebrane na pierwszym planie, gdy stan ≠ zarejestrowany (np. tuż po odparowaniu, opóźnienie usługi):
  nie jest pokazywane.
- Wiadomość przeterminowana (telefon długo offline): usługa jej nie doręcza po upływie ważności ustalonej przez serwer.
- Kilka wiadomości o tym samym terminie (np. powtórka): nowsza zastępuje starszą w centrum powiadomień (klucz zwijania
  ustawia serwer).
- Push z alertem odebrany w tle nie wybudza aplikacji (serwer nie wysyła cichych pushy): synchronizacja następuje przy
  dotknięciu powiadomienia albo według zwykłego harmonogramu.
- Przejście z trybu awaryjnego do push w trakcie dnia: alarmy lokalne zaplanowane na dziś są anulowane dopiero po udanej
  rejestracji; jeden podwójny sygnał w chwili przełączenia jest akceptowalny, utracony — nie.
- Aktualizacja z 2.0.2 przy działającym `push`: pierwsza rejestracja przy pierwszym starcie; do tego czasu działają
  powiadomienia lokalne.
- Telefon zarejestrowany bez przypisanych reguł (stan domyślny po wdrożeniu serwera): powiadomienia lokalne o terminach
  i podsumowaniu są wyłączone, telefon nie dostaje przypomnień; ekran pokazuje ostrzeżenie „Brak przypisanych powiadomień”.
- Restart aplikacji przez system przy aktywnym push: zmiana identyfikatora odbiorcy i wiadomość muszą zostać obsłużone
  (konfiguracja usługi przy starcie, gdy push był aktywny).
- Symulator (testy UI w CI): rejestracja w usłudze Apple niedostępna → tryb awaryjny z ostrzeżeniem.

## Requirements *(mandatory)*

### Functional Requirements

#### Wykrywanie i rejestracja

- **FR-001**: Aplikacja MUSI uznawać push z serwera za dostępny wyłącznie w trybie z serwerem i wyłącznie, gdy lista
  `capabilities` serwera zawiera nazwę `push`. Nazwę `pushAdmin` i nieznane nazwy MUSI ignorować (dziś nieznane nazwy są
  odrzucane — `push` trzeba dopisać do znanych). Numer wersji serwera NIE jest sprawdzany.
- **FR-002**: Gdy push jest dostępny i jest zgoda, aplikacja MUSI zarejestrować się w systemowej usłudze powiadomień
  zdalnych Apple, pobrać identyfikator odbiorcy usługi dostarczania (token FCM, nie surowy token urządzenia APNs) i zgłosić
  go serwerowi (`PUT /push/device`, platforma `Ios`).
- **FR-003**: Rejestracja MUSI być ponawiana (gdy jest zgoda) przy: starcie aplikacji, powrocie do aplikacji z nowo
  udzieloną zgodą, udanym sparowaniu, odświeżeniu `capabilities`, w którym `push` się pojawił (a gdy jest stale — nie
  częściej niż raz na dobę według daty ostatniej rejestracji), oraz przy odnowieniu identyfikatora odbiorcy. Rejestracja
  jest idempotentna i nie wymaga klucza idempotencji.
- **FR-004**: Błąd sieci lub czasowy błąd serwera przy rejestracji MUSI skutkować ponowieniem później, bez komunikatu przy
  pojedynczym błędzie: gdy aplikacja jest otwarta — z rosnącym odstępem 30 s, 1 min, 2 min… (maks. 15 min); poza tym przy
  każdym wejściu na pierwszy plan i w istniejącym zadaniu odświeżania w tle. Czas pierwszego niepowodzenia jest zapisywany
  trwale (podstawa progu 24 h z FR-005) i czyszczony po udanej rejestracji.
- **FR-004a**: Żądania push (`PUT`/`DELETE`/`GET /push/*`) MUSZĄ być zwykłymi żądaniami, nie podlegającymi ograniczeniu
  „tylko przez Wi-Fi” dla plików; MUSZĄ działać na danych komórkowych przez adres publiczny serwera.
- **FR-004b**: Przy zerwanym połączeniu `PUT` i `DELETE /push/device` (idempotentne) MUSZĄ być natychmiast ponawiane do
  2 razy, niezależnie od ponowień z FR-004.
- **FR-005**: Rejestrację uznaje się za trwale nieudaną, gdy serwer odrzuci ją błędem walidacji (`400`) albo gdy próby nie
  udają się przez 24 h od pierwszego niepowodzenia; wtedy aplikacja przechodzi w tryb awaryjny z powodem „Nie udało się
  zarejestrować telefonu na serwerze — powiadomienia planuje telefon.”, a ponowienia trwają dalej.

#### Wyrejestrowanie

- **FR-006**: Przy odparowaniu, przełączeniu na tryb samodzielny, usunięciu danych połączenia i cofnięciu zgody aplikacja
  MUSI wywołać `DELETE /push/device` **zanim** klucz API zniknie z pamięci telefonu, a następnie usunąć identyfikator
  odbiorcy w usłudze dostarczania, wyłączyć jej automatyczną inicjalizację, wyrejestrować się z powiadomień zdalnych Apple
  i wyczyścić lokalny stan push.
- **FR-007**: Odpowiedź `401`, brak sieci lub błąd serwera przy wyrejestrowaniu NIE MOGĄ blokować (krótki limit, ok. 5 s)
  ani przerywać odparowania, zmiany trybu ani usunięcia danych.
- **FR-008**: Po wyrejestrowaniu aplikacja NIE MOŻE wyświetlać powiadomień z serwera odebranych na pierwszym planie i NIE
  MOŻE samoczynnie odnawiać identyfikatora odbiorcy.

#### Stan push, powiadomienia lokalne a push (brak dubli, tryb awaryjny)

- **FR-008a**: Stan push MUSI być wyznaczany jedną funkcją decyzji (testowalną bez interfejsu), sprawdzającą warunki
  w kolejności: tryb samodzielny → `Standalone`; brak `push` → `Fallback(serverHasNoPush)`; brak zgody → `NoPermission`;
  system odmówił rejestracji do powiadomień zdalnych Apple (zgłoszony błąd) → od razu `Fallback(apnsUnavailable)`; trwały
  błąd rejestracji (FR-005; także brak identyfikatora odbiorcy przez 24 h po udanej rejestracji APNs, wcześniej traktowany
  jak błąd chwilowy) → `Fallback(registrationFailed)`; jeszcze niezarejestrowany → `Pending`; ostatnia rejestracja udana dla bieżącego klucza →
  `Registered`. Powiadomienia lokalne o terminach i podsumowaniu są aktywne zawsze, gdy stan ≠ `Registered`. Ekran
  ustawień i planowanie powiadomień lokalnych czytają ten sam stan.
- **FR-009**: W trybie z serwerem z dostępnym push aplikacja MUSI przestać planować lokalne powiadomienia o terminach
  i dziennym podsumowaniu oraz anulować już zaplanowane — **dopiero po udanej rejestracji** — niezależnie od tego, czy do
  telefonu są przypisane reguły (FR-024).
- **FR-010**: Aplikacja MUSI planować powiadomienia lokalne jak w wersji 2.0.2 (tryb awaryjny), gdy w trybie z serwerem
  stan ≠ `Registered`.
- **FR-011**: Zniknięcie `push` z `capabilities` przy synchronizacji MUSI wyczyścić stan „zarejestrowany” bez wyrejestrowania
  na serwerze i przełączyć aplikację na powiadomienia lokalne bez udziału użytkownika; powrót `push` MUSI uruchomić ponowną
  rejestrację i po jej powodzeniu wyłączyć powiadomienia lokalne.
- **FR-012**: W trybie awaryjnym ekran „Powiadomienia” MUSI pokazywać ostrzeżenie z powodem: „Serwer nie wysyła
  powiadomień — powiadomienia planuje telefon.”, „Telefon nie może odbierać powiadomień z serwera — powiadomienia planuje
  telefon.” albo „Nie udało się zarejestrować telefonu na serwerze — powiadomienia planuje telefon.”
- **FR-012a**: Powiadomienia lokalne w trybie z serwerem MUSZĄ naprawdę działać (poprawki z Androida 2.1.0, do sprawdzenia
  i powielenia na iOS): udane parowanie MUSI włączać powiadomienia o terminach, gdy telefon ma zgodę, i planować
  podsumowanie; Pulpit MUSI pokazywać nową kartę „Powiadomienia o terminach są wyłączone” z „Włącz” i „Nie pokazuj”
  (teksty z `strings.xml` Androida 2.1.0 przez skrypt i test zgodności), dopóki są wyłączone — nie przy `Registered`
  i nie po wybraniu „Nie pokazuj” (wybór zapamiętany trwale); ekran powiadomień NIE MOŻE mówić o odrzuconej zgodzie, zanim o nią zapytano; treść
  podsumowania bez odmiany liczebników („Przeterminowane: 2, na dziś i jutro: 3”).
- **FR-013**: Powiadomienia niezwiązane z terminami (np. kolejka zmian, kopia zapasowa w telefonie) działają jak dotąd
  niezależnie od push.

#### Zgoda

- **FR-014**: Aplikacja MUSI prosić o zgodę na powiadomienia w trybie z serwerem, gdy push staje się dostępny po raz
  pierwszy, a zgoda jest nieustalona — wyłącznie przy otwarciu aplikacji (Pulpit), nigdy z tła; odmowę MUSI szanować (bez
  ponawiania pytania) i pokazywać „Brak zgody na powiadomienia” z przyciskiem „Otwórz ustawienia powiadomień”. Ekran MUSI
  mówić, że push i powiadomienia lokalne wymagają tej samej zgody.
- **FR-014a**: Bez zgody aplikacja NIE MOŻE rejestrować telefonu na serwerze; gdy zgoda zniknie po rejestracji, MUSI
  wyrejestrować telefon przy najbliższym starcie lub powrocie do aplikacji. Udzielenie zgody MUSI uruchomić rejestrację bez
  dodatkowej akcji użytkownika.

#### Odbiór i wyświetlanie

- **FR-015**: Gdy aplikacja jest w tle, zamknięta lub ekran jest zablokowany, powiadomienie z serwera MUSI wyświetlić
  system (tytuł i treść z serwera).
- **FR-016**: Gdy aplikacja jest na pierwszym planie i stan to `Registered`, powiadomienie z serwera MUSI być pokazane jako
  baner z dźwiękiem i wpisem w centrum powiadomień, jak powiadomienia lokalne; przy innym stanie NIE MOŻE być pokazane.
- **FR-017**: Obsługa odebranej wiadomości NIE MOŻE wykonywać długiej pracy. Po odebraniu na pierwszym planie albo
  dotknięciu wiadomości `reminder` lub `summary` aplikacja MUSI zlecić synchronizację w tle; dla pozostałych rodzajów NIE
  MOŻE jej zlecać.
- **FR-018**: Aplikacja MUSI ignorować nieznane klucze w danych wiadomości i traktować nieznane wartości `type` jak
  powiadomienie ogólne (bez awarii). Powiadomienia z serwera MUSI odróżniać od lokalnych po kluczu `type` w danych.
- **FR-019**: Dotknięcie powiadomienia MUSI otwierać ekran zależnie od `type` (mapowanie danych wiadomości na cel
  nawigacji jako funkcja testowalna bez interfejsu):

  | `type` | Ekran |
  |---|---|
  | `reminder` z `reminderId` | szczegóły terminu; gdy terminu nie ma lokalnie — po synchronizacji, a gdy dalej go nie ma — lista terminów |
  | `reminder` bez `reminderId` | ekran główny |
  | `summary` | lista terminów (przeterminowane / dziś / jutro) |
  | `backup` | nowy ekran „Kopia zapasowa na serwerze”: „Serwer zgłosił nieudaną kopię zapasową. Sprawdź kopie w UI webowym (Administracja → Kopie zapasowe).”, przycisk „Wróć”, bez połączeń z siecią |
  | `analytic`, `test`, brak, nieznany | ekran główny |

  Pola `horseId` i `targetDate` są odczytywane tolerancyjnie (zła wartość → brak) i w tej wersji nieużywane.
- **FR-020**: Ustawienie „ukryj szczegóły na ekranie blokady” MUSI obowiązywać dla powiadomień lokalnych bez zmian.
  Powiadomienia z serwera pokazują treść z serwera (bez wymogu ukrywania, bez zmiany serwera i bez rozszerzenia
  przetwarzającego powiadomienia); ekran „Powiadomienia” w trybie z serwerem MUSI przy tym ustawieniu dopisywać:
  „Powiadomienia z serwera odebrane w tle pokazują treść także na ekranie blokady.” oraz wskazywać systemowe ustawienie
  podglądów powiadomień („Pokazuj podglądy”) jako sposób ukrycia treści. Powiadomienie z serwera odebrane na pierwszym
  planie jest pokazywane z treścią z serwera także przy włączonym ustawieniu (aplikacja nie tworzy własnej kopii z ukrytą
  treścią) — świadoma różnica wobec Androida.

#### Ekran „Powiadomienia” (tryb z serwerem)

- **FR-021**: Przy stanie `Registered` ekran MUSI ukrywać: włączenie powiadomień, godzinę podsumowania i „w dniu terminu”;
  MUSI zostawić „ukryj szczegóły na ekranie blokady”.
- **FR-022**: Ekran MUSI pokazywać stan push teksami jak na Androidzie: „Powiadomienia z serwera: włączone”,
  „Zarejestrowano: 05.11.2026, 08:15”, „Ostatnie powiadomienie: …” albo „Jeszcze żadnego” (z `GET /push/device`);
  „Rejestruję telefon na serwerze…”; ostrzeżenie trybu awaryjnego z powodem (FR-012); „Brak zgody na powiadomienia”
  z przyciskiem.
- **FR-023**: Ekran MUSI pokazywać listę „Jakie powiadomienia dostaję” z opisem (`description`) każdej reguły
  z `GET /push/rules` w kolejności serwera, bez własnej interpretacji pól reguły, oraz przycisk „Odśwież”. Dane urządzenia
  i reguł są pobierane tylko na żądanie ekranu, nie w tle.
- **FR-024**: Pusta lista reguł MUSI pokazywać ostrzeżenie „Brak przypisanych powiadomień” (telefon nie dostaje wtedy
  żadnych powiadomień o terminach ani podsumowania) oraz „Reguły przypisuje właściciel w UI webowym (Administracja → Serwer →
  Powiadomienia). Po wdrożeniu wszystkie są domyślnie wyłączone.”
- **FR-025**: Odpowiedź `404` z `GET /push/device` (właściciel usunął urządzenie) MUSI uruchomić ponowną rejestrację
  i jednorazowy komunikat „Właściciel usunął ten telefon z listy urządzeń. Telefon zarejestrował się ponownie — reguły
  trzeba znów przypisać w UI webowym.”
- **FR-026**: W stanach `Pending` i `Fallback` ekran MUSI pokazywać dotychczasowe ustawienia powiadomień lokalnych.
- **FR-026a**: Błąd `GET /push/rules` MUSI pokazywać „Nie udało się pobrać listy — spróbuj później” bez zmiany stanu push.

#### Tryb samodzielny

- **FR-027**: W trybie samodzielnym aplikacja NIE MOŻE konfigurować usługi dostarczania push, rejestrować się do
  powiadomień zdalnych, pobierać identyfikatora odbiorcy ani łączyć się z hostami tej usługi; powiadomienia i ekran
  „Powiadomienia” działają jak w wersji 2.0.2.
- **FR-027a**: Usługa dostarczania MUSI być konfigurowana leniwie — dopiero przy trybie z serwerem, `push` i zgodzie; przy
  starcie aplikacji MUSI być konfigurowana od razu tylko wtedy, gdy push był wcześniej aktywny (trwały znacznik usuwany przy
  wyrejestrowaniu), aby obsłużyć zmianę identyfikatora i wiadomości po restarcie procesu.

#### Prywatność

- **FR-028**: Dziennik diagnostyczny MUSI mieć kategorię `push` z wynikami opisanymi słowami (np. „rejestracja ok
  token=abcd1234…”, „rejestracja nieudana: brak połączenia”, „wiadomość type=reminder”) i NIE MOŻE zawierać pełnego
  identyfikatora odbiorcy (najwyżej 8 pierwszych znaków), tytułów, treści ani identyfikatorów z wiadomości. Identyfikator
  odbiorcy z ciała rejestracji NIE MOŻE trafić do dziennika połączeń (potwierdzone testem).
- **FR-029**: Aplikacja NIE MOŻE zawierać analityki ani raportowania awarii dostawcy usługi push; zbieranie analityki
  MUSI być wyłączone, automatyczna inicjalizacja usługi — wyłączona poza ręczną inicjalizacją w trybie z serwerem.
- **FR-030**: Aplikacja NIE MOŻE wysyłać serwerowi niczego poza platformą i identyfikatorem odbiorcy w ramach push;
  lokalnie przechowuje wyłącznie prefiks identyfikatora (8 znaków), nie pełny identyfikator.
- **FR-030a**: Manifest prywatności aplikacji i odpowiedzi „App Privacy” w App Store Connect MUSZĄ być zaktualizowane
  o to, co wnosi usługa dostarczania push.
- **FR-030b**: Rozszerzenie udostępniania NIE MOŻE zawierać usługi dostarczania push ani uprawnienia do powiadomień
  zdalnych.

#### Konfiguracja, dokumenty i wersja

- **FR-031**: Przed realizacją konstytucja MUSI dostać nową wersję z wyjątkiem w zasadzie II dla usługi dostarczania push
  (wyłącznie odbiór powiadomień z serwera użytkownika, tylko tryb z serwerem, bez analityki i raportowania awarii), spójnym
  z konstytucją Androida 2.1.0.
- **FR-032**: Specyfikacja `SPECYFIKACJA_MOBILE_IOS.md` MUSI usunąć „powiadomienia push z serwera” z „Poza zakresem”
  (rozdział 10), dostać rozdział o push (uprawnienia aplikacji, tryb awaryjny, ekran ustawień) i zaktualizowaną listę zgód
  (sekcja 9.2); zmiany zakresu wprowadzane w obu specyfikacjach mobilnych (zasada V).
- **FR-032a**: Plik konfiguracyjny usługi dostarczania (`GoogleService-Info.plist`) MUSI być w repozytorium; README
  i konstytucja MUSZĄ stwierdzać, że nie jest sekretem (nie pozwala wysyłać powiadomień), a klucz API w nim MUSI być
  ograniczony w konsoli Google Cloud do aplikacji iOS `pl.glapa.horsely`. Budowanie z samego repozytorium (w CI) MUSI dawać
  aplikację z działającym push. Klucz APNs, konto serwisowe usługi i inne sekrety NIE MOGĄ trafić do repozytorium.
- **FR-032b**: Podpisana aplikacja MUSI mieć uprawnienie do powiadomień zdalnych ze środowiskiem „production” dla
  TestFlight/App Store i „development” dla kompilacji deweloperskich oraz tryb tła „powiadomienia zdalne”; krok podpisywania
  w CI MUSI to weryfikować (obok dotychczasowych grup aplikacji i pęku kluczy).
- **FR-033**: Zmiana MUSI być wydana jako wersja **2.1.0** (MINOR; numer kompilacji z CI) przez tag `v2.1.0` z wysyłką do
  TestFlight; ekran „O aplikacji” i dziennik diagnostyczny pokazują 2.1.0; `CHANGELOG.md` ma sekcję `[2.1.0]` (Dodano: push
  z serwera, ekran „Powiadomienia” w trybie z serwerem; Zmieniono: powiadomienia lokalne o terminach w trybie z serwerem
  z działającym push).
- **FR-034**: Aktualizacja z 2.0.2 do 2.1.0 NIE MOŻE utracić danych ani ustawień powiadomień lokalnych; dopóki rejestracja
  push się nie powiedzie, powiadomienia lokalne działają jak w 2.0.2.
- **FR-035**: Testy automatyczne MUSZĄ używać zaślepki serwera z `PUT/DELETE/GET /push/device` i `GET /push/rules`,
  przełącznikiem `push` w `capabilities` i wymuszaniem `400`/`404`/`5xx`; modele dekodują tolerancyjnie (nieznane pola
  i nieznany typ reguły to nie błąd); przykłady JSON z kontraktu serwera. Testy ręczne z prawdziwym serwerem — wyłącznie
  na serwerze lokalnym, nigdy na produkcyjnym `192.168.18.33`.

### Key Entities

- **Stan rejestracji push (po stronie telefonu)**: czy zarejestrowany, prefiks identyfikatora odbiorcy (8 znaków, tylko
  diagnostyka), data ostatniej udanej rejestracji, początek serii niepowodzeń, znacznik trwałego niepowodzenia, znacznik
  jednorazowego komunikatu o usunięciu urządzenia przez właściciela, znacznik „push był aktywny”. Część danych połączenia;
  usuwany przy odparowaniu.
- **Stan push**: jeden z `Standalone`, `Fallback(powód)`, `NoPermission`, `Pending`, `Registered`; wyznacza, czy planowane
  są powiadomienia lokalne o terminach i podsumowaniu, i co pokazuje ekran.
- **Urządzenie push (widok serwera)**: platforma, prefiks identyfikatora, data rejestracji, ostatniego kontaktu i ostatniej
  dostawy — tylko do odczytu.
- **Reguła push (widok telefonu)**: identyfikator, typ, gotowy polski opis — tylko do odczytu; aplikacja pokazuje opis.
- **Wiadomość push**: tytuł „Horsely” i krótka treść oraz dane: `type` i dla terminu `reminderId`, `horseId`, `targetDate`;
  klucz zwijania i ważność ustawia serwer.
- **Cel nawigacji z powiadomienia**: szczegóły terminu, lista terminów, ekran „Kopia zapasowa na serwerze”, ekran główny.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Po sparowaniu z serwerem z `push` i wyrażeniu zgody telefon pojawia się na liście urządzeń w UI webowym
  w ciągu 1 minuty (przy dostępnej sieci, także komórkowej).
- **SC-002**: Powiadomienie testowe z UI webowego pojawia się na iPhonie w ciągu 30 sekund — przy zablokowanym ekranie,
  w tle i na ekranie — w 10 na 10 prób, dla kompilacji z TestFlight i kompilacji deweloperskiej.
- **SC-003**: Przy przypisanej regule dla terminu użytkownik dostaje dokładnie jedno powiadomienie o tym terminie (0 dubli
  z powiadomień lokalnych).
- **SC-004**: Po wyłączeniu wysyłania przez właściciela telefon wraca do powiadomień lokalnych najpóźniej przy następnej
  synchronizacji; żaden termin w tym czasie nie zostaje bez powiadomienia (0 utraconych).
- **SC-005**: Po odparowaniu urządzenie znika z listy w UI webowym w ciągu 1 minuty (przy dostępnej sieci), a odparowanie
  bez sieci trwa najwyżej kilka sekund dłużej niż w 2.0.2.
- **SC-006**: Tryb samodzielny i serwer bez `push` przechodzą obecny zestaw testów i scenariuszy powiadomień bez zmian
  w zachowaniu; w trybie samodzielnym aplikacja nie nawiązuje żadnego połączenia z hostami usługi push.
- **SC-007**: W symulatorze (bez rejestracji w usłudze Apple) użytkownik widzi ostrzeżenie trybu awaryjnego, a
  powiadomienia lokalne działają.
- **SC-008**: Użytkownik w ciągu 10 sekund od otwarcia ekranu „Powiadomienia” potrafi powiedzieć, jakie powiadomienia
  dostaje (lista opisów reguł) albo dlaczego ich nie dostaje (stan i powód).
- **SC-009**: Dziennik diagnostyczny z pełnego scenariusza (rejestracja, odbiór, odparowanie) zawiera najwyżej prefiks
  identyfikatora odbiorcy, żadnych tytułów ani treści powiadomień, a błędy są opisane czytelnymi słowami.
- **SC-010**: Zachowanie iOS i Androida 2.1.0 jest zgodne: te same stany, teksty ekranu „Powiadomienia” i cele nawigacji
  (sprawdzane testem zgodności tekstów).

## Assumptions

- Serwer (program Java 2.0, spec. 008) jest wdrożony; kontrakt API telefonu i kształt wiadomości są ustalone; zmiany
  serwera są addytywne, a aplikacja 2.0.2 działa z nim bez różnic. Serwer nie publikuje OpenAPI z push (sprawdzone
  2026-11-05) — przykłady do testów pochodzą z kontraktu.
- Usługa dostarczania to Firebase Cloud Messaging (przez APNs); projekt `horsely-41baf` ma zarejestrowaną aplikację iOS
  `pl.glapa.horsely`, a klucz APNs `.p8` jest wgrany do Firebase i obsługuje oba środowiska APNs.
- Serwer nie wysyła cichych pushy ani `mutable-content` — brak rozszerzenia przetwarzającego powiadomienia.
- Treści powiadomień są przygotowane przez serwer po polsku, bez notatek, kwot, diagnoz i nazw osób.
- Wersja 2.1.0; minimalna wersja serwera nie jest sprawdzana — decyduje wyłącznie `capabilities`.
- Rozstrzygnięcia Androida (ekran blokady, zgoda, synchronizacja po push, brak reguł, wersja, plik konfiguracyjny
  w repozytorium) przyjęte bez ponownego pytania. `scripts/ci/check-secrets.sh` sprawdza tylko obecność sekretów CI, a nie
  zawartość plików, więc `GoogleService-Info.plist` w repozytorium nie koliduje z nim.
- Decyzja techniczna pozostawiona planowi (bez wpływu na zachowanie widoczne dla użytkownika):
  - **Przekazywanie tokenu APNs do usługi dostarczania**: ręczne (bez automatycznego podmieniania metod delegata), dla
    przewidywalności i leniwej inicjalizacji — decyzja techniczna w planie.
- Na iOS nie ma dziś karty Pulpitu „Powiadomienia o terminach są wyłączone” — dochodzi w tej zmianie (FR-012a,
  Clarifications), spójnie z Androidem 2.1.0; obejmuje wzorce migawek Pulpitu z kartą.
- Testy ręczne z prawdziwym serwerem: serwer Java uruchamiany lokalnie na komputerze dewelopera z własnym (testowym)
  przełącznikiem push; iPhone testowy łączy się z nim w sieci lokalnej. Serwer produkcyjny `192.168.18.33` jest wyłączony
  z testów.
