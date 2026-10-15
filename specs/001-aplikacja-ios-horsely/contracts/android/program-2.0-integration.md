# Kontrakt: współpraca z programem 2.0.0 (możliwości, synchronizacja, kolejka)

Źródło po stronie programu: `../zarzadzanie_konmi/specs/009-horsely-2-0-0/contracts/api-2.0-changes.md` (§1–§6) i `export-schema-1.5.md`.
Nazwy możliwości i nagłówków są umową z programem — **nie zmieniać bez uzgodnienia**. Program bez listy `capabilities` (1.5.0–1.6.x) =
zachowanie aplikacji 2.0.0 bez żadnej zmiany (SC-007).

## 1. Możliwości

| Możliwość | Co włącza w aplikacji | Bez możliwości |
|---|---|---|
| `dataStamp` | §3 krok 2 (stop przy tym samym stemplu); odświeżanie w tle co 15 min | pobranie przy każdym odświeżeniu; tło co 60 min |
| `updatedSince` | §3 pobieranie zmian | zawsze pełne pobranie |
| `ifMatchDelete` | §4 `If-Match` przy `DELETE` i przywracaniu, bez odczytu kontrolnego | odczyt kontrolny przed `DELETE` (2.0.0) |
| `idempotencyKey` | §5 `Idempotency-Key` przy `POST` tworzących | „licznik przed i po” (`MatchQueries`) |
| `horsePhotoField` | §6 `photoAttachmentId` w `PUT /horses/{id}` | mapa zdjęć w telefonie (2.0.0) |
| `horseStatusInjured` | §2 nagłówek cech klienta, status „Kontuzjowany” w formularzu i filtrze | brak statusu w trybie online |

Odczyt: każdy `GET /system/info` (parowanie, sprawdzenie połączenia, sondowanie, początek odświeżenia) → `local_meta.program.capabilities`.
Nieznane nazwy — ignorowane. Zmiana zestawu względem zapamiętanego → §3 „wymuszone pełne” gdy zmieniło się `updatedSince` lub
`horseStatusInjured`; odstęp pracy w tle przestawiany, gdy zmieniło się `dataStamp`.

## 2. Nagłówek cech klienta

`X-Client-Features: horse-status-injured` w **każdym** żądaniu do programu (ekrany, kolejka, synchronizacja, tło, sondowanie), gdy zapamiętane
możliwości zawierają `horseStatusInjured`. Pierwsze żądanie parowania (`system/info`) idzie bez nagłówka; kolejne żądania parowania — z nagłówkiem,
jeśli program go ogłosił.

## 3. Odświeżenie (pierwszy plan i tło)

```text
1. wyślij kolejkę (bez zmian)
2. GET /system/info → możliwości; jeśli dataStamp == sync.dataStamp i kolejka pusta i nie (tło i ≥ 24 h od sync.lastFullAt)
      → UpToDate (dane aktualne, bez /export)
3. plan:
   Full        gdy: brak updatedSince | brak sync.nextUpdatedSince | sync.forceFull | (tło i ≥ 24 h od sync.lastFullAt)
   Incremental w pozostałych przypadkach
4. Full:        GET /export?scope=full                         → begin / mergeBatch… / finish (nieobecność = usunięcie)
   Incremental: GET /export?scope=full&updatedSince=<nextUpdatedSince>
                  scope.fullRequired = true  → jak Full (begin / mergeBatch… / finish)
                  inaczej                    → mergeBatch… dla data; applyRemovals(trashed ∪ purged); BEZ finish
5. zapis w transakcji z ostatnią paczką: sync.nextUpdatedSince = scope.nextUpdatedSince, sync.dataStamp = stempel z kroku 2,
   (Full) sync.lastFullAt = teraz, sync.forceFull = usunięte
```

