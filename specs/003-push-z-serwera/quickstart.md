# Quickstart: weryfikacja push z serwera (iOS 2.1.0)

Scenariusze potwierdzające, że funkcja działa. Pola i zachowania: [contracts/](contracts/), stany: [data-model.md](data-model.md),
decyzje: [research.md](research.md).

> **Serwer produkcyjny `192.168.18.33` jest wykluczony z testów.** Nie paruj z nim telefonu testowego, nie wysyłaj testów, nie
> przypisuj reguł. Wszystkie kroki z prawdziwym serwerem — na serwerze uruchomionym lokalnie (§3).

## 0. Warunki wstępne

- Konstytucja 2.1.0 i `SPECYFIKACJA_MOBILE_IOS.md` 1.6 zatwierdzone (commit `c299130`).
- Dwa teksty iOS (`push_state_no_apns`, `push_hide_previews_hint`) dopisane w `strings.xml` repozytorium Androida i
  zsynchronizowane: `scripts\sync-strings.ps1 -AndroidRepo ..\zarzadzanie_konmi_android`.
- iPhone 15 Pro z TestFlight (grupa „Deweloper”), zgoda na powiadomienia nieustalona przed pierwszym scenariuszem (świeża instalacja).

## 1. CI na gałęzi i `main` (automatycznie)

```bash
gh run list --branch 003-push-z-serwera --limit 3
```

Oczekiwane (zielony `ci.yml`):

- `swift test` obu pakietów: `PushPolicyTests` (wszystkie stany i kolejność warunków, `localRemindersActive`), `PushModelsTests`
  (przykłady JSON, 7 cyfr ułamka, nieznane pola i typy), `PushMessageTests` (mapowanie celów, nieznane klucze, zła data),
  `PushRegistrarTests` (wyzwalacze, raz na dobę, 30 s → 15 min, 24 h → `registrationFailed`, `400`, `404`, wyrejestrowanie przed
  usunięciem klucza, brak wywołań źródła tokenu w trybie samodzielnym i bez `push`, zniknięcie `push` bez `DELETE`),
  `ApiClientPushTests` (dane komórkowe + „tylko Wi‑Fi” + adres zdalny → wysłane; dwa zerwania → trzecia próba; token tylko w ciele,
  nie w dzienniku), `ReminderDigestTests` („Przeterminowane: 2, na dziś i jutro: 3”), `NotificationSchedulerTests` (brak
  `daily-`/`due-` przy `registered`).
- `sync-strings.ps1 -Check` bez różnic.
- Migawki z [contracts/ui-push-ios.md](contracts/ui-push-ios.md) (jasny, ciemny, 200 %) — przejrzeć zrzuty z artefaktów.
- Testy UI: `-UITestProgram push -UITestPush apnsRefused` → ekran „Powiadomienia” pokazuje „Telefon nie może odbierać
  powiadomień z serwera — powiadomienia planuje telefon.”; dotknięcie symulowanej wiadomości `backup` otwiera „Kopia zapasowa
  na serwerze”.

## 2. Wydanie testowe (TestFlight)

1. Apple Developer → Identifiers → `pl.glapa.horsely` → Push Notifications włączone (jeśli eksport zgłosi brak — włączyć ręcznie).
2. Po scaleniu gałęzi do `main` i zielonym `ci.yml` na `main` — tag i przebieg wydania:

   ```bash
   git tag v2.1.0 && git push origin v2.1.0
   ```

   ```bash
   gh run watch
   ```

3. Oczekiwane: krok „Uprawnienia push” zielony (`aps-environment = production` w aplikacji, brak w rozszerzeniu, plist Firebase
   tylko w aplikacji); wysyłka do TestFlight udana; podsumowanie z wersją 2.1.0 i numerem kompilacji.
4. App Store Connect → App Privacy: identyfikator urządzenia, funkcjonalność, niepowiązany, bez śledzenia.

## 3. Lokalny serwer testowy (Windows, ten komputer)

