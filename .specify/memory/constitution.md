<!--
Sync Impact Report
- Version change: (brak) → 2.0.1 (pierwsza konstytucja projektu iOS)
- Źródło: konstytucja aplikacji na Androida 2.0.0 (repozytorium zarzadzanie_konmi_android,
  `.specify/memory/constitution.md`, ratyfikowana 2026-10-05, zmieniona 2026-10-09) przeniesiona
  z dopasowaniem do platformy iOS według decyzji z sesji wyjaśniającej 2026-10-15
  (SPECYFIKACJA_MOBILE_IOS.md, wersja dokumentu 1.5). Numer 2.0.1 = zakres funkcji Androida 2.0.1.
- Principles: I–VII jak w Androidzie (treść merytoryczna bez zmian), dopasowane:
  - II. uprawnienia iOS (bez lokalizacji, kontaktów, pełnej biblioteki zdjęć; PhotosPicker,
    selektor dokumentów); wykluczenie z kopii iCloud.
  - III. Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) zamiast Keystore; zasłona
    w przełączniku aplikacji zamiast `FLAG_SECURE`.
  - V. dodana zgodność z aplikacją na Androida 2.0.1 (te same funkcje, teksty, kolory, ikony,
    format kopii zapasowej).
  - VII. preferowane rozwiązania wbudowane w iOS; bez zależności od usług zewnętrznych.
- Added sections: „Zgodność z aplikacją na Androida” (zasada VIII).
- Ograniczenia i proces: Swift/SwiftUI, iOS 18+, iPhone 15 Pro, XcodeGen, GitHub Actions
  bez Maca, wydanie przez TestFlight (testerzy wewnętrzni), testy migawkowe.
- Templates: plan-template.md, spec-template.md, tasks-template.md — skopiowane z projektu
  Androida, bez zmian (odwołują się ogólnie do zasad konstytucji) ✅
- Follow-up TODOs: brak.
-->
# Horsely — aplikacja na iOS — Constitution

## Core Principles

### I. Jedno źródło prawdy w wybranym trybie pracy

- Aplikacja pracuje w jednym z dwóch trybów, wybieranym przy pierwszym uruchomieniu,
  zapamiętanym i zmienianym w Ustawieniach → Tryb pracy:
  - **tryb online** — aplikacja jest klientem programu „Horsely” na komputerze;
    program jest źródłem prawdy o danych i jedynym miejscem reguł biznesowych;
  - **tryb samodzielny** — aplikacja działa bez programu; telefon jest źródłem prawdy i sam
    stosuje reguły programu (walidacja, unikalność, automatyczne terminy, podział kosztów,
    sumy raportów, kosz).
- W każdej chwili MUSI istnieć dokładnie jedno źródło prawdy; aplikacja NIE MOŻE łączyć danych
  obu trybów ani pracować w trybie innym niż zapamiętany.
- W trybie online aplikacja NIE MOŻE przeliczać ani przekształcać wartości biznesowych w sposób
  zmieniający wynik względem programu; po synchronizacji obowiązują wartości zwrócone przez
  program. Walidacja w aplikacji jest wygodą, a komunikaty błędów programu MUSZĄ być pokazywane
  przy właściwych polach.
- W trybie samodzielnym reguły odtworzone w telefonie MUSZĄ dawać wyniki identyczne z programem
  dla tych samych danych (co do grosza i minuty); zakres odtworzonych reguł określa specyfikacja,
  a reguła spoza tego zakresu NIE MOŻE być przybliżana.
- Zmiana trybu, która usuwa lub zastępuje dane lokalne (przejście z samodzielnego na online),
  MUSI być poprzedzona wyraźnym ostrzeżeniem o skutkach i potwierdzeniem użytkownika; NIE MOŻE
  nastąpić automatycznie ani w wyniku pojedynczego przypadkowego dotknięcia.
