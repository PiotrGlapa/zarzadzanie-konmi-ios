<!--
Sync Impact Report
- Version change: 2.1.0 → 3.0.0 (MAJOR — redefinicja zasady II i VII, przejście na zakres 3.0.0; numer zgodny z konstytucją Androida 3.0.0)
- Źródło: specs/001-aplikacja-ios-horsely/plan.md (zadanie 1: konstytucja 3.0.0); odpowiednik: konstytucja Androida 3.0.0.
- Modified principles:
  - II. Prywatność i brak usług zewnętrznych — wyjątek: lokalizacja „Podczas używania” (When In Use) dozwolona TYLKO podczas nagrywania jazdy uruchomionego przez użytkownika; dozwolone są mapy Apple (Apple Maps) oraz Open‑Meteo (położenie zaokrąglone do 0,01° + godzina, z wyłącznikiem);
  - VII. Prostota — wyjątek: mapy (Apple Maps) jako usługa zewnętrzna są dozwolone.
  - VIII. Zgodność z aplikacją na Androida — odniesienie 2.1.0 → 3.0.0.
- Proces: aktualizacja konstytucji i dokumentów projektowych.
- Added sections: brak. Removed sections: brak.
- Templates: plan-template.md ✅, spec-template.md ✅, tasks-template.md ✅.
- Dependent artifacts: ✅ SPECYFIKACJA_MOBILE_IOS.md 3.0.0; ✅ CHANGELOG.md; ✅ .claude/CLAUDE.md (pkt 5).
- Follow-up TODOs: brak placeholderów.
-->
# Horsely — aplikacja na iOS — Constitution

## Core Principles

### I. Jedno źródło prawdy w wybranym trybie pracy

- Aplikacja pracuje w jednym z dwóch trybów, wybieranym przy pierwszym uruchomieniu, zapamiętanym i zmienianym w Ustawieniach → Tryb pracy:
  - **tryb online** — aplikacja jest klientem programu „Horsely” na komputerze; program jest źródłem prawdy o danych i jedynym miejscem reguł biznesowych;
  - **tryb samodzielny** — aplikacja działa bez programu; telefon jest źródłem prawdy i sam stosuje reguły programu (walidacja, unikalność, automatyczne terminy, podział kosztów, sumy raportów, kosz).
- W każdej chwili MUSI istnieć dokładnie jedno źródło prawdy; aplikacja NIE MOŻE łączyć danych obu trybów ani pracować w trybie innym niż zapamiętany.
- W trybie online aplikacja NIE MOŻE przeliczać ani przekształcać wartości biznesowych w sposób zmieniający wynik względem programu; po synchronizacji obowiązują wartości zwrócone przez program. Walidacja w aplikacji jest wygodą, a komunikaty błędów programu MUSZĄ być pokazywane przy właściwych polach.
- W trybie samodzielnym reguły odtworzone w telefonie MUSZĄ dawać wyniki identyczne z programem dla tych samych danych (co do grosza i minuty); zakres odtworzonych reguł określa specyfikacja, a reguła spoza tego zakresu NIE MOŻE być przybliżana.
- Zmiana trybu, która usuwa lub zastępuje dane lokalne (przejście z samodzielnego na online), MUSI być poprzedzona wyraźnym ostrzeżeniem o skutkach i potwierdzeniem użytkownika; NIE MOŻE nastąpić automatycznie ani w wyniku pojedynczego przypadkowego dotknięcia.
- Ustawienia programu i API oraz zarządzanie kluczami NIE MOGĄ być dostępne w aplikacji. Trwałe usuwanie danych i operacje masowe (kosz, odtwarzanie kopii) są dozwolone wyłącznie w trybie samodzielnym, z potwierdzeniem; w trybie online usunięcie wpisu oznacza przeniesienie do kosza programu.

**Uzasadnienie**: reguła zaimplementowana w dwóch miejscach może się rozjechać — dlatego w danym trybie obowiązuje jedna implementacja, a tam, gdzie telefon zastępuje program, zgodność wyników jest wymagana i testowana (SC-M-04, SC-M-09).

### II. Prywatność i brak usług zewnętrznych


