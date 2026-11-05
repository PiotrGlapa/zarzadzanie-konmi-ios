# Zmiana: powiadomienia push z serwera (iOS) — opis dla `/speckit-specify`

Jak użyć:

1. Otwórz sesję w repozytorium `zarzadzanie_konmi_ios` (nowa gałąź, np. `003-push-z-serwera`).
2. Uruchom `/speckit-specify` i wklej **cały blok „Opis funkcji”** poniżej.
3. Po specyfikacji uruchom `/speckit-clarify` — sekcja „Otwarte pytania” zawiera tematy do rozstrzygnięcia.
4. Przed `/speckit-plan` przeczytaj kontrakty serwera (ścieżki względne z tego repozytorium):
   - `../zarzadzanie_konmi_java/specs/008-push-mobilny/contracts/api-push.md` §1 (API telefonu) i „Capabilities”,
   - `../zarzadzanie_konmi_java/specs/008-push-mobilny/contracts/fcm.md` §2 (kształt wiadomości, nagłówki `apns-*`),
   - `../zarzadzanie_konmi_java/specs/008-push-mobilny/spec.md` (US21–US26, US47–US50),
   - `../zarzadzanie_konmi_java/docs/adr/0001-push-mobilny-przez-fcm.md`.
5. Kolejność według specyfikacji serwera: **najpierw Android, potem iOS**. Android jest **gotowy** (wersja 2.1.0, gałąź
   `006-push-z-serwera`, spec `../zarzadzanie_konmi_android/specs/006-push-z-serwera/` — `spec.md` z Clarifications,
   `research.md` R1–R13, `data-model.md` §2, `contracts/ui-push.md`). Jego rozstrzygnięcia i poprawki z wdrożenia są
   przepisane niżej w sekcjach „Rozstrzygnięcia przejęte z Androida” i „Poprawki z wdrożenia Androida” (część bloku do
   wklejenia) — obie aplikacje mają działać tak samo. Przy `/speckit-plan` czytaj też `research.md` Androida.

---

## Opis funkcji (do wklejenia)

Aplikacja iOS Horsely w **trybie z serwerem** (sparowana kluczem API z serwerem Java 2.0) ma odbierać powiadomienia push
wysyłane przez serwer przez Firebase Cloud Messaging, które dostarcza je do iPhone'a przez APNs, zamiast planować
powiadomienia lokalne. O tym, które powiadomienia, kiedy i na który telefon trafiają, decyduje właściciel w UI webowym
(reguły push na serwerze). Telefon tylko: rejestruje swój token FCM na serwerze, wyrejestrowuje go, pokazuje odebrane
powiadomienia i pokazuje, jakie reguły ma przypisane. **Tryb samodzielny pozostaje bez żadnych zmian.**

### Stan serwera i Firebase (gotowe, wdrożone na produkcji 2026-11-05)

- Projekt Firebase `horsely-41baf`, aplikacja iOS zarejestrowana w Firebase jako `pl.glapa.horsely` (zgodnie z
  `PRODUCT_BUNDLE_IDENTIFIER`). Klucz APNs `.p8` jest wgrany do Firebase. Plik `GoogleService-Info.plist` pobiera się
  z konsoli Firebase (Ustawienia projektu → Twoje aplikacje → iOS).
- Serwer nie łączy się z APNs bezpośrednio: wysyła wszystko przez FCM HTTP v1, a FCM przekazuje do APNs.
- Serwer ogłasza w `GET /api/v1/system/info` → `capabilities` dwie nowe nazwy (na końcu listy):
  - `push` — serwer **naprawdę wysyła** push (włączony w konfiguracji, włączony przełącznikiem właściciela, poprawny klucz
    Firebase). Tylko ta nazwa interesuje telefon. Dziś `ProgramCapabilities` odrzuca nieznane nazwy — trzeba dopisać `push`
    do znanych.
  - `pushAdmin` — dotyczy wyłącznie UI webowego; telefon ją ignoruje.
- Wszystkie zmiany serwera są addytywne: obecna aplikacja 2.0.2 działa dalej bez różnic.

### API telefonu (nagłówek `X-Api-Key`, ścieżki pod `/api/v1`)

