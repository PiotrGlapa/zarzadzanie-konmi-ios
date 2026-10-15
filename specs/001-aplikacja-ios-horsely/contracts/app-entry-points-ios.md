# Kontrakt: punkty wejścia aplikacji (iOS)

**Wymagania**: US4/6, US7/3, FR-M-UI-02, FR-M-UI-06, FR-M-POW-*, FR-M-KTK-02, FR-M-RAP-05, FR-016, FR-023 | **Odpowiednik Androida**:
[android/app-entry-points.md](android/app-entry-points.md)

## Adresy wewnętrzne (`horsely://`)

Schemat zarejestrowany w `Info.plist` (`CFBundleURLTypes`), obsługiwany tylko z powiadomień i szybkich akcji; adres
z zewnątrz (Safari, inne aplikacje) otwiera najwyżej Pulpit i niczego nie zmienia.

| Adres | Cel | Android |
|---|---|---|
| `horsely://dashboard` | Pulpit | `zk://dashboard` |
| `horsely://reminders` | Terminy | `zk://reminders` |
| `horsely://reminders/{id}` | Szczegóły terminu z akcjami | `zk://reminders/{id}` |
| `horsely://entry/new?kind=note` | Formularz notatki (wybór konia) | `zk://entry/new?kind=note` |
| `horsely://entry/new?kind=farrier` | Formularz wizyty kowala | `zk://entry/new?kind=farrier` |
| `horsely://queue` | Kolejka wysyłki | `zk://queue` |

Nieznany adres, tryb nieustawiony albo aktywna blokada aplikacji → najpierw ekran powitania / odblokowanie, potem cel.

## Szybkie akcje ikony (MUST, FR-023)

Statyczne `UIApplicationShortcutItems` w `Info.plist` (tytuły z `strings.xml`): „Dodaj notatkę” → `horsely://entry/new?kind=note`,
„Kowal” → `horsely://entry/new?kind=farrier`, „Terminy” → `horsely://reminders`. Ikony: obrazy szablonowe z katalogu zasobów
(`edit_note`, `handyman`, `event`).

## Rozszerzenie udostępniania `HorselyShare`

| Klucz `NSExtensionActivationRule` | Wartość |
|---|---|
| `NSExtensionActivationSupportsImageWithMaxCount` | 20 |
| `NSExtensionActivationSupportsMovieWithMaxCount` | 5 |
| `NSExtensionActivationSupportsFileWithMaxCount` | 20 (UTType: PDF, DOCX, XLSX, TXT) |

Przebieg: kopia plików do App Group → wybór konia → wybór wpisu albo „Nowa notatka” → zapis operacji `CreateAttachment`
(online) lub rekordu załącznika (samodzielny) w bazie App Group → „Gotowe”. Plik niedozwolony lub > 100 MB → komunikat
(FR-M-ZAL-02). Tryb nieustawiony → „Najpierw otwórz aplikację Horsely i wybierz tryb pracy”. Rozszerzenie nie łączy się
z siecią; aplikacja przetwarza pliki (zmniejszanie) i wysyła kolejkę przy otwarciu i w tle.

## Akcje wychodzące

| Akcja | iOS |
|---|---|
| Zadzwoń / SMS / e‑mail | `tel:`, `sms:`, `mailto:` przez `openURL` |
| Nawigacja | `maps://?q=<adres>` (Mapy Apple) |
| Udostępnij raport / log / załącznik | `ShareLink` / `UIActivityViewController` z plikiem tymczasowym (usuwanym po udostępnieniu) |
| Zapisz raport / kopię | `fileExporter` |
| Wybór pliku kopii / folderu kopii automatycznej | `fileImporter` (plik), `UIDocumentPickerViewController` folder + zakładka bezpieczeństwa |
| Kontakt z książki adresowej | `CNContactPickerViewController` (bez zgody na kontakty) |
| Ustawienia zgód (powiadomienia, sieć lokalna, aparat) | `UIApplication.openSettingsURLString` |

## Zadania w tle (`BGTaskSchedulerPermittedIdentifiers`)

`pl.glapa.horsely.refresh` (`BGAppRefreshTask`), `pl.glapa.horsely.sync` i `pl.glapa.horsely.backup` (`BGProcessingTask`);
sesja w tle `pl.glapa.horsely.upload`.

## Powiadomienia

| Kategoria | Treść | Dotknięcie |
|---|---|---|
| Podsumowanie dnia (`daily-RRRR-MM-DD`) | „X przeterminowanych, Y na dziś i jutro” [+ „Dane z <data> — połącz się z komputerem, aby je odświeżyć”] | `horsely://dashboard` |
| W dniu terminu (`due-<id>`) | „Grom — kowal, dziś” | `horsely://reminders/{id}` |
| Wymaga poprawy (`queue-needsfix`) | „N operacji wymaga poprawy” | `horsely://queue` |
| Błąd kopii automatycznej (`backup-error`) | przyczyna + „Wskaż folder ponownie” | Kopia zapasowa |

„Ukryj szczegóły na ekranie blokady” → treść bez imion i tytułów oraz `hiddenPreviewsBodyPlaceholder`; respektowane
systemowe ustawienie podglądów. Ikona powiadomień = ikona aplikacji.

## `Info.plist` — zgody

`NSCameraUsageDescription`, `NSLocalNetworkUsageDescription`, `NSFaceIDUsageDescription` (teksty z `strings.xml`, w tym
„Odblokowanie aplikacji z danymi stajni”). Zabronione klucze: lokalizacja, `NSContactsUsageDescription`,
`NSPhotoLibraryUsageDescription` (pełny dostęp). Test sprawdza listę kluczy (konstytucja II).
