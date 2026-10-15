# Kontrakt: budowanie, testy i wydanie przez TestFlight (bez Maca)

**Wymagania**: FR-025, FR-026, specyfikacja główna 9.6–9.8 | **Research**: R6, R19

## 1. Sekrety i zmienne repozytorium `PiotrGlapa/zarzadzanie-konmi-ios`

Ustawione kreatorem 2026-10-15; nazwy są umową — procesy MUSZĄ używać dokładnie tych.

| Rodzaj | Nazwa | Użycie |
|---|---|---|
| sekret | `ASC_ISSUER_ID` | `-authenticationKeyIssuerID` |
| sekret | `ASC_KEY_ID` | `-authenticationKeyID` |
| sekret | `ASC_KEY_P8` | zapisany do `$RUNNER_TEMP/AuthKey.p8` (uprawnienia 600), usuwany w kroku `always()` |
| zmienna | `APPLE_TEAM_ID` | `DEVELOPMENT_TEAM` |
| zmienna | `IOS_BUNDLE_ID` | `pl.glapa.horsely` (rozszerzenie: `$IOS_BUNDLE_ID.ShareExtension`) |
| zmienna | `IOS_APP_GROUP` | `group.pl.glapa.horsely` (uprawnienia celów) |
| zmienna | `ASC_APP_ID` | odnośniki w podsumowaniu przebiegu |

Sekrety nigdy nie są drukowane; `set -x` wyłączone w krokach z sekretami.

## 2. `ci.yml`

| Wyzwalacz | Kroki | Artefakty |
|---|---|---|
| `pull_request` | `xcodegen generate` → `swift test` (`Packages/HorselyCore`, `Packages/HorselyKit`) → kompilacja aplikacji i rozszerzenia (symulator) → test zgodności tekstów → testy migawkowe | `.xcresult`, różnice migawek |
| `push` na `main` | jak wyżej + testy UI na symulatorze iPhone 15 Pro (iOS 18) + zrzuty ekranów (jasny, ciemny, tekst 200 %) na danych `zrzuty.zkkopia` | `.xcresult`, `screenshots/ios/*.png` obok `Tests/Reference/android/*.png` |

Runner: `macos-latest` (lub nowszy obraz z Xcode obsługującym iOS 18 SDK); wersja Xcode wybierana jawnie (`xcode-select`).
Pamięć podręczna: pakiety SPM (`~/Library/Caches/org.swift.swiftpm`, `.build`). Przebieg PR ma pozostać krótki (bez testów UI).

## 3. `release.yml`

| Wyzwalacz | Znaczenie |
|---|---|
| `workflow_dispatch` (wejście `group`: `Deweloper`) | kompilacja częściowa dla właściciela (spec FR-025) |
| tag `v*` (np. `v2.0.1`) | wydanie pełnego zakresu |

Kroki: pełne testy jak `ci.yml` na `main` → `xcodebuild archive` (Release, `CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`,
`MARKETING_VERSION` z `project.yml` = 2.0.1, `-allowProvisioningUpdates` + klucz API) → `xcodebuild -exportArchive`
z `ExportOptions.plist` (`method = app-store-connect`, `destination = upload`, `signingStyle = automatic`,
`teamID = $APPLE_TEAM_ID`) → podsumowanie przebiegu: wersja, numer kompilacji, wynik wysyłki, odnośnik do TestFlight.

Brak któregokolwiek sekretu/zmiennej → krok „Sprawdź sekrety” kończy przebieg błędem z listą brakujących nazw (bez
cichego pomijania wysyłki, konstytucja).

## 4. Grupy TestFlight

| Grupa | Członkowie | Dystrybucja |
|---|---|---|
| Deweloper | właściciel | automatyczna — każda wysłana kompilacja |
| Właściciele | córka (iPhone 15 Pro) i właściciel | ręcznie w App Store Connect: kompilacja dodawana po ręcznej liście kontrolnej ([quickstart.md](../quickstart.md) §7); pierwsza po zaliczeniu US1–US3 z połączeniem w domu i spoza domu |

Przypomnienie: kompilacja wygasa po 90 dniach — nowa co najmniej raz na 80 dni (CLAUDE.md).

## 5. Lokalnie (Windows)

Na Windows nie ma kompilacji; lokalnie działają tylko: `scripts/sync-strings.ps1`, edycja `project.yml` i kodu, `gh workflow run`,
`gh run watch`, pobieranie artefaktów (`gh run download`).