| Metoda i ścieżka | Wejście | Odpowiedź |
|---|---|---|
| `PUT /push/device` | `{"platform":"Ios","token":"<token FCM>"}` | `200` `PushDevice`; rejestracja nowa, odświeżona albo zastąpiona — zawsze `200`, idempotentnie; `400` z `errors.platform` / `errors.token` |
| `DELETE /push/device` | — | `204` (także gdy nic nie było zarejestrowane) |
| `GET /push/device` | — | `200` `PushDevice`; brak rejestracji → `404` |
| `GET /push/rules` | — | `200` lista **włączonych** reguł przypisanych do klucza tego telefonu |

- `platform` dla iOS to dokładnie `Ios`. `token` to **token rejestracyjny FCM** (z `Messaging.messaging().fcmToken` /
  delegata `messaging(_:didReceiveRegistrationToken:)`), **nie** surowy token urządzenia APNs.
- Jeden token na klucz API: nowa rejestracja nadpisuje poprzedni token. Reguły są przypisane do klucza, nie do tokenu.
- `token`: 1–4096 znaków, bez białych znaków. `PUT` nie wymaga `Idempotency-Key`.
- `PushDevice`: `platform`, `tokenPrefix` (pełny token nigdy nie wraca), `registeredAt`, `lastSeenAt`, `lastDeliveredAt`.
- Reguła (`ClientPushRule`): `id`, `type` (`Reminder` | `DailySummary` | `BackupFailure` | `AnalyticEvent`),
  `reminderKind`, `offsetDays`, `sendTime`, `repeatTime` oraz **`description`** — gotowy polski opis z serwera
  (np. „Kowal: dzień przed o 08:00, powtórka o 07:00”), który aplikacja pokazuje bez własnej logiki.
- Klucz unieważniony lub nieznany → `401` jak dotąd. Właściciel może w UI webowym usunąć urządzenie (token i przypisania
  reguł znikają) — wtedy `GET /push/device` zwraca `404`.

### Wiadomość push (co przychodzi do telefonu)

- Alert: tytuł „Horsely”, treść krótka i gotowa do wyświetlenia, np. „Kowal: Gniada, jutro”,
  „Przeterminowane: 2, dziś: 1, jutro: 3”, „Kopia zapasowa nie powiodła się”, „Test powiadomień Horsely”. Bez notatek,
  kwot, diagnoz i nazw osób.
- Nagłówki APNs ustawia serwer: `apns-push-type: alert`, `apns-priority: 10`, `apns-expiration` = koniec dnia, którego
  dotyczy wiadomość (awaria kopii 24 h), `apns-collapse-id` = `<type>-<id>` (podsumowanie `summary-<data>`).
- Klucze własne w `userInfo` (same stringi, tylko identyfikatory): `type` = `reminder` | `summary` | `backup` |
  `analytic` | `test`; dla terminu także `reminderId`, `horseId`, `targetDate` (`yyyy-MM-dd`). Aplikacja MUSI ignorować
  nieznane klucze i nieznane wartości `type`.
- Serwer **nie** ustawia `mutable-content` ani `content-available` (brak cichych pushy i rozszerzenia Notification Service
  Extension po stronie serwera — patrz otwarte pytanie 1).

### Wymagania funkcjonalne

1. **Konfiguracja projektu.** Firebase iOS SDK (Swift Package Manager, tylko `FirebaseMessaging`; bez Analytics i
   Crashlytics) w `project.yml` (XcodeGen). Capability *Push Notifications*: `aps-environment` w `App/Horsely.entitlements`
   (`development` dla buildów z Xcode, `production` dla TestFlight i App Store). `UIBackgroundModes` →
   `remote-notification` w Info.plist. Rozszerzyć `scripts/ci/embed-entitlements.sh` tak, by podpisywał aplikację
   z `aps-environment` właściwym dla wydania i weryfikował go (dziś sprawdza tylko grupy i keychain). Decyzja o method
   swizzlingu Firebase (`FirebaseAppDelegateProxyEnabled`) — w planie, zgodnie z istniejącym `NotificationDelegate`.
