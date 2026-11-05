# Data Model: Powiadomienia push z serwera (iOS, 003)

Bez zmiany schematu SQLite i formatu kopii zapasowej. Stan push leży w `SettingsStore` (`UserDefaults` aplikacji) i jest
częścią danych połączenia — znika przy „Rozłącz”, przejściu w tryb samodzielny, usunięciu danych połączenia i cofniętej zgodzie.
Odpowiednik: Android `data-model.md` §1–§7. Decyzje: [research.md](research.md) R4–R9, R17.

## 1. `PushRegistration` (telefon, trwałe) — `HorselyCore` (wartość), zapis w `SettingsStore`

| Pole | Typ | Klucz `UserDefaults` | Opis |
|---|---|---|---|
| `registered` | Bool | `push.registered` | ostatni `PUT /push/device` zwrócił `200` dla bieżącego klucza |
| `tokenPrefix` | String? | `push.tokenPrefix` | 8 pierwszych znaków tokenu FCM — tylko diagnostyka (FR-028/FR-030); pełnego tokenu aplikacja nie zapisuje (trzyma go SDK) |
| `registeredAt` | Date? | `push.registeredAt` | czas ostatniej udanej rejestracji (z odpowiedzi serwera) — także podstawa „najwyżej raz na dobę” (FR-003) |
| `failingSince` | Date? | `push.failingSince` | pierwsze niepowodzenie z bieżącej serii; `nil` po sukcesie (FR-004) |
| `permanentFailure` | Bool | `push.permanentFailure` | `400` od serwera albo `now − failingSince ≥ 24 h` (FR-005) |
| `deviceRemovedNotice` | Bool | `push.deviceRemovedNotice` | `404` z `GET /push/device` → jednorazowy komunikat do czasu „Rozumiem” (FR-025) |
| `apnsRefused` | Bool | `push.apnsRefused` | system odmówił rejestracji do powiadomień zdalnych; czyszczone przy udanej rejestracji APNs (R5) |

Znaczniki poza `PushRegistration` (też `SettingsStore`):

| Klucz | Typ | Opis |
|---|---|---|
| `push.active` | Bool | Firebase był skonfigurowany (tryb z serwerem + `push` + zgoda) → konfiguracja synchroniczna przy starcie (R6); usuwany przy wyrejestrowaniu |
| `push.permissionAsked` | Bool | pytanie o zgodę z Pulpitu już padło — odmowa szanowana (FR-014); **nie** jest czyszczony przy odparowaniu (decyzja użytkownika dotyczy telefonu) |
| `notifications.offCardDismissed` | Bool | „Nie pokazuj” na karcie Pulpitu (FR-012a); nie jest częścią danych połączenia |

Wartości domyślne (aktualizacja z 2.0.2, FR-034): wszystkie `false`/`nil` → stan `pending` w trybie z serwerem z `push` → lokalne
powiadomienia działają do pierwszej udanej rejestracji.

`PushRegistrar.clearLocal()` czyści wszystkie klucze `push.*` poza `push.permissionAsked`.

## 2. `PushState` (wyliczany, nietrwały) — `HorselyCore`

`PushPolicy.decide(PushInput) -> PushState`

`PushInput`: `workMode: WorkMode`, `serverHasPush: Bool` (z `ProgramCapabilities.push`), `authorization: PushAuthorization`
(`notDetermined` | `denied` | `allowed`), `registration: PushRegistration` (z `apnsRefused`).

| Stan | Warunek (sprawdzany w tej kolejności) | Lokalne o terminach i podsumowaniu |
|---|---|---|
| `standalone` | `workMode != .online` | według ustawień, jak w 2.0.2 |
| `fallback(.serverHasNoPush)` | `!serverHasPush` | tak |
| `noPermission` | `authorization != .allowed` (przy `notDetermined` ekran nie mówi o odmowie — pokazuje stan `pending` z wyjaśnieniem; zob. niżej) | tak (bez zgody i tak się nie pokażą) |
| `fallback(.apnsUnavailable)` | `registration.apnsRefused` | tak |
| `fallback(.registrationFailed)` | `registration.permanentFailure` | tak |
| `pending` | `!registration.registered` | tak |
| `registered` | `registration.registered` | **nie** — niezależnie od reguł |

