# Zarządzanie końmi — aplikacja mobilna na iOS — specyfikacja

| | |
|---|---|
| **Wersja dokumentu** | 1.4 (2026-10-15) — uzupełniona tak, by sama opisywała pełny zakres aplikacji na Androida **2.0.1** (bez odwołań do dokumentów, których nie ma w repozytorium iOS): zakres 1.1 (stabilny stan połączenia, działy, ikony), 1.2 (wygląd i poprawki), 2.0 (tryby pracy, pełna praca offline, kosz, słowniki, kopia zapasowa, zdjęcie konia, kolory, blokada) i 2.0.1 (Horsely, „Kontuzjowany”, `capabilities`, dziennik diagnostyczny); wzorzec wyglądu (sekcja [5.4](#54-wzorzec-wyglądu)). Wersja 1.3 (2026-10-05) — uzgodniona z programem 1.6.1; decyzje z sesji wyjaśniającej 2026-10-05 |
| **Zakres wersji 1.1 aplikacji** | stabilny stan połączenia (FR-M-POL-14…17, US1/8–8e), działy Treningi · Zakupy · Zawody (US11), nawigacja (5.2), ikony z programu (US12), pamięć 12 miesięcy dla działów (FR-M-SYN-01) |
| **Zakres wersji 1.2 aplikacji** | poprawki (kafel konia → karta konia, zakupy i starty otwierają szczegóły, zawody całego bieżącego roku), ocena gwiazdkami, terminy i koszty w obszarach z tonami, linie między wierszami list, sekcje formularzy (5.1, 5.2, 5.4) |
| **Zakres wersji 2.0 aplikacji** | tryb pracy wybierany przy pierwszym uruchomieniu (online / samodzielny), pełna praca offline z edycją i konfliktami (FR-SYN2-*), reguły programu w telefonie (FR-SAM-*), kosz i słowniki w trybie samodzielnym, kopia zapasowa (FR-KOP-*), zdjęcie konia (FR-ZDK-*), więcej kolorów i nowe ikony (FR-KOL-*), blokada aplikacji (FR-TRB-09) — sekcje [3.1](#31-historie-wersji-20) i [4.12](#412-wersja-20--tryby-pracy-praca-offline-kopia-zapasowa-kolory-zdjęcie-konia) |
| **Zakres wersji 2.0.1 aplikacji** | nazwa „Horsely – Zarządzanie Koniem, Trening i Budżet”, słowniki zgodne z programem 2.0.0, możliwości programu (`capabilities`), status „Kontuzjowany” z ikoną plastra, poprawka układu wierszy raportów, szczegółowy dziennik diagnostyczny — sekcje [3.2](#32-historie-wersji-201) i [4.13](#413-wersja-201--horsely-i-program-200) |
| **Platforma** | iOS (iPhone) — aplikacja natywna (osobny projekt; odpowiednik na Androida: `SPECYFIKACJA_MOBILE_ANDROID.md`, implementacja wzorcowa: repozytorium `zarzadzanie_konmi_android`, wersja 2.0.1) |
| **Współpracuje z** | program „Horsely” (dawniej „Zarządzanie końmi”) na Windows, wersja **1.5.0 lub nowsza** (API `/api/v1`; kontrakt bez zmian do 1.6.1; od 2.0.0 możliwości programu wykrywane polem `capabilities`, §6.6); wersja testowana: **2.0.0** |
| **Autor systemu** | Piotr Glapa |
| **Przeznaczenie** | Wejście do `/speckit-specify` w nowym, osobnym projekcie aplikacji mobilnej |

> **Jak używać tego dokumentu.** W nowym repozytorium aplikacji na iOS uruchom
> `/speckit-specify` i wskaż ten plik jako opis funkcji. Aplikacja na Androida ma osobny projekt i osobny dokument
> (`SPECYFIKACJA_MOBILE_ANDROID.md`) o tym samym zakresie funkcji — różnią się tylko sekcją [9](#9-wymagania-platformy-ios).
> Kontrakt API skopiuj z repozytorium programu na komputer (`specs/001-zarzadzanie-konmi/contracts/openapi.yaml`)
> do nowego projektu albo pobierz z działającego programu: `GET http://<komputer>:5080/openapi/v1.json`
> (tylko z sieci domowej; przy włączonym HTTPS — `https://`; z adresów spoza niej program 1.2 odpowiada `404`).
> Sekcje 1–8 opisują **co** aplikacja ma robić; sekcje 9 i 11 zawierają ograniczenia techniczne dla `/speckit-plan`.
>
> **Cel: ta sama aplikacja co na Androidzie.** Aplikacja na iOS MUST mieć te same funkcje, ekrany, teksty, kolory, ikony
> i zachowanie co aplikacja na Androida 2.0.1; różnice dopuszcza wyłącznie sekcja [9](#9-wymagania-platformy-ios)
> (mechanizmy systemu: Keychain zamiast Keystore, `BGTaskScheduler` zamiast WorkManagera, SF Symbols zamiast ikon Material
> itp.). Przy rozbieżności między tym dokumentem a działaniem aplikacji na Androida 2.0.1 rozstrzyga ten dokument, a
> rozbieżność należy zgłosić i poprawić w obu dokumentach (zasada V konstytucji).
>
> **Materiały wzorcowe do skopiowania do repozytorium iOS** (z repozytorium `zarzadzanie_konmi_android`, wersja 2.0.1):
>
> | Materiał | Plik w repozytorium Androida | Do czego |
> |---|---|---|
> | Wszystkie teksty interfejsu (PL) | `app/src/main/res/values/strings.xml`, `plurals.xml` | `Localizable.xcstrings` — te same teksty co do znaku (odmiana liczebników jak w `plurals.xml`) |
> | Teksty raportów, CSV, PDF | `core/…/report/` (`ReportTexts`), pliki wzorcowe `core/src/test/resources/` | zgodność raportów i CSV bajt w bajt (FR-M-RAP-05, FR-SAM-03) |
> | Reguły programu i pliki wzorcowe | `specs/004-tryb-samodzielny-offline/contracts/rules-parity.md`, `core/src/test/resources/parity` | tryb samodzielny (FR-SAM-02), testy zgodności |
> | Kontrakt API | `specs/005-horsely-2-0-1/contracts/openapi-2.0.0.yaml` (program 2.0.0), `specs/001-aplikacja-mobilna/contracts/openapi.yaml` (1.6.1) | klient API |
> | Schemat eksportu | `specs/004-tryb-samodzielny-offline/contracts/export-schema-1.4.json` + zmiany 1.5 (`program-2.0-integration.md`) | magazyn lokalny, pełne pobranie, kopia zapasowa |
> | Kolejka, połączenie, synchronizacja | `specs/001…/contracts/outbox-operations.md`, `pairing-and-connection.md`, `specs/002…/contracts/connection-behavior.md`, `specs/004…/contracts/mode-and-sync.md`, `specs/005…/contracts/program-2.0-integration.md` | szczegóły algorytmów |
> | Format kopii zapasowej | `specs/004…/contracts/backup-format.md` (format 2 od 2.0.1) | kopia **wymienna między Androidem a iOS** (FR-KOP-09) |
> | Wygląd | `specs/003…/contracts/ui-components.md`, `screen-review.md`, `specs/004…/contracts/ui-screens.md`, `palette-mockup.html`, `icons-mockup.html`, `specs/005…/contracts/ui-2.0.1.md` | wzorzec wyglądu ([5.4](#54-wzorzec-wyglądu)) |
> | Ikony | `app/src/main/res/drawable/ic_horse_head.xml`, `ic_launcher_foreground.xml`, `ic_launcher_background.xml`, `ic_stat_horseshoe.xml` | rysunki wektorowe do przeniesienia do katalogu zasobów iOS (PDF/SVG) |
> | Punkty wejścia | `specs/001…/contracts/app-entry-points.md` | powiadomienia, skróty, udostępnianie |

## Spis treści

1. [Wprowadzenie](#1-wprowadzenie)
2. [Słownik pojęć](#2-słownik-pojęć)
3. [Historie użytkownika](#3-historie-użytkownika)
4. [Wymagania funkcjonalne](#4-wymagania-funkcjonalne)
5. [Ekrany i nawigacja](#5-ekrany-i-nawigacja)
6. [Współpraca z programem na komputer (API)](#6-współpraca-z-programem-na-komputer-api)
7. [Wymagania niefunkcjonalne](#7-wymagania-niefunkcjonalne)
8. [Kryteria sukcesu](#8-kryteria-sukcesu)
9. [Wymagania platformy iOS](#9-wymagania-platformy-ios)
10. [Poza zakresem](#10-poza-zakresem)
11. [Założenia i zależności](#11-założenia-i-zależności)

---

## 1. Wprowadzenie

### 1.1 Cel

Aplikacja mobilna jest **pomocnikiem w stajni** dla programu „Zarządzanie końmi” działającego na komputerze
z Windows. Pozwala przy koniu, z telefonu:

- sprawdzić, co jest do zrobienia (przeterminowane i nadchodzące terminy: kowal, szczepienia, odrobaczanie, wizyty);
- od razu zapisać to, co się wydarzyło (trening, wizyta weterynarza, kowala, fizjoterapeuty, notatka, zakup, start w zawodach)
  razem ze zdjęciami z aparatu;
- przejrzeć historię konia, kontakty, koszty i raporty (te same co w programie, z wykresami i eksportem CSV/PDF);
- dostać przypomnienie o terminie, nawet gdy komputer jest wyłączony.

Od wersji 2.0 aplikacja pracuje w jednym z dwóch **trybów** wybieranych przy pierwszym uruchomieniu (zmiana w Ustawieniach → Tryb pracy):

- **online** — z programem na komputerze: program jest źródłem prawdy, a telefon trzyma w pamięci **wszystkie jego dane** (pełne pobranie
  i uzgadnianie), więc także bez połączenia można dodawać, poprawiać i usuwać; zmiany wychodzą do programu po powrocie sieci,
  a konflikty (ten sam rekord zmieniony w telefonie i w programie) rozstrzyga użytkownik;
- **samodzielny** — bez programu: telefon jest źródłem prawdy i sam stosuje reguły programu (walidacja, terminy z dat następnych wizyt,
  podział kosztów zakupu, raporty, kosz, słowniki); aplikacja nie nawiązuje wtedy żadnych połączeń sieciowych, a dane chroni kopia
  zapasowa do pliku.

### 1.2 Użytkownik

- Właściciel jednego lub kilku (do ok. 50) koni, ten sam, który używa programu na komputerze.
- Korzysta z telefonu w stajni, na padoku, na zawodach: często słaby zasięg lub brak Wi‑Fi, brudne ręce lub
  rękawiczki, pośpiech. Wpis musi dać się zrobić w kilkanaście sekund.
- Nie jest informatykiem: połączenie z komputerem ma się odbyć przez zeskanowanie kodu QR.
- Jedno urządzenie mobilne na osobę; kilka urządzeń (np. telefon i tablet, telefon współwłaściciela) to osobne
  klucze API wygenerowane w programie na komputerze.
- Aplikacji używają wyłącznie właściciel i współwłaściciele. Klucz daje dostęp do wszystkich danych stajni (także
  finansowych), a system nie ma uprawnień — klucza nie przekazuje się trenerom, jeźdźcom ani innym osobom trzecim
  (klucze o ograniczonym zakresie — możliwe przyszłe rozszerzenie, [sekcja 10](#10-poza-zakresem)).

### 1.3 Kontekst — program na komputer

| Aspekt | Stan (wersja 1.6.1 programu; minimalna obsługiwana: 1.5.0) |
|---|---|
| Dane | Baza SQLite i pliki załączników na komputerze użytkownika |
| API | REST/JSON, `http(s)://<adres-komputera>:5080/api/v1`, domyślnie **wyłączone** — użytkownik włącza je w Ustawieniach |
| Zasięg | Sieć lokalna (Wi‑Fi w domu/stajni). Spoza sieci — od programu 1.2 — tryb „Dostęp spoza sieci domowej” (tylko HTTPS, klucz ze zgodą na dostęp spoza domu, blokada adresów po nieudanych próbach; [`SPECYFIKACJA_DOSTEP_ZDALNY.md`](SPECYFIKACJA_DOSTEP_ZDALNY.md) w repozytorium programu): przez nazwę DynDNS albo stały publiczny adres IP i przekierowanie portu w routerze albo przez VPN użytkownika. Program 1.2 uznaje za sieć domową tylko adresy prywatne (10/8, 172.16/12, 192.168/16, 169.254/16, `fc00::/7`, `fe80::/10`): VPN dający telefonowi taki adres działa jak sieć domowa, a VPN z innymi adresami (np. Tailscale, `100.64.0.0/10`) jest traktowany jak internet i wymaga tego trybu |
| Uwierzytelnianie | Nagłówek `X-Api-Key`; klucz generowany w programie, pokazywany raz razem z kodem QR |
| HTTPS | Opcjonalne, certyfikat samopodpisany; odcisk SHA‑256 certyfikatu jest w kodzie QR |
| Dostępność | Tylko gdy komputer jest włączony, program uruchomiony (także ukryty w zasobniku) i API włączone |
| Reguły biznesowe | Walidacja, unikalność, automatyczne terminy, podział kosztów — wykonuje serwer; komunikaty błędów są po polsku |
| Zmiany 1.3–1.6.1 istotne dla aplikacji | **1.3**: dziennik treningów (`/trainings`), kwoty konia (`finance`: zakup, sprzedaż, wartość). **1.4**: typ kontaktu `Trainer`, trener i koszt treningu (`coaching`), kategoria „Treningi” w kosztach. **1.5**: typ kontaktu `Rider`; jeździec treningu i startu w zawodach jest kontaktem (`riderContactId`) zamiast tekstu — **zmiana niezgodna wstecz**: tekstowe pole `rider` wysłane do programu ≥ 1.5 jest po cichu ignorowane; kontaktu użytego jako trener lub jeździec nie da się usunąć (`409 InUse`). **1.6, 1.6.1**: zmiany wyłącznie w wyglądzie programu (imię stajenne na kafelku konia, czas w godzinach i minutach, jednakowa wielkość kafli koni) — API bez zmian |

**Program 2.0.0 („Horsely”).** Od wersji 2.0.0 program nazywa się Horsely – Zarządzanie Koniem, Trening i Budżet; adres API, parowanie i klucze działają bez zmian. Program
2.0.0 dodaje możliwości, które aplikacja wykrywa po polu `capabilities` w `GET /system/info` (§6.6) oraz nowy status konia **Kontuzjowany** (`Injured`), który program
pokazuje klientom jako **Aktywny**, dopóki klient nie zadeklaruje obsługi nagłówkiem `X-Client-Features: horse-status-injured`. Aplikacja 2.0.0 tego nagłówka nie wysyła,
więc widzi konia kontuzjowanego jako aktywnego, a zapis konia z telefonu nie zmienia jego statusu w programie. Aplikacja (jak na Androidzie 2.0.1) **obsługuje status**:
wysyła nagłówek, gdy program ogłasza możliwość `horseStatusInjured` (FR-005…FR-013).

**Zakres wersji 2.0.1 (taki sam jak na Androidzie).** (1) Nazwa aplikacji: „Horsely – Zarządzanie Koniem, Trening i Budżet”, krótka nazwa „Horsely”. (2) Słowniki domyślne
zgodne z programem 2.0.0: 10 rodzajów treningów; u istniejących użytkowników trybu samodzielnego brakujące rodzaje są dopisywane raz, bez zmiany wartości wprowadzonych
przez użytkownika. (3) Możliwości programu (§6.6) wykrywane z `GET /system/info`: stempel danych (`dataStamp`), pobieranie samych zmian (`updatedSince`, pełne pobranie
raz na dobę w tle), `If-Match` przy usuwaniu, `Idempotency-Key` przy dodawaniu, zdjęcie konia jako zmiana konia w kolejce; program 1.5.0–1.6.x działa jak dotąd.
(4) Status „Kontuzjowany”: nagłówek `X-Client-Features: horse-status-injured`, pomarańczowa ikona plastra na kaflu Pulpitu i w wierszu listy koni, plakietka na karcie
konia, filtr listy koni, potwierdzenie przy dodawaniu treningu koniowi kontuzjowanemu. (5) Wersja testowanego programu: 2.0.0. (6) Raporty: etykieta i wartość wiersza
nie łamią się po literze. (7) Dziennik diagnostyczny (FR-M-UST-01, FR-029…FR-033): przeglądanie, wysyłanie i czyszczenie wpisów oraz szczegółowy dziennik połączeń
(adres, IP, sieć, wynik; wyłącza się sam po 7 dniach). Szczegóły: [3.2](#32-historie-wersji-201) i [4.13](#413-wersja-201--horsely-i-program-200).

### 1.4 Zakres w skrócie

W zakresie:

- parowanie z programem przez kod QR i obsługa kilku adresów komputera;
- pulpit, terminy (zrealizuj, odrzuć, przełóż, zarejestruj wizytę z terminu);
- konie: lista, karta konia, oś czasu, dodanie konia (także źrebaka bez paszportu), edycja podstawowych danych;
- dodawanie i edycja wpisów: wizyta weterynaryjna (z lekami), kowal (także dla kilku koni naraz), fizjoterapia,
  inny specjalista, notatka, zakup (z kosztem dostawy), zawody i start w zawodach (jeździec wybierany z kontaktów), trening (rodzaj, czas, intensywność, ocena, trener,
  jeździec, koszt — z podpowiedzią z ostatniego treningu konia), termin;
- zdjęcia i dokumenty: aparat, galeria, pliki, udostępnianie z innych aplikacji;
- kontakty (także trenerzy i jeźdźcy): przeglądanie, telefon/SMS/e‑mail/nawigacja, dodanie kontaktu;
- raporty jak w programie: Koszty, Bilans konia, Podsumowanie treningów, Treningi jeźdźca, Zawody jeźdźca — z wykresami
  i eksportem CSV/PDF (dane i sumy z API programu, pliki tworzone na telefonie i udostępniane albo zapisywane);
- działy jak w programie (zakres wersji 1.1, [US11](#us11--działy-treningi-zakupy-i-zawody-p1-wersja-11-aplikacji)): **Treningi**
  (wszystkie konie), **Zakupy** (z „Powtórz zakup”) i **Zawody** (szczegóły ze startami, formularz zawodów) — z filtrami
  (domyślnie bieżący rok), liczbą i sumami z programu oraz pracą z pamięci z ostatnich 12 miesięcy;
- zakres wersji 1.2 ([5.1](#51-zasady-ogólne), [5.2](#52-struktura), [5.4](#54-wzorzec-wyglądu)): ocena gwiazdkami ★★★☆☆,
  terminy i koszty w obszarach z tonami, linie między wierszami list, sekcje formularzy, domyślny okres działów
  1 stycznia – 31 grudnia bieżącego roku, kafel konia → karta konia, zakupy i starty otwierają szczegóły;
- praca bez połączenia: podgląd z pamięci i kolejka nowych wpisów; stabilny stan połączenia (ponawianie odczytów, „Odśwież”,
  samoczynne wznawianie, komunikat zwijany do ikonki — FR-M-POL-14…17);
- ikony z programu: podkowa (ikona aplikacji i powiadomień) i głowa konia;
- lokalne powiadomienia o terminach.

Od wersji 2.0 dodatkowo:

- wybór trybu pracy przy pierwszym uruchomieniu i zmiana trybu w Ustawieniach (z ostrzeżeniami o usunięciu i zastąpieniu danych);
- pełna praca offline w trybie online: wszystkie dane w telefonie, edycja, usuwanie, „Przełóż”, dodanie konia bez połączenia, kolejka
  z łączeniem zmian i ekran „Konflikty” (pojedynczo i zbiorczo);
- tryb samodzielny: reguły programu w telefonie, raporty i eksport CSV/PDF z danych lokalnych, **Kosz** i **Słowniki**, załączniki w telefonie;
- **kopia zapasowa** do pliku (opcjonalne hasło, odtwarzanie także z ekranu powitalnego, przypomnienie i kopia automatyczna co tydzień);
- zdjęcie konia z aparatu lub telefonu z kadrowaniem; miniatury na liście koni i kaflach Pulpitu;
- więcej kolorów rozpoznawczych rodzajów wpisów i działów oraz nowe ikony;
- opcjonalna blokada aplikacji zabezpieczeniem telefonu.

Od wersji 2.0.1 dodatkowo: nazwa „Horsely”, status konia „Kontuzjowany”, słowniki programu 2.0.0, korzystanie z możliwości programu 2.0.0
(`capabilities`), czytelne wiersze raportów, ekran „Dziennik diagnostyczny” i szczegółowy dziennik połączeń.

Poza zakresem (zostaje w programie na komputerze): ustawienia programu i API, generowanie i unieważnianie kluczy, eksport i import danych
programu, przenoszenie danych trybu samodzielnego do programu — patrz [sekcja 10](#10-poza-zakresem).

---

## 2. Słownik pojęć

| Pojęcie | Znaczenie |
|---|---|
| **Program** | Program „Zarządzanie końmi” na komputerze z Windows (źródło prawdy, serwer API) |
| **Aplikacja** | Aplikacja mobilna opisana w tym dokumencie |
| **Parowanie** | Jednorazowe połączenie aplikacji z programem: adres, klucz API i (opcjonalnie) odcisk certyfikatu |
| **Klucz API** | Tajny ciąg `hk_…` wygenerowany w programie dla jednego urządzenia; można go unieważnić w programie |
| **Wpis** | Wizyta weterynaryjna, kowala, fizjoterapeuty, specjalisty, start w zawodach, zakup, notatka, trening |
| **Termin** | Zaplanowane zdarzenie konia (kowal, szczepienie, odrobaczanie, wizyta, zawody, inne) ze statusem Otwarty / Zrealizowany / Odrzucony |
| **Pamięć podręczna** | Kopia danych pobranych z programu, przechowywana na urządzeniu do przeglądania bez połączenia |
| **Kolejka wysyłki** | Nowe wpisy, zdjęcia i akcje na terminach zapisane bez połączenia, czekające na wysłanie do programu |
| **Źrebak** | Koń oznaczony „Źrebak”; może nie mieć numeru paszportu (od wersji 1.1 programu) |
| **Łączny koszt zakupu** | Kwota zakupu + koszt dostawy (od wersji 1.1 programu) |
| **Trening** | Wpis dziennika treningów konia (od wersji 1.3 programu): dzień, rodzaj (słownik), czas, intensywność, ocena 1–5, opis, wysokość przeszkód (skoki); trener i koszt od 1.4, jeździec jako kontakt od 1.5 |
| **Trener**, **Jeździec** | Typy kontaktu (od wersji 1.4 i 1.5 programu). Trener i jeździec treningu oraz jeździec startu w zawodach są wybierane spośród kontaktów tego typu — nie wpisywane tekstem |
| **Tryb online** / **tryb samodzielny** | Dwa tryby pracy aplikacji (od wersji 2.0): z programem na komputerze albo bez niego; wybór przy pierwszym uruchomieniu, zmiana w Ustawieniach → Tryb pracy |
| **Magazyn lokalny** | Wszystkie dane w telefonie (rekordy w kształcie eksportu programu): w trybie online kopia danych programu z własnymi niewysłanymi zmianami, w samodzielnym — jedyne źródło prawdy |
| **Konflikt** | Ten sam rekord zmieniony w telefonie i w programie (albo zmieniony w jednym, a usunięty w drugim); użytkownik wybiera „Zachowaj moją” albo „Przyjmij z programu” |
| **Kosz** | Tryb samodzielny: usunięte rekordy z zależnymi, które można przywrócić albo usunąć na stałe (jak w programie) |
| **Kopia zapasowa** | Plik `.zkkopia` z wszystkimi danymi telefonu (także koszem, słownikami i załącznikami), opcjonalnie zaszyfrowany hasłem |
| **Imię stajenne** | Przydomek konia (`stableName`); program pokazuje je pod imieniem w cudzysłowie („Gromek”) |
| **Kontuzjowany** | Status konia (`Injured`, od wersji 2.0.0 programu): koń w stajni, traktowany jak aktywny, z plakietką ostrzegawczą w programie. Klientowi bez nagłówka `X-Client-Features: horse-status-injured` program pokazuje go jako **Aktywny** (odpowiedzi i eksport) i nie pozwala przez taki klient zmienić go na aktywnego. W aplikacji: pomarańczowa ikona plastra (FR-007a) |
| **Horsely** | Nazwa programu od wersji 2.0.0 i nazwa aplikacji od wersji 2.0.1 („Horsely – Zarządzanie Koniem, Trening i Budżet”); wszystkie teksty mówią „program Horsely” |
| **Możliwości programu** | Lista nazw w polu `capabilities` odpowiedzi `GET /system/info` (program ≥ 2.0.0): `updatedSince`, `dataStamp`, `ifMatchDelete`, `idempotencyKey`, `horsePhotoField`, `horseStatusInjured`; brak pola = program 1.5.0–1.6.x |
| **Stempel danych** | `dataStamp` z `GET /system/info` — zmienia się po każdej zmianie danych w programie; ten sam stempel = nic do pobrania |
| **Operacja kolejki**, **wersja bazowa** | Zmiana wykonana w telefonie (dodanie, edycja, usunięcie, akcja na terminie, zdjęcie konia) czekająca na wysłanie, ze stałym identyfikatorem i wersją rekordu, na której ją wykonano |
| **Dziennik diagnostyczny** | Plik zdarzeń aplikacji bez danych osobowych (do 5 MB), z opcjonalnym szczegółowym dziennikiem połączeń (adres, IP, sieć, wynik żądania) |

---

## 3. Historie użytkownika

Priorytety: **P1** — bez tego aplikacja nie ma sensu (MVP), **P2** — ważne, **P3** — uzupełniające.
Każda historia daje się przetestować niezależnie od pozostałych (poza US1, która jest warunkiem wszystkich).

> **Wersja 2.0 zmienia ograniczenia 1.x.** Historie US1–US12 opisują tryb online w kształcie 1.x. Wszędzie, gdzie mówią, że
> edycja, usuwanie, „Przełóż” albo dodanie konia wymagają połączenia (US2/4, US3/10–11, US5/2, US6/7, US10/6, FR-M-SYN-04,
> FR-M-SYN-11, FR-M-ZAL-06), od wersji 2.0 obowiązuje FR-SYN2-03: operacja zapisuje się od razu w telefonie i trafia do
> kolejki, a konflikt rozstrzyga użytkownik (FR-SYN2-07). Ograniczenie 1.x wraca tylko przy programie bez wersji rekordów
> (tryb zgodności, FR-SYN2-09). W trybie samodzielnym nie ma ograniczeń połączenia ani elementów związanych z połączeniem
> (FR-TRB-08). Usunięcie w trybie samodzielnym trafia do kosza telefonu (FR-SAM-04).

### US1 — Połączenie z programem na komputerze (P1)

Jako właściciel chcę połączyć telefon z programem na komputerze, skanując kod QR, aby bez wpisywania adresów
i kluczy korzystać ze swoich danych.

**Test niezależny**: w programie włączyć API i wygenerować klucz „Telefon”; w aplikacji zeskanować kod QR →
aplikacja pokazuje nazwę i wersję programu oraz pulpit z danymi.

**Scenariusze akceptacyjne**:

1. **Given** pierwsze uruchomienie aplikacji, **When** skanuję kod QR z programu, **Then** aplikacja zapisuje adres,
   klucz i odcisk certyfikatu, sprawdza połączenie (`GET /system/info` z kluczem, potem pobranie danych) i przechodzi do pulpitu.
2. **Given** brak aparatu lub nieczytelny kod, **When** wybieram „Wpisz ręcznie”, **Then** mogę podać adres i klucz
   (odcisk certyfikatu opcjonalnie), a aplikacja sprawdza je tak samo.
3. **Given** kod QR zawiera `certSha256`, **When** program przedstawia certyfikat o innym odcisku, **Then** aplikacja
   odmawia połączenia z komunikatem „Certyfikat komputera nie zgadza się z kodem QR” i nie wysyła klucza.
4. **Given** adres `http://` (bez szyfrowania), **When** paruję, **Then** aplikacja ostrzega, że połączenie nie jest
   szyfrowane i jest bezpieczne tylko w zaufanej sieci domowej, i wymaga potwierdzenia (adres spoza sieci lokalnej,
   także adres VPN, jest przyjmowany tylko jako `https` — FR-M-POL-06).
5. **Given** program w wersji starszej niż 1.5.0, **When** paruję, **Then** widzę komunikat „Zaktualizuj program na
   komputerze do wersji 1.5.0 lub nowszej” i parowanie się nie kończy.
6. **Given** klucz unieważniony w programie, **When** aplikacja dostaje `401`, **Then** pokazuje „Klucz został
   unieważniony — połącz aplikację ponownie” i przechodzi do ekranu parowania, zachowując kolejkę wysyłki.
7. **Given** sparowana aplikacja, **When** dodaję w ustawieniach aplikacji drugi adres komputera (np. adres VPN, nazwę
   DynDNS albo stały publiczny adres IP), **Then** aplikacja próbuje adresów po kolei i zapamiętuje ostatnio działający;
   adres spoza sieci lokalnej jest przyjmowany tylko jako `https` — z odciskiem certyfikatu z parowania albo, gdy komputer
   jest wystawiony przez pośrednika (reverse proxy) z certyfikatem od zaufanego wystawcy, po potwierdzeniu wystawcy
   i nazwy przez użytkownika (FR-M-POL-05).
7a. **Given** dostęp spoza domu włączony w programie po sparowaniu telefonu (kod QR bez adresu publicznego), **When** dopisuję
   adres publiczny ręcznie, **Then** aplikacja z niego korzysta, o ile klucz ma w programie zgodę na dostęp spoza domu;
   inaczej pokazuje wyjaśnienie (FR-M-POL-11).
7b. **Given** program wygenerował nowy certyfikat (np. po zmianie adresu publicznego), **When** aplikacja łączy się
   z komputerem, **Then** odmawia połączenia z komunikatem „Certyfikat komputera się zmienił — zeskanuj nowy kod QR”
   i nie wysyła klucza; po ponownym sparowaniu kolejka i pamięć podręczna są zachowane.
7c. **Given** zmiana stałego publicznego adresu IP domu, **When** poprawiam adres w ustawieniach aplikacji, **Then**
   aplikacja łączy się pod nowym adresem bez ponownego parowania (jeśli certyfikat się nie zmienił).
7d. **Given** dostęp spoza domu wyłączony w programie (także automatycznie po 30 dniach bez użycia), **When** aplikacja
   łączy się przez adres publiczny albo adres VPN spoza zakresów prywatnych (np. Tailscale), **Then** dostaje `403` bez
   treści, pokazuje „Dostęp spoza domu jest wyłączony w programie” i wstrzymuje żądania do tego adresu (FR-M-POL-13).
8. **Given** komputer wyłączony lub API wyłączone, **When** uruchamiam aplikację, **Then** widzę dane z pamięci
   podręcznej z komunikatem „Komputer nie odpowiada — dane z <data, godzina>”, wskazówką, co sprawdzić
   (komputer włączony, program uruchomiony, API włączone, ta sama sieć Wi‑Fi; poza domem — w programie włączony
   „Dostęp spoza sieci domowej”, także przy VPN z adresami spoza zakresów prywatnych, np. Tailscale) i przyciskiem
   „Odśwież”. Po 3 s komunikat zwija się do pomarańczowej ikonki w prawym górnym rogu paska nawigacji (nie przesuwa treści);
   data danych zostaje jako podtytuł „Dane z …” pod tytułem ekranu.
8a. **Given** działający program, **When** przechodzę między zakładkami po chwili bezczynności telefonu, **Then** nie widzę
   komunikatu „brak połączenia” — zerwany odczyt na „zużytym” połączeniu jest ponawiany raz na tym samym adresie, a potem
   na kolejnych adresach (FR-M-POL-14); odczyt z dowolnego ekranu, który się udał, od razu kasuje komunikat na wszystkich ekranach.
8b. **Given** komunikat „Komputer nie odpowiada”, **When** dotykam „Odśwież” (albo pomarańczowej ikonki), **Then** aplikacja
   sprawdza komputer, a po odpowiedzi kończy tryb bez połączenia, odświeża pamięć i bieżący ekran; gdy komputer nadal nie
   odpowiada — „Komputer nadal nie odpowiada (sprawdzono HH:mm)”. Kilka szybkich naciśnięć daje jedno sprawdzenie.
8c. **Given** tryb bez połączenia i aplikacja na pierwszym planie, **When** komputer wraca, **Then** aplikacja sama to wykrywa
   w ciągu 30 s (też po zmianie sieci i powrocie do aplikacji); w tle nie wysyła żądań sprawdzających.
8d. **Given** telefon bez żadnej sieci, **When** korzystam z aplikacji, **Then** komunikat brzmi „Telefon nie ma połączenia
   z siecią” (bez przycisku sprawdzania; wznowienie samo po powrocie sieci).
8e. **Given** problem wymagający działania (klucz unieważniony, zmieniony certyfikat, klucz tylko do domu, dostęp spoza
   domu wyłączony, blokada adresu), **When** komunikat zwinął się do czerwonej ikonki, **Then** dotknięcie ikonki rozwija
   go i zostaje do zamknięcia (✕).
9. **Given** niepusta kolejka wysyłki, **When** paruję aplikację ponownie (nowy kod QR), **Then** aplikacja sprawdza,
   czy to ta sama stajnia (FR-M-POL-08); jeśli tak, kolejka wysyła się dalej, jeśli nie — kolejka jest wstrzymana,
   a ja wybieram „Wyślij mimo to” albo „Usuń kolejkę”.
10. **Given** sparowana aplikacja, **When** wybieram „Rozłącz”, **Then** po rozłączeniu widzę przypomnienie „Unieważnij
    klucz tego telefonu w programie (Ustawienia → API)”, bo klucz w programie pozostaje ważny.

### US2 — Pulpit i terminy (P1)

Jako właściciel chcę po otwarciu aplikacji od razu widzieć przeterminowane i nadchodzące terminy oraz móc je
załatwić jednym dotknięciem.

**Test niezależny**: w programie są 2 przeterminowane i 3 nadchodzące terminy → w aplikacji pulpit pokazuje je
w dwóch grupach; „Zrealizowany” na jednym z nich → termin znika z pulpitu i w programie ma status Zrealizowany.

**Scenariusze akceptacyjne**:

1. **Given** terminy w programie, **When** otwieram pulpit, **Then** widzę sekcje „Przeterminowane” (od najstarszego,
   wyróżnione kolorem ostrzegawczym), „Nadchodzące (najbliższe N dni)” (N z programu, `horizonDays`) i „Później w tym
   miesiącu”, a pod nimi ostatnie wpisy i koszty bieżącego miesiąca z porównaniem do poprzedniego.
2. **Given** termin na pulpicie, **When** wybieram „Zarejestruj wizytę”, **Then** otwiera się formularz wpisu
   odpowiedniego rodzaju (kowal → wizyta kowala, szczepienie → wizyta weterynaryjna itd.) z uzupełnionym koniem
   i dzisiejszą datą; po zapisie program sam zamyka termin.
3. **Given** termin, **When** wybieram „Zrealizowany” albo „Odrzuć”, **Then** termin znika z listy otwartych
   (od razu w aplikacji; bez połączenia — akcja trafia do kolejki).
4. **Given** termin, **When** wybieram „Przełóż” i nową datę, **Then** termin ma nową datę (tylko z połączeniem).
5. **Given** ekran Terminy, **When** filtruję po koniu, rodzaju i statusie, **Then** widzę pasującą listę;
   domyślnie tylko otwarte.
6. **Given** ekran Terminy, **When** dodaję własny termin (koń, rodzaj, data, tytuł, notatka), **Then** pojawia się
   on na liście i w programie.
7. **Given** źrebak bez paszportu z datą urodzenia, **When** oglądam pulpit, **Then** jego kafel pokazuje
   „bez paszportu od X mies.” (z programu: `monthsWithoutPassport`), wyróżnione od 12 miesięcy.

### US3 — Szybkie dodanie wpisu przy koniu (P1)

Jako właściciel chcę w kilkanaście sekund zapisać wizytę, notatkę albo zakup, zanim zapomnę szczegółów.

**Test niezależny**: dodać wizytę kowala dla konia „Grom” z kosztem 350 zł → wpis widoczny w aplikacji na osi czasu
i w programie; program utworzył termin kolejnej wizyty.

**Scenariusze akceptacyjne**:

1. **Given** dowolny ekran, **When** naciskam „+” (Dodaj wpis), **Then** wybieram rodzaj wpisu i konia (ostatnio
   używany koń jest na górze listy); na karcie konia koń jest już wybrany.
2. **Given** formularz, **When** go otwieram, **Then** data = dziś, widoczne są tylko pola najczęściej używane,
   a pozostałe są w sekcji „Więcej szczegółów”; pola wymagane są oznaczone.
3. **Given** wizyta kowala, **When** wybieram konia i datę, **Then** aplikacja podpowiada datę następnej wizyty
   według interwału konia (`GET /horses/{id}/farrier-next-date`); z połączeniem — z serwera, bez połączenia —
   wyliczoną lokalnie z interwału w pamięci podręcznej. Podpowiedź można zmienić lub usunąć.
4. **Given** wizyta kowala, **When** wybieram „Kilka koni”, **Then** zaznaczam konie i zapisuję jedną wizytę dla
   każdego z nich (osobne wpisy, ten sam kontakt, usługa, koszt na konia).
5. **Given** wizyta weterynaryjna, **When** dodaję leki (nazwa, dawkowanie, podanie/przepisanie), **Then** zapisują
   się razem z wizytą; szczepienie (preparat, numer serii) i „następna wizyta” (data, cel) są dostępne w formularzu.
6. **Given** zakup, **When** podaję ilość i cenę jednostkową, **Then** kwota podpowiada się jako ilość × cena;
   mogę podać koszt dostawy; formularz pokazuje „Razem: <kwota + dostawa>”; przypisanie: jeden koń / kilka koni /
   ogólny (cała stajnia).
7. **Given** start w zawodach, **When** wybieram zawody z listy albo tworzę nowe (nazwa, data, miejscowość),
   **Then** zapisuję start konia: konkurs, jeździec, miejsce, liczba startujących, wynik, ocena 1–5, wpisowe, nagroda;
   jeździec to kontakt typu „Jeździec” wybrany z listy albo dodany bez opuszczania formularza (pole nieobowiązkowe,
   bez podpowiedzi z wcześniejszych startów; dowolny tekst nie jest przyjmowany).
8. **Given** błąd walidacji z programu (`400`), **When** zapisuję, **Then** komunikaty pojawiają się przy
   właściwych polach (nazwy pól z `errors`), a wpisane dane zostają w formularzu.
9. **Given** brak połączenia albo program nie potwierdzi zapisu w ciągu ok. 1 s, **When** zapisuję nowy wpis, **Then**
   widzę „Zapisano — wyślę po połączeniu z komputerem”, wpis jest widoczny na osi czasu konia z oznaczeniem „czeka na
   wysłanie” i wysyła się sam; z połączeniem i szybką odpowiedzią programu widzę „Zapisano” (FR-M-SYN-11).
10. **Given** istniejący wpis, **When** go edytuję i zapisuję (tylko z połączeniem), **Then** zmiana trafia do
    programu; jeśli w międzyczasie ktoś zmienił wpis (`409`), widzę „Wpis został zmieniony w międzyczasie (np. na
    komputerze)” z opcjami „Odśwież” (porzuca moje zmiany) i „Nadpisz moje zmiany”.
11. **Given** istniejący wpis, **When** go usuwam (tylko z połączeniem, z potwierdzeniem), **Then** trafia do kosza
    programu (przywrócić można tylko w programie na komputerze).

### US4 — Zdjęcia i dokumenty (P2)

Jako właściciel chcę dołączyć zdjęcie (np. kopyta, rany, faktury, strony paszportu) do wpisu lub konia prosto
z aparatu.

**Test niezależny**: do wizyty weterynaryjnej dodać 2 zdjęcia z aparatu → w programie wizyta ma 2 załączniki;
w aplikacji widać ich miniatury.

**Scenariusze akceptacyjne**:

1. **Given** formularz wpisu, karta wpisu lub karta konia, **When** wybieram „Dodaj zdjęcie”, **Then** mogę zrobić
   zdjęcie aparatem, wybrać z galerii (kilka naraz) albo wybrać plik (PDF, dokument); mogę dodać opis.
2. **Given** zdjęcie większe niż ustawiony limit (domyślnie dłuższy bok 2560 px), **When** je dodaję, **Then**
   aplikacja je zmniejsza przed wysłaniem (ustawienie „Wysyłaj oryginały” wyłącza zmniejszanie).
3. **Given** plik większy niż 100 MB lub niedozwolonego typu, **When** go wybieram, **Then** widzę komunikat
   i plik nie jest dodawany (dozwolone: jpg, png, heic, webp, pdf, docx, xlsx, txt, mp4, mov).
4. **Given** brak połączenia, **When** dodaję zdjęcie, **Then** trafia do kolejki razem z wpisem, do którego
   należy, i wysyła się po wysłaniu tego wpisu.
5. **Given** załączniki wpisu, **When** je oglądam, **Then** widzę miniatury (`/attachments/{id}/thumbnail`),
   a po dotknięciu pełny plik (`/content`, z obsługą przewijania wideo); ostatnio oglądane pliki są dostępne bez połączenia.
6. **Given** inna aplikacja (galeria, e‑mail, przeglądarka PDF), **When** wybieram „Udostępnij → Zarządzanie końmi”,
   **Then** wybieram konia i wpis (albo tworzę notatkę) i plik zostaje dołączony.
7. **Given** karta konia, **When** ustawiam zdjęcie jako zdjęcie główne konia, **Then** program pokazuje je jako
   zdjęcie konia (`photoAttachmentId`).

### US5 — Praca bez połączenia (P1)

Jako właściciel chcę w stajni bez zasięgu przeglądać dane koni i zapisywać wpisy, które wyślą się same później.

**Test niezależny**: tryb samolotowy → przejrzeć kartę konia i terminy, dodać notatkę ze zdjęciem → wyłączyć
tryb samolotowy w sieci domowej → notatka i zdjęcie są w programie, kolejka jest pusta.

**Scenariusze akceptacyjne**:

1. **Given** wcześniej pobrane dane, **When** nie ma połączenia, **Then** mogę przeglądać pulpit, terminy, listę
   koni, karty koni, oś czasu z ostatnich 12 miesięcy (ustawienie), kontakty i koszty; każdy ekran pokazuje,
   z kiedy są dane.
2. **Given** brak połączenia, **When** dodaję wpis, termin, kontakt, zdjęcie albo oznaczam termin jako
   zrealizowany/odrzucony, **Then** operacja trafia do kolejki wysyłki; edycja i usuwanie istniejących danych
   wymagają połączenia (przyciski są nieaktywne z wyjaśnieniem).
2a. **Given** operacja czekająca w kolejce (np. notatka z literówką), **When** ją otwieram, zanim zacznie się jej
   wysyłanie, **Then** mogę ją poprawić albo usunąć bez połączenia; operacja w trakcie wysyłania jest zablokowana
   (FR-M-SYN-12).
3. **Given** kolejka z kilkoma operacjami, **When** połączenie wraca, **Then** aplikacja wysyła je w kolejności
   dodania (zdjęcie po swoim wpisie), bez udziału użytkownika, także w tle; po wysłaniu odświeża dane.
4. **Given** operacja odrzucona przez program (błąd walidacji, koń usunięty w międzyczasie, konflikt unikalności),
   **When** kolejka ją wysyła, **Then** operacja dostaje status „Wymaga poprawy” z komunikatem programu; mogę ją
   poprawić i wysłać ponownie albo usunąć z kolejki; pozostałe operacje (niezależne od niej) wysyłają się dalej.
4a. **Given** w kolejce „Zrealizowany” lub „Odrzuć” dla terminu, który w międzyczasie zamknięto albo usunięto na
   komputerze, **When** kolejka wysyła tę akcję, **Then** akcja znika z kolejki jako „już załatwione” (widoczna
   w historii kolejki), bez statusu „Wymaga poprawy”.
5. **Given** połączenie przerwane w trakcie wysyłania, **When** aplikacja nie wie, czy program zapisał wpis,
   **Then** nie tworzy duplikatu — także wtedy, gdy w kolejce są dwa celowo identyczne wpisy (oba trafiają do programu;
   FR-M-SYN-06).
6. **Given** kolejka niepusta, **When** zamykam aplikację, restartuję telefon albo aplikacja zostaje zamknięta
   przez system, **Then** kolejka i zdjęcia w niej pozostają i wysyłają się później.
7. **Given** ekran „Kolejka wysyłki”, **When** go otwieram, **Then** widzę operacje czekające, wysyłane i wymagające
   poprawy oraz historię operacji wysłanych i „już załatwionych” z ostatnich 30 dni; licznik niewysłanych operacji jest
   widoczny na głównym ekranie.

### US6 — Karta konia i historia (P2)

Jako właściciel chcę zobaczyć na telefonie wszystko o koniu: dane z paszportu, najbliższe terminy, historię wpisów,
wyniki zawodów i koszty.

**Test niezależny**: otworzyć kartę konia „Grom” → nagłówek ze zdjęciem i numerem paszportu, najbliższe terminy,
oś czasu wpisów, statystyki zawodów, koszty w bieżącym roku zgodne z programem.

**Scenariusze akceptacyjne**:

1. **Given** lista koni, **When** szukam po imieniu lub numerze paszportu, **Then** lista zawęża się na bieżąco;
   domyślnie aktywne konie, przełącznik „Pokaż wszystkie” i „Tylko źrebięta”.
2. **Given** karta konia, **When** ją otwieram, **Then** widzę zdjęcie, imię, rasę, płeć, wiek, status, numer
   paszportu (u źrebaka bez numeru — „brak paszportu”, ewentualnie „bez paszportu od X mies.”), UELN, chip,
   najbliższe terminy i koszty w bieżącym roku z podziałem na kategorie.
3. **Given** karta konia, **When** przewijam oś czasu, **Then** widzę wpisy od najnowszych, doczytywane stronami,
   z filtrem rodzaju wpisu; dotknięcie otwiera szczegóły wpisu z załącznikami.
4. **Given** karta konia, **When** otwieram „Zawody”, **Then** widzę statystyki (starty, zwycięstwa, podia,
   średnia ocena, nagrody, koszty; `GET /horses/{id}/stats/competitions`) i listę startów.
5. **Given** karta konia, **When** otwieram „Paszport”, **Then** widzę dane identyfikacyjne i historię szczepień.
6. **Given** nowy koń, **When** dodaję go (imię, numer paszportu albo zaznaczone „Źrebak”, data urodzenia, płeć,
   rasa), **Then** program zapisuje konia; bez „Źrebak” numer paszportu jest wymagany; imię źrebaka bez paszportu
   musi być unikalne wśród źrebiąt bez paszportu (błąd `409` z programu pokazuję przy polu imienia).
7. **Given** karta konia, **When** edytuję dane (tylko z połączeniem), **Then** obowiązują te same reguły i obsługa
   konfliktu wersji co w US3/10.

### US7 — Powiadomienia o terminach (P2)

Jako właściciel chcę, żeby telefon sam przypomniał mi o kowalu i szczepieniu, także gdy komputer jest wyłączony.

**Test niezależny**: termin na jutro w programie → po odświeżeniu danych i wyłączeniu komputera telefon następnego
dnia o 08:00 pokazuje powiadomienie z tym terminem.

**Scenariusze akceptacyjne**:

1. **Given** otwarte terminy w pamięci podręcznej, **When** nadchodzi godzina dziennego powiadomienia (domyślnie
   08:00, zmienialna), **Then** telefon pokazuje jedno powiadomienie „X przeterminowanych, Y na dziś i jutro”
   (bez połączenia z komputerem); bez takich terminów powiadomienie się nie pojawia.
2. **Given** termin z datą na dziś, **When** włączona opcja „Powiadomienie w dniu terminu”, **Then** telefon
   pokazuje osobne powiadomienie z nazwą konia i tytułem terminu.
3. **Given** powiadomienie, **When** je dotykam, **Then** aplikacja otwiera pulpit albo ten termin.
4. **Given** termin zrealizowany lub przełożony (w aplikacji albo w programie), **When** aplikacja odświeży dane,
   **Then** zaplanowane powiadomienia są aktualizowane (brak powiadomień o załatwionych terminach).
5. **Given** pierwsze włączenie powiadomień, **When** system wymaga zgody, **Then** aplikacja prosi o nią
   z wyjaśnieniem; odmowa nie blokuje reszty aplikacji, a ustawienia pokazują, jak włączyć zgodę później.
5a. (Android — FR-M-POW-05; w iOS nie dotyczy, patrz [9.4](#94-praca-w-tle).)
6. **Given** dane nieodświeżane dłużej niż 7 dni, **When** przychodzi dzienne powiadomienie, **Then** zawiera
   dopisek „Dane z <data> — połącz się z komputerem, aby je odświeżyć”.

### US8 — Kontakty (P3)

Jako właściciel chcę szybko zadzwonić do weterynarza albo kowala i dopisać nowy kontakt.

**Scenariusze akceptacyjne**:

1. **Given** lista kontaktów, **When** szukam po nazwie, telefonie lub e‑mailu i filtruję po typie, **Then** widzę
   pasujące kontakty (bez zarchiwizowanych).
2. **Given** kontakt, **When** dotykam telefonu, e‑maila albo adresu, **Then** otwiera się połączenie, SMS,
   e‑mail albo nawigacja w mapach.
3. **Given** karta kontaktu, **When** ją otwieram, **Then** widzę historię zakupów u tego kontaktu
   z łączną kwotą, a u trenera i jeźdźca — jego treningi (u jeźdźca także starty w zawodach); historia wizyt — gdy
   program ją udostępni ([11.2](#112-zależności)) (z połączeniem).
4. **Given** formularz wpisu, **When** kontaktu nie ma na liście, **Then** mogę go dodać bez opuszczania formularza
   (nazwa, typ, telefon).

### US9 — Raporty (P2)

Jako właściciel chcę na telefonie korzystać z tych samych raportów co w programie — kosztów, bilansu koni,
podsumowania treningów i raportów jeźdźców — razem z wykresami i eksportem do CSV i PDF, np. aby na zawodach pokazać
wyniki konia albo wysłać trenerowi zestawienie jego treningów.

**Test niezależny**: dla tych samych filtrów raport w aplikacji i w programie pokazują te same wiersze i sumy co do
grosza i minuty; plik CSV z aplikacji ma te same kolumny, nagłówki i liczby co eksport CSV programu.

**Scenariusze akceptacyjne**:

1. **Given** ekran „Raporty” (z menu „Więcej”), **When** go otwieram, **Then** wybieram jeden z pięciu raportów
   w kolejności programu: „Koszty”, „Bilans konia”, „Podsumowanie treningów”, „Treningi jeźdźca”, „Zawody jeźdźca”.
2. **Given** „Koszty”, **When** wybieram okres (bieżący miesiąc, poprzedni miesiąc, bieżący rok, poprzedni rok, ostatnie
   12 miesięcy, własny), konie (wszystkie / wybrane / tylko ogólne), kategorie i grupowanie (koń, miesiąc, kategoria),
   **Then** widzę sumy kosztów, przychodów (nagrody) i saldo, listę grup zgodną co do grosza z programem
   (`GET /reports/costs`), wykres słupkowy kosztów miesięcznych skumulowany po kategoriach i wykres kołowy udziału
   kategorii; zakupy ogólne są pokazane osobno jako „Ogólne (stajnia)”.
3. **Given** „Bilans konia”, **When** filtruję po statusie i koniu, **Then** widzę dla każdego konia zakup, koszty
   z całej historii, nagrody, sprzedaż, wynik (zysk / strata opisane słowem, nie tylko kolorem) i wartość
   (informacyjnie), sumę wszystkich koni oraz — po rozwinięciu konia — koszty według lat i kategorii
   (`GET /reports/horse-balance`).
4. **Given** „Podsumowanie treningów”, **When** wybieram konia i zakres (tydzień od poniedziałku, miesiąc, rok,
   wszystko) z przechodzeniem do poprzedniego i następnego okresu (także gestem przesunięcia), **Then** widzę statystyki
   min / średnia / maks. czasu, intensywności, oceny i wysokości przeszkód według rodzaju treningu i łącznie, liczbę
   treningów, łączny czas („23 h 30 min”) i koszt, oraz wykres postępów wybranego parametru (czas, ocena, wysokość
   przeszkód) — przy „Wszystkie rodzaje” osobne serie wyróżnione kolorem i kształtem znacznika
   (`GET /reports/training-summary`).
5. **Given** „Treningi jeźdźca”, **When** wybieram jeźdźca albo „Wszyscy jeźdźcy”, konia i okres, **Then** widzę
   podsumowanie — liczba, łączny czas, średnia ocena, koszt — razem i w podziale na konie albo na jeźdźców, a pod nim
   treningi (data, koń, rodzaj, czas, intensywność, ocena, trener, koszt; przy wszystkich jeźdźcach także jeździec)
   (`GET /reports/rider-trainings`).
6. **Given** „Zawody jeźdźca”, **When** wybieram jeźdźca albo „Wszyscy jeźdźcy”, konia i okres, **Then** widzę
   podsumowanie — liczba zawodów i startów, suma kosztów, suma nagród i różnica — a pod nim zawody z ich startami (data,
   koń, dyscyplina, klasa, wynik / miejsce, wpisowe, pozostałe koszty, nagroda) (`GET /reports/rider-competitions`).
7. **Given** dowolny raport z danymi, **When** wybieram „Eksport CSV” albo „Eksport PDF”, **Then** aplikacja tworzy
   plik w formacie programu z tymi samymi danymi co na ekranie (PDF: nagłówek z filtrami, tabela, wykresy z legendą),
   a ja wybieram „Udostępnij” (e‑mail, komunikator, dysk) albo „Zapisz w plikach”; w PDF czas jest pokazany jak na
   ekranie („2 h 5 min”), w CSV — liczbą minut.
8. **Given** brak danych w wybranym zakresie, **When** otwieram raport, **Then** widzę informację o braku danych
   i zerowe sumy; eksport jest niedostępny.
9. **Given** brak połączenia, **When** otwieram raport, **Then** widzę ostatnio pobraną wersję tego raportu z tymi
   samymi filtrami (z datą pobrania), a dla innych filtrów — informację, że raport wymaga połączenia; eksport danych
   z pamięci podręcznej jest możliwy tylko z wyraźną datą pobrania w nagłówku pliku.

### US10 — Dziennik treningów (P2)

Jako właściciel chcę zaraz po jeździe zapisać trening konia, a przy kolejnym
treningu nie wpisywać od nowa trenera, jeźdźca i kosztu.

**Test niezależny**: dla konia „Grom” zapisać trening „Ujeżdżenie”, 45 min, intensywność średnia, ocena 4, trener
„Anna Nowak”, jeździec „Jan Kowalski”, koszt 120 zł → trening widoczny na zakładce „Treningi” karty konia i w programie;
formularz kolejnego treningu tego konia ma trenera, jeźdźca i koszt wypełnione.

**Scenariusze akceptacyjne**:

1. **Given** formularz treningu, **When** go otwieram, **Then** data = dziś, wybieram konia i rodzaj treningu (słownik
   „Rodzaj treningu” z programu, tylko aktywne pozycje); czas (1–600 min), intensywność (Lekka / Średnia / Ciężka),
   ocena 1–5, opis, trener, jeździec i koszt są nieobowiązkowe; data nie może być z przyszłości.
2. **Given** rodzaj „Skoki” (pozycja słownika z kluczem systemowym `training.jumping`), **When** go wybieram,
   **Then** pojawia się pole wysokości przeszkód (10–200 cm); przy innych rodzajach pole jest ukryte i nie jest wysyłane.
3. **Given** pola „Trener” i „Jeździec”, **When** je otwieram, **Then** wybieram kontakt typu „Trener” albo „Jeździec”
   z listy z wyszukiwaniem (bez zarchiwizowanych) albo dodaję nowy kontakt z tym typem bez opuszczania formularza;
   dowolny tekst nie jest przyjmowany; ta sama osoba może być trenerem i jeźdźcem.
4. **Given** nowy trening konia, który ma wcześniejsze treningi, **When** otwieram formularz albo zmieniam w nim konia,
   **Then** trener, jeździec i koszt (z kwotą w walucie obcej) są wypełnione wartościami z ostatniego treningu tego
   konia, o ile nie zmieniłem ich ręcznie; kontakt zarchiwizowany albo bez odpowiedniego typu nie jest podpowiadany.
   Edycja istniejącego treningu niczego nie podpowiada.
5. **Given** karta konia, **When** otwieram zakładkę „Treningi”, **Then** widzę treningi od najnowszych (data, rodzaj,
   czas w formacie „1 h 5 min” / „45 min”, intensywność, ocena, trener, jeździec, koszt), z filtrem okresu, rodzaju,
   trenera i jeźdźca oraz podliczeniem „Treningów: N · Razem: kwota” dla całego filtra (`totalCount`, `totalCost`
   z programu).
6. **Given** istniejący trening, **When** go edytuję albo usuwam, **Then** obowiązują zasady z US3/10–11 (wersja,
   konflikt, kosz programu).
7. **Given** trening z kosztem, **When** oglądam koszty, **Then** program wlicza go do kategorii „Treningi”
   (aplikacja niczego nie dolicza).
8. **Given** brak połączenia, **When** zapisuję nowy trening, **Then** trafia do kolejki wysyłki jak inne wpisy
   ([US5](#us5--praca-bez-połączenia-p1)); podpowiedź z ostatniego treningu korzysta z pamięci podręcznej.

Treningi nie mają załączników — program 1.6.1 nie przyjmuje plików do treningu.

### US11 — Działy Treningi, Zakupy i Zawody (P1, wersja 1.1 aplikacji)

Jako właściciel chcę mieć w aplikacji te same działy co w menu programu, żeby przeglądać i uzupełniać dane stajni bez
komputera.

**Test niezależny**: w programie treningi dwóch koni, zakup ogólny „Siano” i zawody z dwoma startami → każdy dział w
aplikacji pokazuje te rekordy, a liczby i sumy w stopce są równe stopkom programu dla tych samych filtrów.

**Scenariusze akceptacyjne**:

1. **Given** dolny pasek kart, **When** go oglądam, **Then** zawiera Pulpit · Konie · Terminy · **Treningi** · Więcej; w
   „Więcej”: **Zawody** · **Zakupy** · Kontakty · Raporty, separator, pozycje telefonu zależne od trybu (5.2). Nie ma
   ustawień programu.
2. **Given** dział Treningi, **When** go otwieram, **Then** widzę treningi wszystkich koni od najnowszych (data, koń, rodzaj,
   czas „X h Y min”, wysokość przeszkód przy skokach, trener, koszt, ocena gwiazdkami), filtry w arkuszu u dołu (okres, koń,
   rodzaj, trener, jeździec) i stopkę „Treningów: N · Razem: kwota” z programu dla całego filtra; „+” otwiera formularz
   treningu z wyborem konia.
3. **Given** dział Zakupy, **When** go otwieram, **Then** widzę zakupy (data, produkt, kategoria, dostawca, konie albo
   „Ogólne (stajnia)”, łączna kwota), filtry (okres, kategoria, dostawca, przypisanie: wszystkie / koń / ogólne) i stopkę
   „Zakupów: N · Razem: kwota” (`totalCount`, `totalCost` programu); wiersz otwiera szczegóły zakupu (z „Edytuj”); w menu
   wiersza „Powtórz zakup” (formularz nowego zakupu z danymi tamtego i dzisiejszą datą — jak w programie) i „Usuń”; „+”
   otwiera formularz z przypisaniem „Ogólne (stajnia)”.
4. **Given** dział Zawody, **When** go otwieram, **Then** widzę zawody (nazwa, data od–do, miejscowość, dyscyplina, liczba
   startów, najlepsze miejsce), filtry (okres, dyscyplina, koń); szczegóły pokazują dane zawodów i starty (koń → karta konia,
   jeździec, klasa, wynik/miejsce, ocena gwiazdkami, wpisowe, pozostałe koszty, nagroda), „Dodaj start”, „Edytuj” i „Usuń”
   (z potwierdzeniem; program odmawia usunięcia zawodów ze startami — komunikat programu jest pokazany bez zmian); „+” otwiera
   formularz zawodów (nazwa i data początku wymagane).
5. **Given** dowolny z działów, **When** go otwieram, **Then** okres filtra to cały bieżący rok (od 1 stycznia do 31 grudnia,
   także zawody zaplanowane na później), „Wyczyść filtry” do niego wraca, a filtry zostają do zamknięcia aplikacji.
6. **Given** brak połączenia (tryb online), **When** otwieram dział, **Then** widzę dane z telefonu z oznaczeniem „z pamięci”
   (od 2.0 — pełne dane, sumy wyliczone lokalnie, FR-SYN2-08).

### US12 — Ikony z programu (P2, wersja 1.1 aplikacji; zmienione w 2.0)

Jako właściciel chcę, żeby aplikacja wyglądała jak program na komputerze.

**Scenariusze akceptacyjne**:

1. **Given** zainstalowana aplikacja, **When** oglądam ekran główny telefonu, **Then** ikona aplikacji to biała podkowa
   (wersja 2.0: sama wygięta podkowa z sześcioma otworami, bez konia — FR-KOL-06) na zielonym tle z gradientem programu,
   z wariantem ciemnym i barwionym (iOS 18+), a pod ikoną widnieje „Horsely”.
2. **Given** dolny pasek kart i listy koni, **When** je oglądam, **Then** „Konie” oznacza głowa konia z programu (wersja 2.0:
   dokładniejszy kontur — FR-KOL-05), nie odcisk łapy ani symbol systemowy.

---

## 3.1 Historie wersji 2.0

Wersja 2.0 trzyma w telefonie wszystkie dane (tryb online: pełna praca offline z edycją i synchronizacją), wprowadza
tryb samodzielny bez programu, kopię zapasową, zdjęcie konia z telefonu, więcej kolorów i nowe ikony. Wymagania: [4.12](#412-wersja-20--tryby-pracy-praca-offline-kopia-zapasowa-kolory-zdjęcie-konia).

### US2.0-1 — Wybór trybu pracy przy pierwszym uruchomieniu (P1)

**Test niezależny**: świeża instalacja → ekran powitalny z dwiema opcjami → „Nie, używaj samodzielnie” → „Dalej” →
Pulpit bez danych; zamknąć i otworzyć aplikację → od razu Pulpit, bez pytania.

1. **Given** pierwsze uruchomienie, **When** aplikacja się otwiera, **Then** widzę ekran z tytułem „Horsely – Zarządzanie
   Koniem, Trening i Budżet” i pytaniem „Czy masz program na komputerze?”:

   ```text
   ● Tak, połącz z programem
     Wspólne dane z komputerem, raporty
     i kopie zapasowe w programie.

   ○ Nie, używaj samodzielnie
     Wszystko zapisuje się w telefonie.
     Zadbaj o kopię zapasową.

   [ Dalej ]
   Zmienisz to w Ustawieniach → Tryb pracy.
   ```

   Domyślnie zaznaczone „Tak, połącz z programem”; po wyborze „Nie, używaj samodzielnie” widoczne jest także „Odtwórz z kopii
   zapasowej”.
2. **Given** „Tak, połącz z programem”, **When** dotykam „Dalej”, **Then** przechodzę do parowania (kod QR / wpisz ręcznie);
   tryb online zostaje zapamiętany dopiero po udanym połączeniu.
3. **Given** „Nie, używaj samodzielnie”, **When** dotykam „Dalej”, **Then** po zgodzie na powiadomienia widzę pusty Pulpit
   z podpowiedzią „Dodaj pierwszego konia”, a aplikacja nie łączy się z żadnym komputerem.
4. **Given** parowanie przerwane (powrót z ekranu skanowania), **When** wracam, **Then** widzę ponownie ekran wyboru trybu.

### US2.0-2 — Praca samodzielna bez programu (P1)

**Test niezależny**: tryb samodzielny w trybie samolotowym → dodać 2 konie, wizytę kowala z datą następnej wizyty,
zakup paszy dla obu koni za 100,01 zł, trening z kosztem → na Pulpicie termin kowala; w raporcie Koszty 50,01 zł
i 50,00 zł (różnica groszowa u pierwszego konia wg imienia); usunąć trening → jest w koszu, przywrócić → wraca.

1. **Given** tryb samodzielny, **When** korzystam z aplikacji, **Then** wszystkie funkcje trybu online działają bez
   połączenia (w tym dodanie konia, edycja, usuwanie, „Przełóż”), a nigdzie nie widzę komunikatów o połączeniu z komputerem,
   kolejce wysyłki ani dacie danych.
2. **Given** zapis wpisu z datą następnej wizyty, **When** zapisuję, **Then** powstaje termin tak jak w programie, a
   rejestracja wizyty zamyka pasujący otwarty termin (także do 14 dni przed terminem).
3. **Given** zakup dla kilku koni albo zmiana statusu konia na „Padł”, **When** zapisuję, **Then** koszt dzieli się po
   równo z różnicą groszową u pierwszego konia wg imienia, a „Padł” ustawia cenę sprzedaży 0 — tak jak program.
4. **Given** dane niezgodne z regułami programu (np. brak wymaganego pola, powtórzony unikalny numer), **When** zapisuję,
   **Then** widzę przy polu ten sam komunikat, który pokazałby program, a dane nie są zapisane.
5. **Given** usunięcie wpisu, konia lub kontaktu, **When** potwierdzam, **Then** trafia do kosza (Więcej → Kosz), skąd mogę
   go przywrócić albo trwale usunąć po dodatkowym potwierdzeniu; kontaktu użytego jako trener lub jeździec nie da się usunąć,
   tylko zarchiwizować.
6. **Given** słowniki, **When** zaczynam pracę samodzielną, **Then** mam domyślny zestaw wartości jak w nowym programie
   2.0.0 i mogę dodać, zmienić nazwę, zmienić kolejność i ukryć wartość; wartości systemowych i używanych nie da się usunąć.
7. **Given** dowolny z pięciu raportów, **When** wybieram filtry, **Then** widzę sumy, wykresy, wiersze i mogę wyeksportować
   CSV i PDF — wyniki takie, jakie dałby program dla tych samych danych.

### US2.0-3 — Pełna praca offline w trybie online (P1)

**Test niezależny**: tryb samolotowy → poprawić opis wizyty, usunąć trening, przełożyć termin, dodać konia → w programie
zmienić opis tej samej wizyty → wyłączyć tryb samolotowy → koń, usunięcie i przełożenie są w programie, a dla wizyty
pojawia się konflikt do rozstrzygnięcia; po rozstrzygnięciu kolejka jest pusta.

1. **Given** tryb online po pierwszym pełnym pobraniu, **When** nie ma połączenia, **Then** widzę wszystkie dane programu
   (wszystkie konie, wpisy i treningi z całej historii, terminy we wszystkich statusach, kontakty, zakupy, zawody i starty,
   słowniki) z informacją, z kiedy są dane.
2. **Given** brak połączenia, **When** edytuję, usuwam, przekładam termin albo dodaję konia, **Then** zmiana zapisuje się
   od razu w telefonie, jest widoczna na wszystkich ekranach z oznaczeniem „czeka na wysłanie” i trafia do kolejki.
3. **Given** kolejne zmiany tego samego rekordu bez połączenia, **When** połączenie wraca, **Then** do programu trafia stan
   końcowy rekordu, bez pośrednich wersji i bez duplikatów.
4. **Given** rekord zmieniony w telefonie i w międzyczasie w programie (albo zmieniony w jednym, a usunięty w drugim),
   **When** kolejka wysyła zmianę, **Then** aplikacja pokazuje konflikt z wyborem „Zachowaj moją” / „Przyjmij z programu”;
   przy kilku konfliktach mogę rozstrzygnąć wszystkie naraz („Zachowaj wszystkie moje” / „Przyjmij wszystkie z programu”)
   po potwierdzeniu z ich liczbą; żadna zmiana nie ginie bez wiedzy użytkownika.
5. **Given** raport otwarty bez połączenia, **When** go oglądam, **Then** jest wyliczony z danych w telefonie (z niewysłanymi
   zmianami) z oznaczeniem „z pamięci — może różnić się od programu”; po połączeniu obowiązują wartości z programu.
6. **Given** pierwsze pełne pobranie danych, **When** trwa, **Then** odbywa się w tle z widocznym postępem (baner na Pulpicie),
   a aplikacja jest w tym czasie używalna.

### US2.0-4 — Zmiana trybu pracy w Ustawieniach (P2)

**Test niezależny**: tryb samodzielny z 2 końmi → Ustawienia → Tryb pracy → „Połącz z programem” → ostrzeżenie →
anuluj → dane bez zmian; ponownie → „Utwórz kopię zapasową” → potwierdzić → zeskanować kod QR → dane z programu
zamiast lokalnych; kopia zapasowa istnieje.

1. **Given** Ustawienia → Tryb pracy, **When** otwieram ekran, **Then** widzę bieżący tryb, jego opis i przycisk zmiany.
2. **Given** tryb samodzielny, **When** wybieram „Połącz z programem”, **Then** widzę okno „Połączyć z programem?” z treścią
   „Dane zapisane w telefonie (X koni, Y wpisów) zostaną usunięte i zastąpione danymi z programu. Ostatnia kopia zapasowa:
   <data | brak>.” i przyciskami „Utwórz kopię zapasową”, „Anuluj”, „Dalej”; potem drugie okno z „Usuń dane i połącz”
   (styl niszczący, nie domyślny) / „Anuluj”.
3. **Given** potwierdzone przejście na online, **When** parowanie się nie uda albo je przerwę, **Then** dane lokalne pozostają
   nietknięte, a aplikacja zostaje w trybie samodzielnym; dane są usuwane dopiero po udanym połączeniu.
4. **Given** tryb online, **When** wybieram „Pracuj samodzielnie”, **Then** widzę: „Dane z programu zostaną w telefonie jako
   punkt startowy. Od tej chwili telefon i program będą prowadzone osobno. Niewysłane zmiany: N — nie trafią do programu.”
   → „Pracuj samodzielnie” / „Anuluj”; połączenie i klucz są usuwane.
5. **Given** przejście z online na samodzielny przy niepełnych danych (np. brak oryginałów załączników), **When** potwierdzam,
   **Then** aplikacja najpierw je pobiera; bez połączenia przejście jest możliwe tylko po ostrzeżeniu, czego brakuje.

### US2.0-5 — Kopia zapasowa w trybie samodzielnym (P2)

**Test niezależny**: tryb samodzielny z końmi, wpisami i zdjęciami → „Utwórz kopię zapasową” do pliku → usunąć aplikację →
zainstalować → „Nie, używaj samodzielnie” → „Odtwórz z kopii” → wszystkie dane i zdjęcia są takie jak przed usunięciem.
Ten sam plik odtworzony w aplikacji na Androida (i odwrotnie) daje te same dane (FR-KOP-09).

1. **Given** tryb samodzielny, **When** wybieram Więcej → Kopia zapasowa → „Utwórz kopię zapasową”, **Then** wybieram miejsce
   i nazwę pliku (domyślnie z datą), opcjonalnie hasło (wpisywane dwa razy, z ostrzeżeniem), a aplikacja zapisuje wszystkie
   dane, słowniki, kosz i załączniki w jednym pliku, z postępem i informacją o rozmiarze.
2. **Given** plik kopii, **When** wybieram „Odtwórz z kopii”, **Then** widzę datę kopii, liczbę koni i wpisów, ostrzeżenie
   „Obecne dane zostaną zastąpione” → „Odtwórz” / „Anuluj”; przerwane odtwarzanie nie zostawia danych częściowych.
3. **Given** brak kopii od 7 dni przy zmianach danych, **When** otwieram Pulpit, **Then** widzę przypomnienie „Zadbaj o kopię
   zapasową” z akcjami „Utwórz teraz” i „Przypomnij później”; przy udanej kopii automatycznej przypomnienia nie ma.
4. **Given** plik uszkodzony, niekompletny, z nowszej wersji aplikacji albo błędne hasło, **When** próbuję go odtworzyć,
   **Then** widzę zrozumiały komunikat („Nieprawidłowe hasło”, „Plik uszkodzony lub niekompletny”, „Kopia z nowszej wersji
   aplikacji”), a obecne dane pozostają bez zmian.

### US2.0-6 — Więcej kolorów i nowe ikony (P3)

**Test niezależny**: oś czasu konia z wpisami 8 rodzajów → każdy rodzaj ma inny kolor ikony i paska, taki sam na Pulpicie,
w menu „Więcej” i w formularzu; w motywie ciemnym kolory są czytelne.

1. **Given** oś czasu, „Ostatnie wpisy” lub listy działów, **When** je oglądam, **Then** każdy wpis ma ikonę i pasek w kolorze
   swojego rodzaju (FR-KOL-01, [5.4](#54-wzorzec-wyglądu)).
2. **Given** „Więcej” i dolny pasek kart, **When** je oglądam, **Then** ikony działów mają kolory działów (FR-KOL-03).
3. **Given** formularz wpisu, **When** go otwieram, **Then** nagłówek formularza ma akcent koloru rodzaju wpisu.
4. **Given** motyw jasny i ciemny, tekst 200 % i VoiceOver, **When** oglądam kolorowe elementy, **Then** spełniają kontrast
   WCAG 2.1 AA, a kolor nigdy nie jest jedynym nośnikiem informacji.

### US2.0-7 — Zdjęcie konia z telefonu (P2)

**Test niezależny**: karta konia bez zdjęcia → dotknąć miejsca na zdjęcie → „Zrób zdjęcie” → wykadrować → „Zapisz” →
zdjęcie w nagłówku karty, na kaflu konia na Pulpicie i (w trybie online) w programie; ponownie → „Wybierz z telefonu”
→ nowe zdjęcie, stare jest w zakładce „Załączniki”.

1. **Given** karta konia, **When** dotykam zdjęcia (albo miejsca z ikoną głowy konia i podpisem „Dodaj zdjęcie”), **Then**
   widzę arkusz: „Zrób zdjęcie”, „Wybierz z telefonu”, „Wybierz z załączników konia” oraz — gdy koń ma zdjęcie — „Pokaż
   zdjęcie” i „Usuń zdjęcie”. Ten sam wybór ma pole „Zdjęcie” w formularzu konia.
2. **Given** zrobione lub wybrane zdjęcie, **When** pojawia się ekran kadrowania, **Then** przesuwam i powiększam kwadratowy
   kadr, mogę obrócić zdjęcie o 90°; „Zapisz” ustawia wykadrowane zdjęcie, „Anuluj” niczego nie zmienia.
3. **Given** koń ze zdjęciem, **When** ustawiam nowe albo wybieram „Usuń zdjęcie”, **Then** poprzednie zostaje w załącznikach
   konia; bez zdjęcia koń ma ikonę głowy konia.
4. **Given** Pulpit, **When** oglądam kafle koni, **Then** każdy kafel ma miniaturę zdjęcia (bez zdjęcia — głowę konia); kafel
   nie pozwala zmienić zdjęcia.
5. **Given** tryb online bez połączenia, **When** ustawiam zdjęcie, **Then** widzę je od razu z oznaczeniem „czeka na
   wysłanie”, a po połączeniu trafia do programu (najpierw plik, potem zmiana konia).

**Przypadki brzegowe 2.0**: brak miejsca podczas pełnego pobrania, zapisu zdjęcia lub kopii — operacja przerywa się bez
uszkodzenia danych z komunikatem, ile miejsca brakuje (tryb samodzielny ostrzega poniżej 500 MB wolnego miejsca); przerwane
pełne pobranie wznawia się od miejsca przerwania; konflikt na rekordzie zależnym (wpis konia usuniętego w programie) pokazuje
oba fakty; długa praca offline (setki zmian) wysyła się w tle z postępem i limitem żądań; automatyczna kopia przy niedostępnym
folderze — powiadomienie z przyczyną; usunięta blokada ekranu telefonu wyłącza blokadę aplikacji z informacją; unieważniony
klucz — zmiany czekają do ponownego parowania z tym samym programem; zmiana strefy czasowej nie zmienia dat; odtworzenie kopii
w trybie online jest niedostępne; „Wyczyść pamięć podręczną” w trybie samodzielnym nie istnieje; jedno dotknięcie nigdy nie
usuwa danych (dwa kroki, przycisk usuwający oddzielony od domyślnego).

## 3.2 Historie wersji 2.0.1

Wymagania: [4.13](#413-wersja-201--horsely-i-program-200).

### US2.0.1-1 — Słowniki rodzajów treningów jak w programie 2.0.0 (P1)

1. **Given** nowa instalacja, **When** wybieram tryb samodzielny, **Then** rodzaje treningów to: Ujeżdżenie, Skoki, Teren,
   Lonża, Karuzela, Spacer, Zajeżdżanie, Gimnastyka, Wszechstronny, Inne — w tej kolejności; pozostałe słowniki są identyczne
   z programem 2.0.0.
2. **Given** tryb samodzielny z 7 rodzajami (stan sprzed 2.0.1, np. z kopii zapasowej), **When** aplikacja ich używa pierwszy
   raz, **Then** Zajeżdżanie, Gimnastyka i Wszechstronny są dopisane na końcu, jako aktywne; istniejące wartości się nie
   zmieniają, a wartość o tej samej nazwie (bez względu na wielkość liter, polskie znaki i spacje, także nieaktywna) nie jest
   dublowana; usunięty dopisany rodzaj nie wraca.
3. **Given** tryb online, **When** aplikacja pobiera dane, **Then** rodzaje treningów są dokładnie takie jak w programie.

### US2.0.1-2 — Status konia „Kontuzjowany” (P1)

1. **Given** koń kontuzjowany, **When** oglądam listę koni lub kartę konia, **Then** widzę plakietkę „Kontuzjowany” z ikoną
   plastra w kolorze ostrzegawczym (informacja nigdy tylko kolorem).
2. **Given** koń kontuzjowany, **When** patrzę na Pulpit, **Then** na kaflu konia w prawym górnym rogu jest pomarańczowa
   ikona plastra; VoiceOver czyta kafel „<imię>, kontuzjowany”; w wierszu listy koni pod imieniem — ikona i napis
   „Kontuzjowany”; po zmianie statusu na „Aktywny” znikają.
3. **Given** koń kontuzjowany, **When** korzystam z wyboru konia, Pulpitu, raportów i wyszukiwania, **Then** jest uwzględniony
   wszędzie tam, gdzie koń aktywny.
4. **Given** lista koni, **When** filtruję po statusie, **Then** „Kontuzjowany” pokazuje tylko kontuzjowane, „Aktywny” tylko
   aktywne, a widok domyślny — aktywne i kontuzjowane.
5. **Given** koń aktywny, **When** zmieniam status na „Kontuzjowany” (z datą i notatką), a potem z powrotem na „Aktywny”,
   **Then** obie zmiany są zapisane (w trybie online — także w programie).
6. **Given** koń kontuzjowany, **When** zapisuję mu trening, **Then** aplikacja pyta „Koń jest kontuzjowany. Zapisać trening?”
   („Zapisz” / „Anuluj” — powrót do formularza bez utraty danych).
7. **Given** tryb online z programem 1.6.1, **When** otwieram formularz konia, **Then** status „Kontuzjowany” i filtr
   „Kontuzjowany” nie są dostępne.

### US2.0.1-3 — Nazwa Horsely (P2)

1. **Given** zainstalowana aplikacja, **When** patrzę na ekran główny i przełącznik aplikacji, **Then** widzę „Horsely”.
2. **Given** ekran powitalny i „O aplikacji”, **When** je otwieram, **Then** widzę „Horsely – Zarządzanie Koniem, Trening i Budżet”.
3. **Given** dowolny tekst mówiący o programie (parowanie, połączenie, kopia, PDF, powiadomienia), **When** jest pokazywany,
   **Then** mówi o „programie Horsely”; stara nazwa nie występuje nigdzie w interfejsie.

### US2.0.1-4 — Szybsza i pewniejsza synchronizacja z programem 2.0.0 (P2)

1. **Given** program z `dataStamp`, **When** odświeżam, a stempel się nie zmienił, **Then** nic nie jest pobierane, a „dane z”
   się odświeża.
2. **Given** program z `updatedSince`, **When** odświeżam po wcześniejszym pobraniu, **Then** pobierane są tylko zmiany,
   rekordy z kosza i trwale usunięte znikają z telefonu, a punkt kolejnego pobrania jest zapamiętany; gdy program żąda pełnego
   pobrania — aplikacja je wykonuje, chroniąc kolejkę i konflikty.
3. **Given** program z `ifMatchDelete`, **When** kolejka usuwa rekord zmieniony w międzyczasie w programie, **Then** powstaje
   konflikt — bez osobnego sprawdzania wersji.
4. **Given** program z `idempotencyKey`, **When** przerwane dodanie jest ponawiane, **Then** w programie powstaje dokładnie
   jeden rekord — bez „licznika przed i po”.
5. **Given** program z `horsePhotoField`, **When** ustawiam lub usuwam zdjęcie konia, **Then** zmiana trafia do programu jako
   zmiana konia.
6. **Given** program 1.6.1, **When** aplikacja synchronizuje, **Then** działa jak 2.0 i nie wysyła nowych parametrów ani nagłówków.

### US2.0.1-5 — Czytelne „Więcej szczegółów” w raportach (P1)

1. **Given** „Bilans konia” z koniem, którego uwagi to „strata; brak ceny zakupu; koń nie sprzedany (wynik bieżący)”,
   **When** rozwijam „Więcej szczegółów”, **Then** etykieta „Uwagi” jest całym słowem, a treść zawija się w kolejnych liniach.
2. **Given** dowolny raport, tekst 200 % i ekran 320 pt, **When** przeglądam karty, **Then** ani etykieta, ani wartość nie są
   ściśnięte do pojedynczych liter; gdy się nie mieszczą, wartość przechodzi pod etykietę.

### US2.0.1-6 — Dziennik diagnostyczny (P2)

1. **Given** Ustawienia → Połączenie z programem, **When** włączam „Szczegółowy dziennik połączeń”, **Then** każde żądanie
   do programu jest zapisywane: czas, metoda i ścieżka (bez parametrów zapytania), adres z listy (host i port), IP faktycznego
   połączenia, lokalny/zewnętrzny, sieć telefonu (Wi‑Fi / komórkowa / brak), wynik (kod albo rodzaj błędu: brak połączenia,
   przekroczony czas, odrzucony certyfikat, adres pominięty przez „tylko przez Wi‑Fi”, adres wstrzymany) i czas trwania;
   pod przełącznikiem „Włączony do <data, godzina>”; po 7 dniach wyłącza się sam.
2. **Given** Ustawienia → O aplikacji → Dziennik diagnostyczny, **When** go otwieram, **Then** widzę wpisy od najnowszych
   (czcionka o stałej szerokości), rozmiar, „Wyślij” i „Wyczyść” (z potwierdzeniem „Wyczyścić dziennik diagnostyczny? Wpisy
   zostaną usunięte z telefonu.”); pusty — „Dziennik jest pusty.”.
3. **Given** dowolny wpis, **When** jest zapisywany lub pokazywany, **Then** nie zawiera klucza API, treści wpisów, nazw koni,
   danych kontaktów ani parametrów zapytań.

---

## 4. Wymagania funkcjonalne

Identyfikatory: `FR-M-<obszar>-<nr>`. Słowa MUST/SHOULD jak w RFC 2119.

### 4.1 Połączenie i parowanie (`POL`)

- **FR-M-POL-01**: Aplikacja MUST umożliwiać parowanie przez zeskanowanie kodu QR z programu. Kod zawiera JSON
  `{"url": "<adres bazowy API>", "key": "hk_…", "certSha256": "<HEX>" | null, "remoteUrl": "<adres publiczny API>"}`
  (`remoteUrl` opcjonalne, od programu 1.2; [6.2](#62-kod-qr-parowania)).
- **FR-M-POL-02**: Aplikacja MUST umożliwiać ręczne wpisanie adresu, klucza i opcjonalnie odcisku certyfikatu.
- **FR-M-POL-03**: Przed zapisaniem parowania aplikacja MUST sprawdzić połączenie: `GET /system/info` i jedno pobranie
  danych (np. `GET /dictionaries`); wynik (wersja programu, liczba koni) pokazuje użytkownikowi. Aplikacja MUST wysyłać
  klucz w **każdym** żądaniu, także do `/system/info` i przy sprawdzaniu dostępności adresów (FR-M-POL-07): program 1.2
  traktuje żądanie z internetu bez klucza jako nieudaną próbę, a 10 takich prób w 10 minut blokuje adres telefonu.
- **FR-M-POL-04**: Aplikacja MUST odmówić współpracy z programem w wersji niższej niż 1.5.0, z komunikatem o aktualizacji
  (w programie 1.1–1.4 jeździec był tekstem, a typy kontaktu „Trener” i „Jeździec” nie istniały).
- **FR-M-POL-05**: Każdy adres `https` MUST mieć własny tryb zaufania:
  - **przypięty odcisk** — adresy z kodu QR i adresy, których certyfikat ma odcisk SHA‑256 z parowania: aplikacja MUST
    akceptować wyłącznie certyfikat o tym odcisku i MUST NOT wysyłać klucza do serwera z innym certyfikatem;
  - **zaufany wystawca** — tylko adres dopisany ręcznie, którego certyfikat nie ma odcisku z parowania, ale ma ważny
    łańcuch od urzędu certyfikacji zaufanego przez system i nazwę hosta zgodną z adresem (np. reverse proxy z certyfikatem
    Let's Encrypt pod nazwą DynDNS): przed pierwszym użyciem aplikacja MUST pokazać wystawcę i nazwę z certyfikatu
    i wymagać potwierdzenia użytkownika; potwierdzenie zapisuje tryb dla tego adresu;
  - certyfikat samopodpisany bez znanego odcisku, nieważny albo z niezgodną nazwą hosta MUST być odrzucany.
- **FR-M-POL-06**: Połączenie `http://` MUST być dozwolone tylko z adresem w sieci lokalnej — wyłącznie prywatny adres
  IPv4/IPv6 podany wprost albo nazwa `.local` — i tylko po świadomym potwierdzeniu ostrzeżenia o braku szyfrowania. Każda
  inna nazwa (także nazwa z routera rozwiązywana na adres prywatny) i każdy adres spoza sieci lokalnej (nazwa DynDNS,
  publiczny IP, adres VPN) MUST używać `https` (FR-M-POL-05); `http` do takiego adresu MUST być odrzucane. Ustawienia
  MUST pokazywać dla każdego adresu, czy połączenie jest szyfrowane i w jakim trybie zaufania.
- **FR-M-POL-07**: Aplikacja MUST obsługiwać listę adresów komputera (adres z QR + dodatkowe, np. adres VPN),
  próbować ich po kolei z krótkim limitem czasu (≤ 3 s na adres) i zapamiętywać ostatnio działający. Adres
  `remoteUrl` z kodu QR (program 1.2) MUST być dodawany do listy automatycznie jako drugi, po adresie lokalnym.
  Adresy (także publiczne: nazwa DynDNS albo stały adres IP) MUST dać się dodawać, poprawiać i usuwać w ustawieniach
  aplikacji; adres spoza sieci lokalnej MUST używać `https` w jednym z trybów zaufania z FR-M-POL-05.
- **FR-M-POL-11**: Odpowiedź `403` z adresu publicznego („Ten klucz działa tylko w sieci domowej”) MUST być pokazana
  z wyjaśnieniem, że klucz nie ma w programie zgody na dostęp spoza domu (Ustawienia → API → klucz), i wskazówką, że
  w domowej sieci Wi‑Fi aplikacja działa. Odpowiedź `429` z `Retry-After` MUST wstrzymać wszystkie żądania do tego adresu
  do podanego czasu, bez ponawiania w pętli; przy oczekiwaniu dłuższym niż minuta (blokada adresu) aplikacja MUST
  pokazać „Program zablokował adres sieci, z której się łączysz, do <godzina>. Połącz się przez Wi‑Fi albo odblokuj
  adres w programie (Ustawienia → API → Zablokowane adresy)” — w sieci komórkowej wiele telefonów może mieć ten sam
  publiczny adres, więc blokada może wynikać z cudzych prób.
- **FR-M-POL-12**: Po odpowiedzi `401` lub `403` aplikacja MUST wstrzymać wszystkie żądania z tym kluczem do tego adresu
  (także wysyłkę kolejki i odświeżanie w tle) do czasu działania użytkownika (ponowne parowanie, „Sprawdź połączenie”),
  aby powtarzane odmowy nie doprowadziły do zablokowania adresu telefonu. Pozostałe adresy z listy mogą być używane.
- **FR-M-POL-13**: Odpowiedź `403` **bez treści** z adresu spoza sieci lokalnej oznacza, że tryb „Dostęp spoza sieci
  domowej” jest w programie wyłączony (nigdy niewłączony, wyłączony ręcznie albo automatycznie po 30 dniach bez użycia).
  Aplikacja MUST pokazać „Dostęp spoza domu jest wyłączony w programie. Włącz go na komputerze (Ustawienia → API →
  Dostęp spoza sieci domowej) albo połącz się przez domowe Wi‑Fi” i MUST NOT prowadzić do ponownego parowania (klucz
  pozostaje ważny). Dotyczy także adresów VPN spoza zakresów prywatnych (np. Tailscale `100.64.0.0/10`), które program 1.2
  traktuje jak internet. Obowiązuje wstrzymanie żądań z FR-M-POL-12.
- **FR-M-POL-08**: Odpowiedź `401` MUST prowadzić do ekranu ponownego parowania z zachowaniem pamięci podręcznej
  i kolejki. `GET /system/info` nie zawiera identyfikatora instalacji programu, więc po ponownym parowaniu przy niepustej
  kolejce aplikacja MUST sprawdzić, czy to ta sama stajnia: konie, do których odwołuje się kolejka, MUST istnieć w programie
  z tym samym `id`, imieniem i numerem paszportu; gdy kolejka nie odwołuje się do koni (np. tylko nowy kontakt albo zakup
  ogólny), MUST zgadzać się co najmniej jeden koń z pamięci podręcznej. Wynik pozytywny — kolejka wysyła się dalej;
  negatywny — kolejka jest wstrzymana, a użytkownik wybiera „Wyślij mimo to” albo „Usuń kolejkę”.
- **FR-M-POL-09**: „Rozłącz” w ustawieniach MUST usuwać klucz, pamięć podręczną i zaplanowane powiadomienia;
  jeśli kolejka jest niepusta, aplikacja MUST ostrzec, że niewysłane wpisy zostaną utracone. Po rozłączeniu aplikacja
  MUST przypomnieć, że klucz w programie pozostaje ważny i należy go unieważnić (Ustawienia → API).
- **FR-M-POL-10**: Aplikacja MUST być sparowana z jednym programem naraz (jedna stajnia).
- **FR-M-POL-14** (wersja 1.1): Odczyty (GET) zerwane po nawiązaniu połączenia MUST być ponawiane raz na tym samym adresie, a
  potem na kolejnych adresach niezależnie od tego, czy nagłówki zdążyły wyjść; zapisy (POST/PUT/DELETE) po wysłaniu treści
  MUST NOT być ponawiane poza kolejką. Limity: połączenie ≤ 3 s na adres, odpowiedź 30 s, przesyłanie plików przerywane po
  60 s bez postępu; czas oczekiwania na ogranicznik tempa nie wlicza się do limitów.
- **FR-M-POL-15** (wersja 1.1): Stan „brak połączenia” MUST być jeden dla całej aplikacji i aktualizowany wynikiem **każdego**
  żądania do programu (odpowiedź z dowolnym kodem HTTP = komputer odpowiada); udany odczyt z dowolnego ekranu kasuje go od
  razu. Zmiana zakładki ani ekranu MUST NOT zmieniać tego stanu ani wywoływać komunikatu.
- **FR-M-POL-16** (wersja 1.1): „Odśwież” MUST zwalniać wstrzymania czasowe (nie odrzucony klucz i nie zmieniony certyfikat),
  pytać adresy o `GET /system/info`, a po odpowiedzi odświeżać pamięć (bez progu 5 minut) i bieżący ekran; jedno sprawdzanie
  naraz. W trybie bez połączenia na pierwszym planie aplikacja MUST sprawdzać komputer co 30 s oraz po zmianie sieci i
  powrocie na pierwszy plan; w tle MUST NOT wysyłać takich żądań. Brak jakiejkolwiek sieci w telefonie ma osobny komunikat
  „Telefon nie ma połączenia z siecią”.
- **FR-M-POL-17** (wersja 1.1): Komunikat o problemie z połączeniem MUST być nakładką nad treścią (nie przesuwa układu),
  zwijaną po 3 s (lub dłuższym czasie, gdy włączone są ustawienia dostępności wydłużające czas komunikatów, np. VoiceOver)
  do ikonki w prawym górnym rogu paska nawigacji (pomarańczowa: brak połączenia/sieci; czerwona: wymaga działania). Rozwija
  się tylko przy pojawieniu się problemu albo zmianie jego rodzaju. Data danych nieaktualnych MUST być podtytułem „Dane z …”
  w pasku nawigacji. W trybie samodzielnym ikonki i komunikatu nie ma (FR-TRB-08).

### 4.2 Synchronizacja, pamięć podręczna i kolejka (`SYN`)

> **Wersja 2.0.** Pamięć podręczna jest zastąpiona magazynem lokalnym ze wszystkimi danymi programu (FR-SYN2-01…09, [4.12](#412-wersja-20--tryby-pracy-praca-offline-kopia-zapasowa-kolory-zdjęcie-konia);
> od 2.0.1 z możliwościami programu 2.0.0 — FR-014…FR-020, [4.13](#413-wersja-201--horsely-i-program-200)):
> pełne pobranie `GET /export` (start, powrót na pierwszy plan po 15 min, ręcznie, w tle co godzinę), uzgadnianie wg wersji rekordów
> (`If-Match`), operacje `Update`/`Delete` w kolejce łączone przed wysyłką, konflikty rozstrzygane przez użytkownika, tryb zgodności
> z programem bez wersji rekordów (edycja i usuwanie wymagają wtedy aktualizacji programu). Poniższe wymagania 1.x opisują zachowanie
> do wersji 1.2; tam, gdzie mówią o „pamięci podręcznej”, w wersji 2.0 czytaj „magazyn lokalny”.

- **FR-M-SYN-01**: Pamięć podręczna MUST obejmować: informacje o programie, słowniki (`GET /dictionaries`), konie
  (wszystkie statusy), kontakty, otwarte terminy, pulpit, oś czasu każdego aktywnego konia za ostatnie 12 miesięcy
  (ustawienie 3/12/24 miesiące), a od wersji 1.1 także dane działów za ostatnie 12 miesięcy niezależnie od tego ustawienia:
  treningi wszystkich koni jednym zapytaniem (`GET /trainings?from=`), zakupy (`GET /purchases?from=`), zawody
  (`GET /competitions?from=`) i starty (`GET /competition-starts?from=`), miniatury zdjęć koni, raport kosztów bieżącego roku, ostatnio otwarte raporty (każdy z filtrami, z którymi
  go pobrano; do 20 ostatnich) i ostatnio oglądane załączniki
  (limit miejsca, domyślnie 200 MB, najstarsze usuwane jako pierwsze).
- **FR-M-SYN-02**: Aplikacja MUST odświeżać pamięć przy uruchomieniu i powrocie na pierwszy plan (jeśli dane są
  starsze niż 5 minut), po geście „pociągnij, aby odświeżyć” i okresowo w tle (w miarę możliwości systemu, gdy
  jest połączenie z komputerem). API nie udostępnia zmian przyrostowych — odświeżenie pobiera dane na nowo
  z poszanowaniem limitu 100 żądań / 10 s (odpowiedź `429` → odczekanie i ponowienie).
- **FR-M-SYN-03**: Każdy ekran z danymi z pamięci MUST pokazywać, z kiedy są dane, gdy nie są aktualne
  (brak połączenia lub odświeżenie nieudane).
- **FR-M-SYN-04**: Bez połączenia aplikacja MUST pozwalać dodawać do kolejki: nowe wpisy wszystkich rodzajów
  z [US3](#us3--szybkie-dodanie-wpisu-przy-koniu-p1), nowe treningi ([US10](#us10--dziennik-treningów-p2)), nowe terminy, nowe kontakty, nowe załączniki (także do wpisów
  z kolejki) oraz akcje „Zrealizowany” i „Odrzuć” na terminach. Edycja, usuwanie, „Przełóż” i dodanie konia
  MUST wymagać połączenia.
- **FR-M-SYN-05**: Kolejka MUST być trwała (przetrwa zamknięcie aplikacji i restart urządzenia), wysyłana w kolejności
  dodania, z zależnościami (załącznik po swoim wpisie; wpis z nowym kontaktem po tym kontakcie) i automatycznym
  ponawianiem przy błędach sieci (rosnące odstępy, bez limitu prób, dopóki operacja nie zostanie wysłana lub usunięta).
- **FR-M-SYN-06**: Kolejka MUST NOT tworzyć duplikatów, gdy wynik wysłania jest nieznany (przerwane połączenie po
  wysłaniu żądania), i MUST NOT gubić celowo identycznych wpisów. Każda operacja ma stały identyfikator nadany na
  urządzeniu. Aplikacja MUST go wysyłać w nagłówku `Idempotency-Key` (program 1.6.1 go ignoruje — na przyszłość,
  [11.2](#112-zależności)). Dopóki program nie obsługuje tego nagłówka, obowiązuje **licznik przed i po**: tuż przed
  wysłaniem operacji aplikacja MUST zapisać liczbę pasujących rekordów w programie (zapytanie listy z filtrem), a po
  wysłaniu z nieznanym wynikiem policzyć je ponownie — wzrost oznacza, że operacja została zapisana (aplikacja odnajduje
  nowy rekord i przyjmuje jego `id`), brak wzrostu — że trzeba ją wysłać ponownie. Klucze dopasowania: wpis i trening —
  koń, rodzaj, data i treść; termin — koń, `kind`, `dueDate`, tytuł; kontakt — nazwa i telefon; załącznik — `ownerType`,
  `ownerId` i `sha256` pliku (pomocniczo nazwa pliku i rozmiar). Akcje na terminach są sprawdzane po statusie terminu. Ryzyko szczątkowe (identyczny
  rekord dodany na komputerze w tej samej chwili) jest akceptowane.
- **FR-M-SYN-07**: Operacja odrzucona przez program (`400`, `404`, `409`, `413`, `415`) MUST dostać status „Wymaga
  poprawy” z komunikatem programu; użytkownik MUST móc ją poprawić, wysłać ponownie lub usunąć. Operacje od niej
  zależne czekają; niezależne wysyłają się dalej. Wyjątek: „Zrealizowany” / „Odrzuć” dla terminu, który jest już
  zamknięty (zrealizowany lub odrzucony) albo usunięty (`404`), MUST zostać usunięte z kolejki jako „już załatwione”
  i zapisane w historii kolejki.
- **FR-M-SYN-08**: Wpisy z kolejki MUST być widoczne w aplikacji (oś czasu, pulpit „Ostatnie wpisy”, lista terminów)
  z oznaczeniem „czeka na wysłanie” / „wymaga poprawy”; ich koszt nie jest wliczany do kosztów z programu.
- **FR-M-SYN-09**: Licznik niewysłanych operacji MUST być widoczny na głównym ekranie; ekran „Kolejka wysyłki”
  pokazuje wszystkie operacje z ich stanem i pozwala wymusić wysłanie.
- **FR-M-SYN-10**: Czas lokalny urządzenia MUST NOT decydować o danych programu: daty wpisów są datami kalendarzowymi
  (`DateOnly`), a „dziś” dla podpowiedzi to lokalna data urządzenia.
- **FR-M-SYN-11**: Każdy nowy rekord (wpis, trening, termin, kontakt, załącznik, akcja „Zrealizowany” / „Odrzuć”) MUST
  przechodzić przez kolejkę także przy połączeniu: jest wysyłany natychmiast, a użytkownik widzi „Zapisano” po
  potwierdzeniu programu albo „Zapisano — wyślę po połączeniu z komputerem”, gdy potwierdzenie nie nadejdzie w ciągu ok.
  1 s (NFR-M-02). Błąd walidacji (`400`) otrzymany w tym czasie MUST wrócić do formularza (US3/8), a nie do „Wymaga
  poprawy”. Edycja, usuwanie, „Przełóż” i dodanie konia nie przechodzą przez kolejkę.
- **FR-M-SYN-12**: Operację czekającą w kolejce (także „Wymaga poprawy”) użytkownik MUST móc edytować i usuwać bez
  połączenia, dopóki nie zacznie się jej wysyłanie; operacja w trakcie wysyłania lub z nieznanym wynikiem jest
  zablokowana do jego ustalenia.
- **FR-M-SYN-13**: Ekran „Kolejka wysyłki” MUST pokazywać historię operacji wysłanych i „już załatwionych” z ostatnich
  30 dni; starsze wpisy historii są usuwane automatycznie (bez treści wpisów w logach).

### 4.3 Pulpit i terminy (`PUL`, `TER`)

- **FR-M-PUL-01**: Pulpit MUST pokazywać dane `GET /dashboard`: przeterminowane, nadchodzące (horyzont z programu),
  później w tym miesiącu, ostatnie wpisy, koszty bieżącego i poprzedniego miesiąca, oraz kafle aktywnych koni
  z najbliższym terminem i oznaczeniem „bez paszportu od X mies.”. Kafel pokazuje pod imieniem imię stajenne
  w cudzysłowie („Gromek”, gdy wpisane); wszystkie kafle mają jednakową wielkość, a treść jest wyrównana do góry
  (jak strona „Konie” w programie 1.6.1).
- **FR-M-PUL-02**: Pulpit MUST mieć przyciski szybkiego dodawania: Weterynarz, Kowal, Kilka koni (kowal), Termin,
  Zakup, Zawody (start), Trening, Notatka.
- **FR-M-TER-01**: Terminy MUST dać się filtrować po koniu, rodzaju (`ReminderKind`), statusie (domyślnie Otwarty)
  i zakresie dat.
- **FR-M-TER-02**: Akcje na terminie: Zarejestruj wizytę (formularz rodzaju odpowiadającego `kind`), Zrealizowany
  (`POST /reminders/{id}/complete`), Odrzuć (`/dismiss`), Przełóż (`PUT` z nową datą), Edytuj, Usuń.
- **FR-M-TER-03**: Mapowanie rodzaju terminu na formularz: `Vet`, `Vaccination`, `Deworming` → wizyta weterynaryjna;
  `Farrier` → kowal; `Physio` → fizjoterapia; `Specialist` → inny specjalista (z typem z terminu); `Competition` →
  start w zawodach; `Other` → notatka.

### 4.4 Konie (`KON`)

- **FR-M-KON-01**: Lista koni MUST obsługiwać wyszukiwanie (imię, numer paszportu, bez rozróżniania wielkości liter
  i polskich znaków), przełączniki „Pokaż wszystkie” i „Tylko źrebięta”, sortowanie po imieniu. Wyszukiwanie
  obejmuje też imię stajenne (jak w programie). Pod imieniem konia lista pokazuje imię stajenne w cudzysłowie
  („Gromek”) mniejszą, jaśniejszą czcionką; koń bez imienia stajennego nie ma pustego wiersza.
- **FR-M-KON-02**: Karta konia MUST pokazywać dane z [US6](#us6--karta-konia-i-historia-p2): nagłówek, paszport
  i szczepienia, najbliższe terminy, koszty bieżącego roku, oś czasu (`GET /horses/{id}/timeline`, stronicowana,
  filtr rodzajów), zawody (statystyki i starty), treningi (`GET /trainings?horseId=` — oś czasu programu
  nie zawiera treningów), załączniki konia.
- **FR-M-KON-03**: Dodanie i edycja konia MUST obejmować co najmniej: imię, numer paszportu, „Źrebak”, płeć, rasa,
  maść, data urodzenia (lub tylko rok), UELN, chip, interwał kowala (1–26 tygodni), status z datą statusu, zdjęcie
  główne. Numer paszportu wymagany, chyba że zaznaczono „Źrebak”; ostateczną walidację wykonuje program.
  SHOULD: kwoty konia (`finance`: cena i data zakupu, cena i data sprzedaży, wartość — ocena własna właściciela).
  Formularz bez tych pól MUST pomijać obiekt `finance` przy zapisie (program zachowuje wtedy kwoty); wysłany obiekt
  zastępuje wszystkie pięć pól. Zmianę statusu na „Padł” program sam łączy z ceną sprzedaży 0 — aplikacja tego
  nie powiela, tylko odświeża dane.
- **FR-M-KON-04**: Konie w listach wyboru MUST być wyświetlane po imieniu (u źrebaka bez paszportu — bez pustych
  nawiasów ani „null”); ostatnio używane konie na górze.

### 4.5 Wpisy (`WPI`)

- **FR-M-WPI-01**: Formularze MUST obsługiwać pola API ([6.4](#64-pola-formularzy)); pola wymagane przez API są
  zawsze widoczne, pozostałe w sekcji „Więcej szczegółów”.
- **FR-M-WPI-02**: Wartości słownikowe (rodzaj wizyty, usługa kowalska, okolice ciała i techniki fizjoterapii, typ
  specjalisty, ranga i dyscyplina zawodów, kategoria zakupu, jednostka, rodzaj treningu) MUST pochodzić ze słowników programu
  (tylko aktywne pozycje w nowych wpisach; nieaktywne wyświetlane w istniejących wpisach).
- **FR-M-WPI-03**: Kwoty MUST być wprowadzane w złotych z dokładnością do grosza (klawiatura numeryczna, przecinek
  dziesiętny); kwota w walucie obcej (kwota i waluta) jest informacyjna, jak w programie.
- **FR-M-WPI-04**: Podpowiedzi jak w programie: data następnej wizyty kowala z interwału konia, kwota zakupu
  z ilości × ceny (do czasu ręcznej zmiany), łączny koszt zakupu z dostawą, trener, jeździec i koszt nowego treningu z ostatniego treningu konia
  (FR-M-TRN-03).
- **FR-M-WPI-05**: Kowal „Kilka koni” MUST tworzyć osobny wpis dla każdego zaznaczonego konia (osobne operacje
  w kolejce).
- **FR-M-WPI-06**: Edycja MUST wysyłać `version` otrzymane z programu; `409` z inną wersją MUST prowadzić do wyboru
  „Odśwież” / „Nadpisz moje zmiany” (nadpisanie = ponowne wysłanie z aktualną wersją).
- **FR-M-WPI-07**: Porzucenie formularza z niezapisanymi zmianami MUST wymagać potwierdzenia; SHOULD zachować
  szkic formularza nowego wpisu, gdy system zamknie aplikację w tle.

### 4.5a Treningi (`TRN`)

- **FR-M-TRN-01**: Formularz treningu MUST obsługiwać pola `TrainingInput` ([6.4](#64-pola-formularzy)): koń, data
  (nie z przyszłości), rodzaj (słownik `TrainingType`, tylko aktywne pozycje w nowych wpisach), czas 1–600 min,
  intensywność (`Light` / `Medium` / `Hard` → „Lekka” / „Średnia” / „Ciężka”), ocena 1–5, opis; wysokość przeszkód
  10–200 cm tylko dla rodzaju z kluczem systemowym `training.jumping` (przy innym rodzaju pole MUST NOT być wysyłane).
- **FR-M-TRN-02**: Trener i jeździec MUST być wybierane spośród kontaktów typu `Trainer` i `Rider`
  (`GET /contacts?type=`, bez zarchiwizowanych) albo dodawane jako nowy kontakt z tym typem. Zapis: jeździec
  w `riderContactId` — zwykłe pole, które `PUT` zastępuje (brak = bez jeźdźca), więc edycja MUST zawsze wysyłać
  bieżącą wartość; trener i koszt w obiekcie `coaching` (`trainerContactId`, `cost`, `originalAmount`,
  `originalCurrency`) — `PUT` bez `coaching` zostawia je bez zmian, wysłany obiekt zastępuje wszystkie cztery pola.
  Błędy `400` z kluczami `riderContactId` i `coaching.trainerContactId` (kontakt nie istnieje, jest w koszu albo
  nie ma wymaganego typu) MUST być pokazane przy właściwym polu.
- **FR-M-TRN-03**: Nowy trening MUST wstępnie wypełniać trenera, jeźdźca i koszt (z kwotą w walucie obcej)
  wartościami z ostatniego treningu tego konia (najnowszy z `GET /trainings?horseId=&pageSize=1`; treningi z kosza
  program pomija) — przy otwarciu formularza i po zmianie konia, o ile użytkownik nie zmienił pola ręcznie. Kontakt
  zarchiwizowany albo bez typu `Trainer` / `Rider` MUST NOT być podpowiadany. Reguła nie dotyczy edycji.
- **FR-M-TRN-04**: Lista treningów (zakładka karty konia) MUST obsługiwać filtry `from`, `to`, `typeId`, `trainerId`,
  `riderId` i pokazywać podliczenie z programu: liczbę (`totalCount`) i sumę kosztów (`totalCost`, całego filtra,
  nie tylko strony). Czas MUST być pokazywany jak w programie: „X h Y min” od 60 minut, „Y min” poniżej, „—” bez czasu.

### 4.6 Załączniki (`ZAL`)

- **FR-M-ZAL-01**: Źródła: aparat, galeria (wiele plików), pliki urządzenia, udostępnienie z innej aplikacji.
- **FR-M-ZAL-02**: Dozwolone typy i limit jak w programie: jpg, png, heic, webp, pdf, docx, xlsx, txt, mp4, mov;
  maks. 100 MB na plik. Aplikacja MUST sprawdzać to przed dodaniem do kolejki.
- **FR-M-ZAL-03**: Zdjęcia MUST być domyślnie zmniejszane do dłuższego boku 2560 px (JPEG/HEIC jakość ~85%);
  ustawienie „Wysyłaj oryginały” to wyłącza. Dane lokalizacji (EXIF GPS) MUST być usuwane przed wysłaniem,
  chyba że użytkownik włączy ich zachowanie.
- **FR-M-ZAL-04**: Wysyłanie dużych plików MUST odbywać się w tle, z postępem, i być wznawiane po przerwaniu
  (ponowne wysłanie pliku w całości jest dopuszczalne).
- **FR-M-ZAL-05**: Podgląd: miniatury, pełny obraz z powiększaniem, PDF w przeglądarce systemowej lub wbudowanej,
  wideo z przewijaniem; „Zapisz na urządzeniu” / „Udostępnij”.
- **FR-M-ZAL-06**: Usunięcie załącznika MUST wymagać połączenia i potwierdzenia (trafia do kosza programu).

### 4.7 Kontakty (`KTK`)

- **FR-M-KTK-01**: Lista kontaktów z wyszukiwaniem i filtrem typu (`ContactType`), bez zarchiwizowanych; typy obejmują „Trener” (`Trainer`,
  od 1.4) i „Jeździec” (`Rider`, od 1.5), z nazwami jak w programie.
- **FR-M-KTK-02**: Akcje: zadzwoń, SMS, e‑mail, nawigacja do adresu, kopiuj; karta kontaktu z historią zakupów
  (`GET /purchases?supplierId=`), treningami trenera lub jeźdźca (`GET /trainings?trainerId=` / `riderId=`) i startami
  jeźdźca (z połączeniem); historia wizyt — gdy program ją udostępni ([11.2](#112-zależności)).
- **FR-M-KTK-03**: Dodanie kontaktu (nazwa, typy, firma, telefon, e‑mail, adres, specjalizacja, notatki), także
  z poziomu formularza wpisu; edycja z połączeniem. SHOULD: import danych z książki adresowej telefonu przy dodawaniu. Usunięcie kontaktu
  wskazanego jako trener lub jeździec program odrzuca (`409` `InUse`) — aplikacja MUST pokazać „Kontakt jest używany
  we wpisach — możesz go zarchiwizować” z akcją „Archiwizuj”.

### 4.8 Raporty (`RAP`)

- **FR-M-RAP-01**: Ekran „Raporty” MUST udostępniać te same raporty co program 1.6.1, w tej kolejności: „Koszty”
  (`GET /reports/costs`), „Bilans konia” (`GET /reports/horse-balance`), „Podsumowanie treningów”
  (`GET /reports/training-summary`), „Treningi jeźdźca” (`GET /reports/rider-trainings`), „Zawody jeźdźca”
  (`GET /reports/rider-competitions`), z filtrami, kolumnami i podsumowaniami jak w programie (US9). Układ jest
  dopasowany do telefonu: sumy na górze, wiersze jako karty lub lista rozwijana zamiast szerokiej tabeli; żadna
  kolumna programu nie jest pomijana (mniej ważne pola po rozwinięciu wiersza).
- **FR-M-RAP-02**: Wszystkie wartości i sumy raportów MUST pochodzić z odpowiedzi API — aplikacja niczego nie przelicza
  (kwoty co do grosza, czasy co do minuty, średnie jak w programie). Kategorie kosztów są tekstem z programu (od 1.4
  także „Treningi”) — aplikacja MUST NOT zakładać stałej listy kategorii. Wpisy z kolejki wysyłki nie są wliczane
  (FR-M-SYN-08).
- **FR-M-RAP-03**: Wykresy MUST powstawać z danych odpowiedzi bez zmiany wartości: „Koszty” — słupkowy kosztów
  miesięcznych skumulowany po kategoriach (wiersze `groupBy=month` z polami `month` i `category`) i kołowy udziału
  kategorii; „Podsumowanie treningów” — wykres postępów z serii `series` (seria na rodzaj, kolor według `paletteIndex`
  jak w programie, różne kształty znaczników, legenda). Wykresy MUST być czytelne w obu motywach i w orientacji pionowej
  (pozioma dozwolona do powiększenia wykresu), z opisem dla czytnika ekranu i nie tylko kolorem.
- **FR-M-RAP-04**: Czas w raportach MUST być pokazywany jak w programie: łączny czas i czas treningu „X h Y min” od
  60 minut, „Y min” poniżej, „—” bez wpisanego czasu; statystyki czasu pojedynczego treningu — w minutach.
- **FR-M-RAP-05**: Każdy raport z danymi MUST dać się wyeksportować do **CSV** i **PDF** w formacie programu:
  CSV — zgodny bajt w bajt z eksportem programu (`CsvReportWriter`): UTF‑8 z BOM, separator `;`, przecinek dziesiętny,
  te same kolumny i nagłówki (czas jako liczba minut w kolumnach „Łączny czas (min)” / „Czas (min)”), sprawdzany
  w testach z plikami CSV wygenerowanymi przez program dla zestawu testowego; PDF (A4) — te same dane i elementy co PDF
  programu: nagłówek z nazwą raportu, filtrami i datą danych, tabela z sumami, wykresy z legendą (koszty, podsumowanie
  treningów), czas w formacie z FR-M-RAP-04, kwoty `1 250,00 zł` — w układzie aplikacji, bez wymogu identyczności
  wizualnej z PDF programu. Plik powstaje na telefonie i jest przekazywany przez systemowe „Udostępnij” albo zapisywany
  w wybranym miejscu („Zapisz w plikach”); kopia robocza w pamięci tymczasowej aplikacji MUST być usuwana po
  udostępnieniu lub przy zamknięciu aplikacji. Nazwa domyślna jak w programie (nazwa raportu i data).
- **FR-M-RAP-06**: Z połączeniem eksport MUST używać raportu pobranego ponownie z tymi samymi filtrami. Bez połączenia
  raport MUST być pokazany z pamięci podręcznej z datą pobrania (FR-M-SYN-03); jego eksport jest dozwolony tylko
  z datą pobrania w nagłówku PDF i w nazwie pliku.
- **FR-M-RAP-07**: Karta konia SHOULD pokazywać skrót bilansu konia (zakup, koszty, nagrody, sprzedaż, wynik —
  `GET /reports/horse-balance?horseIds=<id>`) z przejściem do raportu „Bilans konia”, jak w programie.

### 4.9 Powiadomienia (`POW`)

- **FR-M-POW-01**: Aplikacja MUST planować lokalne powiadomienia na podstawie otwartych terminów z pamięci podręcznej,
  bez serwera w internecie.
- **FR-M-POW-02**: Dzienne podsumowanie o wybranej godzinie (domyślnie 08:00): liczba przeterminowanych i terminów
  na dziś/jutro; pomijane, gdy nie ma czego zgłosić. Opcjonalnie powiadomienie w dniu terminu dla każdego terminu.
- **FR-M-POW-03**: Po każdym odświeżeniu danych i każdej akcji na terminie aplikacja MUST przeliczyć zaplanowane
  powiadomienia; po restarcie urządzenia MUST je odtworzyć.
- **FR-M-POW-04**: Treść powiadomień MUST być zrozumiała bez otwierania aplikacji („Grom — kowal, termin minął 3 dni temu”)
  i nie zawierać danych wrażliwych ponad imię konia i tytuł terminu. Ustawienie „Ukryj szczegóły na ekranie
  blokady” SHOULD być dostępne.
- **FR-M-POW-05**: (Android) prośba o wyłączenie optymalizacji baterii i instrukcja dla producenta. **W iOS nie
  dotyczy** — powiadomienia lokalne planowane z wyprzedzeniem działają niezależnie od pracy w tle ([9.4](#94-praca-w-tle)).

### 4.10 Ustawienia aplikacji (`UST`)

- **FR-M-UST-01**: Połączenie: nazwa i wersja programu, adresy (dodaj, popraw, usuń, kolejność), szyfrowanie tak/nie i tryb
  zaufania przy każdym adresie (FR-M-POL-06),
  „Sprawdź połączenie”, „Połącz ponownie (nowy kod QR)”, „Rozłącz”. Przełącznik „Szczegółowy dziennik połączeń”
  (tylko tryb online): zapisuje w dzienniku diagnostycznym adres, IP połączenia, rodzaj sieci i wynik każdego żądania do programu (bez klucza, nagłówków, zapytań i treści);
  włączony na 7 dni, po czym wyłącza się sam; Ustawienia pokazują, do kiedy. „O aplikacji → Dziennik diagnostyczny” (oba tryby): rozmiar, wpisy od najnowszych,
  „Wyślij” i „Wyczyść” (z potwierdzeniem).
- **FR-M-UST-00**: Ekran Ustawienia MUST zawierać pozycje w tej kolejności (lista z liniami między wierszami i strzałką):
  „Połączenie z programem” (tylko tryb online) · „Tryb pracy” · „Powiadomienia” · „Blokada aplikacji” · „Dane” · „Wygląd”.
  „Kopia zapasowa” (tryb samodzielny) i „O aplikacji” są pozycjami menu „Więcej”.
- **FR-M-UST-02**: Powiadomienia: włącz/wyłącz, godzina dziennego podsumowania, powiadomienie w dniu terminu,
  ukrywanie szczegółów.
- **FR-M-UST-03**: Dane: zakres osi czasu w pamięci (3/12/24 mies.), limit miejsca na załączniki, „Wysyłaj
  oryginały zdjęć”, „Zachowaj lokalizację zdjęć”, „Wyczyść pamięć podręczną” (bez kolejki), zajętość miejsca,
  „Załączniki i odświeżanie w tle tylko przez Wi‑Fi” (domyślnie włączone; dotyczy połączeń przez adres publiczny
  w sieci komórkowej — wpisy bez załączników wysyłają się zawsze).
- **FR-M-UST-04**: Wygląd: motyw systemowy / jasny / ciemny.
- **FR-M-UST-07** (2.0): Tryb pracy: bieżący tryb i zmiana na drugi z ostrzeżeniami (samodzielny → online: dane z telefonu zostają usunięte po
  udanym parowaniu, propozycja kopii zapasowej; online → samodzielny: dane programu zostają jako punkt startowy, liczba niewysłanych zmian).
- **FR-M-UST-08** (2.0): Blokada aplikacji (domyślnie wyłączona): odblokowanie zabezpieczeniem telefonu przy otwarciu i po ponad 5 min w tle,
  bez osobnego PIN-u; telefon bez blokady ekranu — przełącznik nieaktywny z wyjaśnieniem; podgląd w ostatnich aplikacjach ukryty.
- **FR-M-UST-09** (2.0, tryb samodzielny): Kopia zapasowa: data i rodzaj ostatniej kopii, „Utwórz kopię zapasową” (hasło opcjonalne wpisywane
  dwa razy), „Odtwórz z kopii”, „Automatyczna kopia co tydzień” z folderem wskazanym raz. W trybie samodzielnym ustawień połączenia, pamięci
  podręcznej i „Pobieraj wszystkie załączniki” nie ma (FR-TRB-08).
- **FR-M-UST-05**: O aplikacji: wersja aplikacji, autor systemu „Piotr Glapa”, wersja programu na komputerze,
  link do instrukcji, „Wyślij log diagnostyczny” (log bez treści wpisów i danych osobowych, udostępniany przez
  systemowe „Udostępnij”).
- **FR-M-UST-06**: Aplikacja nie sprawdza nowych wersji w internecie (NFR-M-09; aktualizacje dostarcza TestFlight /
  App Store). Gdy program
  na komputerze (`appVersion` z `/system/info`) jest nowszy niż najnowsza wersja programu, z którą aplikację testowano
  (stała w aplikacji), aplikacja MUST pokazać — raz na wersję programu oraz w „O aplikacji” — informację „Program
  <wersja> — aplikacja testowana z <wersja>; sprawdź, czy jest nowa wersja aplikacji”; aplikacja działa dalej.

### 4.11 Interfejs i nawigacja (`UI`)

- **FR-M-UI-01**: Interfejs MUST być po polsku zgodnie z [5.1](#51-zasady-ogólne) (daty, kwoty, tydzień od poniedziałku);
  polskie nazwy wartości wyliczeniowych MUST być zgodne z programem ([6.4](#64-pola-formularzy)).
- **FR-M-UI-02**: Struktura nawigacji MUST odpowiadać [5.2](#52-struktura): dolna nawigacja, „Więcej”, przycisk „+”,
  zakładki karty konia, przebieg pierwszego uruchomienia.
- **FR-M-UI-03**: Obsługa jedną ręką (najważniejsze akcje u dołu, duże cele dotyku), kolorystyka spójna z programem,
  motyw jasny i ciemny, koń oznaczany ikoną głowy konia ([5.1](#51-zasady-ogólne)).
- **FR-M-UI-04**: Każdy ekran MUST mieć stany: ładowanie, pusto (z podpowiedzią), brak połączenia (ikonka w pasku nawigacji
  i podtytuł z datą danych — FR-M-POL-17), błąd (komunikat po polsku + „Spróbuj ponownie”).
- **FR-M-UI-07**: Wygląd MUST odpowiadać wzorcowi z [5.4](#54-wzorzec-wyglądu) (kolory, ikony, obszary, układ Pulpitu,
  karty konia, list i formularzy), a teksty interfejsu MUST być identyczne z tekstami aplikacji na Androida 2.0.1
  (`strings.xml`, `plurals.xml`).
- **FR-M-UI-05**: Po zapisie MUST pojawić się krótki komunikat („Zapisano” / „Zapisano — wyślę po połączeniu
  z komputerem”) z akcją „Cofnij” dla wpisów jeszcze niewysłanych.
- **FR-M-UI-06**: SHOULD: skróty z ikony aplikacji „Dodaj notatkę”, „Kowal”, „Terminy” ([9.5](#95-integracje-systemowe)).

### 4.12 Wersja 2.0 — tryby pracy, praca offline, kopia zapasowa, kolory, zdjęcie konia

Te same identyfikatory co w aplikacji na Androida (`specs/004-tryb-samodzielny-offline`).

#### Tryb pracy (`TRB`)

- **FR-TRB-01**: Aplikacja MUST pracować w jednym z dwóch trybów: **online** (z programem) albo **samodzielnym** (bez programu);
  tryb MUST być zapamiętany i obowiązywać przy każdym uruchomieniu.
- **FR-TRB-02**: Przy pierwszym uruchomieniu aplikacja MUST pokazać ekran wyboru trybu z US2.0-1 (tytuł, pytanie, dwie opcje
  z opisami, „Dalej”, informacja o Ustawieniach); domyślnie zaznaczone „Tak, połącz z programem”.
- **FR-TRB-03**: Tryb online MUST zostać zapamiętany dopiero po udanym parowaniu; przerwane parowanie wraca do wyboru trybu.
- **FR-TRB-04**: (Android: aktualizacja z 1.x bez pytania o tryb.) iOS nie ma wydań 1.x — FR-TRB-04 nie dotyczy, a każda
  przyszła aktualizacja aplikacji iOS MUST zachować tryb, połączenie, kolejkę i ustawienia.
- **FR-TRB-05**: Ustawienia MUST zawierać pozycję „Tryb pracy” z bieżącym trybem i akcją zmiany na drugi tryb.
- **FR-TRB-06**: Przejście z samodzielnego na online MUST: pokazać ostrzeżenie z liczbą koni i wpisów oraz datą ostatniej
  kopii, zaproponować kopię zapasową, wymagać osobnego potwierdzenia „Usuń dane i połącz” i usunąć dane lokalne dopiero po
  udanym parowaniu. Dane nie są przenoszone do programu.
- **FR-TRB-07**: Przejście z online na samodzielny MUST zachować pełne dane programu jako punkt startowy (z oryginałami
  załączników), usunąć połączenie i klucz API oraz ostrzec o liczbie niewysłanych zmian, które zostaną tylko w telefonie;
  brakujące dane MUST być najpierw pobrane albo — bez połączenia — wskazane z wymaganiem potwierdzenia. Przerwana zmiana
  trybu MUST być bezpiecznie wznawiana.
- **FR-TRB-08**: W trybie samodzielnym aplikacja MUST NOT nawiązywać żadnych połączeń sieciowych (poza mapami, telefonem
  i e‑mailem w innych aplikacjach na żądanie) i MUST NOT pokazywać elementów połączenia (stan połączenia, data danych,
  kolejka wysyłki, Konflikty, ustawienia połączenia, „Wyczyść pamięć podręczną”, „Pobieraj wszystkie załączniki”).
- **FR-TRB-09**: W obu trybach „Blokada aplikacji” (domyślnie wyłączona): przy otwarciu i po powrocie po ponad 5 min w tle
  aplikacja MUST wymagać odblokowania zabezpieczeniem telefonu (Face ID / Touch ID / kod urządzenia), bez własnego PIN-u.
  Zablokowana aplikacja MUST NOT pokazywać danych (także w przełączniku aplikacji); praca w tle działa dalej. Bez kodu
  urządzenia opcja jest nieaktywna z wyjaśnieniem; usunięcie kodu urządzenia wyłącza blokadę z informacją przy następnym
  otwarciu. Ekran blokady: ikona aplikacji, przycisk „Odblokuj”.

#### Dane w telefonie i synchronizacja w trybie online (`SYN2`)

- **FR-SYN2-01**: W trybie online aplikacja MUST przechowywać wszystkie dane programu udostępniane przez API (`GET /export?scope=full`):
  konie (wszystkie statusy i kwoty), wpisy wszystkich rodzajów i treningi z całej historii, terminy we wszystkich statusach,
  kontakty (także zarchiwizowane), zakupy, zawody i starty, słowniki, metadane załączników oraz miniatury zdjęć koni.
  Oryginały załączników — na żądanie i przy otwarciu, z limitem miejsca (domyślnie 200 MB); ustawienie „Pobieraj wszystkie
  załączniki” (domyślnie wyłączone).
- **FR-SYN2-02**: Pierwsze pełne pobranie MUST odbywać się w tle z postępem (baner na Pulpicie: liczba rekordów), wznawiać się
  po przerwaniu i nie blokować aplikacji; kolejne odświeżenia MUST zachować niewysłane zmiany i konflikty.
- **FR-SYN2-03**: Bez połączenia MUST być dostępne wszystkie operacje (dodawanie, edycja, usuwanie, „Przełóż”, dodanie konia,
  zmiana statusu i zdjęcia konia), poza zarezerwowanymi dla programu (słowniki, kosz, ustawienia programu). Zmiana MUST być
  od razu widoczna z oznaczeniem „czeka na wysłanie”.
- **FR-SYN2-04**: Każda zmiana MUST trafiać do trwałej kolejki (kolejność, zależności, brak duplikatów, „Wymaga poprawy”,
  historia 30 dni); kolejne zmiany tego samego rekordu MUST być łączone, o ile wcześniejsza operacja nie jest w trakcie
  wysyłania, o nieznanym wyniku ani w konflikcie: dodanie + edycja = dodanie ze stanem końcowym; dodanie + usunięcie = obie
  usunięte z kolejki (z zależnymi, np. załącznikami nowego wpisu); edycja + edycja = jedna edycja ze stanem końcowym i wersją
  bazową pierwszej; edycja + usunięcie = usunięcie z wersją bazową pierwszej.
- **FR-SYN2-05**: Każda edycja i usunięcie MUST nieść wersję bazową rekordu (`If-Match` / `version`); odmowa z powodu nowszej
  wersji MUST dać konflikt, nie nadpisanie. Bez `ifMatchDelete` (program < 2.0.0) wersja przed `DELETE` jest sprawdzana
  osobnym `GET`.
- **FR-SYN2-06**: Ekran „Konflikty” (karta z licznikiem na Pulpicie, pozycja w „Więcej” tylko gdy są) MUST pokazywać każdy
  konflikt: rekord, koń, rodzaj (zmiana–zmiana, zmiana–usunięcie, usunięcie–zmiana) i datę; szczegóły — dwie kolumny „Moja”
  / „Z programu” z wyróżnionymi różnicami (tło + ikona, nie tylko kolor).
- **FR-SYN2-07**: Każdy konflikt rozstrzyga użytkownik: „Zachowaj moją” (moja wersja trafia do programu jako zmiana
  najnowszej wersji; przy usunięciu w programie rekord jest przywracany z kosza programu `POST /trash/{type}/{id}/restore`
  albo tworzony ponownie) lub „Przyjmij z programu”. Do rozstrzygnięcia rekord pokazuje moją wersję z oznaczeniem „konflikt”;
  zależne zmiany czekają. Przy > 1 konflikcie — „Zachowaj wszystkie moje” / „Przyjmij wszystkie z programu” z potwierdzeniem
  i liczbą. Rozstrzygnięte konflikty są w historii kolejki 30 dni.
- **FR-SYN2-08**: Bez połączenia raporty, sumy działów i Pulpit MUST być wyliczane z danych w telefonie (z niewysłanymi
  zmianami) regułami trybu samodzielnego i oznaczone „z pamięci”; po połączeniu obowiązują wartości programu.
- **FR-SYN2-09**: Program bez wersji rekordów (tryb zgodności) → edycja, usuwanie i „Przełóż” wymagają połączenia, a
  „O aplikacji” informuje o potrzebie aktualizacji programu.
- **FR-SYN2-10**: Odświeżanie: przy starcie, po powrocie na pierwszy plan po ≥ 15 min, ręcznie („pociągnij, aby odświeżyć”,
  „Odśwież”) i w tle (co godzinę; z `dataStamp` — co 15 min, w miarę możliwości iOS, [9.4](#94-praca-w-tle)).

#### Tryb samodzielny (`SAM`)

- **FR-SAM-01**: W trybie samodzielnym MUST być dostępne wszystkie funkcje trybu online, bez ograniczeń połączenia.
- **FR-SAM-02**: Aplikacja MUST stosować reguły programu z identycznym wynikiem: walidacja pól i komunikaty błędów (te same
  teksty), unikalność, termin z daty następnej wizyty, zamknięcie pasującego otwartego terminu (tolerancja 14 dni), termin
  z zawodów w przyszłości, podział kosztu zakupu po równo z różnicą groszową u pierwszego konia wg imienia, cena sprzedaży 0
  przy „Padł”, koszt treningu w kategorii „Treningi”, zakaz usunięcia kontaktu użytego jako trener lub jeździec. Zgodność
  MUST być sprawdzana plikami wzorcowymi programu (`rules-parity.md`).
- **FR-SAM-03**: Pięć raportów MUST dawać te same wartości co program, a CSV MUST być bajt w bajt zgodny z CSV programu.
- **FR-SAM-04**: Kosz jak w programie: usunięty koń, wpis, trening, termin, kontakt, zakup, zawody lub załącznik trafia do
  kosza partią z zależnymi; ekran Kosz pokazuje partie (opis, koń, data usunięcia, liczba zależnych) z akcjami „Przywróć”
  (z kontrolą powiązań), „Usuń trwale” i „Opróżnij kosz” (z potwierdzeniem).
- **FR-SAM-05**: Słowniki startują z domyślnym zestawem programu 2.0.0 (FR-001); ekran Słowniki: rodzaje słowników → wartości;
  dodaj, zmień nazwę, zmień kolejność (przeciągnięcie), ukryj; wartości systemowych i używanych nie da się usunąć (komunikat
  jak w programie).
- **FR-SAM-06**: Każdy zapis MUST być niepodzielny; po zapisie „Zapisano” z „Cofnij”.

#### Kopia zapasowa (`KOP`)

- **FR-KOP-01**: Tryb samodzielny: kopia wszystkich danych (z koszem, słownikami, załącznikami) do jednego pliku `.zkkopia`
  w miejscu wybranym w systemowym oknie (`fileExporter` / `UIDocumentPickerViewController`), z domyślną nazwą
  `Zarzadzanie-konmi-kopia-RRRR-MM-DD.zkkopia` (jak w aplikacji na Androida 2.0.1 — nazwa pliku nie zmieniła się wraz
  z nazwą aplikacji), postępem i rozmiarem.
- **FR-KOP-02**: Odtwarzanie z Ustawień / „Więcej → Kopia zapasowa” oraz z ekranu powitalnego po wyborze trybu samodzielnego —
  po pokazaniu daty kopii, liczby koni i wpisów i potwierdzeniu.
- **FR-KOP-03**: Odtwarzanie MUST być niepodzielne; plik uszkodzony, niekompletny, z nowszej wersji albo przerwanie →
  dane bez zmian, zrozumiały komunikat.
- **FR-KOP-04**: Kopia z każdej wcześniejszej wersji formatu MUST dać się odtworzyć w każdej późniejszej wersji aplikacji.
- **FR-KOP-05**: ≥ 7 dni od ostatniej udanej kopii i dane zmienione → przypomnienie na Pulpicie („Utwórz teraz” / „Przypomnij
  później” — ponownie po 7 dniach); ekran kopii pokazuje datę i rodzaj ostatniej kopii.
- **FR-KOP-06**: Kopia nigdy nie jest wysyłana samodzielnie; dane trybu samodzielnego są wykluczone z kopii iCloud
  (`isExcludedFromBackup`).
- **FR-KOP-07**: Hasło opcjonalne (domyślnie bez, z informacją, że plik zawiera wszystkie dane stajni, także finansowe),
  wpisywane dwa razy, z ostrzeżeniem, że zapomnianego hasła nie da się odzyskać; plik z hasłem zaszyfrowany (AES-256-GCM,
  PBKDF2-HMAC-SHA256, 310 000 iteracji); błędne hasło → „Nieprawidłowe hasło”.
- **FR-KOP-08**: „Automatyczna kopia co tydzień” (domyślnie wyłączona; propozycja po pierwszej ręcznej kopii): folder wskazany
  raz (zakładka z uprawnieniem do folderu), co 7 dni przy zmianach danych, bez hasła, zostają 4 najnowsze `zk-auto-*.zkkopia`;
  błąd → powiadomienie i informacja z przyczyną i akcją „Wskaż folder ponownie”. Na iOS kopia automatyczna powstaje
  w `BGProcessingTask` albo przy najbliższym otwarciu aplikacji, gdy termin minął ([9.4](#94-praca-w-tle)).
- **FR-KOP-09** (iOS): Format pliku MUST być identyczny z formatem aplikacji na Androida (`backup-format.md`, format 2 od
  2.0.1: ZIP z `manifest.json`, `export.json` w schemacie eksportu 1.5, `phone.json`, `attachments/<id>`; wariant z hasłem
  z nagłówkiem `ZKKOPIA1` i porcjami AES-GCM ≤ 1 MiB) — kopia z Androida MUST dać się odtworzyć na iOS i odwrotnie.

#### Kolory i ikony (`KOL`)

- **FR-KOL-01**: Każdy rodzaj wpisu MUST mieć własny kolor i ikonę wg [5.4](#54-wzorzec-wyglądu): weterynarz — niebieski,
  kowal — brązowy, fizjoterapia — turkusowy, specjalista — fioletowy, notatka — szaroniebieski, zakup — bursztynowy, zawody
  i start — karmazynowy, trening — zielony (kolor główny); termin — kolor rodzaju terminu.
- **FR-KOL-02**: Kolor rodzaju MUST być użyty w ikonie wpisu na osi czasu, w „Ostatnich wpisach”, w listach działów (pasek
  4 pt po lewej), w akcencie nagłówka formularza i szczegółów wpisu, w wyborze rodzaju po „+”, w szybkim dodawaniu i przy terminach.
- **FR-KOL-03**: Ikony działów w „Więcej” i w dolnym pasku MUST mieć kolory działów (Pulpit — indygo, Konie — kasztanowy,
  Terminy — cyjan, Treningi — zielony, Zakupy — bursztynowy, Zawody — karmazynowy, Kontakty — niebieski, Raporty — fioletowy,
  Kosz — szary, Kopia zapasowa — turkusowy, Konflikty — pomarańczowy); Kolejka, Słowniki, Ustawienia i O aplikacji — kolor
  tekstu drugorzędnego.
- **FR-KOL-04**: Każdy kolor MUST mieć wariant jasny i ciemny o kontraście ≥ 3:1 (ikony, paski) i ≥ 4,5:1 (tekst); kolor
  nigdy nie jest jedynym nośnikiem informacji.
- **FR-KOL-05**: Ikona głowy konia MUST być tym samym rysunkiem co w aplikacji na Androida i w programie (kontur z uchem,
  grzywą, okiem, linią policzka i chrapami; [5.4](#54-wzorzec-wyglądu)), jako obraz szablonowy barwiony kolorem.
- **FR-KOL-06**: Ikona aplikacji MUST przedstawiać białą podkowę (szerszą u góry, ramiona zagięte do środka, sześć otworów
  na wylot, bez konia) na ukośnym gradiencie `#2C7756` → `#1D553E`; warianty ciemny i barwiony (iOS 18+).

#### Zdjęcie konia (`ZDK`)

- **FR-ZDK-01**: Karta konia (dotknięcie zdjęcia) i formularz konia (pole „Zdjęcie”): „Zrób zdjęcie”, „Wybierz z telefonu”
  (`PhotosPicker`, bez zgody na bibliotekę), „Wybierz z załączników konia”, „Pokaż zdjęcie”, „Usuń zdjęcie”.
- **FR-ZDK-02**: Przed zapisem — ekran kadrowania z kwadratowym kadrem (przesuwanie, powiększanie, obrót o 90°, „Anuluj”,
  „Zapisz”); zapis zmniejszony jak inne zdjęcia (niezależnie od „Wysyłaj oryginały”), bez lokalizacji.
- **FR-ZDK-03**: Ustawienie dodaje plik do załączników konia i ustawia go jako zdjęcie; podmiana zostawia poprzednie w
  załącznikach; „Usuń zdjęcie” (z potwierdzeniem) tylko odpina zdjęcie.
- **FR-ZDK-04**: Miniatura: nagłówek karty konia (72 pt, okrąg), lista koni (40 pt), kafel Pulpitu (40 pt, bez akcji zdjęcia);
  bez zdjęcia — głowa konia.
- **FR-ZDK-05**: Działa w obu trybach i bez połączenia (plik, potem zmiana konia w kolejce; konflikt jak przy edycji).
- **FR-ZDK-06**: Miniatury wszystkich koni MUST być w telefonie (widoczne bez połączenia).

### 4.13 Wersja 2.0.1 — Horsely i program 2.0.0

Te same identyfikatory co w aplikacji na Androida (`specs/005-horsely-2-0-1`).

- **FR-001**: Domyślne słowniki trybu samodzielnego MUST być identyczne z programem 2.0.0; rodzaje treningów: Ujeżdżenie 1,
  Skoki 2 (systemowy `training.jumping` — wysokość przeszkód), Teren 3, Lonża 4, Karuzela 5, Spacer 6, Zajeżdżanie 7,
  Gimnastyka 8, Wszechstronny 9, Inne 10.
- **FR-002 / FR-003**: Słowniki rodzajów treningów sprzed 2.0.1 (np. z kopii zapasowej z Androida 2.0.0) MUST być jednorazowo
  uzupełnione o Zajeżdżanie, Gimnastykę i Wszechstronny (gdy nie ma wartości o tej nazwie bez względu na wielkość liter,
  spacje i polskie znaki, także nieaktywnej), na końcu, jako aktywne; brak jakichkolwiek rodzajów → pełna lista domyślna;
  istniejących wartości nie wolno zmieniać.
- **FR-004**: W trybie online aplikacja MUST NOT zmieniać słowników.
- **FR-005**: Status konia MUST mieć wartość „Kontuzjowany” (obok Aktywny, Sprzedany, Padł, Wydzierżawiony) — w trybie
  samodzielnym zawsze, w online gdy program ogłasza `horseStatusInjured`.
- **FR-006**: Gdy program ogłasza `horseStatusInjured`, każde żądanie (także w tle i z kolejki) MUST mieć nagłówek
  `X-Client-Features: horse-status-injured` (pierwsze `GET /system/info` przy parowaniu — bez nagłówka).
- **FR-007 / FR-007a**: Plakietka „Kontuzjowany” (ikona plastra + tekst w kolorze ostrzegawczym) na liście koni (pod imieniem,
  ikona 18 pt) i w nagłówku karty konia; kafel Pulpitu — pomarańczowa ikona plastra 24 pt w prawym górnym rogu (nie zasłania
  zdjęcia ani imienia), VoiceOver: „<imię>, kontuzjowany”; ta sama ikona w filtrze statusu.
- **FR-008**: Koń kontuzjowany MUST być traktowany jak aktywny wszędzie (listy poza filtrem statusu, wybory konia, Pulpit,
  raporty, wyszukiwanie, powiadomienia, reguły trybu samodzielnego).
- **FR-009**: Filtr statusu listy koni z „Kontuzjowany”; widok domyślny — aktywne i kontuzjowane.
- **FR-010**: Formularz konia MUST pozwalać ustawić „Kontuzjowany” (z datą statusu i notatką) i wrócić do „Aktywny”.
- **FR-011**: Zapis treningu konia kontuzjowanego (formularz i szybkie dodawanie) MUST pytać: tytuł „Koń jest kontuzjowany”,
  treść „Koń jest kontuzjowany. Zapisać trening?”, „Zapisz” / „Anuluj”; nie blokuje zapisu.
- **FR-012 / FR-013**: Kopia zapasowa zachowuje status „Kontuzjowany” (schemat eksportu 1.5); reguły statusu identyczne
  z programem 2.0.0 (pliki wzorcowe).
- **FR-014**: Aplikacja MUST odczytywać `capabilities` przy każdym połączeniu (parowanie, sprawdzenie, start odświeżania)
  i używać tylko ogłoszonych możliwości; nieznane nazwy ignoruje; brak pola = zachowanie 2.0.
- **FR-015** (`dataStamp`): stempel równy zapamiętanemu i pusta kolejka → odświeżenie bez pobierania; tło co 15 min zamiast
  co godzinę (na iOS — prośba o taki odstęp w `BGAppRefreshTaskRequest.earliestBeginDate`).
- **FR-016** (`updatedSince`): pobieranie zmian `GET /export?scope=full&updatedSince=<nextUpdatedSince>`; `trashed[]` i
  `purged[]` usuwane z telefonu (z plikami); `scope.fullRequired` → pełne pobranie; punkt zapisywany dopiero po pełnym
  wczytaniu; pełne pobranie w tle, gdy od ostatniego minęły ≥ 24 h; `400` przy `updatedSince` → jedno pełne pobranie.
- **FR-017** (`ifMatchDelete`): `DELETE` i `POST /trash/{type}/{id}/restore` z `If-Match`; `409` → konflikt; bez osobnego `GET`.
- **FR-018** (`idempotencyKey`): każde dodanie z nagłówkiem `Idempotency-Key` = stały identyfikator operacji; `Idempotent-Replayed`
  = sukces pierwszego zapisu; „żądanie w toku” → ponowienie później; „klucz z inną treścią” → „Wymaga poprawy”; bez
  „licznika przed i po”.
- **FR-019** (`horsePhotoField`): zdjęcie konia wysyłane jako `photoAttachmentId` w `PUT /horses/{id}` (brak pola = bez zmian,
  `null` = brak zdjęcia).
- **FR-020**: Bez danej możliwości aplikacja MUST NOT wysyłać jej parametrów ani nagłówków.
- **FR-021 / FR-022**: Nazwa pod ikoną „Horsely” (`CFBundleDisplayName`); pełna nazwa na ekranie powitalnym i w „O aplikacji”;
  wszystkie teksty o programie — „program Horsely”; CSV bez nazwy programu (zgodność bajt w bajt).
- **FR-024**: Wersja testowana programu: 2.0.0 (ostrzeżenie FR-M-UST-06 dopiero dla nowszej); minimalna: 1.5.0.
- **FR-025** (iOS): Pierwsze wydanie aplikacji iOS ma wersję **2.0.1** (`CFBundleShortVersionString`), aby numer odpowiadał
  zakresowi funkcji Androida.
- **FR-027 / FR-028**: Wiersz „etykieta — wartość” w kartach raportów: etykieta mieści co najmniej swoje najdłuższe słowo,
  długa wartość się zawija, a gdy dla wartości zostaje < 40 % szerokości albo jej najdłuższe słowo się nie mieści — wartość
  przechodzi pod etykietę (wyrównana do lewej); test dla „Bilans konia” z długimi uwagami przy tekście 200 % i szerokości 320 pt.
- **FR-029…FR-033**: Szczegółowy dziennik połączeń i ekran „Dziennik diagnostyczny” jak w US2.0.1-6: przełącznik tylko
  w trybie online, wyłączenie po 7 dniach (liczone także przy zamkniętej aplikacji), wynik każdego adresu osobno przy
  sprawdzaniu połączenia, rotacja 5 MB, bez klucza i danych osobowych (dozwolone: host, port i IP komputera); zdarzenia
  podstawowe (synchronizacja, kolejka, sprawdzenie połączenia, kopia) zapisywane zawsze; temat przy wysyłaniu
  „Log diagnostyczny — Horsely”.

---

## 5. Ekrany i nawigacja

### 5.1 Zasady ogólne

- Język interfejsu: **polski** (daty `30.09.2026`, kwoty `1 250,00 zł`, tydzień od poniedziałku). Teksty w plikach
  zasobów, gotowe do tłumaczenia w przyszłości.
- Obsługa jedną ręką: najważniejsze akcje w dolnej części ekranu, duże cele dotyku, pływający przycisk „+”.
- Kolorystyka spójna z programem na komputer: zieleń jako kolor główny, pomarańcz jako kolor ostrzegawczy
  (przeterminowane, „bez paszportu od ≥ 12 mies.”), czerwień dla błędów; motyw jasny i ciemny.
- Spójność z programem 1.5–1.6.1: koń oznaczany ikoną głowy konia; imię stajenne pod imieniem konia w cudzysłowie,
  mniejszą i jaśniejszą czcionką; czas treningu i sumy czasu w formacie „X h Y min” / „Y min”.
- Stany: ładowanie (szkielety list), pusto (z podpowiedzią, co zrobić), brak połączenia (ikonka w pasku nawigacji
  i podtytuł „Dane z …” — FR-M-POL-17), błąd (komunikat po polsku + „Spróbuj ponownie”).
- Od wersji 1.2: ocena treningu i startu jako gwiazdki ★★★☆☆ (w listach i szczegółach; w formularzu wybór
  gwiazdką, „Wyczyść”; średnie ocen zostają liczbami, eksport CSV/PDF bez zmian); terminy, koszty i bilans w obszarach
  (kafelkach) z tłem wg tonu — przeterminowane pomarańczowe z etykietą „Przeterminowany” (informacja nigdy tylko
  kolorem); wszystkie listy mają cienką linię **między** kolejnymi wierszami (nie po ostatnim; kafle koni i kafelki
  terminów rozdziela odstęp); formularze podzielone na sekcje z nagłówkami (Podstawowe · Szczegóły · Koszty · Następna
  wizyta · Uwagi), pola wymagane z „*”, przycisk „Zapisz” w pasku nawigacji i u dołu ekranu (nad klawiaturą); kontrast
  tekstu ≥ 4,5:1, cele dotyku ≥ 44 pt, tekst 200 % bez obcinania. Szczegóły: [5.4](#54-wzorzec-wyglądu).
- Po zapisie: krótki komunikat („Zapisano” / „Zapisano — wyślę po połączeniu z komputerem”) z akcją „Cofnij”
  dla wpisów jeszcze niewysłanych.

### 5.2 Struktura

| Miejsce | Zawartość |
|---|---|
| Dolna nawigacja (`TabView`) | **Pulpit** · **Konie** · **Terminy** · **Treningi** · **Więcej** — ikony w kolorach działów ([5.4](#54-wzorzec-wyglądu)); karta „Więcej” z plakietką liczby niewysłanych operacji; pływający przycisk „+” (Dodaj wpis) nad paskiem w prawym dolnym rogu na Pulpicie, Koniach, Terminach i karcie konia (tam z wybranym koniem) |
| „Więcej” | Zawody · Zakupy · Kontakty · Raporty — separator (pełnej szerokości) — **online**: Konflikty (tylko gdy są, z licznikiem) · Kolejka wysyłki (z licznikiem) · Ustawienia · O aplikacji; **samodzielny** (2.0): Kosz · Słowniki · Kopia zapasowa · Ustawienia · O aplikacji. Wiersz: kolorowa ikona działu w kółku, nazwa, licznik albo strzałka |
| Ustawienia | Połączenie z programem (online) · Tryb pracy · Powiadomienia · Blokada aplikacji · Dane · Wygląd (FR-M-UST-00) |
| Działy Treningi · Zakupy · Zawody | Lista od najnowszych · filtry w arkuszu u dołu (domyślnie bieżący rok: **1 stycznia – 31 grudnia**, także zawody przyszłe) · stopka z liczbą i sumą · „+” · szczegóły zawodów ze startami |
| Raporty | Lista pięciu raportów jak w programie: Koszty · Bilans konia · Podsumowanie treningów · Treningi jeźdźca · Zawody jeźdźca; w każdym: filtry (arkusz u dołu ekranu) → sumy → wykresy → wiersze → „Eksport CSV”, „Eksport PDF” |
| Przycisk „+” | Wybór rodzaju wpisu → wybór konia → formularz |
| Karta konia | Nagłówek (zdjęcie, imię, paszport) · zakładki: Oś czasu · Terminy · Paszport · Treningi · Zawody · Zakupy · Załączniki; dotknięcie kafla konia (Pulpit, Konie) otwiera kartę tego konia; wiersz zakupu, startu i „Ostatnich wpisów” Pulpitu otwiera szczegóły wpisu (z „Edytuj”); nieistniejący koń — „Nie znaleziono konia” z przyciskiem „Wróć” |
| Pierwsze uruchomienie | Wybór trybu („Tak, połącz z programem” / „Nie, używaj samodzielnie” + „Odtwórz z kopii zapasowej”) → online: „Zeskanuj kod QR” / „Wpisz ręcznie” → sprawdzenie połączenia → pierwsze pobranie danych (aplikacja używalna w trakcie) → Pulpit; samodzielny: zgoda na powiadomienia → pusty Pulpit „Dodaj pierwszego konia” |

### 5.3 Formularze

Kolejność pól w formularzach szybkiego dodawania (pozostałe w „Więcej szczegółów”):

| Formularz | Pola widoczne od razu |
|---|---|
| Weterynarz | Koń · data i godzina · rodzaj wizyty · lekarz (kontakt) · powód · rozpoznanie · koszt · leki · zdjęcia |
| Kowal | Koń (lub „Kilka koni”) · data · kowal (kontakt) · usługa · koszt · następna wizyta (podpowiedź) · zdjęcia |
| Fizjoterapia | Koń · data · fizjoterapeuta · okolice ciała · techniki · koszt · następna wizyta |
| Specjalista | Koń · data · typ specjalisty · kontakt · opis · koszt · następna wizyta |
| Start w zawodach | Zawody (wybór/nowe) · koń · konkurs · jeździec (kontakt) · miejsce / liczba startujących · wynik · ocena · wpisowe · nagroda |
| Zakup | Data · produkt · kategoria · ilość × cena → kwota · koszt dostawy · „Razem” · dla kogo (koń / kilka / stajnia) · dostawca |
| Notatka | Koń · data · tytuł · treść · przypięta · zdjęcia |
| Trening | Koń · data · rodzaj · czas · intensywność · ocena · trener (kontakt) · jeździec (kontakt) · koszt (trener, jeździec i koszt — podpowiedź z ostatniego treningu) · wysokość przeszkód (tylko skoki) · opis |
| Termin | Koń · rodzaj · data · tytuł · notatka |

Sekcje formularzy (od 1.2): **Podstawowe** (koń/konie, data, rodzaj/typ, kontakt, zawody) → **Szczegóły** (pola merytoryczne:
diagnoza, leki, usługa, czas, intensywność, ocena, klasa, wynik, produkt, ilość) → **Koszty** (kwota, waluta, dostawa,
wpisowe, pozostałe koszty, nagroda) → **Następna wizyta** → **Uwagi** (opis, uwagi). Pola „więcej” zostają w swojej sekcji pod
przełącznikiem „Pokaż więcej pól”. Formularz konia: Podstawowe · Szczegóły · „Kwoty konia (ocena własna)”; formularz terminu:
Podstawowe · Uwagi.

### 5.4 Wzorzec wyglądu

Wygląd MUST odpowiadać aplikacji na Androida 2.0.1. Poniższe wartości są wiążące; komponenty systemowe iOS (paski nawigacji,
arkusze, listy, przełączniki) zastępują odpowiedniki Material, ale kolory, kolejność elementów, teksty, ikony i układ są te same.
Rozmiary w dp z Androida przenosi się 1:1 na punkty (pt).

**Paleta motywu** (jasny / ciemny; tryb wybierany: systemowy / jasny / ciemny — FR-M-UST-04; bez kolorów zależnych od tapety):

| Rola | Jasny | Ciemny | Użycie |
|---|---|---|---|
| Główny (`primary`) / na głównym | `#2E7D32` / `#FFFFFF` | `#81C784` / `#003910` | przyciski, zaznaczenia, nagłówki sekcji, trening |
| Kontener główny / tekst | `#C8E6C9` / `#0B3D12` | `#1B5E20` / `#C8E6C9` | wyróżnione tła |
| Drugorzędny / kontener | `#4F6354` / `#D2E8D5` | `#B7CCBA` / `#384B3D` | chipy, filtry |
| Trzeciorzędny (pomarańcz) / kontener | `#9A4A00` / `#FFDCC2` | `#FFB77C` / `#723600` | akcenty pomocnicze |
| Błąd / kontener błędu | `#B3261E` / `#F9DEDC` | `#F2B8B5` / `#8C1D18` | błędy, akcje niszczące |
| Tło i powierzchnia / tekst | `#FBFDF8` / `#191C19` | `#191C19` / `#E1E3DD` | tło ekranów |
| Wariant powierzchni / tekst drugorzędny | `#DDE5DB` / `#414941` | `#414941` / `#C1C9C0` | kafle koni, obszary neutralne |
| Obrys / obrys delikatny | `#6E766D` / `#C1C9C0` | `#8B938A` / `#414941` | linie między wierszami (obrys delikatny) |
| Ostrzeżenie / na ostrzeżeniu | `#B45309` / `#FFFFFF` | `#FFB77C` / `#4F2500` | przeterminowane, kontuzja, konflikty, gwiazdki oceny |
| Kontener ostrzeżenia / tekst | `#FFE8CC` / `#3A1B00` | `#5B2C00` / `#FFDCC2` | obszar „Przeterminowane”, kafel „bez paszportu ≥ 12 mies.” |
| „Nadchodzące” — tło / tekst / ramka | `#E2F0E1` / `#0B3D12` / `#81C784` | `#213A23` / `#C8E6C9` / `#2E7D32` | obszar „Nadchodzące” na Pulpicie |
| Powodzenie | `#2E7D32` | `#81C784` | potwierdzenia |

**Kolory i ikony rodzajów wpisów** (FR-KOL-01/02; ikona w kółku z tłem 12 % krycia koloru, pasek 4 pt po lewej w wierszach;
ikony Material z Androida → odpowiedniki SF Symbols):

| Rodzaj | Jasny | Ciemny | Ikona (Android → iOS) |
|---|---|---|---|
| Wizyta weterynaryjna | `#1565C0` | `#90CAF9` | MedicalServices → `cross.case` |
| Kowal | `#6D4C41` | `#BCAAA4` | Handyman → `hammer` |
| Fizjoterapia | `#00796B` | `#80CBC4` | FitnessCenter → `dumbbell` |
| Inny specjalista | `#5E35B1` | `#B39DDB` | Person → `person` |
| Notatka | `#546E7A` | `#B0BEC5` | EditNote → `note.text` |
| Zakup | `#A15C00` | `#FFCC80` | ShoppingCart → `cart` |
| Zawody, start | `#B71C3C` | `#F48FB1` | EmojiEvents → `trophy` |
| Trening | kolor główny | kolor główny | DirectionsRun → `figure.run` |

Terminy: kolor rodzaju (`Vet`, `Vaccination`, `Deworming` → weterynarz; `Farrier` → kowal; `Physio` → fizjoterapia;
`Specialist` → specjalista; `Competition` → zawody; `Other` → notatka); ikony jak wpis tego rodzaju, poza: szczepienie —
Vaccines → `syringe`, odrobaczanie — BugReport → `ladybug`, inne — Event → `calendar`.

**Kolory i ikony działów** (FR-KOL-03):

| Dział | Jasny | Ciemny | Ikona (Android → iOS) |
|---|---|---|---|
| Pulpit | `#3949AB` | `#9FA8DA` | Home → `house` |
| Konie | `#8D4A2B` | `#FFAB91` | głowa konia (własny rysunek) |
| Terminy | `#00838F` | `#80DEEA` | Event → `calendar` |
| Treningi | kolor główny | kolor główny | DirectionsRun → `figure.run` |
| Zakupy | `#A15C00` | `#FFCC80` | ShoppingCart → `cart` |
| Zawody | `#B71C3C` | `#F48FB1` | EmojiEvents → `trophy` |
| Kontakty | `#1565C0` | `#90CAF9` | Contacts → `person.crop.rectangle.stack` |
| Raporty | `#5E35B1` | `#B39DDB` | Assessment → `chart.bar.doc.horizontal` |
| Kosz | `#616161` | `#BDBDBD` | Delete → `trash` |
| Kopia zapasowa | `#00796B` | `#80CBC4` | Backup → `externaldrive.badge.icloud` |
| Konflikty | ostrzeżenie | ostrzeżenie | Warning → `exclamationmark.triangle` |
| Kolejka wysyłki, Słowniki, Ustawienia, O aplikacji, Więcej | tekst drugorzędny | tekst drugorzędny | CloudSync → `arrow.triangle.2.circlepath.icloud`, MenuBook → `book`, Settings → `gearshape`, Info → `info.circle`, MoreHoriz → `ellipsis` |
| Kontuzja (plakietka, kafel, filtr) | ostrzeżenie | ostrzeżenie | Healing → `bandage` |

**Rysunki własne** (z plików Androida; przenieść do katalogu zasobów jako wektor, siatka 24 × 24, linia 1,5, końce i złącza
zaokrąglone, bez wypełnienia, obraz szablonowy):

- Głowa konia (`ic_horse_head.xml`): obrys `M13.2,5.2 L14.2,1.8 L16.4,4.6 C19.6,7.6 20.6,12 20.2,16.4 L20,21.8 L12.2,21.8
  C12.6,19.2 12.2,16.8 11,15 C9.8,16.6 8.4,17.8 6.6,18.2 C5,18.6 3.4,18 3,16.6 C2.7,15.6 3.1,14.6 3.9,13.8 C6.6,10.6 9.6,7.4
  13.2,5.2 Z`; grzywa `M17.6,5.9 L19.6,5.3 M19.2,8.7 L21.3,8.5 M20.1,11.8 L22,12.2 M20.3,15 L21.9,15.8`; policzek i chrapy
  `M7.8,12.6 C9.4,12.4 10.6,13.4 11,15 M4.7,14.5 C5.3,14.4 5.6,14.9 5.4,15.4 M3.3,16.7 L4.9,16.9`; oko — punkt (11.4, 8.7),
  linia 1,9.
- Ikona aplikacji (`ic_launcher_foreground.xml`, siatka 256): biała podkowa `M78,198 C60,180 50,155 50,128 C50,84 85,50 128,50
  C171,50 206,84 206,128 C206,155 196,180 178,198 C172,204 160,204 156,196 C168,178 176,154 176,130 C176,100 155,78 128,78
  C101,78 80,100 80,130 C80,154 88,178 100,196 C96,204 84,204 78,198 Z` z sześcioma otworami (okręgi r = 4,5 o środkach
  (67, 160), (65, 128), (74, 96), (189, 160), (191, 128), (182, 96)) wyciętymi na wylot (even-odd), na ukośnym gradiencie
  `#2C7756` (lewy górny) → `#1D553E` (prawy dolny). iOS: jeden obraz 1024 × 1024 bez przezroczystości (podkowa wyśrodkowana,
  ok. 61 % szerokości), wariant ciemny i barwiony (iOS 18+). Ikona powiadomień — na iOS ikona aplikacji (system nie ma
  osobnej małej ikony).

**Odstępy i kształty**: krawędź ekranu 16 pt, przed nagłówkiem sekcji 16 pt (pod nagłówkiem 4 pt), między elementami 8 pt,
wnętrze obszaru 12 pt; obszar (kafelek) zaokrąglony 12 pt, ramka 1 pt (tylko „Nadchodzące” i „Przeterminowane”); linia
między wierszami 1 pt w kolorze obrysu delikatnego, wcięta 16 pt od lewej, **tylko między** wierszami. Nagłówek sekcji —
styl `subheadline` półgruby w kolorze głównym, oznaczony jako nagłówek dla VoiceOver. Typografia — style Dynamic Type
(tytuł ekranu półgruby; tytuły kart „headline”), bez sztywnych wysokości.

**Obszary z tonem** (FR-OBS z Androida 1.2): **Neutralny** (wariant powierzchni) — koszty, bilans, terminy z kolejki;
**Zielony** („Nadchodzące”: jasnozielone tło z zieloną ramką); **Ostrzegawczy** (pomarańczowe tło i ramka) — terminy
przeterminowane. Termin jako obszar: wiersz 1 — ikona rodzaju 20 pt w kolorze rodzaju, „rodzaj · koń”, data `dd.MM.yyyy`
z prawej; wiersz 2 — tytuł; wiersz 3 — notatka; wiersz 4 — pogrubiona etykieta stanu („Przeterminowany” / „czeka na wysłanie” /
„wymaga poprawy” / „konflikt”) i „N dni temu”.

**Pulpit** (od góry): baner pierwszego pobrania (online) · karta „Konflikty do rozstrzygnięcia: N” (tło ostrzegawcze) ·
przypomnienie o kopii (tryb samodzielny, obszar ostrzegawczy z „Utwórz teraz” i „Przypomnij później”) · „Zmiany czekające na wysłanie: N” ·
karta „Dodaj pierwszego konia” (samodzielny, brak koni) · **Szybkie dodawanie** — przewijany poziomo wiersz chipów z ikoną
w kolorze rodzaju: Weterynarz · Kowal · Kilka koni (kowal) · Termin · Zakup · Zawody (start) · Trening · Notatka · obszary
terminów: „Przeterminowane” (ostrzegawczy), „Nadchodzące (najbliższe N dni)” (zielony), „Później w tym miesiącu” (neutralny),
w środku wiersze rozdzielone liniami; bez terminów — „Brak terminów do wykonania” · **Koszty** — dwa obszary neutralne obok
siebie: „Ten miesiąc” i „Poprzedni miesiąc” · **Ostatnie wpisy** — wiersze z paskiem i ikoną rodzaju, tytuł, „rodzaj ·
skrót · stan”, data z prawej · **Konie** — kafle po **2 w rzędzie**, odstęp 12 pt, równa wysokość w rzędzie, treść do góry:
miniatura 40 pt (okrąg; bez zdjęcia głowa konia), imię, „imię stajenne” w cudzysłowie, najbliższy termin („data · tytuł”,
przeterminowany pogrubiony z dopiskiem), „bez paszportu od X mies.”; tło wariantu powierzchni, przy ≥ 12 mies. bez paszportu —
kontener ostrzegawczy; kontuzja — ikona plastra 24 pt w prawym górnym rogu. Dół listy z zapasem 96 pt na przycisk „+”.

**Lista koni**: pole wyszukiwania; chipy filtrów: Aktywny · Kontuzjowany (gdy dostępny) · Pokaż wszystkie · Tylko źrebięta;
wiersz: miniatura 40 pt, imię (tytuł), „imię stajenne” mniejszą, jaśniejszą czcionką, podtytuł (numer paszportu albo „brak
paszportu” / „bez paszportu od X mies.” u źrebaka), plakietka „Kontuzjowany”; przycisk „Dodaj konia” na końcu listy
(„+” na dole dodaje wpis, nie konia).

**Karta konia**: nagłówek — miniatura 72 pt (okrąg; bez zdjęcia głowa konia i „Dodaj zdjęcie” w kolorze głównym; dotknięcie →
arkusz zdjęcia), imię, imię stajenne, status (plakietka), „Paszport: …”, UELN, chip; przycisk edycji w pasku nawigacji;
„Najbliższe terminy” (każdy termin jako obszar), „Koszty <rok>” (obszar neutralny z podziałem na kategorie i sumą), skrót
bilansu (zakup, koszty, nagrody, sprzedaż, wynik, „Pełny bilans”); przewijany pasek zakładek: Oś czasu · Terminy · Paszport ·
Treningi · Zawody · Zakupy · Załączniki. Oś czasu — chipy filtra rodzaju („Wszystkie” + rodzaje), wiersze z paskiem koloru,
„Pokaż starsze”.

**Gwiazdki oceny**: wyświetlanie „★★★☆☆” — wypełnione w kolorze ostrzeżenia, puste w kolorze tekstu drugorzędnego, brak
oceny „—”, VoiceOver „Ocena: N z 5” / „Brak oceny”; wprowadzanie — 5 przycisków gwiazdek ≥ 44 pt („N z 5”), „Wyczyść”.

**Formularze**: nagłówek z akcentem koloru rodzaju wpisu (ikona w kółku), sekcje z nagłówkami (5.3), „*” przy polach
wymaganych, „Zapisz” w pasku nawigacji i szeroki przycisk „Zapisz” przypięty u dołu nad klawiaturą (w trakcie zapisu —
wskaźnik postępu, przycisk nieaktywny), błędy pod polami.

**Raporty**: wyniki jako karty rozdzielone odstępem (nie linie), wiersze „etykieta — wartość” wg FR-027.

**Komunikat połączenia**: nakładka u góry treści (FR-M-POL-17), zwijana do ikonki w pasku nawigacji: pomarańczowa
(`wifi.exclamationmark` / brak połączenia) albo czerwona (`exclamationmark.octagon` / wymaga działania).

---

## 6. Współpraca z programem na komputer (API)

Pełny kontrakt: `openapi.yaml` programu w wersji 1.6.1 (`/api/v1` bez zmian od 1.5.0) (patrz uwaga na początku dokumentu). Poniżej to, czego
aplikacja potrzebuje.

### 6.1 Zasady

| Aspekt | Ustalenie |
|---|---|
| Adres bazowy | Z kodu QR, np. `http://192.168.1.20:5080/api/v1` (lub `https://…`) |
| Nagłówki | `X-Api-Key: hk_…`, `Accept: application/json`; przy edycji `version` w treści (lub `If-Match`) |
| Format | JSON UTF‑8, `camelCase`; daty `"2026-09-30"`, data i czas `"2026-09-30T14:30:00"`, kwoty liczbami (`250.00`) |
| Listy | `page`, `pageSize` (maks. 200), odpowiedź `{ items, page, pageSize, totalCount }` |
| Usuwanie | `DELETE` = do kosza programu; przywracanie i trwałe usuwanie tylko w programie |
| Limity | 100 żądań / 10 s na klucz (`429`), plik do 100 MB (`413`), typ pliku (`415`) |
| Błędy | RFC 9457 `application/problem+json`; `errors` = słownik pole → lista komunikatów po polsku |
| Konflikty | `409` przy niezgodnej wersji (treść zawiera aktualny rekord) i przy naruszeniu unikalności |
| Bez klucza | `GET /system/info` — wersja programu, wersja schematu, czas serwera (test połączenia); od programu 1.2 z adresów spoza sieci lokalnej wymaga klucza — aplikacja zawsze wysyła klucz (FR-M-POL-03) |
| Spoza sieci domowej (program 1.2) | Tylko `https`; blokada adresu po 10 nieudanych próbach w 10 min (`429` z `Retry-After`, od 1 h do 7 dni); klucz bez zgody na dostęp spoza domu → `403` z treścią `key-home-only`; tryb wyłączony w programie → `403` bez treści (FR-M-POL-13); dokumentacja API niedostępna (`404`). Adresem spoza sieci domowej jest każdy adres spoza zakresów prywatnych, także adres VPN (np. Tailscale `100.64.0.0/10`) |

### 6.2 Kod QR parowania

Program pokazuje kod QR po wygenerowaniu klucza (Ustawienia → API → Generuj klucz). Treść — JSON:

```json
{ "url": "https://192.168.1.20:5080/api/v1", "key": "hk_Xy…", "certSha256": "3F9A…C1",
  "remoteUrl": "https://stajnia.dyndns.org:48123/api/v1" }
```

albo, przy stałym publicznym adresie IP: `"remoteUrl": "https://203.0.113.25:48123/api/v1"`.

- `url` — pierwszy adres komputera w sieci lokalnej (dodatkowe adresy, np. VPN, użytkownik dopisuje w aplikacji);
- `key` — klucz API (pokazywany tylko raz; w programie przechowywany wyłącznie jako skrót);
- `certSha256` — odcisk SHA‑256 certyfikatu (wielkie litery HEX, bez separatorów) albo `null`, gdy HTTPS wyłączone;
- `remoteUrl` — (od programu 1.2, opcjonalne) adres publiczny przy włączonym dostępie spoza sieci domowej: nazwa DynDNS
  albo stały publiczny adres IP (IPv4 lub IPv6 w nawiasach kwadratowych); obecny tylko, gdy klucz ma zgodę na dostęp
  spoza domu. Brak pola lub `null` — dostęp tylko w sieci lokalnej. Aplikacja MUST ignorować nieznane pola kodu QR.

### 6.3 Używane zasoby

| Obszar | Metody i ścieżki |
|---|---|
| System | `GET /system/info` |
| Pulpit | `GET /dashboard` |
| Konie | `GET /horses` (`status`, `q`, `foal`), `GET/POST/PUT /horses[/{id}]`, `GET /horses/{id}/timeline`, `GET /horses/{id}/photo`, `GET /horses/{id}/stats/competitions`, `GET /horses/{id}/farrier-next-date?visitDate=` |
| Wizyty | `/vet-visits`, `/farrier-visits`, `/physio-visits`, `/specialist-visits` — `GET/POST/PUT/DELETE` |
| Zawody | `/competitions` (CRUD), `/competitions/{id}/starts` (CRUD), `GET /competition-starts?horseId=` |
| Zakupy | `/purchases` (CRUD; filtry `horseId`, `categoryId`, `general`) |
| Notatki | `/notes` (CRUD) |
| Treningi | `/trainings` (CRUD; filtry `horseId`, `from`, `to`, `typeId`, `trainerId`, `riderId`; lista z `totalCost`) — od 1.3 |
| Terminy | `/reminders` (CRUD; filtry `status`, `kind`, `dueFrom`, `dueTo`, `overdue`), `POST /reminders/{id}/complete`, `POST /reminders/{id}/dismiss` |
| Kontakty | `/contacts` (CRUD; `type`, `includeArchived`); `type=Trainer` / `type=Rider` dla pól trenera i jeźdźca |
| Słowniki | `GET /dictionaries` (tylko odczyt w aplikacji) |
| Załączniki | `GET /attachments?ownerType=&ownerId=`, `POST /attachments` (`multipart/form-data`: `ownerType`, `ownerId`, `description`, `file`), `GET /attachments/{id}/content` (obsługa `Range`), `GET /attachments/{id}/thumbnail`, `DELETE /attachments/{id}` |
| Raporty | `GET /reports/costs` (`from`, `to`, `horseIds` — pusty = wszystkie, `general` = tylko ogólne, `categories`, `groupBy=horse|month|category`); `GET /reports/horse-balance` (`status`, `horseIds`); `GET /reports/training-summary` (`horseId` — wymagany, `range=week|month|year|all`, `date`); `GET /reports/rider-trainings` i `GET /reports/rider-competitions` (`riderId` — brak = wszyscy jeźdźcy, `horseId`, `from`, `to`; także starty na karcie kontaktu-jeźdźca) |

| Pełne pobranie (2.0) | `GET /export?scope=full` (strumień JSON w schemacie eksportu 1.4/1.5; z `updatedSince` — zmiany od punktu, program 2.0.0) |
| Kosz programu (2.0) | `GET /trash` (odczyt partii z `rootVersion`), `POST /trash/{type}/{id}/restore` (przywrócenie przy „Zachowaj moją” w konflikcie usunięcie–zmiana; z `If-Match` przy `ifMatchDelete`) |

Nieużywane przez aplikację: zapisy w `/dictionaries`, trwałe usuwanie i opróżnianie kosza programu.

### 6.4 Pola formularzy

Pola wymagane przez API pogrubione.

| Zasób | Pola |
|---|---|
| Koń (`HorseInput`) | **name**, passportNumber (wymagany, gdy `isFoal = false`), isFoal, stableName, ueln, microchipNumber, passportIssuer, passportIssueDate, breed, sex (`Mare`/`Stallion`/`Gelding`), color, birthDate, birthYearOnly, birthCountry, sire, dam, damSire, breeder, owner, markings, photoAttachmentId, farrierIntervalWeeks (1–26), status (`Active`/`Sold`/`Deceased`/`Leased`), statusDate, statusNote, notes, finance (`purchasePrice`, `purchaseDate`, `salePrice`, `saleDate`, `estimatedValue` — od 1.3; pominięty przy zapisie = bez zmian) |
| Wizyta weterynaryjna | **horseId**, **visitDateTime**, **visitTypeId**, contactId, reason, diagnosis, recommendations, vaccineOrProduct, batchNumber, cost, medications[] (name, dosage, sposób: `AdministeredAtVisit`/`Prescribed`), nextVisitDate, nextVisitPurpose, kwota w walucie |
| Kowal | **horseId**, **visitDate**, **serviceId**, contactId, hoofNotes, cost, nextVisitDate (serwer nie wylicza — podpowiedź to funkcja aplikacji) |
| Fizjoterapia | **horseId**, **visitDate**, contactId, reason, bodyAreaIds[], techniqueIds[], observations, recommendations, cost, nextVisitDate, nextVisitPurpose |
| Specjalista | **horseId**, **visitDate**, **specialistTypeId**, contactId, reason, description, recommendations, cost, nextVisitDate, nextVisitPurpose |
| Zawody | **name**, **dateFrom**, dateTo, city, venue, organizerContactId, rankId, disciplineId, notes |
| Start | **horseId**, startDate, disciplineId, className, riderContactId (kontakt typu `Rider`; od 1.5 zamiast tekstowego `rider`, odpowiedź zawiera też `riderName`), placement, participantsCount, resultStatus (`Completed`/`Eliminated`/`Retired`/`DidNotStart`), penaltyPoints, scorePercent, timeSeconds, description, subjectiveRating (1–5), entryFee, otherCosts, prizeMoney |
| Zakup | **purchaseDate**, **productName**, **categoryId**, supplierContactId, quantity, unitId, unitPrice, **totalAmount** (bez dostawy), deliveryCost (≥ 0, domyślnie 0), **assignment** (`SingleHorse`/`MultipleHorses`/`General`), horseIds[], notes; odpowiedź zawiera `totalCost` |
| Notatka | **horseId**, **noteDate**, **title**, content, isPinned |
| Trening | **horseId**, **trainingDate** (nie z przyszłości), **trainingTypeId**, durationMinutes (1–600), intensity (`Light`/`Medium`/`Hard`), obstacleHeightCm (10–200, tylko rodzaj `training.jumping`), riderContactId (`PUT` bez pola = bez jeźdźca), rating (1–5), description, coaching (`trainerContactId`, `cost`, `originalAmount`, `originalCurrency`; `PUT` bez obiektu = bez zmian); odpowiedź zawiera też `horseName`, `trainingTypeName`, `trainerName`, `riderName` |
| Termin | **horseId**, **kind** (`Vet`, `Vaccination`, `Deworming`, `Farrier`, `Physio`, `Specialist`, `Competition`, `Other`), **dueDate**, **title**, specialistTypeId, notes |
| Kontakt | **name**, **types[]** (`Vet`, `Farrier`, `Physio`, `Specialist`, `Shop`, `Organizer`, `Other`, `Trainer`, `Rider`), company, phone, email, address, specialization, notes, isArchived |

Polskie nazwy wartości wyliczeniowych MUST być zgodne z programem (np. `Deworming` → „Odrobaczanie”,
`General` → „Ogólny (cała stajnia)”, `Leased` → „Wydzierżawiony”, `Deceased` → „Padł”, `Trainer` → „Trener”,
`Rider` → „Jeździec”, `Hard` → „Ciężka”).

### 6.5 Automatyczne działania programu

**FR-M-PRG-01**: Aplikacja MUST NOT powielać logiki, którą wykonuje program — po zapisie odświeża dane:

- wpis z datą następnej wizyty tworzy termin; zarejestrowanie wizyty zamyka pasujący otwarty termin
  (z tolerancją 14 dni przed terminem);
- zawody w przyszłości tworzą termin;
- zakup dla kilku koni jest dzielony po równo (różnica groszowa do pierwszego konia wg imienia);
- zmiana statusu konia na „Padł” ustawia cenę sprzedaży 0 (od 1.3);
- koszt treningu wchodzi do kategorii „Treningi” w raporcie kosztów i na pulpicie (od 1.4);
- kontaktu wskazanego jako trener lub jeździec program nie usunie (`409` `InUse`) — można go tylko zarchiwizować.

---

### 6.6 Zalecenia dla programu na komputerze (wersja 2.0 aplikacji)

Wersja 2.0 aplikacji działa z programem 1.6.1 bez zmian po stronie programu (pełne pobranie `GET /export?scope=full`, wersje rekordów w `If-Match`).
Poniższe zmiany programu ułatwiłyby synchronizację i usunęłyby obejścia w aplikacji — **zalecenia, nie wymagania 2.0**:

- `updatedSince` (albo `ETag`/`since` na listach i w `GET /export`): zmiany przyrostowe zamiast pełnego pobrania co godzinę;
- `If-Match` także przy `DELETE` (dziś aplikacja sprawdza wersję osobnym `GET`, więc zmiana między `GET` a `DELETE` nie jest wykrywana);
- `Idempotency-Key` przy `POST` (dziś duplikaty po zerwanym połączeniu wykrywa „licznik przed i po”);
- `PUT /horses/{id}` przyjmujący `photoAttachmentId` (dziś ignorowane — `AttachmentService.SetHorsePhotoAsync` nie ma punktu końcowego), żeby zdjęcie konia
  ustawione w telefonie wracało z programu; do tego czasu aplikacja pamięta wybór zdjęcia lokalnie.

#### Stan w programie 2.0.0 i jak go wykryć

Program 2.0.0 wdraża wszystkie powyższe zalecenia. Aplikacja sprawdza, które działają, w polu `capabilities` odpowiedzi `GET /system/info` (nazwy są umową z programem;
program starszy niż 2.0.0 nie ma tego pola — aplikacja używa wtedy dotychczasowych obejść):

| Zalecenie | Nazwa w `capabilities` | Jak z tego korzystać |
|---|---|---|
| Zmiany przyrostowe | `updatedSince` | `GET /export?scope=full&updatedSince=<chwila>` zwraca schemat 1.5: zmienione rekordy, `trashed[]`, `purged[]`, `scope.nextUpdatedSince`, `scope.fullRequired` (gdy trzeba pobrać wszystko) |
| `If-Match` przy `DELETE` i przy przywracaniu | `ifMatchDelete` | niezgodna wersja → `409` z aktualnym rekordem, rekord nietknięty |
| `Idempotency-Key` przy `POST` | `idempotencyKey` | powtórzenie tego samego żądania → zapamiętana odpowiedź i `Idempotent-Replayed: true` |
| `photoAttachmentId` w `PUT /horses/{id}` | `horsePhotoField` | brak pola = bez zmiany, `null` = brak zdjęcia, identyfikator obrazu tego konia = ustaw zdjęcie |
| Stempel danych | `dataStamp` | `dataStamp` w `GET /system/info` zmienia się po każdej zmianie danych; ten sam stempel = nic do pobrania |
| Status „Kontuzjowany” | `horseStatusInjured` | nagłówek `X-Client-Features: horse-status-injured`; bez niego program pokazuje `Active` i zachowuje status `Injured` przy zapisie `Active` |

Wartości statusu konia w odpowiedziach: `Active`, `Sold`, `Deceased`, `Leased`, a dla klienta z nagłówkiem także `Injured`. Filtr listy: bez `status` — aktywne i
kontuzjowane; `status=Active` dla klienta z nagłówkiem — tylko aktywne, dla klienta bez nagłówka — aktywne i kontuzjowane (widziane jako aktywne); `status=Injured` — tylko
kontuzjowane; `status=all` — wszystkie. Pełny opis: `specs/009-horsely-2-0-0/contracts/api-2.0-changes.md`.

---

## 7. Wymagania niefunkcjonalne

| ID | Wymaganie |
|---|---|
| NFR-M-01 | Uruchomienie do pulpitu z pamięci podręcznej < 2 s; odświeżenie pulpitu z komputerem w tej samej sieci Wi‑Fi < 2 s. Progi czasowe (NFR-M-01…03, SC-M-02, SC-M-09) mierzy się na urządzeniu odniesienia platformy — iOS: **iPhone 15 Pro** (urządzenie, na którym aplikacja będzie uruchamiana); Android: Honor Magic 6 Pro |
| NFR-M-02 | Zapis wpisu (do programu albo do kolejki) — informacja zwrotna < 1 s; dodanie notatki ze zdjęciem możliwe w < 30 s od otwarcia aplikacji |
| NFR-M-03 | Pełne odświeżenie pamięci dla 50 koni i 50 000 wpisów (oś czasu 12 mies.) < 60 s w sieci Wi‑Fi, w tle, bez blokowania interfejsu, z poszanowaniem limitu żądań |
| NFR-M-04 | Klucz API przechowywany wyłącznie w bezpiecznym magazynie systemu, niedostępny dla kopii zapasowych w chmurze i innych aplikacji; nigdy w logach ani w komunikatach |
| NFR-M-05 | Pamięć podręczna i kolejka w prywatnym obszarze aplikacji; wykluczone z kopii w chmurze (dane pochodzą z programu, który ma własne kopie) |
| NFR-M-06 | Logi diagnostyczne bez treści wpisów, nazw koni i danych kontaktów; rotacja (maks. 5 MB) |
| NFR-M-07 | Dostępność: czytnik ekranu (etykiety wszystkich kontrolek), skalowanie tekstu do 200% bez obcinania, kontrast WCAG 2.1 AA, cele dotyku ≥ 48 dp / 44 pt |
| NFR-M-08 | Działanie w tle oszczędne dla baterii: odświeżanie w tle nie częściej niż co godzinę i tylko przy połączeniu z komputerem |
| NFR-M-09 | Zużycie danych: bez połączenia z komputerem aplikacja nie łączy się z żadnym innym serwerem (brak telemetrii, reklam i usług zewnętrznych; jedyny wyjątek — mapy/telefon/e‑mail otwierane w innych aplikacjach na żądanie; brak sprawdzania aktualizacji w internecie — FR-M-UST-06). |
| NFR-M-10 | Odporność: przerwanie połączenia, zamknięcie aplikacji przez system lub restart telefonu w dowolnym momencie nie powoduje utraty wpisu z kolejki ani duplikatu w programie |
| NFR-M-11 | Zgodność wstecz z programem: aplikacja działa z programem 1.5.0 i nowszymi wersjami `/api/v1` (w 1.6.0 i 1.6.1 kontrakt bez zmian); nieznane pola w odpowiedziach są ignorowane; z programem 1.1–1.4 aplikacja nie współpracuje (FR-M-POL-04) |
| NFR-M-12 | Testy: logika kolejki, mapowanie błędów, podpowiedzi (kowal, kwota zakupu, trener / jeździec / koszt z ostatniego treningu), mapowanie terminów na formularze, format czasu i kwot w raportach, zawartość CSV raportów (porównanie z plikami CSV
  programu dla tych samych danych) — testy jednostkowe; komunikacja z API — testy z serwerem testowym (zaślepka zgodna z `openapi.yaml`);
  od 2.0 także: reguły trybu samodzielnego na plikach wzorcowych programu (te same co w Androidzie), łączenie operacji kolejki,
  konflikty, kopia zapasowa (zgodność plików z Androidem), kontrast palety |

---

## 8. Kryteria sukcesu

- **SC-M-01**: Nowy użytkownik paruje aplikację z programem (od otwarcia aplikacji do pulpitu z danymi) w < 2 minuty,
  bez wpisywania adresu ani klucza.
- **SC-M-02**: Notatkę ze zdjęciem z aparatu dla wybranego konia da się dodać w < 30 s; wizytę kowala z podpowiedzianą
  datą następnej wizyty w < 45 s; trening z podpowiedzianym trenerem, jeźdźcem i kosztem w < 30 s.
- **SC-M-03**: 100% operacji dodanych bez połączenia trafia do programu po odzyskaniu połączenia, bez duplikatów —
  sprawdzane na scenariuszu: 20 wpisów i 10 zdjęć bez sieci, przerwanie połączenia w trakcie wysyłania, restart telefonu.
- **SC-M-04**: Kwoty i terminy w aplikacji są zgodne z programem w 100% (pulpit, karta konia, lista treningów z podliczeniem, wszystkie raporty, co do grosza).
- **SC-M-05**: Dzienne powiadomienie pojawia się o ustawionej godzinie (± 15 min) przy wyłączonym komputerze, na podstawie
  danych odświeżonych wcześniej (w Androidzie — przy wyłączonej optymalizacji baterii, FR-M-POW-05); sprawdzane na urządzeniu
  odniesienia (NFR-M-01).
- **SC-M-06**: Klucz API nie pojawia się w żadnym logu, kopii zapasowej telefonu ani zrzucie ekranu ustawień.
- **SC-M-07**: Wszystkie ekrany przechodzą przegląd dostępności (czytnik ekranu, tekst 200%, kontrast) bez błędów krytycznych.
- **SC-M-08**: Przy łączeniu przez adres publiczny aplikacja nigdy sama nie doprowadza do zablokowania adresu telefonu —
  sprawdzane scenariuszem: 50 uruchomień i powrotów do aplikacji w 10 minut oraz kolejka 20 wpisów po unieważnieniu klucza
  w programie → 0 blokad (najwyżej 1 odmowa na adres przed wstrzymaniem żądań).
- **SC-M-09**: Dla tych samych filtrów każdy z pięciu raportów w aplikacji pokazuje te same wartości i sumy co program
  (100% zgodności co do grosza i minuty na zestawie testowym); plik CSV z aplikacji jest bajt w bajt zgodny z CSV
  programu dla tych samych danych, a PDF ma te same dane i elementy (czytelny wykres, nagłówek z filtrami) w układzie
  aplikacji. Raport dla 2 000 treningów
  albo 50 koni wyświetla się w < 3 s w sieci Wi‑Fi, a PDF z wykresem powstaje i otwiera się w oknie udostępniania
  w < 5 s.
- **SC-M-10** (wersja 1.1): Przy działającym programie 30 przejść między zakładkami po 60 s bezczynności nie pokazuje komunikatu
  „brak połączenia”; po uruchomieniu zamkniętego programu „Odśwież” kończy tryb bez połączenia w ≤ 5 s, a bez dotykania
  aplikacja wykrywa powrót komputera w ≤ 30 s; komunikat nie przesuwa treści ekranu.
- **SC-M-11** (wersja 1.1): Dla tych samych filtrów dział Treningi, Zakupy i Zawody pokazuje te same rekordy, liczbę i sumy co
  program (100% zgodności co do grosza).
- **SC-M-12** (iOS): Dla każdego ekranu z listy w [5.2](#52-struktura) i [5.4](#54-wzorzec-wyglądu) zrzut ekranu iOS i Androida
  2.0.1 na tych samych danych pokazuje te same elementy w tej samej kolejności, te same teksty, kolory (± odcień systemowy)
  i ikony (SF Symbol odpowiadający ikonie Material z tabeli) — w motywie jasnym i ciemnym.
- **SC-M-13** (iOS): Kopia zapasowa utworzona na Androidzie 2.0.1 odtwarza się na iOS (i odwrotnie) z 100 % rekordów i
  zgodnymi `sha256` załączników, z hasłem i bez.

Kryteria wersji 2.0 (te same identyfikatory co na Androidzie):

- **SC-2-01**: Tryb samodzielny i pierwszy koń w < 1 min od pierwszego otwarcia, bez sieci.
- **SC-2-02**: W trybie samodzielnym 0 połączeń sieciowych podczas 30 min pracy obejmującej wszystkie funkcje.
- **SC-2-03**: Zestaw testowy (≥ 10 koni, ≥ 1 000 wpisów i treningów, zakupy dla kilku koni, zawody) w trybie samodzielnym
  i w programie: 100 % zgodności terminów automatycznych, podziału kosztów i sald, identyczne raporty, CSV bajt w bajt.
- **SC-2-04**: Offline w trybie online — 10 nowych rekordów, 20 edycji, 5 usunięć, 3 „Przełóż”, 1 nowy koń, w tym czasie
  5 tych samych rekordów zmienionych w programie, przerwanie wysyłania i restart telefonu → 0 utraconych zmian, 0 duplikatów,
  100 % konfliktów wykrytych, kolejka pusta po rozstrzygnięciu.
- **SC-2-05**: Pierwsze pełne pobranie 50 koni / 50 000 wpisów (bez oryginałów załączników) < 3 min w Wi‑Fi, aplikacja używalna.
- **SC-2-06**: W obu trybach Pulpit z danych w telefonie < 2 s, każdy raport dla 2 000 treningów albo 50 koni < 3 s bez połączenia.
- **SC-2-07**: Kopia 50 koni, 50 000 wpisów i 1 GB załączników < 5 min; odtworzenie na innym telefonie — dane identyczne.
- **SC-2-08**: W 20 próbach zmiany trybu dane nigdy nie są usuwane bez dwóch potwierdzeń ani przed udanym parowaniem.
- **SC-2-10**: Wszystkie kolorowe elementy przechodzą kontrast WCAG 2.1 AA w obu motywach; 8 rodzajów wpisu rozróżnialnych
  po kolorze i ikonie.
- **SC-2-11**: Zdjęcie konia z aparatu, z kadrowaniem, w < 30 s od otwarcia karty konia; miniatury widoczne bez połączenia.

Kryteria wersji 2.0.1: **SC-001** pliki wzorcowe programu 2.0.0 (słowniki, koń kontuzjowany) dają identyczne wyniki;
**SC-003** odświeżenie bez zmian w programie 2.0.0 przesyła ≥ 95 % mniej danych niż pełne pobranie i trwa < 2 s;
**SC-005** 100 przerwań przy dodawaniu z programem 2.0.0 → 0 duplikatów i 0 utraconych wpisów; **SC-006** status
„Kontuzjowany” przechodzi w obu kierunkach bez konfliktu; **SC-007** z programem 1.6.1 wszystkie scenariusze 2.0 przechodzą;
**SC-008** 0 wystąpień nazwy „Zarządzanie końmi” w interfejsie; **SC-009** żaden wiersz raportu nie łamie się po literze
(tekst 100 % i 200 %, szerokość 320 pt); **SC-010** z dziennika w < 1 min widać adres, IP i przyczynę nieudanego odświeżenia,
0 wpisów z kluczem lub danymi osobowymi.

---

## 9. Wymagania platformy iOS

### 9.1 Wersje i urządzenia

| Aspekt | Ustalenie |
|---|---|
| Minimalna wersja | iOS 17 |
| Urządzenia | iPhone; iPad z układem telefonu (bez osobnego układu dwukolumnowego) |
| Urządzenie docelowe i odniesienia | **iPhone 15 Pro** — na nim aplikacja będzie uruchamiana; na nim mierzy się progi czasowe (NFR-M-01) i wykonuje testy na urządzeniu (Face ID, aparat i skaner QR, powiadomienia, praca w tle, VoiceOver, tekst 200 %). Układ MUST uwzględniać Dynamic Island i ekran 6,1″ (393 × 852 pt); działanie na innych iPhone'ach z iOS 17+ zapewnia układ adaptacyjny |
| Orientacja | Pionowa; pozioma dozwolona dla podglądu zdjęć i wideo |

### 9.2 Zgody i opisy w `Info.plist`

> **Wersja 2.0.** Blokada aplikacji (FR-TRB-09) używa `LocalAuthentication` (Face ID / Touch ID / kod urządzenia): dodaj `NSFaceIDUsageDescription`
> („Odblokowanie aplikacji z danymi stajni”), bez osobnego PIN-u aplikacji. Plik kopii zapasowej i folder kopii automatycznych — `UIDocumentPicker`
> (zakładka z uprawnieniem do folderu, `startAccessingSecurityScopedResource`).

| Klucz | Po co | Kiedy system pyta |
|---|---|---|
| `NSLocalNetworkUsageDescription` | Połączenie z komputerem w sieci lokalnej (iOS wymaga zgody „Sieć lokalna”) | Przy pierwszym połączeniu z adresem w sieci lokalnej — aplikacja MUST wcześniej pokazać ekran wyjaśnienia, a po odmowie instrukcję włączenia zgody w Ustawieniach |
| `NSCameraUsageDescription` | Skanowanie kodu QR, zdjęcia | Przy pierwszym skanowaniu / zdjęciu |
| Powiadomienia (`UNUserNotificationCenter`) | Przypomnienia o terminach, błąd kopii automatycznej | Po parowaniu albo po wyborze trybu samodzielnego, z ekranem wyjaśnienia |
| Brak dostępu do biblioteki zdjęć | Wybór zdjęć przez `PHPickerViewController` / `PhotosPicker` (bez zgody), plików przez selektor dokumentów | — |

Aplikacja MUST NOT prosić o lokalizację, kontakty (import kontaktu przez `CNContactPicker` bez zgody) ani pełny
dostęp do biblioteki zdjęć.

### 9.3 Sieć i bezpieczeństwo

- **App Transport Security**: `NSAllowsLocalNetworking = YES` (połączenia `http` z adresami w sieci lokalnej i `.local`);
  adresy spoza zakresów lokalnych — VPN (np. Tailscale `100.x.y.z`), nazwa DynDNS, stały publiczny adres IP — MUST działać
  przez `https` w trybie zaufania z FR-M-POL-05; przy takim adresie z `http` aplikacja MUST pokazać wyjaśnienie, że trzeba
  włączyć HTTPS w programie.
  Wyjątku `NSAllowsArbitraryLoads` MUST NOT być używany (wymóg App Review).
- **Certyfikat samopodpisany**: obsługa `URLSessionDelegate` `didReceive challenge` — akceptacja wyłącznie certyfikatu
  o odcisku SHA‑256 z parowania (FR-M-POL-05); weryfikacja nazwy hosta pomijana tylko dla przypiętego certyfikatu.
- **Zaufany wystawca** (FR-M-POL-05): dla adresu potwierdzonego w tym trybie — domyślna ocena zaufania systemu
  (`SecTrustEvaluateWithError`, łańcuch i nazwa hosta); tryb zapisany osobno dla każdego adresu.
- **Sieć lokalna** (FR-M-POL-06): `http` tylko dla prywatnego IP podanego wprost i nazw `.local`; każda inna nazwa —
  `https`, nawet jeśli rozwiązuje się na adres prywatny.
- **Klucz API**: pęk kluczy (Keychain), `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — dostępny dla pracy w tle,
  niekopiowany do kopii iCloud ani na inne urządzenie.
- **Kopie zapasowe**: pamięć podręczna i kolejka z atrybutem `isExcludedFromBackup` (NFR-M-05); pliki kolejki
  z ochroną `completeUntilFirstUserAuthentication`. Dane trybu samodzielnego także wykluczone z iCloud (FR-KOP-06) —
  zabezpieczeniem jest kopia `.zkkopia`.
- **Szyfrowanie kopii z hasłem** (FR-KOP-07, FR-KOP-09): AES-256-GCM (`CryptoKit`) i PBKDF2-HMAC-SHA256 310 000 iteracji
  (`CommonCrypto`), układ pliku jak w `backup-format.md`; ZIP zgodny z `java.util.zip` (DEFLATE/STORED).
- **Dziennik połączeń** (FR-030): IP faktycznego połączenia z `URLSessionTaskMetrics` (`remoteAddress`), rodzaj sieci
  z `NWPathMonitor`.
- Ekran z kluczem (wpisywanie ręczne) MUST ukrywać treść w przełączniku aplikacji (zasłona przy przejściu w tło).

### 9.4 Praca w tle

- iOS nie gwarantuje regularnej pracy w tle. Odświeżanie: **`BGAppRefreshTask`** (system decyduje o terminie; aplikacja
  prosi o 60 min, a przy programie z `dataStamp` o 15 min — FR-015) oraz odświeżenie przy każdym otwarciu aplikacji;
  pełne pobranie danych w tle (FR-SYN2-02, raz na dobę przy `updatedSince` — FR-016) w **`BGProcessingTask`**
  (`requiresNetworkConnectivity`), z wznawianiem przy kolejnym otwarciu; aplikacja MUST poprawnie działać, gdy praca
  w tle nie następuje wcale. Kryteria czasowe odświeżania w tle z Androida (SC-003a: zmiana z programu w telefonie
  ≤ 20 min) na iOS są celem „w miarę możliwości systemu”, nie wymaganiem.
- Kopia automatyczna co tydzień (FR-KOP-08): `BGProcessingTask`; gdy system jej nie uruchomi, kopia powstaje przy najbliższym
  otwarciu aplikacji po terminie; błąd → lokalne powiadomienie.
- Blokada aplikacji (FR-TRB-09): `LocalAuthentication` (`deviceOwnerAuthentication` — Face ID / Touch ID z kodem urządzenia
  jako zapasowym); przy przejściu w tło zasłona (widok z ikoną) ukrywa treść w przełączniku aplikacji; licznik 5 min od
  przejścia w tło. Brak kodu urządzenia (`LAError.passcodeNotSet`) → przełącznik nieaktywny z wyjaśnieniem.
- Wysyłanie załączników i kolejki: **tło `URLSession`** (background configuration) — wysyłka kontynuowana po
  zamknięciu aplikacji; operacje JSON wysyłane przy otwarciu aplikacji, w `BGProcessingTask` i po odzyskaniu sieci
  (`NWPathMonitor`).
- Powiadomienia lokalne: `UNCalendarNotificationTrigger`. Limit iOS **64 zaplanowanych powiadomień** — aplikacja
  MUST planować najbliższe: dzienne podsumowania na 14 dni naprzód i powiadomienia w dniu terminu dla najbliższych
  terminów, w sumie ≤ 60; uzupełnia je przy każdym odświeżeniu.
- Treść powiadomień z opcją ukrycia szczegółów (FR-M-POW-04) — dodatkowo respektuje systemowe ustawienie podglądów.

### 9.5 Integracje systemowe

- **Rozszerzenie udostępniania (Share Extension)** dla obrazów, wideo, PDF i dokumentów (US4/6); rozszerzenie
  zapisuje plik do wspólnego kontenera (App Group) i dodaje operację do kolejki — nie łączy się samo z komputerem.
- **Akcje kontaktu**: `tel:`, `sms:`, `mailto:`, Mapy Apple (`maps://`) dla adresu.
- **Szybkie akcje** ikony (Home Screen Quick Actions): „Dodaj notatkę”, „Kowal”, „Terminy” — SHOULD.
- **Wygląd**: komponenty systemowe zgodne z Human Interface Guidelines, ale kolory, ikony, kolejność elementów i teksty
  wg wzorca [5.4](#54-wzorzec-wyglądu) (identyczne z Androidem 2.0.1); motyw jasny/ciemny z wyborem w aplikacji
  (`preferredColorScheme`), Dynamic Type; kolor akcentu aplikacji (`AccentColor`) = kolor główny `#2E7D32` / `#81C784`.
- **Ikony**: SF Symbols wg tabeli w [5.4](#54-wzorzec-wyglądu); głowa konia i podkowa — własne obrazy wektorowe.
- **Gest przesunięcia wstecz** i zamknięcie arkusza formularza MUST pytać o niezapisane zmiany (FR-M-WPI-07).
- Zdjęcia z aparatu w formacie HEIC są dozwolone przez program; przy włączonym zmniejszaniu SHOULD wysyłać JPEG
  dla lepszej zgodności podglądu w programie na Windows.

### 9.6 Dystrybucja

- Wymaga konta Apple Developer Program. Testy przez **TestFlight**, potem App Store (lub dystrybucja niepubliczna,
  jeśli dostępna).
- **App Review**: od wersji 2.0 aplikacja działa bez programu w **trybie samodzielnym** (FR-TRB-*), więc recenzent może
  sprawdzić wszystkie funkcje bez serwera — osobny tryb demonstracyjny nie jest wymagany (ekran powitania MUST pozostać taki
  jak na Androidzie). W notatkach dla recenzenta: opis trybu samodzielnego i działania z programem Horsely na Windows; SHOULD
  dołączyć plik kopii zapasowej z danymi przykładowymi do odtworzenia („Odtwórz z kopii zapasowej”).
- Nazwa w App Store: „Horsely – Zarządzanie Koniem, Trening i Budżet”; nazwa pod ikoną „Horsely” (FR-021).
- Etykieta prywatności (App Privacy): „Dane niezbierane” — dane trafiają tylko do komputera użytkownika.

### 9.7 Wskazówki technologiczne (dla `/speckit-plan`)

Zalecany stos (do potwierdzenia w planie): **Swift 6**, **SwiftUI**, architektura MVVM / Observation, **SwiftData**
(lub Core Data) dla pamięci podręcznej i kolejki, **URLSession** (w tym sesja w tle) z `Codable`, **AVFoundation /
VisionKit `DataScannerViewController`** (skaner QR), **PhotosUI**, **BackgroundTasks**, **UserNotifications**,
**Swift Charts** (wykresy raportów), PDF — `UIGraphicsPDFRenderer` / `ImageRenderer` (wykresy Swift Charts do PDF),
udostępnianie przez `ShareLink` / `UIActivityViewController`, zapis przez `fileExporter`,
testy: Swift Testing / XCTest, `URLProtocol` jako zaślepka serwera, testy UI XCUITest. Generowanie klienta
z `openapi.yaml` (np. Swift OpenAPI Generator) jest dopuszczalne.

---

## 10. Poza zakresem

Zostaje w programie na komputerze (aplikacja może co najwyżej poinformować, że dana funkcja jest w programie):

- ustawienia programu i API, generowanie i unieważnianie kluczy; w trybie online także słowniki i kosz (zmiany w nich robi się w programie);
- kopie zapasowe programu, eksport i import danych programu (kopia zapasowa telefonu w trybie samodzielnym jest w zakresie 2.0);
- przenoszenie danych z trybu samodzielnego do programu (przy zmianie trybu na online dane telefonu są usuwane po ostrzeżeniu i propozycji kopii);
- drukowanie bezpośrednio z aplikacji (wyeksportowany PDF można wydrukować przez systemowe „Udostępnij”);
- wyszukiwanie globalne we wszystkich danych (aplikacja przeszukuje konie i kontakty z pamięci podręcznej).

Poza zakresem obu części systemu (możliwe przyszłe rozszerzenia):

- serwer pośredniczący w internecie, powiadomienia push z serwera (dostęp spoza sieci lokalnej zapewnia od programu 1.2
  tryb „Dostęp spoza sieci domowej”);
- wielu użytkowników z uprawnieniami, kilka stajni w jednej aplikacji;
- pomiary, OCR paszportu i paragonów; załączniki do treningów (program 1.6.1 ich nie przyjmuje);
- widżety ekranu głównego, zegarki, wersja na tablet z osobnym układem (tablet używa układu telefonu).

---

## 11. Założenia i zależności

### 11.1 Założenia

1. Użytkownik ma program w wersji ≥ 1.5.0 z włączonym API, a telefon jest w tej samej sieci Wi‑Fi co komputer.
   Poza domem: w programie włączony tryb „Dostęp spoza sieci domowej” i klucz ze zgodą na dostęp spoza domu —
   przez adres publiczny albo VPN (np. Tailscale); konfiguracja routera i VPN należy do użytkownika.
2. Jeden użytkownik i jedna stajnia na instalację aplikacji; kilka urządzeń = kilka kluczy. Klucze dostają tylko
   właściciel i współwłaściciele ([1.2](#12-użytkownik)).
3. W trybie online program jest źródłem prawdy i ostatecznie wykonuje walidację oraz logikę biznesową; telefon sprawdza te same reguły
   z góry (kopia reguł programu 1.6.1, zgodna z plikami wzorcowymi z programu), a rozbieżność kończy się komunikatem programu. W trybie
   samodzielnym telefon jest źródłem prawdy i sam stosuje reguły programu (zasady I i IV konstytucji, zmiana MAJOR).
4. Liczba danych jak w programie: do ~50 koni, do ~50 000 wpisów, załączniki do 100 MB.
5. Interfejs tylko po polsku; waluta PLN.
6. Aplikacja nie wymaga konta użytkownika ani logowania poza parowaniem z programem.

### 11.2 Zależności

1. **Kontrakt API programu 1.5.0** (`/api/v1`; w 1.6.0 i 1.6.1 bez zmian) — jeździec treningu i startu jako kontakt,
   typy kontaktu `Trainer` i `Rider`, treningi z trenerem i kosztem, kwoty konia; wystarcza do działania w sieci domowej.
1a. **Program 1.2 z trybem „Dostęp spoza sieci domowej”** (`specs/003-dostep-zdalny-api` w repozytorium programu) —
   wymagany do pracy przez nazwę DynDNS albo stały publiczny adres IP, a przy programie 1.2 także do pracy przez VPN
   z adresami spoza zakresów prywatnych (np. Tailscale `100.64.0.0/10`) — jako adres publiczny w programie podaje się
   wtedy adres VPN komputera, bez przekierowania portu w routerze.
2. **Zalecana zmiana w programie (przyszła wersja — w 1.6.1 jej nie ma): obsługa nagłówka `Idempotency-Key`** w `POST` (wpisy, terminy,
   kontakty, załączniki, akcje na terminach): powtórzone żądanie z tym samym kluczem zwraca wynik pierwszego zamiast
   tworzyć nowy rekord. Do czasu wprowadzenia tej zmiany aplikacja stosuje licznik pasujących rekordów przed i po
   wysłaniu (FR-M-SYN-06) — rozwiązanie mniej pewne tylko przy identycznym rekordzie dodanym równocześnie na komputerze.
   Zalecana także (opcjonalnie): **identyfikator instalacji programu** w `GET /system/info`, który zastąpiłby porównanie
   koni przy ponownym parowaniu (FR-M-POL-08).
3. **Zalecana zmiana w programie (przyszła wersja, opcjonalna — w 1.6.1 jej nie ma): parametr `updatedSince`** w listach, aby odświeżanie
   pamięci podręcznej pobierało tylko zmiany. Bez niego obowiązuje pełne odświeżenie (NFR-M-03).
3a. **Zalecana zmiana w programie (przyszła wersja — w 1.6.1 jej nie ma): filtr `contactId`** w listach wizyt, aby karta
   kontaktu mogła pokazać historię wizyt (US8/3). W 1.6.1 dostępna jest historia zakupów (`supplierId`) oraz treningów
   trenera i jeźdźca (`trainerId`, `riderId`).
3b. **Zalecana zmiana w programie (przyszła wersja — w 1.6.1 jej nie ma): treningi na osi czasu konia i w „Ostatnich
   wpisach” pulpitu** (`TimelineEntryType` nie zawiera treningu). Do tego czasu aplikacja pokazuje treningi na osobnej
   zakładce karty konia (FR-M-KON-02).
3c. **Decyzja 2026-10-05**: zmiany z punktów 2–3b nie są warunkiem wydania aplikacji — aplikacja działa z programem
   1.5.0+ i obejściami opisanymi w tym dokumencie.
4. Dostęp do sklepu z aplikacjami lub dystrybucji testowej — patrz [sekcja 9](#9-wymagania-platformy-ios).
5. Aplikacja na Androida (`SPECYFIKACJA_MOBILE_ANDROID.md`, specyfikacje `specs/001…005` w repozytorium
   `zarzadzanie_konmi_android`) ma ten sam zakres funkcji, identyfikatory wymagań i kryteria sukcesu; jest implementacją
   wzorcową (wersja 2.0.1) dla tekstów, ikon i plików wzorcowych. Zmiany zakresu należy wprowadzać w obu dokumentach.
6. **Pliki wzorcowe reguł programu** (`core/src/test/resources/parity` w repozytorium Androida, generowane narzędziem
   `ParityFixtures` programu 2.0.0) — warunek testów zgodności trybu samodzielnego (FR-SAM-02, FR-013).
