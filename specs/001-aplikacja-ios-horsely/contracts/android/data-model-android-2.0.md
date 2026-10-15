# Data Model: Wersja 2.0

**Feature**: [spec.md](spec.md) | **Research**: [research.md](research.md) (R2, R3, R5, R6, R10, R13–R16)

Model domenowy pozostaje modelem programu (`export-schema-1.4`, [contracts/export-schema-1.4.json](contracts/export-schema-1.4.json));
ten dokument opisuje, jak telefon go przechowuje i jakie stany dokłada.

## 1. Rodzaje rekordów (`RecordType`)

Kanoniczne klasy w `:core` (`pl.glapa.zk.core.local`), 1:1 z `$defs` schematu eksportu.

| `RecordType` | Klasa eksportu | `horseId` | `dateKey` | `ownerId` | Zagnieżdżone (w `body`) |
|---|---|---|---|---|---|
| `Dictionary` | `ExportDictionaryItem` | — | — | — | — |
| `Contact` | `ExportContact` | — | — | — | `types` |
| `Horse` | `ExportHorse` | = `id` | — | — | — |
| `VetVisit` | `ExportVetVisit` | ✓ | data z `visitDateTime` | — | `medications` |
| `FarrierVisit` | `ExportFarrierVisit` | ✓ | `visitDate` | — | — |
| `PhysioVisit` | `ExportPhysioVisit` | ✓ | `visitDate` | — | `bodyAreaIds`, `techniqueIds` |
| `SpecialistVisit` | `ExportSpecialistVisit` | ✓ | `visitDate` | — | — |
| `Competition` | `ExportCompetition` (bez `starts`) | — | `dateFrom` | — | — |
| `CompetitionStart` | `ExportCompetitionStart` | ✓ | `startDate` lub `dateFrom` zawodów | `competitionId` | — |
| `Purchase` | `ExportPurchase` | — (wiele: `horseIds`) | `purchaseDate` | — | `horseIds` |
| `Note` | `ExportNote` | ✓ | `noteDate` | — | — |
| `Training` | `ExportTraining` | ✓ | `trainingDate` | — | — |
| `Reminder` | `ExportReminder` | ✓ | `dueDate` | `sourceId` | — |
| `Attachment` | `ExportAttachment` | `horseId` | data `createdAt` | `ownerId` | — |

Starty zawodów są przechowywane jako osobne rekordy (w eksporcie zagnieżdżone w `competitions[].starts`) — rozdzielane
przy wczytaniu, scalane przy zapisie kopii (R14). Zakup wielu koni: dodatkowa tabela łącząca `record_horse(type, id, horseId)`
dla zapytań po koniu.

## 2. Tabele Room (baza w wersji 3)

### `local_record`

| Kolumna | Typ | Opis |
|---|---|---|
| `type` | TEXT | `RecordType` (PK razem z `id`) |
| `id` | TEXT (UUID) | id z programu lub nadane w telefonie (UUID v4) |
| `version` | INTEGER | wersja z programu; w trybie samodzielnym zwiększana przy każdej zmianie |
| `createdAt`, `updatedAt` | TEXT (ISO, lokalny czas bez strefy jak w programie) | audyt |
| `horseId` | TEXT? | indeks |
| `dateKey` | TEXT? (`LocalDate`) | indeks |
| `ownerId` | TEXT? | indeks (starty → zawody, załączniki → właściciel, termin → źródło) |
| `deletedAt` | TEXT? | kosz (tylko tryb samodzielny) |
| `deletionBatchId` | TEXT? | id korzenia partii usunięcia |
| `syncState` | TEXT | §3 |
| `baseVersion` | INTEGER? | wersja z programu, od której zaczęła się lokalna zmiana (tryb online) |
| `body` | TEXT (JSON) | rekord w kształcie eksportu |

Indeksy: `(type, horseId, dateKey)`, `(type, dateKey)`, `(type, ownerId)`, `(deletionBatchId)`, `(syncState)`.

### `record_horse`

`(type, id, horseId)` — PK złożony; utrzymywana dla `Purchase` (i każdego rekordu z wieloma końmi).

### `local_file`

| Kolumna | Opis |
|---|---|
| `attachmentId` (PK), `kind` (`Original`/`Thumbnail`) | |
| `path` | ścieżka w `noBackupFilesDir` |
| `sizeBytes`, `sha256` | weryfikacja, kopia zapasowa |
| `lastOpenedAt` | LRU (tylko tryb online) |
| `pinned` | `true` w trybie samodzielnym i dla miniatur koni (poza LRU) |

### `conflict`

| Kolumna | Opis |
|---|---|
| `id` (PK) | |
| `operationId` | operacja kolejki w stanie `Conflict` |
| `recordType`, `recordId` | |
| `kind` | `EditEdit` / `EditDelete` / `DeleteEdit` |
| `mine` | JSON mojej wersji (albo `null` dla usunięcia) |
| `theirs` | JSON wersji z programu (albo `null`, gdy usunięty); `theirsVersion` |
| `trashBatchId`, `trashBatchSize` | dla `EditDelete`, gdy rekord jest w koszu programu |
| `detectedAt`, `resolvedAt`, `resolution` (`KeepMine`/`AcceptTheirs`) | historia 30 dni |

### `queue_operation` (istniejąca, rozszerzona)

Nowe kolumny: `recordType`, `recordId`, `baseVersion`. Nowe wartości `kind` (R5): `Update*`, `Delete*`, `CreateHorse`,
`UpdateHorse`, `RescheduleReminder`. Nowy stan `Conflict` (§4).

