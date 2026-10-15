# Kontrakty — Horsely na iOS

## Kontrakty iOS (ta specyfikacja)

| Plik | Zakres |
|---|---|
| [ci-release.md](ci-release.md) | GitHub Actions, sekrety, wydanie przez TestFlight, grupy testerów |
| [app-entry-points-ios.md](app-entry-points-ios.md) | adresy `horsely://`, szybkie akcje, rozszerzenie udostępniania, powiadomienia, `Info.plist` |
| [ui-screens-ios.md](ui-screens-ios.md) | lista ekranów, odpowiedniki komponentów Android → iOS, ikony, dostępność |
| [test-fixtures.md](test-fixtures.md) | wspólne dane testowe i zrzuty wzorcowe z Androidem |

## Kontrakty normatywne z Androida 2.0.1 (`android/`)

Skopiowane bez zmian z repozytorium `zarzadzanie_konmi_android`, commit `c4a869d` (2026-10-15). Obowiązują aplikację iOS tak
samo jak Androida; odwołania do Kotlina, Room, WorkManagera itp. czytać jako opis zachowania, nie technologii. Przy zmianie
w Androidzie kopię odświeża się świadomie (zasada V konstytucji).

| Plik | Źródło w repozytorium Androida |
|---|---|
| `openapi-2.0.0.yaml`, `program-2.0-integration.md`, `ui-2.0.1.md` | `specs/005-horsely-2-0-1/contracts/` |
| `openapi.yaml` (1.6.1), `outbox-operations.md`, `pairing-and-connection.md`, `report-export.md`, `app-entry-points.md` | `specs/001-aplikacja-mobilna/contracts/` |
| `connection-behavior.md`, `navigation-and-icons.md`, `api-usage.md` | `specs/002-ikony-menu-polaczenie/contracts/` |
| `ui-components.md`, `screen-review.md` | `specs/003-poprawki-wersja-1-2/contracts/` |
| `backup-format.md` (format 1; format 2 — research R5), `export-schema-1.4.json`, `mode-and-sync.md`, `rules-parity.md`, `ui-screens.md`, `palette-mockup.html`, `icons-mockup.html` | `specs/004-tryb-samodzielny-offline/contracts/` |
| `data-model-android-2.0.md` | `specs/004-tryb-samodzielny-offline/data-model.md` |