2. **Zgoda i rejestracja.** W trybie z serwerem, gdy `capabilities` zawiera `push`, aplikacja (po zgodzie
   `UNUserNotificationCenter`) wywołuje `registerForRemoteNotifications`, pobiera token FCM i rejestruje go
   `PUT /push/device`. Rejestracja jest ponawiana: przy starcie aplikacji, po sparowaniu, po odświeżeniu `capabilities`
   w synchronizacji i przy każdej zmianie tokenu FCM. Błąd sieci → ponowienie później (np. przy kolejnym wejściu na pierwszy
   plan lub zadaniu w tle), bez komunikatu przy pojedynczym błędzie.
3. **Wyrejestrowanie.** Przy odparowaniu, zmianie trybu na samodzielny i usunięciu danych połączenia aplikacja wywołuje
   `DELETE /push/device` (jeśli klucz jest jeszcze ważny), usuwa token FCM (`deleteToken`) i wyrejestrowuje się z APNs.
   `401` nie jest błędem tego kroku.
4. **Brak dubli.** W trybie z serwerem z działającym push aplikacja **nie planuje** lokalnych powiadomień o terminach
   i dziennym podsumowaniu (`NotificationScheduler` usuwa już zaplanowane) dopiero **po udanej rejestracji** tokenu.
5. **Tryb awaryjny (powiadomienia lokalne).** Aplikacja w trybie z serwerem planuje powiadomienia lokalne jak dziś, gdy:
   serwer nie ogłasza `push` (stary serwer, push wyłączony przez administratora lub właściciela, brak konfiguracji Firebase),
   rejestracja w APNs się nie udała (`didFailToRegisterForRemoteNotificationsWithError`), nie udało się pobrać tokenu FCM
   albo rejestracja na serwerze trwale się nie udaje. Zniknięcie `push` z `capabilities` przy kolejnej synchronizacji
   przełącza na powiadomienia lokalne bez udziału użytkownika; powrót `push` przełącza z powrotem. W trybie awaryjnym
   aplikacja pokazuje ostrzeżenie z powodem.
6. **Odbiór i wyświetlenie.** W tle i przy zablokowanym ekranie alert wyświetla system. Na pierwszym planie
   `userNotificationCenter(_:willPresent:)` pokazuje baner (`.banner`, `.list`, `.sound`), jak dla powiadomień lokalnych.
7. **Dotknięcie powiadomienia** (`didReceive response`) otwiera ekran zależnie od `type`: `reminder` → szczegóły terminu
   (`reminderId`; gdy go nie ma lokalnie — po synchronizacji albo lista terminów), `summary` → lista terminów
   (przeterminowane / dziś / jutro), `backup` → informacja o kopiach zapasowych programu, `analytic` / `test` / nieznany →
   ekran główny. Rozróżnienie od powiadomień lokalnych po kluczu `type` w `userInfo`.
8. **Ekran „Powiadomienia” w ustawieniach (tryb z serwerem)** (`App/Features/Settings/NotificationSettingsView.swift`):
   - Ukryte: włączenie powiadomień, godzina podsumowania, „w dniu terminu” — tym steruje serwer.
   - Zostaje lokalne: „ukryj szczegóły na ekranie blokady” (zakres działania dla pushy — otwarte pytanie 1).
   - Nowe: stan push (zarejestrowany / tryb awaryjny z powodem / brak zgody z przyciskiem do Ustawień systemu), data
     rejestracji i ostatniej dostawy z `GET /push/device`, lista „Jakie powiadomienia dostaję” z `GET /push/rules`
     (`description` każdej reguły), przycisk „Odśwież”. Pusta lista → wyjaśnienie, że reguły przypisuje właściciel w UI
     webowym (Administracja → Serwer → Powiadomienia), a po wdrożeniu wszystkie są domyślnie wyłączone.
   - `404` z `GET /push/device` (właściciel usunął urządzenie) → aplikacja rejestruje się ponownie i pokazuje, że reguły
     trzeba znów przypisać w UI webowym.
9. **Tryb samodzielny**: bez zmian (Firebase nieskonfigurowany w działaniu — `FirebaseApp.configure()` i rejestracja APNs
   tylko w trybie z serwerem, żadnych połączeń do Google; powiadomienia lokalne jak dziś).
10. **Prywatność.** Logi bez pełnego tokenu (najwyżej prefiks 8 znaków) i bez treści powiadomień. Wyłączona analityka
    i zbieranie danych Firebase (`FIREBASE_ANALYTICS_COLLECTION_ENABLED = NO`, `FirebaseMessagingAutoInitEnabled = NO`
    z ręczną inicjalizacją w trybie z serwerem). Zaktualizować manifest prywatności (`PrivacyInfo.xcprivacy`) i odpowiedzi
    „App Privacy” w App Store Connect.