- Ustawienia programu i API oraz zarządzanie kluczami NIE MOGĄ być dostępne w aplikacji.
  Trwałe usuwanie danych i operacje masowe (kosz, odtwarzanie kopii) są dozwolone wyłącznie
  w trybie samodzielnym, z potwierdzeniem; w trybie online usunięcie wpisu oznacza przeniesienie
  do kosza programu.

**Uzasadnienie**: reguła zaimplementowana w dwóch miejscach może się rozjechać — dlatego w danym
trybie obowiązuje jedna implementacja, a tam, gdzie telefon zastępuje program, zgodność wyników
jest wymagana i testowana (SC-M-04, SC-M-09).

### II. Prywatność i brak usług zewnętrznych

- Aplikacja MUSI łączyć się wyłącznie ze sparowanym komputerem użytkownika (w trybie samodzielnym —
  z nikim); NIE MOŻE zawierać telemetrii, analityki, raportowania awarii do usług zewnętrznych,
  reklam ani SDK nawiązujących połączenia wychodzące. Jedyny wyjątek: mapy, telefon i e‑mail
  otwierane w innych aplikacjach na żądanie użytkownika.
- Aplikacja MUSI prosić wyłącznie o zgody z listy w specyfikacji (sekcja 9.2) i NIE MOŻE prosić
  o lokalizację, dostęp do kontaktów ani pełny dostęp do biblioteki zdjęć; zdjęcia wybiera się
  przez `PhotosPicker`, pliki przez selektor dokumentów, kontakt przez `CNContactPickerViewController`.
- Logi diagnostyczne NIE MOGĄ zawierać treści wpisów, nazw koni, danych kontaktów ani klucza API;
  rozmiar logów MUSI być ograniczony (rotacja, maks. 5 MB).
- Lokalna baza danych, kolejka zmian i załączniki MUSZĄ leżeć w prywatnym obszarze aplikacji
  (i wspólnym kontenerze App Group dla rozszerzenia udostępniania) i być wykluczone z kopii iCloud.
  Kopia zapasowa danych trybu samodzielnego MOŻE powstawać wyłącznie na żądanie użytkownika
  (albo w włączonej przez niego kopii automatycznej) do miejsca wskazanego przez niego.

**Uzasadnienie**: dane to prywatna ewidencja właściciela; nie opuszczają jego telefonu i komputera
bez jego decyzji (NFR-M-05, NFR-M-06, NFR-M-09).

### III. Bezpieczne połączenie i klucz API

- Klucz API MUSI być przechowywany wyłącznie w pęku kluczy (Keychain,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) i NIE MOŻE trafić do logów, komunikatów,
  kopii zapasowych ani zrzutów ekranu; ekran wpisywania klucza MUSI być zasłaniany w przełączniku
  aplikacji.
- Każdy adres `https` MUSI mieć własny tryb zaufania. Adresy z kodu QR i adresy z certyfikatem
  o odcisku z parowania: aplikacja MUSI akceptować wyłącznie certyfikat o tym odcisku SHA‑256
  i NIE MOŻE wysyłać klucza do serwera z innym certyfikatem. Adres dopisany ręcznie z certyfikatem
  od urzędu certyfikacji zaufanego przez system MOŻE być używany w trybie „zaufany wystawca”
  wyłącznie po pokazaniu wystawcy i nazwy oraz potwierdzeniu przez użytkownika, ze standardową
  weryfikacją łańcucha i nazwy hosta. Pozostałe certyfikaty MUSZĄ być odrzucane.
- `http` MUSI być dozwolone tylko dla adresów sieci lokalnej (wyłącznie prywatny adres IP podany
  wprost albo nazwa `.local`) i tylko po świadomym potwierdzeniu ostrzeżenia; `NSAllowsArbitraryLoads`
  jest zabronione.
- Aplikacja MUSI wysyłać klucz w każdym żądaniu, a po `401`/`403` MUSI wstrzymać wszystkie żądania
  z tym kluczem do tego adresu (w tym synchronizację i pracę w tle) do działania użytkownika;
  `429` MUSI wstrzymać żądania do czasu `Retry-After`. Aplikacja NIE MOŻE sama doprowadzić do
  zablokowania adresu telefonu (SC-M-08).