`applyRemovals` — dla każdego `{type, id}` z `trashed`/`purged` ta sama tabela co dla rekordu nieobecnego w pełnym eksporcie
(`SyncMerger.finish`): `Synced`/`Local` → usuń (z plikami); niewysłany bez operacji → usuń; niewysłany z wersją bazową → konflikt
`EditDelete`; nowy lokalny → bez zmian. Typy z `export-schema-1.5` (`Horse`, `VetVisit`, …, `DictionaryItem`, `Attachment`) mapowane na
`RecordType`; nieznany typ → pominięty z wpisem w dzienniku.

Błędy: `400` przy `updatedSince` (np. punkt nieczytelny po zmianie programu) → kasowanie `sync.nextUpdatedSince` i jedno pełne pobranie
w tym samym odświeżeniu. Przerwanie strumienia → nic z kroku 5 nie jest zapisane.

Reguła „tylko przez Wi‑Fi” dla odświeżania w tle — bez zmian (cała praca w tle przez `BulkGateway`).

## 4. Usuwanie i przywracanie z `If-Match`

| Żądanie | Z `ifMatchDelete` | Wynik → kolejka |
|---|---|---|
| `DELETE /<zasób>/{id}` | `If-Match: "<baseVersion>"`, bez odczytu kontrolnego | `204` → wysłano; `409` + rekord → konflikt usunięcie–zmiana (`deleteEdit`); `400` → wymaga poprawy; `404` → jak 2.0.0 |
| `POST /trash/{type}/{id}/restore` | `If-Match: "<wersja korzenia partii>"` (`rootVersion` z `/trash`) | `200` → wysłano; `409` + `ApiTrashItem` → konflikt; `400`/`404` → jak wyżej |

## 5. Tworzenie z `Idempotency-Key`

Dotyczy wszystkich operacji tworzących (wpisy, kontakty, konie, starty, załączniki, akcje terminów, przywrócenie). Klucz = `op.id`.

| Odpowiedź | Kolejka |
|---|---|
| `2xx` (także `Idempotent-Replayed: true`) | wysłano; `Location`/treść jak przy pierwszym zapisie |
| `409` `…/idempotency-key-in-progress` | ponowienie wg odstępów (jak brak odpowiedzi), bez komunikatu |
| `422` `…/idempotency-key-reused` | „Wymaga poprawy” z komunikatem programu |
| wynik nieznany (zerwanie po wysłaniu treści) | ponowienie z tym samym kluczem — **chyba że** `preCount ≠ null` (próba bez klucza) → `MatchQueries` |
| `429` | jak dziś (wstrzymanie do `Retry-After`) |

## 6. Zdjęcie konia

- Z `horsePhotoField`: `UpdateHorse` z `photoAttachmentId` (id obrazu tego konia albo `null`), zależna od `CreateAttachment` zdjęcia.
  `400 HorsePhotoInvalid` → wymaga poprawy; `404` → wymaga poprawy („zdjęcie usunięte w programie”).
- Przejście (raz, `photos.migrated`): wpis mapy `horse.photos` × zdjęcie w programie:

| Mapa w telefonie | Program | Akcja |
|---|---|---|
| zdjęcie X | brak | `UpdateHorse(photo = X)` |
| zdjęcie X | X | usuń wpis mapy |
| zdjęcie X | Y | konflikt (obie miniatury) — „Zachowaj moje” → `UpdateHorse(X)`; „Przyjmij z programu” → usuń wpis |
| „usunięte” | brak | usuń wpis mapy |
| „usunięte” | Y | konflikt — „Zachowaj moje” → `UpdateHorse(null)`; „Przyjmij” → usuń wpis |

## 7. Testy kontraktu (`:core`, `FakeProgramServer`)

`FakeProgramServer` dostaje tryb „program 2.0.0”: `capabilities`, `dataStamp`, `updatedSince` (z `trashed`/`purged`/`fullRequired`),
`If-Match` na `DELETE`/przywracaniu, `Idempotency-Key` (pamięć odpowiedzi, `409`/`422`), `photoAttachmentId`, maskowanie `Injured` bez nagłówka.
Każdy wiersz tabel §3–§6 = co najmniej jeden test; dodatkowo regresja „program 1.6.1” (brak pola `capabilities`) dla wszystkich ścieżek.