11. **Rozszerzenie udostępniania** (`ShareExtension`) nie dostaje Firebase ani `aps-environment`.

### Rozstrzygnięcia przejęte z Androida (2.1.0, spec 006 — obowiązują także iOS)

Android rozstrzygnął w `/speckit-clarify` i w planie sprawy, które ta zmiana ma powielić. Gdzie iOS różni się technicznie,
podany jest odpowiednik.

1. **Stan push — jedna czysta funkcja decyzji** (w `HorselyCore`, testowalna bez UIKit): `PushPolicy.decide(input) →
   PushState`. Wejście: tryb pracy, `push` w `capabilities`, zgoda na powiadomienia, dostępność rejestracji systemowej
   (na Androidzie Usługi Google Play; na iOS — udana rejestracja APNs), stan rejestracji. Stany sprawdzane **w tej
   kolejności**:

   | Stan | Warunek | Lokalne powiadomienia o terminach i podsumowaniu |
   |---|---|---|
   | `Standalone` | tryb samodzielny | według ustawień, jak dziś |
   | `Fallback(serverHasNoPush)` | brak `push` w `capabilities` | tak |
   | `NoPermission` | brak zgody | tak (i tak się nie pokażą; ekran mówi „Brak zgody”) |
   | `Fallback(apnsUnavailable)` | APNs odmówił rejestracji / brak tokenu FCM (odpowiednik „brak Usług Google Play”) | tak |
   | `Fallback(registrationFailed)` | trwały błąd rejestracji | tak |
   | `Pending` | jeszcze nie zarejestrowano / ponowienia trwają | tak |
   | `Registered` | ostatni `PUT /push/device` zwrócił `200` dla bieżącego klucza | **nie** |

   `localRemindersActive = state != Registered`. Ekran ustawień i `NotificationScheduler` czytają ten sam stan.
2. **Brak reguł nie przywraca powiadomień lokalnych.** Po udanej rejestracji lokalne o terminach i podsumowaniu są wyłączone
   niezależnie od tego, czy właściciel przypisał reguły. Pusta lista reguł → wyraźne ostrzeżenie „Brak przypisanych
   powiadomień” (telefon nie dostaje wtedy żadnych powiadomień o terminach ani podsumowania) + instrukcja dla właściciela.
   Świadoma decyzja.
3. **Zgoda.** Bez zgody telefon **nie rejestruje się** na serwerze, a wcześniejszą rejestrację wycofuje
   (`DELETE /push/device` przy najbliższym starcie lub powrocie na pierwszy plan). Udzielenie zgody (wykryte przy powrocie
   do aplikacji) uruchamia rejestrację bez dodatkowej akcji. Pytanie o zgodę: przy **pierwszym** pojawieniu się `push`, gdy
   zgody nie ma i użytkownik wcześniej nie odmówił — wyzwalane przy otwarciu aplikacji (Pulpit), nigdy z tła; odmowa jest
   szanowana (bez ponawiania pytania przy każdym starcie). Ekran: „Brak zgody na powiadomienia” + „Otwórz ustawienia
   powiadomień” (na iOS `UIApplication.openNotificationSettingsURLString`). Push i powiadomienia lokalne wymagają tej samej
   zgody — odmowa wyłącza oba rodzaje, ekran to mówi.
4. **„Ukryj szczegóły na ekranie blokady”** — bez zmiany serwera i bez Notification Service Extension: ustawienie działa dla
   powiadomień lokalnych i dla pushy pokazywanych, gdy aplikacja jest na pierwszym planie; pushe wyświetlane przez system
   w tle pokazują pełną treść z serwera. Ekran przy tym ustawieniu dopisuje: „Powiadomienia z serwera odebrane w tle
   pokazują treść także na ekranie blokady.” (Na iOS dodatkowo można wskazać systemowe „Pokazuj podglądy”.)