**Uzasadnienie**: klucz daje pełny dostęp do danych stajni, a program blokuje adres po
powtarzanych odmowach.

### IV. Praca offline i synchronizacja bez utraty i duplikatów

- Aplikacja MUSI przechowywać lokalnie wszystkie dane potrzebne do pracy bez połączenia, w zakresie
  odpowiadającym programowi. W trybie online bez połączenia dozwolone jest dodawanie, edycja
  i usuwanie danych; zmiany trafiają do trwałej kolejki, która przetrwa zamknięcie aplikacji przez
  system i restart telefonu, i są wysyłane w kolejności powstania, z zachowaniem zależności.
- Każda operacja MUSI mieć stały identyfikator nadany na urządzeniu; ponowienie po nieznanym
  wyniku NIE MOŻE utworzyć duplikatu (`Idempotency-Key` przy programie, który go obsługuje,
  inaczej „licznik przed i po”).
- Każda zmiana istniejącego rekordu MUSI nieść wersję, na której ją wykonano. Konflikt MUSI zostać
  wykryty i NIE MOŻE skończyć się cichą utratą którejkolwiek ze zmian; rozstrzyga go użytkownik.
- Operacja odrzucona przez program MUSI dostać status „Wymaga poprawy” z komunikatem programu
  i NIE MOŻE być po cichu porzucona ani blokować operacji od niej niezależnych.
- Każdy ekran z danymi lokalnymi w trybie online MUSI pokazywać, z kiedy są dane, gdy nie są
  aktualne, oraz liczbę zmian oczekujących na wysłanie.
- Zapis do lokalnej bazy MUSI być transakcyjny: przerwanie NIE MOŻE pozostawić danych w stanie
  częściowym.
- Aplikacja MUSI działać poprawnie, gdy iOS nie uruchomi pracy w tle wcale — zaległe odświeżenie,
  wysyłka i kopia automatyczna są nadrabiane przy otwarciu aplikacji.

**Uzasadnienie**: wpis zrobiony w stajni bez zasięgu jest wartościowy tylko wtedy, gdy nigdy nie
zginie, nie zdubluje się i nie nadpisze po cichu zmiany zrobionej w programie (NFR-M-10, SC-M-03).

### V. Zgodność z kontraktem API i modelem danych programu

- Aplikacja MUSI działać z programem 1.5.0 i nowszymi wersjami `/api/v1`, odmawiać współpracy
  z wersją niższą niż 1.5.0, ignorować nieznane pola i używać możliwości programu 2.0.0 tylko,
  gdy program je ogłasza (`capabilities`).
- Źródłem prawdy o kontrakcie jest `openapi.yaml` programu; aplikacja NIE MOŻE zakładać pól,
  endpointów ani zachowań spoza kontraktu. Zmiana kontraktu MUSI być odzwierciedlona najpierw
  w kopii kontraktu i testach, potem w kodzie.
- Model danych lokalnych (w obu trybach) MUSI odwzorowywać pojęcia, pola i ograniczenia programu.
- Wartości pieniężne MUSZĄ być reprezentowane typem dokładnym (`Decimal` albo liczba całkowita
  groszy); `Double`/`Float` dla kwot są zabronione. Daty kalendarzowe wpisów MUSZĄ być datami bez
  strefy; czas lokalny urządzenia NIE MOŻE decydować o danych programu.
- Zakres funkcji, identyfikatory wymagań i kryteria sukcesu MUSZĄ pozostać zgodne z wersją na
  Androida (`SPECYFIKACJA_MOBILE_ANDROID.md`) i ze specyfikacją w repozytorium programu; zmiany
  zakresu wprowadza się we wszystkich dotkniętych dokumentach.

**Uzasadnienie**: program i aplikacje wydawane są niezależnie; cicha rozbieżność kontraktu lub
modelu objawiałaby się utratą lub zniekształceniem danych.

### VI. Testy (NIEPODLEGAJĄCE NEGOCJACJI)

