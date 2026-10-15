# Zarządzanie końmi — aplikacja mobilna na iOS — specyfikacja

| | |
|---|---|
| **Wersja dokumentu** | 1.3 (2026-10-05) — uzgodniona z programem 1.6.1; decyzje z sesji wyjaśniającej 2026-10-05 (zaufanie certyfikatów dla każdego adresu, kontrola duplikatów licznikiem, jedna ścieżka zapisu przez kolejkę, rozpoznawanie stajni po ponownym parowaniu, ostrzeżenie o nowszym programie; decyzje dotyczące wyłącznie Androida — w dokumencie Androida) |
| **Platforma** | iOS (iPhone) — aplikacja natywna (osobny projekt; odpowiednik na Androida: `SPECYFIKACJA_MOBILE_ANDROID.md`) |
| **Współpracuje z** | program „Zarządzanie końmi” na Windows, wersja **1.5.0 lub nowsza** (API `/api/v1`; kontrakt bez zmian do 1.6.1) |
| **Autor systemu** | Piotr Glapa |
| **Przeznaczenie** | Wejście do `/speckit-specify` w nowym, osobnym projekcie aplikacji mobilnej |

> **Jak używać tego dokumentu.** W nowym repozytorium aplikacji na iOS uruchom
> `/speckit-specify` i wskaż ten plik jako opis funkcji. Aplikacja na Androida ma osobny projekt i osobny dokument
> (`SPECYFIKACJA_MOBILE_ANDROID.md`) o tym samym zakresie funkcji — różnią się tylko sekcją [9](#9-wymagania-platformy-ios).
> Kontrakt API skopiuj z repozytorium programu na komputer (`specs/001-zarzadzanie-konmi/contracts/openapi.yaml`)
> do nowego projektu albo pobierz z działającego programu: `GET http://<komputer>:5080/openapi/v1.json`
> (tylko z sieci domowej; przy włączonym HTTPS — `https://`; z adresów spoza niej program 1.2 odpowiada `404`).
> Sekcje 1–8 opisują **co** aplikacja ma robić; sekcje 9 i 11 zawierają ograniczenia techniczne dla `/speckit-plan`.

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
więc widzi konia kontuzjowanego jako aktywnego, a zapis konia z telefonu nie zmienia jego statusu w programie. Obsługa statusu w aplikacji jest zadaniem następczym
(kolejna wersja aplikacji).

**Zakres równoległy do Androida 2.0.1.** Aplikacja na iOS obejmuje ten sam zakres funkcji co aplikacja na Androida 2.0.1 (opis: `SPECYFIKACJA_MOBILE_ANDROID.md`, akapit
„Zakres wersji 2.0.1”): nazwa „Horsely – Zarządzanie Koniem, Trening i Budżet”, słowniki zgodne z programem 2.0.0, wykrywanie możliwości programu (`capabilities`),
status „Kontuzjowany” z ikoną plastra, poprawka układu wierszy raportów oraz szczegółowy dziennik diagnostyczny (FR-M-UST-01).

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
- działy jak w programie (zakres z wersji 1.1 aplikacji na Androida; opis: `SPECYFIKACJA_MOBILE_ANDROID.md`, US11): **Treningi**
  (wszystkie konie), **Zakupy** (z „Powtórz zakup”) i **Zawody** (szczegóły ze startami, formularz zawodów) — z filtrami
  (domyślnie bieżący rok), liczbą i sumami z programu oraz pracą z pamięci z ostatnich 12 miesięcy;
- zakres z wersji 1.2 aplikacji na Androida (opis: `SPECYFIKACJA_MOBILE_ANDROID.md`, 5.1 i 5.2): ocena gwiazdkami ★★★☆☆,
  terminy i koszty w obszarach z tonami, linie między wierszami list, sekcje formularzy, domyślny okres działów
  1 stycznia – 31 grudnia bieżącego roku, kafel konia → karta konia, zakupy i starty otwierają szczegóły;
- praca bez połączenia: podgląd z pamięci i kolejka nowych wpisów; stabilny stan połączenia (ponawianie odczytów, „Odśwież”,
  samoczynne wznawianie, komunikat zwijany do ikonki — Android: FR-M-POL-14…17);
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
| **Kontuzjowany** | Status konia (`Injured`, od wersji 2.0.0 programu): koń w stajni, traktowany jak aktywny, z plakietką ostrzegawczą w programie. Klientowi bez nagłówka `X-Client-Features: horse-status-injured` program pokazuje go jako **Aktywny** (odpowiedzi i eksport) i nie pozwala przez taki klient zmienić go na aktywnego |

---

## 3. Historie użytkownika

Priorytety: **P1** — bez tego aplikacja nie ma sensu (MVP), **P2** — ważne, **P3** — uzupełniające.
Każda historia daje się przetestować niezależnie od pozostałych (poza US1, która jest warunkiem wszystkich).

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
   podręcznej z informacją „Brak połączenia z komputerem — dane z <data, godzina>” i wskazówką, co sprawdzić
   (komputer włączony, program uruchomiony, API włączone, ta sama sieć Wi‑Fi; poza domem — w programie włączony
   „Dostęp spoza sieci domowej”, także przy VPN z adresami spoza zakresów prywatnych, np. Tailscale).
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

### 4.2 Synchronizacja, pamięć podręczna i kolejka (`SYN`)

> **Wersja 2.0.** Pamięć podręczna jest zastąpiona magazynem lokalnym ze wszystkimi danymi programu (FR-SYN2-01…09, [`specs/004-tryb-samodzielny-offline`](specs/004-tryb-samodzielny-offline/spec.md)):
> pełne pobranie `GET /export` (start, powrót na pierwszy plan po 15 min, ręcznie, w tle co godzinę), uzgadnianie wg wersji rekordów
> (`If-Match`), operacje `Update`/`Delete` w kolejce łączone przed wysyłką, konflikty rozstrzygane przez użytkownika, tryb zgodności
> z programem bez wersji rekordów (edycja i usuwanie wymagają wtedy aktualizacji programu). Poniższe wymagania 1.x opisują zachowanie
> do wersji 1.2; tam, gdzie mówią o „pamięci podręcznej”, w wersji 2.0 czytaj „magazyn lokalny”.

- **FR-M-SYN-01**: Pamięć podręczna MUST obejmować: informacje o programie, słowniki (`GET /dictionaries`), konie
  (wszystkie statusy), kontakty, otwarte terminy, pulpit, oś czasu i treningi (`GET /trainings?horseId=&from=`) każdego aktywnego konia
  za ostatnie 12 miesięcy (ustawienie 3/12/24 miesiące), miniatury zdjęć koni, raport kosztów bieżącego roku, ostatnio otwarte raporty (każdy z filtrami, z którymi
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
  `ownerId`, nazwa pliku i rozmiar. Akcje na terminach są sprawdzane po statusie terminu. Ryzyko szczątkowe (identyczny
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

- **FR-M-UST-01**: Połączenie: nazwa i wersja programu, adresy (dodaj, usuń, kolejność), szyfrowanie tak/nie,
  „Sprawdź połączenie”, „Połącz ponownie (nowy kod QR)”, „Rozłącz”. Przełącznik „Szczegółowy dziennik połączeń”
  (tylko tryb online): zapisuje adres, IP połączenia, rodzaj sieci i wynik każdego żądania do programu (bez klucza, nagłówków, zapytań i treści); włączony na 7 dni,
  po czym wyłącza się sam. „O aplikacji → Dziennik diagnostyczny”: rozmiar, wpisy od najnowszych, „Wyślij” i „Wyczyść” (z potwierdzeniem).
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
- **FR-M-UI-04**: Każdy ekran MUST mieć stany: ładowanie, pusto (z podpowiedzią), brak połączenia (pasek z datą danych),
  błąd (komunikat po polsku + „Spróbuj ponownie”).
- **FR-M-UI-05**: Po zapisie MUST pojawić się krótki komunikat („Zapisano” / „Zapisano — wyślę po połączeniu
  z komputerem”) z akcją „Cofnij” dla wpisów jeszcze niewysłanych.
- **FR-M-UI-06**: SHOULD: skróty z ikony aplikacji „Dodaj notatkę”, „Kowal”, „Terminy” ([9.5](#95-integracje-systemowe)).

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
- Stany: ładowanie (szkielety list), pusto (z podpowiedzią, co zrobić), brak połączenia (pasek z datą danych),
  błąd (komunikat po polsku + „Spróbuj ponownie”).
- Po zapisie: krótki komunikat („Zapisano” / „Zapisano — wyślę po połączeniu z komputerem”) z akcją „Cofnij”
  dla wpisów jeszcze niewysłanych.

### 5.2 Struktura

| Miejsce | Zawartość |
|---|---|
| Dolna nawigacja | **Pulpit** · **Konie** · **Terminy** · **Treningi** · **Więcej** (zakres z wersji 1.1; w 1.0 zamiast Treningów były Kontakty) |
| „Więcej” | Zawody · Zakupy · Kontakty · Raporty — separator — **online**: Konflikty (gdy są) · Kolejka wysyłki (z licznikiem) · Ustawienia · O aplikacji; **samodzielny** (2.0): Kosz · Słowniki · Kopia zapasowa · Ustawienia · O aplikacji |
| Działy Treningi · Zakupy · Zawody | Lista od najnowszych · filtry (domyślnie bieżący rok) · stopka z liczbą i sumą z programu · „+” · szczegóły zawodów ze startami |
| Raporty | Lista pięciu raportów jak w programie: Koszty · Bilans konia · Podsumowanie treningów · Treningi jeźdźca · Zawody jeźdźca; w każdym: filtry (arkusz u dołu ekranu) → sumy → wykresy → wiersze → „Eksport CSV”, „Eksport PDF” |
| Przycisk „+” | Wybór rodzaju wpisu → wybór konia → formularz |
| Karta konia | Nagłówek (zdjęcie, imię, paszport) · zakładki: Oś czasu · Terminy · Paszport · Treningi · Zawody · Zakupy · Załączniki |
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

Nieużywane przez aplikację: `/export`, `/trash`, zapisy w `/dictionaries`.

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
| NFR-M-01 | Uruchomienie do pulpitu z pamięci podręcznej < 2 s; odświeżenie pulpitu z komputerem w tej samej sieci Wi‑Fi < 2 s. Progi czasowe (NFR-M-01…03, SC-M-02, SC-M-09) mierzy się na urządzeniu odniesienia platformy — iOS: iPhone klasy średniej sprzed 3 lat (konkretny model do ustalenia w planie iOS); Android: Honor Magic 6 Pro |
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
  programu dla tych samych danych) — testy jednostkowe; komunikacja z API — testy z serwerem testowym (zaślepka zgodna z `openapi.yaml`) |

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

---

## 9. Wymagania platformy iOS

### 9.1 Wersje i urządzenia

| Aspekt | Ustalenie |
|---|---|
| Minimalna wersja | iOS 17 |
| Urządzenia | iPhone; iPad z układem telefonu (bez osobnego układu dwukolumnowego) |
| Orientacja | Pionowa; pozioma dozwolona dla podglądu zdjęć i wideo |

### 9.2 Zgody i opisy w `Info.plist`

> **Wersja 2.0.** Blokada aplikacji (FR-TRB-09) używa `LocalAuthentication` (Face ID / Touch ID / kod urządzenia): dodaj `NSFaceIDUsageDescription`
> („Odblokowanie aplikacji z danymi stajni”), bez osobnego PIN-u aplikacji. Plik kopii zapasowej i folder kopii automatycznych — `UIDocumentPicker`
> (zakładka z uprawnieniem do folderu, `startAccessingSecurityScopedResource`).

| Klucz | Po co | Kiedy system pyta |
|---|---|---|
| `NSLocalNetworkUsageDescription` | Połączenie z komputerem w sieci lokalnej (iOS wymaga zgody „Sieć lokalna”) | Przy pierwszym połączeniu z adresem w sieci lokalnej — aplikacja MUST wcześniej pokazać ekran wyjaśnienia, a po odmowie instrukcję włączenia zgody w Ustawieniach |
| `NSCameraUsageDescription` | Skanowanie kodu QR, zdjęcia | Przy pierwszym skanowaniu / zdjęciu |
| Powiadomienia (`UNUserNotificationCenter`) | Przypomnienia o terminach | Po parowaniu, z ekranem wyjaśnienia |
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
  z ochroną `completeUntilFirstUserAuthentication`.
- Ekran z kluczem (wpisywanie ręczne) MUST ukrywać treść w przełączniku aplikacji (zasłona przy przejściu w tło).

### 9.4 Praca w tle

- iOS nie gwarantuje regularnej pracy w tle. Odświeżanie: **`BGAppRefreshTask`** (system decyduje o terminie)
  oraz odświeżenie przy każdym otwarciu aplikacji; aplikacja MUST poprawnie działać, gdy odświeżanie w tle nie
  następuje wcale.
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
- **Wygląd**: zgodny z Human Interface Guidelines, kolory aplikacji (zieleń/pomarańcz), tryb ciemny, Dynamic Type.
- **Gest przesunięcia wstecz** i zamknięcie arkusza formularza MUST pytać o niezapisane zmiany (FR-M-WPI-07).
- Zdjęcia z aparatu w formacie HEIC są dozwolone przez program; przy włączonym zmniejszaniu SHOULD wysyłać JPEG
  dla lepszej zgodności podglądu w programie na Windows.

### 9.6 Dystrybucja

- Wymaga konta Apple Developer Program. Testy przez **TestFlight**, potem App Store (lub dystrybucja niepubliczna,
  jeśli dostępna).
- **App Review**: aplikacja wymaga własnego serwera użytkownika. Na potrzeby recenzji MUST istnieć **tryb
  demonstracyjny** (np. „Wypróbuj na danych przykładowych” na ekranie powitania) z wbudowanymi danymi, bez połączenia
  z komputerem; wyraźnie oznaczony, niedostępny po sparowaniu. W notatkach dla recenzenta opis działania z programem na Windows.
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
5. Aplikacja na Androida (`SPECYFIKACJA_MOBILE_ANDROID.md`) ma ten sam zakres funkcji, identyfikatory wymagań i kryteria
   sukcesu; zmiany zakresu należy wprowadzać w obu dokumentach.
