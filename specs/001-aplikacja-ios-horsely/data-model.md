# Data Model: Horsely na iOS

**Feature**: [spec.md](spec.md) | **Research**: [research.md](research.md) (R1, R3, R5, R20)

Model domenowy = model programu w schemacie eksportu **1.5** (`export-schema-1.4.json` + zmiany 1.5 z
[contracts/android/program-2.0-integration.md](contracts/android/program-2.0-integration.md); m.in. status `Injured`).
Magazyn odwzorowuje rozwiązanie Androida 2.0.1 ([contracts/android/data-model-android-2.0.md](contracts/android/data-model-android-2.0.md));
różnice iOS opisane niżej. Baza: SQLite (GRDB) w kontenerze App Group; iOS nie ma wersji 1.x, więc **nie ma migracji
z pamięci podręcznej 1.x** — schemat startuje od razu w kształcie 2.0.1 (wersja migracji GRDB `v1`).

## 1. Rodzaje rekordów (`RecordType`)

Jak w Androidzie (tabela §1 dokumentu Androida): `Dictionary`, `Contact`, `Horse`, `VetVisit`, `FarrierVisit`,
`PhysioVisit`, `SpecialistVisit`, `Competition`, `CompetitionStart`, `Purchase`, `Note`, `Training`, `Reminder`,
`Attachment`. Treść (`body`) = obiekt eksportu tego typu (Codable w `HorselyCore.Model`), starty zawodów jako osobne rekordy
(łączone z zawodami przy zapisie kopii i odczycie eksportu).

Kluczowe pola i reguły (z specyfikacji głównej 6.4 — walidacja w `HorselyCore.Rules`):

| Rekord | Wymagane | Reguły |
|---|---|---|
| Koń | `name`; `passportNumber`, gdy `isFoal = false` | numer paszportu unikalny; imię źrebaka bez paszportu unikalne wśród takich źrebiąt; `farrierIntervalWeeks` 1–26; status `Active`/`Injured`/`Sold`/`Deceased`/`Leased` (+ `statusDate`); `Deceased` → `salePrice = 0` |
| Wizyta weterynaryjna | `horseId`, `visitDateTime`, `visitTypeId` | leki: `AdministeredAtVisit`/`Prescribed`; `nextVisitDate` → termin |
| Kowal | `horseId`, `visitDate`, `serviceId` | podpowiedź `nextVisitDate` z interwału konia |
| Fizjoterapia, specjalista | `horseId`, `visitDate` (+ `specialistTypeId`) | `nextVisitDate` → termin |
| Zawody / start | `name`, `dateFrom` / `horseId` | start w dniach zawodów; zawody w przyszłości → termin; nie usuwa się zawodów ze startami |
| Zakup | `purchaseDate`, `productName`, `categoryId`, `totalAmount`, `assignment` | `deliveryCost ≥ 0`; podział po równo, reszta groszowa do pierwszego konia wg imienia |
| Notatka | `horseId`, `noteDate`, `title` | — |
| Trening | `horseId`, `trainingDate` (nie z przyszłości), `trainingTypeId` | czas 1–600, ocena 1–5, wysokość 10–200 tylko dla `training.jumping`; trener `Trainer`, jeździec `Rider` |
| Termin | `horseId`, `kind`, `dueDate`, `title` | status `Open`/`Completed`/`Dismissed`; zamykanie przez wizytę do 14 dni przed |
| Kontakt | `name`, `types[]` | nie usuwa się kontaktu użytego jako trener/jeździec (`InUse`) |

Kwoty: `Decimal` (dwa miejsca), daty: `LocalDate` (`yyyy-MM-dd`), data i czas wizyty: lokalny czas bez strefy jak w programie.

## 2. Tabele (GRDB, migracja `v1`)

| Tabela | Kolumny (jak w Androidzie, §2) | Indeksy |
|---|---|---|
| `local_record` | `type`, `id` (PK złożony), `version`, `createdAt`, `updatedAt`, `horseId`, `dateKey`, `ownerId`, `deletedAt`, `deletionBatchId`, `syncState`, `baseVersion`, `body` (JSON) | `(type, horseId, dateKey)`, `(type, dateKey)`, `(type, ownerId)`, `(deletionBatchId)`, `(syncState)` |
| `record_horse` | `type`, `id`, `horseId` (PK) — zakupy wielu koni | `(horseId)` |
| `local_file` | `attachmentId`, `kind` (`Original`/`Thumbnail`) (PK), `relativePath` (w App Group), `sizeBytes`, `sha256`, `lastOpenedAt`, `pinned` | `(lastOpenedAt)` |
| `queue_operation` | `id` (UUID, stały — `Idempotency-Key`), `seq` (kolejność), `kind`, `recordType`, `recordId`, `baseVersion`, `payload` (JSON), `fileRef`, `dependsOn` (JSON listy id), `state`, `attempts`, `nextAttemptAt`, `lastError`, `countBefore` (licznik przed i po), `createdAt`, `updatedAt` | `(state, seq)` |
| `queue_history` | `operationId`, `kind`, `outcome` (`Sent`/`AlreadyHandled`/`ConflictResolved`), `summary` (bez treści wpisów), `at` — 30 dni | `(at)` |
| `conflict` | jak w Androidzie §2 (`kind`: `EditEdit`/`EditDelete`/`DeleteEdit`, `mine`, `theirs`, `theirsVersion`, `trashBatchId`, `resolution`) | `(resolvedAt)` |
| `local_meta` | `key`, `value` — `changeCounter`, `sync.dataStamp`, `sync.nextUpdatedSince`, `sync.lastFullAt`, `sync.forceFull`, `program.capabilities`, `dictionaries.trainingTypes200Done` | — |
| `address` | `id`, `url`, `position` (kolejność; „order” to słowo zastrzeżone SQL), `trustMode` (`Pinned`/`TrustedIssuer`/`PlainHttpConfirmed`), `certSha256`, `issuerSummary`, `isRemote`, `lastOkAt`, `heldUntil`, `heldReason` | `(order)` |