5. **Synchronizacja po odebraniu**: tak dla `reminder` i `summary` (zlecona w tle, bez blokowania obsługi wiadomości), dla
   pozostałych rodzajów nie. Ograniczenie (jak na Androidzie): push z alertem odebrany w tle jest wyświetlany przez system
   bez wybudzania aplikacji (serwer nie wysyła `content-available`) — wtedy synchronizacja następuje przy dotknięciu albo
   według zwykłego harmonogramu. Na iOS: `willPresent` (pierwszy plan) i `didReceive response` (dotknięcie).
6. **Wiadomość na pierwszym planie przy stanie ≠ `Registered`** (np. tuż po odparowaniu, opóźnienie FCM) — nie jest
   pokazywana (`willPresent` zwraca `[]`). Po wyrejestrowaniu aplikacja nie odnawia tokenu sama (auto-init FCM wyłączony).
7. **Ponowienia rejestracji**: przy starcie, powrocie z nowo udzieloną zgodą, udanym parowaniu, odświeżeniu `capabilities`,
   w którym `push` **się pojawił** (gdy jest stale — najwyżej raz na dobę według `registeredAt`, bo synchronizacja w tle jest
   częsta), i przy zmianie tokenu FCM. Odstęp rosnący od 30 s. Rejestracja **trwale nieudana**: `400` od serwera albo
   24 h kolejnych niepowodzeń od pierwszego (`failingSince`) → `Fallback(registrationFailed)` z powodem „Nie udało się
   zarejestrować telefonu na serwerze — powiadomienia planuje telefon.”; ponowienia trwają dalej w tle. `401/403/429` —
   istniejąca obsługa jak dla każdego żądania, bez osobnego komunikatu push.
8. **Zniknięcie `push`** przy synchronizacji: czyści stan `registered` **bez** `DELETE` (serwer i tak nie wysyła) → lokalne
   wracają; powrót `push` → `Pending` → ponowna rejestracja → po sukcesie lokalne znikają. Alarmy lokalne na dziś są
   anulowane dopiero po udanej rejestracji — jeden podwójny sygnał w chwili przełączenia jest akceptowalny, utracony nie.
9. **Wyrejestrowanie przed usunięciem klucza**: `DELETE /push/device` musi pójść **zanim** klucz API zniknie z Keychain
   (przy „Rozłącz”, przejściu online → samodzielny, usunięciu danych połączenia, cofniętej zgodzie). Kolejność: `DELETE`
   (krótki limit, ~5 s; wynik ignorowany: `401`, brak sieci, 5xx nie blokują) → `Messaging.deleteToken` → wyłączenie
   auto-init → wyczyszczenie lokalnego stanu push. Przerwane przejście trybu wznawiane po restarcie robi tylko część
   lokalną (klucza może już nie być). Zmiana adresu/klucza na inny serwer: stary wyrejestrowany (jeśli osiągalny), nowy
   zarejestrowany według jego `capabilities`.
10. **Lokalny stan rejestracji** (trwały, część danych połączenia, znika przy odparowaniu): `registered`, `tokenPrefix`
    (8 znaków, tylko diagnostyka — pełnego tokenu aplikacja nie zapisuje), `registeredAt`, `failingSince`,
    `permanentFailure`, `deviceRemovedNotice` (po `404` z `GET /push/device` → jednorazowy komunikat „Właściciel usunął ten
    telefon z listy urządzeń. Telefon zarejestrował się ponownie — reguły trzeba znów przypisać w UI webowym.”).
11. **Inicjalizacja Firebase leniwa** — dopiero gdy: tryb z serwerem + `push` + zgoda. Poza tym żaden kod Firebase nie jest
    wołany. Lekcja z Androida (R2): po restarcie procesu SDK potrzebuje skonfigurowanego Firebase, żeby obsłużyć zmianę
    tokenu / wiadomość — Android zapisuje znacznik „push aktywny” przy pierwszej inicjalizacji i **przy starcie aplikacji
    konfiguruje Firebase synchronicznie tylko, gdy znacznik istnieje**; wyrejestrowanie usuwa znacznik. iOS ma przyjąć ten
    sam wzorzec dla `FirebaseApp.configure()` w `application(_:didFinishLaunchingWithOptions:)`.
12. **Plik konfiguracyjny Firebase w repozytorium** (Android: `app/google-services.json`), z notatką w README i konstytucji,
    że to nie sekret (nie pozwala wysyłać powiadomień), a klucz API w nim ograniczony w konsoli Google Cloud do aplikacji
    (na iOS: ograniczenie „iOS apps” do bundle ID `pl.glapa.horsely`). Budowanie z samego repozytorium daje działający push.