1. Serwer Java z repozytorium `../zarzadzanie_konmi_java` uruchomiony lokalnie według `specs/008-push-mobilny/quickstart.md`
   (osobna, testowa baza danych; plik konta usługi Firebase projektu `horsely-41baf` wskazany w konfiguracji lokalnego serwera —
   nigdy w repozytorium iOS).
2. `GET http://<IP komputera>:5080/api/v1/system/info` → `capabilities` zawiera `push` (i `pushAdmin`).
3. W UI webowym lokalnego serwera: nowy klucz API dla telefonu testowego, kod QR do parowania.
4. Zapora Windows przepuszcza port serwera w sieci prywatnej; iPhone w tej samej sieci Wi‑Fi.

## 4. Scenariusze ręczne na iPhonie (lokalny serwer)

| # | Kroki | Oczekiwane |
|---|---|---|
| 1 | Sparuj z lokalnym serwerem; na Pulpicie okno zgody → „Dalej” → zezwól | w UI webowym lista urządzeń pokazuje telefon (iOS) ≤ 1 min; ekran „Powiadomienia”: „Włączone…”, data rejestracji, „Brak przypisanych powiadomień” |
| 2 | UI webowe → „Wyślij test” przy zablokowanym ekranie, potem przy otwartej aplikacji | „Test powiadomień Horsely” ≤ 30 s w obu przypadkach (10/10) |
| 3 | Przypisz regułę „Kowal: dzień przed o 08:00”, termin kowala na jutro; „Odśwież” na ekranie | lista pokazuje opis reguły; o 08:00 jedno powiadomienie z serwera, brak lokalnego (sprawdzić także, że nie ma zaplanowanego `due-`/`daily-` — dziennik diagnostyczny) |
| 4 | Dotknij powiadomienia o terminie / podsumowania / testu | szczegóły terminu / lista terminów / Pulpit |
| 5 | UI webowe: wyłącz przełącznik wysyłania; w aplikacji pociągnij do odświeżenia | ekran: „Serwer nie wysyła powiadomień…”, ustawienia lokalne widoczne, powiadomienia lokalne zaplanowane; włącz z powrotem → po synchronizacji znów „Włączone…” |
| 6 | Wi‑Fi wyłączone, „tylko przez Wi‑Fi” włączone, telefon sparowany także z publicznym adresem lokalnego serwera (jeśli dostępny) | rejestracja i test działają na danych komórkowych |
| 7 | UI webowe: usuń urządzenie; w aplikacji otwórz „Powiadomienia” | komunikat „Właściciel usunął ten telefon…”, telefon wraca na listę |
| 8 | Ustawienia iOS → Horsely → Powiadomienia wyłączone; wróć do aplikacji | urządzenie znika z listy w UI webowym; ekran „Brak zgody…”; przywrócenie zgody → ponowna rejestracja |
| 9 | Ustawienia → Połączenie → „Rozłącz” | urządzenie znika z listy ≤ 1 min; „Wyślij test” niemożliwy |
| 10 | Bez sieci: sparuj ponownie, zarejestruj, wyłącz sieć, „Rozłącz” | rozłączenie najwyżej ~5 s dłuższe niż w 2.0.2 |
| 11 | Tryb samodzielny | ekran „Powiadomienia” jak w 2.0.2; brak sekcji serwera; powiadomienia lokalne działają |
| 12 | O aplikacji → Dziennik diagnostyczny po scenariuszach 1–9 | wpisy `push` słowami, tylko prefiks tokenu (8 znaków), brak tytułów i treści |

## 5. Ruch sieciowy (prywatność)

Opcjonalnie, serwer proxy na komputerze (np. podgląd DNS w routerze): w trybie samodzielnym brak zapytań do `*.googleapis.com`;
w trybie z serwerem z `push` — tylko `firebaseinstallations.googleapis.com` i `fcmtoken.googleapis.com`/FCM oraz APNs.

## 6. Zakończenie

- Lista kontrolna 1–12 zaliczona → TestFlight do grupy „Właściciele”.
- Zaktualizować pamięć: data ostatniej kompilacji TestFlight (przypomnienie po 80 dniach).