## 3. Stany rekordu (`syncState`)

Identyczne z Androidem §3: online `Synced` → `Pending` → `Synced` / `Conflict`; `Projected` (przewidywany skutek reguły dla
niewysłanej zmiany, usuwany przy pełnym pobraniu); samodzielny — `Local` (usunięcie = `deletedAt`). Rekord `Pending`/`Conflict`
nie jest nadpisywany przez pobranie. Przejście online → samodzielny: `Synced`/`Pending`/`Conflict` → `Local` (moja wersja),
`Projected` usuwane.

## 4. Stany operacji kolejki

`Pending` → `Sending` → `Sent` (do historii) | `Unknown` (wynik nieznany → licznik przed i po albo ponowienie z
`Idempotency-Key`) | `NeedsFix` (400/404/409/413/415 z komunikatem) | `AlreadyHandled` (akcja na zamkniętym terminie) |
`Held` (inna stajnia po ponownym parowaniu, FR-M-POL-08; wstrzymanie 401/403) | `Conflict` (§ Android 4). Edycja i usunięcie
operacji możliwe w `Pending`, `NeedsFix`, `Held` (FR-M-SYN-12). Łączenie operacji tylko w `Pending`
(tabela w [FR-SYN2-04](../../SPECYFIKACJA_MOBILE_IOS.md)). Rodzaje (`kind`) i klucze dopasowania licznika:
[contracts/android/outbox-operations.md](contracts/android/outbox-operations.md).

## 5. Ustawienia (`UserDefaults` grupy App Group) i Keychain

| Klucz | Domyślnie | Wymaganie |
|---|---|---|
| `workMode` (`unset`/`online`/`standalone`) | `unset` | FR-TRB-01 |
| `modeChange.pending` (przerwana zmiana trybu) | — | FR-TRB-07 |
| `theme` (`system`/`light`/`dark`) | `system` | FR-M-UST-04 |
| `notifications.enabled`, `.dailyTime` (08:00), `.onDueDate`, `.hideDetails` | wył. / 08:00 / wył. / wył. | FR-M-UST-02 |
| `data.timelineMonths` (3/12/24), `.attachmentLimitMB` (200), `.sendOriginals`, `.keepPhotoLocation`, `.wifiOnly` (wł.), `.downloadAllAttachments` | 12 / 200 / wył. / wył. / wł. / wył. | FR-M-UST-03, FR-SYN2-01 |
| `backup.lastAt`, `.lastKind`, `.lastChangeCounter`, `.reminderSnoozedUntil`, `.auto.enabled`, `.auto.folderBookmark`, `.auto.lastError` | — | FR-KOP-05/08 |
| `appLock.enabled`, `.lastBackgroundAt` | wył. | FR-TRB-09 |
| `connectionLog.until` | — | FR-029 |
| `programVersion.warnedFor` | — | FR-M-UST-06 |
| Keychain `apiKey` (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, grupa dostępu wspólna z rozszerzeniem) | — | NFR-M-04 |

## 6. Reguły i skutki zapisu

Jak w Androidzie §6 (tabela zdarzeń i skutków); pełna lista i pliki wzorcowe:
[contracts/android/rules-parity.md](contracts/android/rules-parity.md). Dopisanie rodzajów treningów 2.0.0: FR-002/003.

## 7. Kopia zapasowa

Format `.zkkopia` 2 (research R5): `manifest.json` (`formatVersion: 2`, `exportSchemaVersion: "1.5"`), `export.json`,
`phone.json` (kosz, ustawienia danych), `attachments/<id>`. Odtworzenie: rozpakowanie do katalogu tymczasowego z kontrolą
`sha256` → jedna transakcja GRDB zastępująca `local_record`, `record_horse`, `local_file`, `local_meta` → przeniesienie plików.

## 8. Zdjęcie konia i miniatury

Jak w Androidzie §8; miniatury koni `pinned` (poza limitem LRU). Z `horsePhotoField` — zmiana konia `photoAttachmentId`
w kolejce (plik przed zmianą konia); bez tej możliwości — wybór zapamiętany lokalnie (`local_meta`).

## 9. Dziennik diagnostyczny

Pliki tekstowe w App Group, rotacja 2 × 2,5 MB (łącznie 5 MB). Wpis: czas, kategoria, komunikat bez danych osobowych;
wpis połączenia (FR-030): metoda, ścieżka bez zapytania, host:port, IP, lokalny/zewnętrzny, sieć, wynik, czas trwania.
