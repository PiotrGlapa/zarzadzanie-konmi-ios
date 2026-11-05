# Kontrakt UI: push z serwera (iOS 2.1.0)

Odpowiednik Androida: `specs/006-push-z-serwera/contracts/ui-push.md`. Teksty z `strings.xml` Androida przez
`scripts/sync-strings.ps1` (klucze `push_*`, `dashboard_notifications_off_*`); dwa teksty tylko dla iOS dopisane w `strings.xml`
Androida (research R14). Dostępność: każda kontrolka z etykietą VoiceOver, stan opisany słowami (nie tylko kolorem), tekst 200 %
bez obcinania, cele dotyku ≥ 44 pt. Ikony Material (Outlined) jak w Androidzie.

## Ustawienia → Powiadomienia (tryb z serwerem)

Sekcja „Powiadomienia z serwera” (`push_section_title`) na górze ekranu, sterowana `PushState` ([data-model.md](../data-model.md) §2):

| `PushState` | Pokazane | Ukryte |
|---|---|---|
| `registered` | `push_state_registered`; `push_registered_at` („Zarejestrowano: 05.11.2026, 08:15”); `push_last_delivered` albo `push_never_delivered` (z `GET /push/device`); sekcja `push_rules_title` z listą `description` w kolejności serwera albo ostrzeżenie `push_rules_empty_title` + `push_rules_empty_text`; przycisk `push_refresh`; „Ukryj szczegóły na ekranie blokady” z dopiskiem `push_hide_background_note` i `push_hide_previews_hint` (systemowe „Pokazuj podglądy”) | włączenie powiadomień, godzina podsumowania, „w dniu terminu” |
| `pending` (także `noPermission(asked: false)`) | `push_state_pending` + dotychczasowe ustawienia lokalne | — |
| `fallback(.serverHasNoPush)` | ostrzeżenie `push_state_no_push` + ustawienia lokalne | — |
| `fallback(.apnsUnavailable)` | ostrzeżenie `push_state_no_apns` („Telefon nie może odbierać powiadomień z serwera — powiadomienia planuje telefon.”) + ustawienia lokalne | — |
| `fallback(.registrationFailed)` | ostrzeżenie `push_state_failed` + ustawienia lokalne | — |
| `noPermission(asked: true)` | `push_state_no_permission` + przycisk „Otwórz ustawienia powiadomień” (`UIApplication.openNotificationSettingsURLString`) | — |
| `standalone` | ekran jak w 2.0.2 | cała sekcja serwera |

- `GET /push/device` i `GET /push/rules` przy otwarciu ekranu (`.task`) i po `push_refresh`; w trakcie — wskaźnik postępu w sekcji.
  Błąd reguł → `push_rules_failed` w miejscu listy.
- `deviceRemovedNotice` → okno z `push_device_removed` i przyciskiem `push_device_removed_ok`, pokazane raz.
- Powrót z Ustawień iOS (`scenePhase == .active`) → odczyt zgody i `reconcile` (rejestracja albo wyrejestrowanie bez dodatkowej akcji).
- Dostępność: identyfikatory `push-state`, `push-rules`, `push-refresh`, `push-open-settings` (testy UI).

## Pulpit

- Karta „Powiadomienia o terminach są wyłączone” (`dashboard_notifications_off_title`, `…_text`, przyciski `…_enable` „Włącz”,
  `…_hide` „Nie pokazuj”) — oba tryby pracy. Widoczna, gdy `!notificationsEnabled`, `PushState != .registered` i karta nie
  została ukryta. „Włącz” → zgoda (wyjaśnienie `notif_permission_*` przy `notDetermined`, instrukcja przy `denied`) i
  `notificationsEnabled = true`; „Nie pokazuj” → `notifications.offCardDismissed = true`.
- Pytanie o zgodę (FR-014): przy pojawieniu się Pulpitu w trybie z serwerem, gdy `capabilities.push`, zgoda `notDetermined`
  i `push.permissionAsked == false` → okno z `push_permission_text` i „Dalej” → systemowe pytanie → `push.permissionAsked = true`.
  Nigdy z tła ani z innych ekranów.

## Ekran „Kopia zapasowa na serwerze” (`horsely://server-backup`)

Tytuł `push_server_backup_title`, tekst `push_server_backup_text`, przycisk powrotu z tym samym tekstem co w Androidzie
(klucz sprawdzony przy synchronizacji tekstów; domyślnie `common_back` „Wstecz”). Ikona Material
`cloud_off` (Outlined). Bez połączeń z siecią. Otwierany na karcie „Więcej”.

## Migawki (AppSnapshotTests — jasny, ciemny, tekst 200 %)

`NotificationSettings_registered_rules`, `…_registered_empty`, `…_pending`, `…_fallback_noPush`, `…_fallback_apns`,
`…_noPermission`, `…_notDetermined` (bez komunikatu o odmowie), `Dashboard_notificationsOffCard`, `ServerBackupInfo`.