13. **Ekran „Powiadomienia”** — teksty jak na Androidzie (`contracts/ui-push.md`):
    - `Registered`: „Powiadomienia z serwera: włączone”, „Zarejestrowano: 05.11.2026, 08:15”, „Ostatnie powiadomienie: …”
      albo „Jeszcze żadnego”; sekcja „Jakie powiadomienia dostaję” (same `description` w kolejności serwera) albo
      ostrzeżenie „Brak przypisanych powiadomień” + „Reguły przypisuje właściciel w UI webowym (Administracja → Serwer →
      Powiadomienia). Po wdrożeniu wszystkie są domyślnie wyłączone.”; „Odśwież”; ukryte: włączenie, godzina
      podsumowania, „w dniu terminu”.
    - `Pending`: „Rejestruję telefon na serwerze…” + dotychczasowe ustawienia lokalne.
    - `Fallback`: ostrzeżenie z powodem („Serwer nie wysyła powiadomień — powiadomienia planuje telefon.” / odpowiednik iOS
      dla APNs, np. „Telefon nie może odbierać powiadomień z serwera — powiadomienia planuje telefon.” / „Nie udało się
      zarejestrować…”) + dotychczasowe ustawienia lokalne.
    - Błąd `GET /push/rules` → „Nie udało się pobrać listy — spróbuj później” bez zmiany stanu push. `GET /push/device`
      i `GET /push/rules` tylko na żądanie ekranu, nie w tle.
    - Karta Pulpitu „Powiadomienia o terminach są wyłączone” (jeśli iOS ją ma lub dostanie — patrz poprawki niżej) nie
      pokazuje się przy `Registered`.
14. **Dotknięcie `backup`** → nowy prosty ekran informacyjny „Kopia zapasowa na serwerze”: „Serwer zgłosił nieudaną kopię
    zapasową. Sprawdź kopie w UI webowym (Administracja → Kopie zapasowe).”, przycisk „Wróć”, bez połączeń z siecią
    (aplikacja nie ma ekranu kopii programu, a ekran kopii telefonu dotyczy trybu samodzielnego). `reminder` bez
    `reminderId` → ekran główny. Mapowanie `userInfo → cel nawigacji` jako czysta funkcja w `HorselyCore` (test bez UI).
    `horseId`, `targetDate` parsowane tolerancyjnie (zła data → brak), w tej wersji nieużywane.
15. **Dziennik diagnostyczny** — kategoria `push`, wynik słowami (Android: `PushDiagnostics`), np. „rejestracja ok
    token=abcd1234…”, „rejestracja nieudana: brak połączenia (zerwane połączenie)”, „wiadomość type=reminder”. Bez pełnego
    tokenu, tytułów, treści i identyfikatorów. Nazwy błędów nie mogą być nieczytelne (na Androidzie w wydaniu zaciemnione
    nazwy klas dawały „ik”). Token w ciele `PUT` nie może trafić do dziennika połączeń — potwierdzić testem.
16. **Wersja**: MINOR — **2.1.0** (nowy numer kompilacji), `CHANGELOG` z sekcją `[2.1.0]` (Dodano: push z serwera, ekran
    „Powiadomienia” w trybie z serwerem; Zmieniono: powiadomienia lokalne o terminach w trybie z serwerem z działającym
    push). Aktualizacja z 2.0.2 nie może utracić danych ani ustawień powiadomień lokalnych; do pierwszej udanej rejestracji
    działają lokalne.
17. **Testy**: zaślepka serwera (odpowiednik `FakeProgramServer`) z `PUT/DELETE/GET push/device` i `GET push/rules`,
    przełącznikiem `push` w `capabilities` i wymuszaniem `400`/`404`/`5xx`. Serwer nie publikuje OpenAPI z push
    (sprawdzone 2026-11-05) — przykłady JSON do testów dekodowania przepisać z `api-push.md`. Modele dekodują tolerancyjnie
    (nieznane pola i nieznany `type` reguły to nie błąd).

### Poprawki z wdrożenia Androida (błędy znalezione na telefonie — sprawdzić i zapobiec na iOS)