Uściślenie `notDetermined`: `PushPolicy` zwraca `noPermission(asked: false)` przy `notDetermined` i `noPermission(asked: true)` przy
`denied`; ekran pokazuje „Brak zgody na powiadomienia” tylko dla `asked: true` (FR-012a), a dla `asked: false` — `push_state_pending`.
W obu przypadkach rejestracja nie rusza (FR-014a).

Pochodne: `localRemindersActive = state != .registered`; `showsServerSection = workMode == .online`;
`registrationAllowed = state ∈ {pending, registered, fallback(.registrationFailed)}` (rejestrator próbuje tylko wtedy; przy
`registered` — odświeżenie najwyżej raz na dobę albo przy zmianie tokenu).

Przejścia:

- `pending → registered` — `PUT` `200`; `pending → fallback(.registrationFailed)` — `400` albo 24 h błędów (ponowienia trwają).
- `registered → fallback(.serverHasNoPush)` — synchronizacja bez `push` (lokalny `registered = false`, bez `DELETE`, FR-011);
  powrót `push` → `pending` → `registered`.
- dowolny online → `noPermission` — cofnięcie zgody (wykryte przy starcie/powrocie) → `unregister` (R9).
- dowolny → `fallback(.apnsUnavailable)` — `didFailToRegisterForRemoteNotifications`; udana rejestracja APNs → `pending`.
- `registered → pending` — `404` z `GET /push/device` (właściciel usunął urządzenie): `registered = false`,
  `deviceRemovedNotice = true`, natychmiastowa rejestracja.
- online → `standalone` / brak trybu — `unregister` przed usunięciem klucza (R9).

## 3. `DeviceRegistration` (żądanie) — `HorselyCore`

`{"platform": "Ios", "token": "<token FCM>"}` — nic więcej (FR-030). `token`: 1–4096 znaków, bez białych znaków (walidacja przed
wysłaniem; naruszenie → traktowane jak brak tokenu, R7).

## 4. `PushDevice` (odpowiedź, nietrwała) — `HorselyCore`

`platform: String`, `tokenPrefix: String`, `registeredAt: Date`, `lastSeenAt: Date?`, `lastDeliveredAt: Date?`. Daty przez
`SyncMerger.parseInstant` (7 cyfr ułamka, R17). Nieznane pola pomijane. Pełny token nigdy nie wraca.

## 5. `ClientPushRule` (odpowiedź, nietrwała) — `HorselyCore`

`id: String`, `type: String` (`Reminder` | `DailySummary` | `BackupFailure` | `AnalyticEvent` | nieznany), `reminderKind: String?`,
`offsetDays: Int?`, `sendTime: String?`, `repeatTime: String?`, `description: String`. Ekran pokazuje **tylko** `description`
w kolejności z serwera (FR-023). Element bez `description` jest pomijany (nie przerywa dekodowania listy).

## 6. `PushMessage` (wiadomość, nietrwała) — `HorselyCore`

Z `userInfo` (`[AnyHashable: Any]`, wszystkie wartości własne to napisy): `kind: PushKind` (`reminder` | `summary` | `backup` |
`analytic` | `test` | `other(String)`), `reminderId: String?`, `horseId: String?`, `targetDate: LocalDate?` (zła data → `nil`).
Wiadomość z serwera = obecny klucz `type`; klucze `aps`, `gcm.*`, `google.*` i nieznane — pomijane (FR-018). Tytuł i treść
(`aps.alert`) nie są czytane przez model (nigdy do dziennika).

`PushDeepLink.url(for:)`: `reminder` + `reminderId` → `horsely://reminders/{id}`; `summary` → `horsely://reminders`;
`backup` → `horsely://server-backup`; pozostałe → `horsely://dashboard` (FR-019, R11).

`PushMessage.triggersSync = kind ∈ {reminder, summary}` (FR-017).

## 7. Zmiany w istniejących modelach

- `ProgramCapabilities`: `pushName = "push"` w `known`, `var push: Bool`. `CapabilitiesChange`: `pushAppeared`, `pushVanished`.
- `ApiRequest`: `retryOnDrop: Int = 0` (R8).
- `DeepLinkTarget`: `.serverBackup` (karta „Więcej”).
- `SettingsStore`: klucze z §1; brak zmian istniejących kluczy.
- `ReminderDigest.dailySummary`: „Przeterminowane: X, na dziś i jutro: Y” (bez odmiany liczebników; części zerowe pomijane).
