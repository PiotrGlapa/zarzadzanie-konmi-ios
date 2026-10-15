# Kontrakt: plik kopii zapasowej `.zkkopia` (format 1)

Wymagania: FR-KOP-01…08, SC-2-07. Decyzje: research R14, R15.

## 1. Plik bez hasła

ZIP (`java.util.zip`, kompresja DEFLATE; pliki `attachments/` jako STORED, jeśli już skompresowane — jpg/png/mp4/pdf):

| Wpis | Zawartość |
|---|---|
| `manifest.json` | patrz §3 — **pierwszy** wpis w archiwum |
| `export.json` | dokument `export-schema-1.4` (`scope.type = "full"`, `includesAttachmentFiles = true`), aktywne rekordy |
| `phone.json` | `{ "trash": [ {rekord eksportu, "recordType", "deletedAt", "deletionBatchId"} ], "dataSettings": {…} }` |
| `attachments/<attachmentId>` | oryginał pliku (także plików rekordów w koszu) |

Nazwa domyślna: `Zarzadzanie-konmi-kopia-RRRR-MM-DD.zkkopia`; automatyczne: `zk-auto-RRRR-MM-DD.zkkopia`.

## 2. Plik z hasłem

```text
magic      8 B   "ZKKOPIA1"
kdf        1 B   1 = PBKDF2-HMAC-SHA256
iterations 4 B   big-endian (310 000)
salt      16 B
chunks:    powtarzane do końca pliku
  length   4 B   długość szyfrogramu porcji (z 16 B znacznika)
  nonce   12 B   losowy
  data     n B   AES-256-GCM(porcja ZIP ≤ 1 MiB)
           AAD = magic ‖ salt ‖ numer porcji (8 B) ‖ flaga ostatniej porcji (1 B)
```

Błędny znacznik pierwszej porcji → „Nieprawidłowe hasło”; błąd dalej, brak porcji z flagą ostatniej → „Plik
uszkodzony lub niekompletny”. Hasło nie jest nigdzie zapisywane.

## 3. `manifest.json`

```json
{
  "format": "zk-kopia",
  "formatVersion": 1,
  "createdAt": "2026-10-09T18:30:00",
  "appVersion": "2.0.0",
  "exportSchemaVersion": "1.4",
  "counts": { "horses": 12, "entries": 4310, "attachments": 220, "trash": 5 },
  "entries": { "export.json": "<sha256>", "phone.json": "<sha256>", "attachments/<id>": "<sha256>" }
}
```

## 4. Odtwarzanie

1. Odczyt `manifest.json` (po odszyfrowaniu pierwszych porcji) → ekran z datą i liczbami.
2. `formatVersion` > obsługiwanej → „Kopia z nowszej wersji aplikacji” (FR-KOP-03).
3. Rozpakowanie do `noBackupFilesDir/restore-tmp/` z weryfikacją `sha256` każdego wpisu.
4. Wczytanie `export.json` (pliki 1.3/1.4 z domyślnymi wartościami jak `ExportModels.cs`) i `phone.json`.
5. Jedna transakcja: zastąpienie magazynu; następnie przeniesienie plików; usunięcie `restore-tmp`.
6. Błąd w krokach 1–4 → dane bez zmian; błąd w 5 → wycofanie transakcji, pliki tymczasowe usunięte.

## 5. Zgodność

- Aplikacja ≥ 2.0 odtwarza każdy `formatVersion` ≤ swojego (FR-KOP-04); nowe pola — tylko addytywnie.
- `export.json` jest zgodny ze schematem importu programu (konstytucja V) — przeniesienie do programu poza zakresem 2.0,
  ale format tego nie wyklucza.

## 6. Kopia automatyczna

Folder z `ACTION_OPEN_DOCUMENT_TREE` (trwałe uprawnienie); co 7 dni, gdy `changeCounter` > wartości z ostatniej kopii;
po zapisie usuń najstarsze `zk-auto-*.zkkopia` ponad 4; zawsze bez hasła. Błąd (brak dostępu, brak miejsca) →
powiadomienie + `backup.auto.lastError`.

## 7. Testy

- utworzenie i odtworzenie (z hasłem i bez) zbioru 50 koni / 50 000 rekordów / 1 GB plików — zgodność 100% rekordów
  i `sha256` (SC-2-07, czas < 5 min);
- błędne hasło, obcięty plik, zmieniony bajt w porcji, brak wpisu, zła suma `sha256`, `formatVersion` 2;
- przerwanie odtwarzania w każdym kroku → dane bez zmian;
- rotacja kopii automatycznych (4 najnowsze, kopie ręczne nietknięte).
