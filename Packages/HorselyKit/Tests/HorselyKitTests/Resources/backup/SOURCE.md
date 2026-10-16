# Wzorcowe kopie Androida 2.0.1

Pliki utworzone kodem `BackupWriter` z repozytorium `zarzadzanie_konmi_android` (rdzeń 2.0.1, `core/src/main/kotlin/pl/glapa/zk/core/backup`),
uruchomionym jednorazowo testem JVM z danymi `BackupFixtures` (zegar 2026-10-09T18:30Z):

- `android-2.0.1.zkkopia` — bez hasła;
- `android-2.0.1-haslo.zkkopia` — hasło `Siano-2026`;
- `android-2.0.1-expected.txt` — rekordy magazynu Androida (`rodzaj|id|wersja|deletedAt|partia`) i `sha256` plików załączników.

Zawartość: 2 konie (w tym „Kontuzjowany”), domyślne słowniki, 3 notatki z polskimi znakami, notatka w koszu (partia `batch-1`),
2 załączniki z plikami (zdjęcie i tekst UTF-8). Test `BackupTests` odtwarza oba pliki w iOS i porównuje rekordy oraz sumy plików.