1. **Rejestracja nie może iść „plikową” ścieżką sieci.** Na Androidzie `PUT /push/device` z pracy w tle szedł przez bramę
   dla dużych transferów, która przy „tylko przez Wi-Fi”, adresie spoza sieci domowej i danych komórkowych **w ogóle nie
   wysyła** żądania (`NoUsableAddress`); aplikacja uznawała to za błąd chwilowy i wisiała na „Rejestruję telefon na
   serwerze…”. Na iOS odpowiednik to `ApiClient` z `request.forFile && wifiOnly() && conditions.isExpensive`
   (`Packages/HorselyKit/Sources/HorselyKit/Network/ApiClient.swift`) — żądania push (`PUT`/`DELETE`/`GET push/*`) MUSZĄ być
   zwykłymi żądaniami (`forFile = false`) i działać na danych komórkowych przez adres publiczny. Test: rejestracja przy
   `FixedNetwork.cellular` + `wifiOnly = true` + adres zdalny.
2. **Ponawianie `PUT`/`DELETE /push/device` po zerwanym połączeniu.** Sieć komórkowa zrywa bezczynne połączenia z puli,
   a klient ponawia tylko odczyty (na iOS `request.method.isIdempotentRead`), więc rejestracja kończyła się błędem sieci.
   `PUT` i `DELETE /push/device` są idempotentne — dopuścić do 2 natychmiastowych ponowień przy błędzie sieci (poza
   backoffem pracy w tle).
3. **Powiadomienia lokalne w trybie z serwerem naprawdę muszą działać** (tryb awaryjny), bo w 2.0.1 na Androidzie nie
   przychodziły. Poprawki 2.1.0 do sprawdzenia na iOS 2.0.2 i ewentualnego powielenia:
   - udane parowanie **włącza** powiadomienia o terminach, gdy telefon ma zgodę (wcześniej zostawały wyłączone);
   - Pulpit pokazuje kartę „Powiadomienia o terminach są wyłączone” z „Włącz” i „Nie pokazuj”, dopóki są wyłączone
     (nie przy `Registered`);
   - ekran powiadomień nie mówi o odrzuconej zgodzie, zanim o nią zapytano (`UNAuthorizationStatus.notDetermined` ≠ odmowa);
   - treść podsumowania bez odmiany liczebników: „Przeterminowane: 2, na dziś i jutro: 3”;
   - (Android: dzienny alarm przez `setAndAllowWhileIdle` — na iOS nie dotyczy, `UNCalendarNotificationTrigger` dzwoni
     w uśpieniu; sprawdzić tylko, czy podsumowanie jest planowane po parowaniu).

### Zmiany dokumentów (wymagane przed kodem)

- **Konstytucja, zasada II „Prywatność i brak usług zewnętrznych”** (`.specify/memory/constitution.md`): dziś zakazuje
  SDK z połączeniami wychodzącymi. Potrzebny wyjątek: Firebase Cloud Messaging (przez APNs) wyłącznie do odbioru push
  z serwera użytkownika, tylko w trybie z serwerem, bez Analytics/Crashlytics. Zmiana wersji konstytucji
  (`/speckit-constitution`), spójna z wyjątkiem w konstytucji Androida 2.1.0
  (`../zarzadzanie_konmi_android/.specify/memory/constitution.md`, zasada II — wyjątek FCM wraz z notatką, że plik
  konfiguracyjny Firebase nie jest sekretem).
- **Specyfikacja** `SPECYFIKACJA_MOBILE_IOS.md`: usunąć „powiadomienia push z serwera” z listy „Poza zakresem”, dopisać
  rozdział o push (entitlements, tryb awaryjny, ekran ustawień).

### Kryteria akceptacji

- iPhone (TestFlight, `aps-environment = production`) sparowany z serwerem z `push`: po zgodzie rejestruje token (widać go
  w UI webowym na liście urządzeń jako iOS); „Wyślij test” z UI webowego daje powiadomienie „Test powiadomień Horsely”
  przy zablokowanym ekranie i na pierwszym planie.
- Build z Xcode (`development`) również dostaje powiadomienie testowe (klucz `.p8` w Firebase obsługuje oba środowiska).
- Reguła „Kowal: dzień przed o 08:00” przypisana do telefonu → powiadomienie przychodzi z serwera, a lokalne nie
  (brak dubli).
