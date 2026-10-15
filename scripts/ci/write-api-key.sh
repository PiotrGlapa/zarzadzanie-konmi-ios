#!/usr/bin/env bash
# Zapisuje klucz API App Store Connect (sekret ASC_KEY_P8) do $RUNNER_TEMP/AuthKey.p8 z uprawnieniami 600.
# Plik usuwa krok `always()` wydania (scripts/ci/remove-api-key.sh). Zawartość klucza nigdy nie trafia do dziennika.
set +x
set -eu

key_file="${RUNNER_TEMP:?}/AuthKey.p8"
umask 077

# Sekret może być zapisany jako zwykły PEM albo jako base64 tego pliku.
case "$ASC_KEY_P8" in
  *"BEGIN PRIVATE KEY"*) printf '%s\n' "$ASC_KEY_P8" > "$key_file" ;;
  *) printf '%s' "$ASC_KEY_P8" | base64 --decode > "$key_file" ;;
esac
chmod 600 "$key_file"

if ! grep -q "BEGIN PRIVATE KEY" "$key_file"; then
  rm -f "$key_file"
  echo "::error title=Klucz API::ASC_KEY_P8 nie zawiera klucza prywatnego .p8 (PEM albo base64 PEM)."
  exit 1
fi

echo "key_file=$key_file" >> "$GITHUB_OUTPUT"
