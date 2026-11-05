#!/usr/bin/env bash
# Sprawdza w rozpakowanym pliku .ipa konfigurację powiadomień push (spec 003, contracts/ci-push.md; FR-030a, FR-030b, FR-032b):
#   1. aplikacja ma uprawnienie `aps-environment` = `production`;
#   2. rozszerzenie udostępniania NIE ma `aps-environment`;
#   3. `GoogleService-Info.plist` (BUNDLE_ID = pl.glapa.horsely) jest w aplikacji i NIE ma go w rozszerzeniu;
#   4. manifest prywatności `PrivacyInfo.xcprivacy` jest w aplikacji.
# Błąd kończy przebieg PRZED wysyłką do TestFlight — wysyłka nigdy nie jest po cichu pomijana.
# Użycie: verify-push-entitlements.sh <katalog z Payload/Horsely.app>
set -uo pipefail

root="${1:?Podaj katalog z Payload/Horsely.app}"
app="$root/Payload/Horsely.app"
appex="$app/PlugIns/HorselyShare.appex"
errors=()

[ -d "$app" ] || { echo "::error title=Uprawnienia push::Brak $app"; exit 1; }
[ -d "$appex" ] || errors+=("brak rozszerzenia HorselyShare.appex w aplikacji")

entitlements_of() { codesign -d --entitlements :- "$1" 2>/dev/null || true; }

app_entitlements="$(entitlements_of "$app")"
aps_value="$(printf '%s' "$app_entitlements" | tr -d '\n\t ' | sed -n 's/.*<key>aps-environment<\/key><string>\([^<]*\)<\/string>.*/\1/p')"
echo "aps-environment aplikacji: ${aps_value:-<brak>}"
if [ "$aps_value" != "production" ]; then
  errors+=("aplikacja ma aps-environment='${aps_value:-brak}', wymagane 'production' (włącz możliwość Push Notifications dla pl.glapa.horsely w Apple Developer)")
fi

if [ -d "$appex" ]; then
  if entitlements_of "$appex" | grep -q "aps-environment"; then
    errors+=("rozszerzenie HorselyShare ma aps-environment — nie może (push tylko w aplikacji)")
  fi
  [ -e "$appex/GoogleService-Info.plist" ] && errors+=("rozszerzenie HorselyShare zawiera GoogleService-Info.plist — Firebase tylko w aplikacji")
fi

plist="$app/GoogleService-Info.plist"
if [ ! -e "$plist" ]; then
  errors+=("brak GoogleService-Info.plist w aplikacji")
else
  bundle_id="$(plutil -extract BUNDLE_ID raw -o - "$plist" 2>/dev/null || true)"
  [ "$bundle_id" = "pl.glapa.horsely" ] || errors+=("GoogleService-Info.plist ma BUNDLE_ID='${bundle_id:-brak}', wymagane 'pl.glapa.horsely'")
fi

[ -e "$app/PrivacyInfo.xcprivacy" ] || errors+=("brak PrivacyInfo.xcprivacy w aplikacji (manifest prywatności)")

if [ "${#errors[@]}" -gt 0 ]; then
  for e in "${errors[@]}"; do echo "::error title=Uprawnienia push::$e"; done
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## Uprawnienia push: BŁĄD (wysyłka do TestFlight wstrzymana)"
      echo
      for e in "${errors[@]}"; do echo "- $e"; done
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 1
fi

echo "Uprawnienia push w porządku: aps-environment=production tylko w aplikacji, plist Firebase tylko w aplikacji, manifest prywatności jest."
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "- Uprawnienia push: aps-environment=production (aplikacja), brak w rozszerzeniu, GoogleService-Info.plist i PrivacyInfo.xcprivacy w aplikacji" >> "$GITHUB_STEP_SUMMARY"
fi
