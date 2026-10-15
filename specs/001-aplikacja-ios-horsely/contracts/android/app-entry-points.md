# Kontrakt: punkty wejścia aplikacji (system Android)

**Wymagania**: US4/6, US7/3, FR-M-UI-02, FR-M-UI-06, FR-M-POW-01…05, FR-M-KTK-02, FR-M-RAP-05 | **Źródło**: SPECYFIKACJA_MOBILE_ANDROID.md §9

## Głębokie linki wewnętrzne (`zk://`, tylko z powiadomień i skrótów — `exported` przez `PendingIntent`/skrót, nie z sieci)

| Link | Cel |
|---|---|
| `zk://dashboard` | Pulpit |
| `zk://reminders/{id}` | Szczegóły terminu (z akcjami) |
| `zk://reminders` | Lista terminów |
| `zk://entry/new?kind=note` | Formularz notatki (wybór konia) |
| `zk://entry/new?kind=farrier` | Formularz wizyty kowala |
| `zk://queue` | Kolejka wysyłki (powiadomienie o operacjach „Wymaga poprawy”) |

Nieznany link lub brak parowania → ekran powitania / parowania.

## Udostępnianie do aplikacji

| Intencja | Typy MIME | Zachowanie |
|---|---|---|
| `ACTION_SEND` | `image/*`, `video/mp4`, `video/quicktime`, `application/pdf`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document`, `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`, `text/plain` | kopia pliku → wybór konia → wybór wpisu albo „Nowa notatka” → operacja `CreateAttachment` |
| `ACTION_SEND_MULTIPLE` | jw. | jw. dla wielu plików |

Plik niedozwolony lub > 100 MB → komunikat, brak operacji (FR-M-ZAL-02). Bez parowania → komunikat „Najpierw połącz aplikację
z programem”.

## Intencje wychodzące

| Akcja | Intencja |
|---|---|
| Zadzwoń | `ACTION_DIAL tel:<numer>` (bez uprawnienia `CALL_PHONE`) |
| SMS | `ACTION_SENDTO smsto:<numer>` |
| E‑mail | `ACTION_SENDTO mailto:<adres>` |
| Nawigacja | `ACTION_VIEW geo:0,0?q=<adres>` |
| Udostępnij raport / log / załącznik | `ACTION_SEND` z `content://` (`FileProvider`), `FLAG_GRANT_READ_URI_PERMISSION` |
| Zapisz raport | `ACTION_CREATE_DOCUMENT` |
| Kontakt z książki adresowej | `ACTION_PICK` `ContactsContract.CommonDataKinds.Phone.CONTENT_URI` (bez `READ_CONTACTS`) |
| Optymalizacja baterii | `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (`package:`), `ACTION_APPLICATION_DETAILS_SETTINGS` |
| Ustawienia powiadomień | `ACTION_APP_NOTIFICATION_SETTINGS` |

## Odbiorniki systemowe

| Zdarzenie | Działanie |
|---|---|
| `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED` | odtworzenie alarmów powiadomień, zaplanowanie `OutboxWorker` |
| `TIME_SET`, `TIMEZONE_CHANGED` | przeliczenie alarmów |
| Alarm „podsumowanie dnia” / „w dniu terminu” | treść z Room (bez sieci); brak terminów → brak powiadomienia; dopisek przy danych > 7 dni |

## Powiadomienia i kanały

| Kanał | Ważność | Treść |
|---|---|---|
| „Terminy — podsumowanie dnia” | domyślna | „X przeterminowanych, Y na dziś i jutro” [+ „Dane z <data> — połącz się z komputerem, aby je odświeżyć”] |
| „Terminy — w dniu terminu” | domyślna | „Grom — kowal, dziś” |
| „Wysyłanie danych” | niska | postęp wysyłki dużych plików; „N operacji wymaga poprawy” |

Na ekranie blokady przy „Ukryj szczegóły” — wersja publiczna bez imion i tytułów (`setPublicVersion`).

## Skróty aplikacji (SHOULD, FR-M-UI-06)

Statyczne `shortcuts.xml`: „Dodaj notatkę” (`zk://entry/new?kind=note`), „Kowal” (`zk://entry/new?kind=farrier`),
„Terminy” (`zk://reminders`).

## Uprawnienia w manifeście

`INTERNET`, `ACCESS_NETWORK_STATE`, `CAMERA` (tylko skaner QR), `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `WAKE_LOCK` (WorkManager).
Zabronione: lokalizacja, `READ_CONTACTS`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `READ_MEDIA_*`, `READ/WRITE_EXTERNAL_STORAGE`.
Test manifestu sprawdza listę (konstytucja II).