- Wyłączenie przełącznika właściciela w UI webowym → po synchronizacji telefon wraca do powiadomień lokalnych.
- Odparowanie → urządzenie znika z listy w UI webowym.
- Tryb samodzielny i serwer bez `push` zachowują się jak w 2.0.2; w trybie samodzielnym brak połączeń do hostów Google.
- Symulator bez rejestracji APNs → tryb awaryjny z ostrzeżeniem (testy UI).
- iPhone na **danych komórkowych** (Wi-Fi wyłączone, „tylko przez Wi-Fi” włączone, adres publiczny serwera) rejestruje się
  i dostaje test — błąd znaleziony na Androidzie.
- Telefon zarejestrowany bez przypisanych reguł → brak lokalnych powiadomień o terminach i ostrzeżenie „Brak przypisanych
  powiadomień” na ekranie.
- Cofnięcie zgody w Ustawieniach iOS → po powrocie do aplikacji urządzenie znika z listy w UI webowym, ekran „Brak zgody”;
  przywrócenie zgody → ponowna rejestracja.
- Właściciel usuwa urządzenie w UI webowym → po wejściu na ekran „Powiadomienia” komunikat o ponownym przypisaniu reguł,
  telefon wraca na listę.
- Dziennik diagnostyczny po pełnym scenariuszu: tylko prefiks tokenu, brak tytułów i treści, błędy opisane słowami.

---

## Otwarte pytania (do `/speckit-clarify`)

Rozstrzygnięte przez Androida (przyjąć bez ponownego pytania, chyba że iOS ma powód techniczny — wtedy zapisać różnicę):

- ~~Ukryj szczegóły na ekranie blokady~~ → wariant (a), bez NSE i bez zmiany serwera (rozstrzygnięcie 4).
- ~~Moment pytania o zgodę i odmowa~~ → rozstrzygnięcie 3.
- ~~Synchronizacja po push~~ → tak dla `reminder` i `summary` (rozstrzygnięcie 5).
- ~~Wersja~~ → 2.1.0, decyduje wyłącznie `capabilities`, bez sprawdzania numeru serwera (rozstrzygnięcie 16).
- ~~Lokalne powiadomienia przy braku reguł~~ → wyłączone, ostrzeżenie na ekranie (rozstrzygnięcie 2).

Zostają do `/speckit-clarify` (specyficzne dla iOS):

1. **`GoogleService-Info.plist` w repozytorium** — Android trzyma `google-services.json` w repozytorium (rozstrzygnięcie 12).
   Na iOS sprawdzić zgodność z `scripts/ci/check-secrets.sh` (klucz `API_KEY` w pliku może zostać uznany za sekret —
   wtedy wyjątek w skrypcie z uzasadnieniem) i ograniczyć klucz w Google Cloud do bundle ID.
2. **Method swizzling Firebase**: zostawić czy wyłączyć i przekazywać token APNs ręcznie (`Messaging.messaging().apnsToken`)
   — ważne przy istniejącym `NotificationDelegate`. Android nie ma odpowiednika; preferencja: wyłączyć
   (`FirebaseAppDelegateProxyEnabled = NO`) dla przewidywalności i leniwej inicjalizacji (rozstrzygnięcie 11).
3. **Kiedy uznać „APNs niedostępny”** — `didFailToRegisterForRemoteNotificationsWithError` od razu, czy dopiero po kilku
   próbach / limicie czasu bez tokenu FCM (odpowiednik „brak Usług Google Play”, który na Androidzie jest wykrywany od razu).
4. **Ponowienia w tle na iOS** — Android używa WorkManager z backoffem od 30 s; iOS nie ma odpowiednika. Wystarczy
   ponowienie przy wejściu na pierwszy plan + istniejące zadanie `BGAppRefreshTask` (`BackgroundTasks.swift`)? Jak liczyć
   24 h do „trwale nieudanej”?
5. **Wiadomość na pierwszym planie** — iOS wyświetla ją przez `willPresent` (system zastępuje po `apns-collapse-id`), więc
   aplikacja nie buduje powiadomienia sama jak Android; ustalić, czy przy „Ukryj szczegóły” na pierwszym planie wystarczy
   nie pokazywać banera (`[.list, .sound]`), czy pokazać własny lokalny odpowiednik z ukrytą treścią.
