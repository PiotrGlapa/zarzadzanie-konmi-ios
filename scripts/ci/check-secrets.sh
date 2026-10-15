#!/usr/bin/env bash
# Krok „Sprawdź sekrety” wydania (contracts/ci-release.md §1, §3): przebieg kończy się błędem z listą brakujących nazw,
# a wysyłka do TestFlight nigdy nie jest po cichu pomijana (konstytucja, SPECYFIKACJA_MOBILE_IOS.md 9.6).
# Wartości sekretów nie są drukowane; `set -x` jest wyłączone.
set +x
set -u

missing=()
for name in ASC_ISSUER_ID ASC_KEY_ID ASC_KEY_P8 APPLE_TEAM_ID IOS_BUNDLE_ID IOS_APP_GROUP ASC_APP_ID; do
  if [ -z "${!name:-}" ]; then
    missing+=("$name")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  list="${missing[*]}"
  echo "::error title=Brak sekretów lub zmiennych::Nie można wysłać kompilacji do TestFlight. Brakuje: ${list}"
  {
    echo "## Wysyłka do TestFlight: NIE WYKONANO"
    echo
    echo "Brakujące sekrety lub zmienne repozytorium: \`${list}\`"
    echo
    echo "Uzupełnij je w Settings → Secrets and variables → Actions (nazwy: contracts/ci-release.md §1)."
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 1
fi

# Identyfikator pakietu w project.yml musi być zgodny ze zmienną repozytorium.
project_bundle_id="$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *\(pl\.glapa\.horsely\) *$/\1/p' project.yml | head -n 1)"
if [ "$project_bundle_id" != "$IOS_BUNDLE_ID" ]; then
  echo "::error title=Niezgodny identyfikator pakietu::project.yml: '${project_bundle_id}', IOS_BUNDLE_ID: '${IOS_BUNDLE_ID}'"
  exit 1
fi

echo "Sekrety i zmienne kompletne."