- Logika kolejki i synchronizacji, mapowanie błędów API, podpowiedzi, mapowanie terminów na
  formularze oraz format czasu i kwot MUSZĄ mieć testy jednostkowe (przypadek pozytywny i brzegowy).
- Komunikacja z API MUSI być testowana z zaślepką serwera (`URLProtocol`) zgodną z `openapi.yaml`,
  w tym `401`, `403`, `409`, `413`, `415`, `429`, przerwanie połączenia i konflikt.
- Każda reguła programu odtworzona w telefonie MUSI mieć testy na plikach wzorcowych programu —
  tych samych co w aplikacji na Androida; CSV raportów MUSI być porównywany bajt w bajt.
- Zmiana trybu pracy, kopia zapasowa (w tym odtworzenie pliku utworzonego na Androidzie) oraz
  zgodność tekstów z `strings.xml` MUSZĄ mieć testy.
- Kluczowe ekrany MUSZĄ mieć testy migawkowe (jasny i ciemny motyw, tekst 200 %) na symulatorze
  iPhone 15 Pro.
- Logika zależna od czasu MUSI korzystać ze wstrzykiwanego zegara.
- Zmiana nie jest ukończona, dopóki wszystkie testy w CI nie przechodzą.

**Uzasadnienie**: błędy w synchronizacji, w odtworzonych regułach i w kwotach są ciche (NFR-M-12).

### VII. Prostota

- Rozwiązanie MUSI używać najprostszej konstrukcji spełniającej wymagania ze specyfikacji;
  funkcje spoza specyfikacji NIE SĄ implementowane „na zapas”.
- Każda dodatkowa warstwa, wzorzec lub zależność zewnętrzna MUSI mieć uzasadnienie w
  `research.md` lub w „Complexity Tracking” planu.
- Nowa biblioteka MUSI mieć zgodną licencję, być aktywnie utrzymywana i NIE MOŻE wymagać usług
  zewnętrznych; preferowane są rozwiązania wbudowane w iOS.

**Uzasadnienie**: jeden użytkownik i jedno źródło danych w danym trybie — złożoność nie przynosi
korzyści, a podnosi koszt utrzymania.

### VIII. Zgodność z aplikacją na Androida

- Aplikacja na iOS MUSI mieć te same funkcje, ekrany, teksty, kolory, ikony (Material, wariant
  Outlined) i zachowanie co aplikacja na Androida 2.0.1; różnice dopuszcza wyłącznie sekcja 9
  specyfikacji (mechanizmy systemu, natywne komponenty iOS).
- Teksty interfejsu MUSZĄ pochodzić z `strings.xml` aplikacji na Androida przez skrypt, z testem
  zgodności; plik kopii zapasowej MUSI być wymienny między platformami.

**Uzasadnienie**: właściciel i współwłaściciele mogą używać różnych telefonów — ta sama aplikacja
oznacza te same nawyki, ten sam opis w instrukcji i przenośne dane.

## Ograniczenia technologiczne i platformowe

- Platforma: natywna aplikacja na iPhone, minimalna wersja **iOS 18**; urządzenie docelowe
  i odniesienia — **iPhone 15 Pro**; poprawne działanie na każdym iPhonie z iOS 18+; iPad poza
  zakresem; orientacja pionowa (pozioma dla podglądu zdjęć i wideo).
- Języki i narzędzia: Swift 6, SwiftUI z natywnymi komponentami iOS; szczegółowy stos potwierdza
  plan na podstawie sekcji 9.7 specyfikacji. Rdzeń (reguły, raporty, CSV, kolejka, synchronizacja)
  pisany w Swift, bez współdzielenia kodu z Androidem.
- Projekt: XcodeGen (`project.yml`), `.xcodeproj` nie trafia do repozytorium; logika w pakietach SPM.
- Praca w tle: `BGTaskScheduler`, sesja `URLSession` w tle; odświeżanie w tle nie częściej niż co
  15 min (przy `dataStamp`) / co godzinę.