### Usuwane po migracji (R18)

`cached_document`, `cache_meta`, `horse`, `contact`, `reminder_open`, `dictionary_item`, `training`, `purchase`,
`competition`, `competition_start`, `attachment_meta` — po pierwszym udanym pełnym pobraniu.

## 3. Stan rekordu (`syncState`)

```text
Tryb online:
  Synced ──zmiana lokalna──▶ Pending ──wysłano (2xx)──▶ Synced
                               │  ▲
                               │  └─ rozstrzygnięcie KeepMine (wysłano)
                               └──409 / usunięty w programie / zmieniony przed DELETE──▶ Conflict
  Conflict ──AcceptTheirs──▶ Synced (stan z programu)
  Projected — przewidywany skutek reguły dla niewysłanej zmiany (R9); usuwany przy każdym pełnym pobraniu

Tryb samodzielny:
  Local (jedyny stan; usunięcie = deletedAt ≠ null)
```

Reguły:

- Rekord `Pending`/`Conflict` nie jest nadpisywany przez pełne pobranie (R4) — porównywany jest tylko `version` z `baseVersion`.
- `Projected` nigdy nie trafia do kolejki ani do kopii zapasowej.
- Przejście online → samodzielny: `Synced`/`Pending` → `Local`, `Conflict` → `Local` z moją wersją, `Projected` usuwane.

## 4. Stany operacji kolejki

Istniejące (1.x): `Pending`, `Sending`, `Unknown`, `Sent`, `NeedsFix`, `AlreadyHandled`, `Held`. Nowe:

| Stan | Znaczenie | Wyjście |
|---|---|---|
| `Conflict` | wysyłka wykryła konflikt (R6); zależne operacje czekają | `KeepMine` → `Pending` (z nowym `baseVersion` albo z przywróceniem z kosza); `AcceptTheirs` → usunięta, zależne → `NeedsFix` |

Łączenie operacji (R5) dotyczy tylko `Pending`.

## 5. Ustawienia (DataStore)

| Klucz | Typ | Domyślnie | Wymaganie |
|---|---|---|---|
| `workMode` | `Unset`/`Online`/`Standalone` | `Unset` (migracja: `Online`, gdy jest parowanie) | FR-TRB-01/04 |
| `lastFullSyncAt` | Instant? | — | FR-SYN2-02, R4 |
| `downloadAllAttachments` | Boolean | `false` | FR-SYN2-01 |
| `backup.lastAt`, `backup.lastKind` (`Manual`/`Auto`), `backup.lastChangeCounter` | | — | FR-KOP-05 |
| `backup.reminderSnoozedUntil` | LocalDate? | — | FR-KOP-05 |
| `backup.auto.enabled`, `backup.auto.treeUri`, `backup.auto.lastError` | | `false` | FR-KOP-08 |
| `appLock.enabled` | Boolean | `false` | FR-TRB-09 |
| `appLock.lastBackgroundAt` | Instant? (w pamięci procesu + DataStore przy zimnym starcie) | — | FR-TRB-09 |

Licznik zmian danych (`changeCounter`) — wartość w tabeli `local_meta`, zwiększana w każdej transakcji zapisu; służy
kopii automatycznej i przypomnieniu.

## 6. Walidacja i reguły (tryb samodzielny i podgląd offline)

Z `pl.glapa.zk.core.rules` (R8): walidacja pól i unikalności → błąd przy polu z tekstem programu; skutki zapisu:

| Zdarzenie | Skutek |
|---|---|
| Zapis wizyty / zabiegu z `nextVisitDate` | nowy termin (`Reminder`, `sourceType`/`sourceId`) jak `*Registrations` w programie |
| Zapis wizyty pasującej do otwartego terminu (≤ 14 dni przed) | termin `Completed`, `completedByType/Id` |
| Zawody z datą w przyszłości | termin rodzaju „Zawody” |
| Zakup dla wielu koni | podział `totalAmount + deliveryCost` po równo, reszta groszowa do pierwszego konia wg imienia (porządek jak w programie) |
| Koń → status `Deceased` | `salePrice = 0` |
| Usunięcie kontaktu użytego jako trener/jeździec | błąd `InUse` („zarchiwizuj”) |
| Usunięcie rekordu | partia kosza: korzeń + zależne (np. koń → jego wpisy, treningi, terminy, załączniki) |

Pełna lista i pliki wzorcowe: [contracts/rules-parity.md](contracts/rules-parity.md).

## 7. Kopia zapasowa

Plik `.zkkopia`: [contracts/backup-format.md](contracts/backup-format.md). Odtworzenie zastępuje `local_record`,
`record_horse`, `local_file` i `local_meta` w jednej transakcji; pliki rozpakowane wcześniej do katalogu tymczasowego.

## 8. Zdjęcie konia

`Horse.photoAttachmentId` → rekord `Attachment` (`ownerType = Horse`, `ownerId = horseId`) + `local_file`
(`Thumbnail`, `pinned = true`; w trybie samodzielnym także `Original`). Podmiana: nowy załącznik, zmiana konia;
stary załącznik bez zmian. „Usuń zdjęcie”: `photoAttachmentId = null`.

## 9. Kolory

Nie są danymi — tokeny motywu (`EntryKindColor`, `SectionColor`) mapowane z `RecordType`/rodzaju terminu/działu
([contracts/ui-screens.md](contracts/ui-screens.md)).