- Aplikacja MUSI łączyć się wyłącznie ze sparowanym komputerem użytkownika (w trybie samodzielnym — z nikim); NIE MOŻE zawierać telemetrii, analityki, raportowania awarii do usług zewnętrznych, reklam ani SDK nawiązujących połączenia wychodzące (np. Firebase Analytics, Crashlytics). Wyjątki: mapy, telefon i e‑mail otwierane w innych aplikacjach na żądanie użytkownika oraz Firebase Cloud Messaging na warunkach z punktu niżej.
- Firebase Cloud Messaging (FCM, dostarczający przez APNs) MOŻE być używany **wyłącznie** do odbioru powiadomień push wysyłanych przez serwer użytkownika i **wyłącznie w trybie z serwerem**, gdy serwer ogłasza możliwość `push`:
  - w trybie samodzielnym FCM NIE MOŻE być konfigurowany ani łączyć się z siecią, a aplikacja NIE MOŻE rejestrować się do powiadomień zdalnych APNs; automatyczna inicjalizacja FCM MUSI być wyłączona domyślnie, a konfiguracja wykonywana ręcznie tylko w trybie z serwerem;
  - z rodziny Firebase dozwolony jest tylko moduł Messaging (z jego zależnościami); Analytics, Crashlytics, Performance, Remote Config i inne moduły są zabronione, a zbieranie analityki MUSI być jawnie wyłączone; rozszerzenie udostępniania NIE MOŻE zawierać Firebase ani uprawnienia do powiadomień zdalnych;
  - serwerowi wolno przekazać wyłącznie platformę i token FCM; przy odparowaniu, przejściu w tryb samodzielny, usunięciu danych połączenia i cofnięciu zgody token MUSI zostać wyrejestrowany na serwerze (gdy to możliwe) i usunięty z telefonu, a aplikacja wyrejestrowana z APNs;
  - niedziałający push (brak rejestracji APNs, brak tokenu, serwer bez `push`) NIE MOŻE pozbawić użytkownika powiadomień — aplikacja wraca wtedy do powiadomień planowanych w telefonie.
- Plik `GoogleService-Info.plist` NIE jest sekretem (nie pozwala wysyłać powiadomień) i MOŻE być w repozytorium, pod warunkiem że klucz API w nim jest ograniczony w konsoli Google Cloud do aplikacji iOS o identyfikatorze pakietu `pl.glapa.horsely`. Klucz konta usługi FCM (do wysyłania) i klucz APNs (`.p8`) NIE MOGĄ nigdy trafić do aplikacji ani do jej repozytorium.
- Aplikacja MUSI prosić wyłącznie o zgody z listy w specyfikacji (sekcja 9.2) i NIE MOŻE prosić o lokalizację, dostęp do kontaktów ani pełny dostęp do biblioteki zdjęć; zdjęcia wybiera się przez `PhotosPicker`, pliki przez selektor dokumentów, kontakt przez `CNContactPickerViewController`.
- Lokalizacja „Podczas używania” (When In Use) jest dozwolona **tylko** w trakcie nagrywania jazdy uruchomionego przez użytkownika (nigdy w logach, nigdy poza nagrywaniem); dopuszcza się użycie kafli Apple Maps oraz Open‑Meteo (z zaokrąglonym położeniem do 0,01° i godziną startu), w obu trybach pracy (online i samodzielnym).
- Logi diagnostyczne NIE MOGĄ zawierać treści wpisów, nazw koni, danych kontaktów, klucza API, pełnego tokenu FCM (najwyżej 8 pierwszych znaków) ani tytułów i treści powiadomień; rozmiar logów MUSI być ograniczony (rotacja, maks. 5 MB).
- Lokalna baza danych, kolejka zmian i załączniki MUSZĄ leżeć w prywatnym obszarze aplikacji (i wspólnym kontenerze App Group dla rozszerzenia udostępniania) i być wykluczone z kopii iCloud. Kopia zapasowa danych trybu samodzielnego MOŻE powstawać wyłącznie na żądanie użytkownika (albo w włączonej przez niego kopii automatycznej) do miejsca wskazanego przez niego.

**Uzasadnienie**: dane to prywatna ewidencja właściciela; nie opuszczają jego telefonu i komputera bez jego decyzji (NFR-M-05, NFR-M-06, NFR-M-09). Serwer użytkownika wysyła push przez FCM (który przekazuje je do APNs), więc wyjątek jest wąski i taki sam jak w aplikacji na Androida 2.1.0: tylko odbiór, tylko w trybie z serwerem, tylko identyfikatory w danych wiadomości, a o treści i odbiorcach decyduje serwer użytkownika (specs/003-push-z-serwera).
