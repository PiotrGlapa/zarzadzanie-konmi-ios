# Kontrakt: wiadomość push na iPhonie

Źródło: `../zarzadzanie_konmi_java/specs/008-push-mobilny/contracts/fcm.md` §2. Serwer wysyła przez FCM HTTP v1, FCM przekazuje
do APNs. Odpowiednik Androida: `specs/006-push-z-serwera/contracts/fcm-message.md`.

## Co przychodzi (APNs)

```json
{
  "aps": { "alert": { "title": "Horsely", "body": "Kowal: Gniada, jutro" } },
  "type": "reminder",
  "reminderId": "6F1C…",
  "horseId": "A0B2…",
  "targetDate": "2026-11-05",
  "gcm.message_id": "…",
  "google.c.a.e": "1"
}
```

Nagłówki APNs (ustawia serwer): `apns-push-type: alert`, `apns-priority: 10`, `apns-expiration` = koniec dnia, którego dotyczy
wiadomość (awaria kopii: 24 h), `apns-collapse-id` = `<type>-<id>` (podsumowanie `summary-<data>`). Brak `mutable-content`
i `content-available` → bez Notification Service Extension i bez wybudzania aplikacji w tle.

Treści (przykłady z serwera): „Kowal: Gniada, jutro”, „Przeterminowane: 2, dziś: 1, jutro: 3”, „Kopia zapasowa nie powiodła się”,
„Test powiadomień Horsely”. Bez notatek, kwot, diagnoz i nazw osób.

## Rozpoznanie i mapowanie (`HorselyCore`)

| Krok | Reguła |
|---|---|
| Czy to wiadomość z serwera? | `userInfo["type"]` jest napisem. Powiadomienia lokalne mają klucz `link` i nie mają `type`. |
| `PushMessage(userInfo:)` | `type` → `PushKind` (`reminder`, `summary`, `backup`, `analytic`, `test`, inne → `other`); `reminderId`, `horseId` — napisy niepuste albo `nil`; `targetDate` — `LocalDate("yyyy-MM-dd")` albo `nil`. Klucze `aps`, `gcm.*`, `google.*` i nieznane pomijane. |
| `PushDeepLink.url(for:)` | `reminder` + `reminderId` → `horsely://reminders/{id}`; `reminder` bez `reminderId` → `horsely://dashboard`; `summary` → `horsely://reminders`; `backup` → `horsely://server-backup`; `analytic`, `test`, `other` → `horsely://dashboard` |
| `triggersSync` | `reminder`, `summary` → `true`; pozostałe → `false` |

## Zachowanie aplikacji

| Sytuacja | Zachowanie |
|---|---|
| tło / zamknięta / ekran zablokowany | alert wyświetla system (pełna treść z serwera, także na ekranie blokady); aplikacja nie jest wybudzana |
| pierwszy plan, `PushState == .registered` | `willPresent` → `[.banner, .list, .sound]` (także przy „ukryj szczegóły”); dla `triggersSync` — `refresh(force: true)` w osobnym zadaniu; dziennik „wiadomość type=<rodzaj>” |
| pierwszy plan, inny stan | `willPresent` → `[]` (wiadomość nie jest pokazywana, FR-016/FR-008) |
| dotknięcie (`didReceive`) | klucz `link` → jak dziś; inaczej `PushDeepLink` → `DeepLinkRouter.handle`; dla `triggersSync` — synchronizacja; `reminders/{id}` bez rekordu lokalnie → synchronizacja, potem szczegóły albo lista terminów |
| kilka wiadomości o tym samym terminie | system zastępuje wpis o tym samym `apns-collapse-id` |
| wiadomość przeterminowana | APNs jej nie doręcza po `apns-expiration` |

Dziennik nigdy nie zawiera tytułu, treści ani identyfikatorów z wiadomości (FR-028).