- Interfejs w języku polskim (daty `30.09.2026`, kwoty `1 250,00 zł`, tydzień od poniedziałku);
  kod, identyfikatory i komentarze w kodzie po angielsku.
- Dostępność: VoiceOver, Dynamic Type do 200 % bez obcinania, kontrast WCAG 2.1 AA, cele dotyku
  ≥ 44 pt.
- Wymagania wydajnościowe (NFR-M-01…03) są wiążące na iPhonie 15 Pro i MUSZĄ być zweryfikowane
  przed wydaniem — w obu trybach pracy.

## Proces wytwórczy i bramki jakości

- Źródłem prawdy o wymaganiach jest `SPECYFIKACJA_MOBILE_IOS.md`; artefakty w `specs/` MUSZĄ być
  z nią zgodne. Rozbieżność rozstrzyga się aktualizacją specyfikacji (i specyfikacji Androida),
  nie cichym odstępstwem w kodzie.
- Każdy plan (`/speckit-plan`) MUSI zawierać „Constitution Check” odnoszący się do zasad I–VIII,
  rozpatrywany osobno dla trybu online i samodzielnego, przed i po fazie projektowej.
- Realizacja przebiega przyrostowo według historii użytkownika i priorytetów; każdy przyrost MUSI
  być uruchamialny i testowalny niezależnie.
- Budowanie wyłącznie w CI (GitHub Actions, runnery macOS) — rozwój na Windows bez Maca: pull
  request i `main` — kompilacja i wszystkie testy (jednostkowe, UI, migawkowe) ze zrzutami ekranów
  jako artefaktami; tag `v*` lub ręczne uruchomienie — także archiwum, podpis i wysyłka do TestFlight.
- Przed uznaniem zadania za ukończone: kompilacja bez ostrzeżeń (ostrzeżenia jako błędy), zielone
  testy w CI, a dla zmian UI — przejrzane zrzuty ekranów z CI (jasny i ciemny motyw, tekst 200 %).
- Wydanie: po zielonym CI na `main` tag `v<wersja>` → wysyłka do TestFlight; podsumowanie podaje
  wersję, numer kompilacji i wynik wysyłki. Brak sekretów podpisywania lub klucza API App Store
  Connect zgłasza się wprost — nigdy nie pomija się wysyłki po cichu. Wersja jest wydana po
  ręcznej liście kontrolnej na iPhone 15 Pro. Nowa kompilacja trafia do TestFlight co najmniej raz
  na 80 dni.
- Sekrety podpisywania i klucz API App Store Connect są wyłącznie w sekretach repozytorium GitHub;
  NIE MOGĄ trafiać do repozytorium ani do logów.
- Aktualizacja aplikacji NIE MOŻE utracić danych lokalnych użytkownika (w szczególności danych
  trybu samodzielnego i niewysłanych zmian).

## Governance

- Konstytucja ma pierwszeństwo przed innymi praktykami i dokumentami procesu projektu.
- Zmiana konstytucji wymaga opisu i uzasadnienia, aktualizacji raportu wpływu (Sync Impact Report)
  oraz przeglądu zależnych artefaktów (`plan.md`, `tasks.md`, specyfikacje iOS i Android);
  zmiany zasad wspólnych (I–VII) wprowadza się także w konstytucji aplikacji na Androida.
- Wersjonowanie semantyczne: MAJOR — redefinicja zasady niezgodna wstecz; MINOR — nowa zasada
  lub sekcja albo istotne rozszerzenie; PATCH — doprecyzowania.
- Każdy przegląd zmian MUSI weryfikować zgodność z zasadami I–VIII; odstępstwa MUSZĄ być
  uzasadnione w „Complexity Tracking” planu, inaczej zmiana jest odrzucana.
- Bieżące wskazówki wytwórcze: `SPECYFIKACJA_MOBILE_IOS.md`, `.claude/CLAUDE.md` oraz
  `specs/<feature>/plan.md` i `quickstart.md`.

**Version**: 2.0.1 | **Ratified**: 2026-10-15 | **Last Amended**: 2026-10-15
