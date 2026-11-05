# Kontrakt: konfiguracja projektu, podpis i CI dla push (iOS 2.1.0)

Uzupełnienie `specs/001-aplikacja-ios-horsely/contracts/ci-release.md`. Decyzje: [research.md](../research.md) R1, R15, R16.

## `project.yml`

- `packages.Firebase`: `url: https://github.com/firebase/firebase-ios-sdk`, `exactVersion: <12.x z dnia implementacji>`.
- Cel `Horsely` → `dependencies: - package: Firebase, product: FirebaseMessaging`. Cele `HorselyShare`, `AppSnapshotTests`,
  `AppUITests` i pakiety `HorselyCore`/`HorselyKit` — **bez** Firebase.
- `MARKETING_VERSION: "2.1.0"`.
- Zasób `App/Resources/GoogleService-Info.plist` trafia do aplikacji (ścieżka `App` już jest źródłem); do rozszerzenia — nie.

## `App/Info.plist`

| Klucz | Wartość |
|---|---|
| `UIBackgroundModes` | `fetch`, `processing`, **`remote-notification`** |
| `FirebaseAppDelegateProxyEnabled` | `false` |
| `FirebaseMessagingAutoInitEnabled` | `false` |
| `FIREBASE_ANALYTICS_COLLECTION_ENABLED` | `false` |

## Uprawnienia

| Plik | Zmiana |
|---|---|
| `App/Horsely.entitlements` | `aps-environment` = `development` (eksport dystrybucyjny zastępuje profilem: `production`) |
| `ShareExtension/HorselyShare.entitlements` | bez zmian — **bez** `aps-environment` |

Apple Developer: identyfikator `pl.glapa.horsely` z możliwością **Push Notifications** (automatyczne podpisywanie z
`-allowProvisioningUpdates` i kluczem API ASC ją włącza; gdy eksport zgłosi brak możliwości — włączyć ręcznie, quickstart §2).
Klucz APNs `.p8` jest w Firebase — **nie** jest sekretem CI i nie trafia do repozytorium.

## `release.yml` — nowy krok po eksporcie `.ipa`

`bash scripts/ci/verify-push-entitlements.sh "$RUNNER_TEMP/ipa"` — po istniejącym rozpakowaniu `.ipa` do `$RUNNER_TEMP/ipa`
(`release.yml`, krok po `-exportArchive`), przed `upload-build.js`:

1. Wejście: katalog z `Payload/Horsely.app`.
2. `codesign -d --entitlements :- Payload/Horsely.app` → MUSI zawierać `aps-environment` = `production`.
3. `codesign -d --entitlements :- Payload/Horsely.app/PlugIns/HorselyShare.appex` → NIE MOŻE zawierać `aps-environment`.
4. `Payload/Horsely.app/GoogleService-Info.plist` MUSI istnieć i mieć `BUNDLE_ID = pl.glapa.horsely`;
   w `HorselyShare.appex` — NIE MOŻE istnieć.
5. Błąd → `::error title=Uprawnienia push::…` z opisem i wpis w `GITHUB_STEP_SUMMARY`; przebieg kończy się niepowodzeniem
   **przed** wysyłką do TestFlight (nigdy ciche pominięcie).

`embed-entitlements.sh`: dotychczasowa kontrola rozszerzona o wypisanie `aps-environment` (diagnostyka).

## `ci.yml`

Bez nowych kroków poza istniejącymi: `xcodegen generate`, testy pakietów, `sync-strings.ps1 -Check`, migawki, testy UI.
Pamięć podręczna SPM obejmuje teraz Firebase (klucz zależny od `project.yml`, bo wersja Firebase jest tam przypięta).

## Manifest prywatności — `App/PrivacyInfo.xcprivacy` (nowy)

- `NSPrivacyTracking` = `false`, `NSPrivacyTrackingDomains` = `[]`.
- `NSPrivacyCollectedDataTypes`: `NSPrivacyCollectedDataTypeDeviceID` — `Linked = false`, `Tracking = false`,
  cel `NSPrivacyCollectedDataTypePurposeAppFunctionality` (token FCM / identyfikator instalacji do dostarczania powiadomień).
- `NSPrivacyAccessedAPITypes`: `NSPrivacyAccessedAPICategoryUserDefaults` — powód `CA92.1`.

App Store Connect → App Privacy: „Identyfikator urządzenia — funkcjonalność aplikacji, niepowiązany z tożsamością, bez śledzenia”
(krok ręczny właściciela; dystrybucja tylko TestFlight, ale dane zgodne z manifestem).

## Sprawdzenie „brak Firebase w trybie samodzielnym”

Test jednostkowy `PushRegistrarTests`: w trybie samodzielnym i przy serwerze bez `push` zaślepka `PushTokenSource` nie dostaje
żadnego wywołania (`configureIfNeeded`, `token`, `setAutoInit(true)`), a `registerForRemoteNotifications` nie jest wołane.
Ręcznie: quickstart §5 (ruch sieciowy telefonu).
