# Data Model: Poprawki 2.0.2

Bez zmian w bazie danych, formacie kopii zapasowej i kontrakcie API. Nowe są tylko modele w pamięci.

## AppLockMachine (HorselyKit, w pamięci)

| Pole | Typ | Znaczenie |
|------|-----|-----------|
| `enabled` | Bool | ustawienie „Blokada aplikacji” (odczyt z `SettingsStore`) |
| `locked` | Bool | ekran „Aplikacja zablokowana” widoczny |
| `covered` | Bool | zasłona w przełączniku aplikacji |
| `backgroundedAt` | Date? | moment przejścia w tło **po** odblokowaniu; tylko w pamięci |
| `authenticating` | Bool | trwa okno uwierzytelniania |
| `autoPromptAvailable` | Bool | czy ekran blokady może sam otworzyć okno (raz na epizod blokady) |

Przejścia (próg `AppLockPolicy.timeout` = 5 min):

| Zdarzenie | Warunek | Wynik |
|-----------|---------|-------|
| `launch` | `enabled` | `locked = true`, `autoPromptAvailable = true` |
| `didEnterBackground(t)` | `enabled` | `covered = true`; jeśli `!locked` → `backgroundedAt = t` |
| `willResignActive` | `enabled && !authenticating` | `covered = true` |
| `didBecomeActive(t, passcode)` | `!passcode` | blokada wyłączona, `locked = false`, komunikat |
| `didBecomeActive(t, passcode)` | `backgroundedAt != nil && t − backgroundedAt > 5 min` | `locked = true`, `autoPromptAvailable = true` |
| `didBecomeActive(t, …)` | zawsze | `covered = false`, `backgroundedAt = nil` |
| `authenticationStarted` | `locked && !authenticating` | `authenticating = true`, `autoPromptAvailable = false` |
| `authenticationFinished(true)` | — | `locked = false`, `authenticating = false`, `backgroundedAt = nil` |
| `authenticationFinished(false)` | — | `authenticating = false` (zostaje `locked`) |

Niezmienniki: `didBecomeActive` bez wcześniejszego `didEnterBackground` nigdy nie blokuje; po
`authenticationFinished(true)` blokada wraca tylko po `didEnterBackground` + > 5 min albo po `launch`.

## Zdjęcie konia — źródło miniatury (HorselyKit)

Kolejność dla `attachmentId` konia: plik `thumbnail` → plik `original` (wygenerowanie miniatury, zapis przypięty) →
online: `GET attachments/{id}/thumbnail` (zapis przypięty) → brak (`nil`). Stan w `HorseDirectory` (w pamięci):
`failed: Set<String>` (ponowienie po kolejnej synchronizacji), `unavailable: Set<String>` (404, do końca sesji).

## GroupBarChart (HorselyCore)

| Pole | Typ | Znaczenie |
|------|-----|-----------|
| `metric` | `count` \| `minutes` | miara wykresu |
| `bars` | `[(label: String, value: Int)]` | grupy raportu w kolejności raportu; > 12 → 11 + „Pozostałe” |

Źródło: `RiderTrainingsReport.groups` (`name`, `count`, `totalMinutes`) — bez przeliczania. Pusty raport → `nil`.
