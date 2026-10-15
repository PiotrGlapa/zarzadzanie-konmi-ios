#!/usr/bin/env bash
# Wkłada uprawnienia (App Group, pęk kluczy) do niepodpisanego archiwum przez podpis doraźny plików .app i .appex.
# Powód: zespół nie ma zarejestrowanych urządzeń, więc archiwum nie może dostać podpisu deweloperskiego, a SDK urządzenia
# zabrania podpisu doraźnego w xcodebuild. Eksport z `-allowProvisioningUpdates` zastępuje ten podpis podpisem
# dystrybucyjnym z chmury Apple i zachowuje uprawnienia.
# Użycie: embed-entitlements.sh <ścieżka.xcarchive>
set -euo pipefail

archive="$1"
app="$archive/Products/Applications/Horsely.app"
appex="$app/PlugIns/HorselyShare.appex"
: "${APPLE_TEAM_ID:?Brak APPLE_TEAM_ID}"

tmp="$(mktemp -d)"
sign() {
  local bundle="$1" source="$2" out="$tmp/$(basename "$source")"
  # W pliku źródłowym $(AppIdentifierPrefix) to „<ID zespołu>.”
  sed "s/\$(AppIdentifierPrefix)/${APPLE_TEAM_ID}./g" "$source" > "$out"
  codesign --force --sign - --entitlements "$out" "$bundle"
}

sign "$appex" ShareExtension/HorselyShare.entitlements
sign "$app" App/Horsely.entitlements
rm -rf "$tmp"

echo "Uprawnienia wstawione do archiwum."
codesign -d --entitlements :- "$app" 2>/dev/null | grep -E "group\.|keychain" || true
