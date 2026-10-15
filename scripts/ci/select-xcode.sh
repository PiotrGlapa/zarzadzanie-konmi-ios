#!/usr/bin/env bash
# Jawny wybór Xcode na runnerze: najnowsza zainstalowana wersja o podanym przedrostku (XCODE_VERSION, np. "26").
# App Store Connect wymaga SDK z Xcode 26 lub nowszego (błąd 90725 przy wysyłce z Xcode 16.4); cel wdrożenia pozostaje iOS 18.
set -euo pipefail

prefix="${XCODE_VERSION:?Brak XCODE_VERSION}"
selected="$(ls -d /Applications/Xcode_"${prefix}"*.app 2>/dev/null | sort -V | tail -n 1 || true)"
if [ -z "$selected" ]; then
  echo "::error title=Xcode::Brak /Applications/Xcode_${prefix}*.app na runnerze. Zainstalowane:"
  ls -d /Applications/Xcode*.app
  exit 1
fi
sudo xcode-select -s "$selected"
echo "Wybrany Xcode: $selected"
xcodebuild -version
