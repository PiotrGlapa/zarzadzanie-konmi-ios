# Kontrakt: operacje kolejki wysyłki

**Wymagania**: FR-M-SYN-04…13, FR-M-POL-08, FR-M-WPI-05 | **Model**: [data-model.md §4](../data-model.md#4-kolejka-wysyłki)
| **API**: [openapi.yaml](openapi.yaml)

Każda nowa operacja (także zapis z połączeniem — FR-M-SYN-11) jest zapisywana w kolejce i wysyłana przez `OutboxProcessor`.
Dla każdego rodzaju kontrakt określa: żądanie, zależności, **zapytanie dopasowania** do licznika przed i po (FR-M-SYN-06)
i obsługę odpowiedzi. Wszystkie żądania mają nagłówki `X-Api-Key`, `Accept: application/json` i `Idempotency-Key: <operation.id>`
(program 1.6.1 ignoruje ten nagłówek).

## Rodzaje operacji

| `OperationKind` | Żądanie | Zależności (`local:` w treści) |
|---|---|---|
| `CreateVetVisit` | `POST /vet-visits` (`VetVisitInput`, leki w treści) | `contactId` |
| `CreateFarrierVisit` | `POST /farrier-visits` — dla „Kilka koni” jedna operacja na konia (FR-M-WPI-05) | `contactId` |
| `CreatePhysioVisit` | `POST /physio-visits` | `contactId` |
| `CreateSpecialistVisit` | `POST /specialist-visits` | `contactId` |
| `CreateCompetition` | `POST /competitions` | `organizerContactId` |
| `CreateCompetitionStart` | `POST /competitions/{competitionId}/starts` | `competitionId`, `riderContactId` |
| `CreatePurchase` | `POST /purchases` | `supplierContactId` |
| `CreateNote` | `POST /notes` | — |
| `CreateTraining` | `POST /trainings` | `riderContactId`, `coaching.trainerContactId` |
| `CreateReminder` | `POST /reminders` | — |
| `CreateContact` | `POST /contacts` | — |
| `CreateAttachment` | `POST /attachments` (`multipart/form-data`: `ownerType`, `ownerId`, `description`, `file`) | `ownerId` (wpis, zawody, start, kontakt, koń) |
| `CompleteReminder` | `POST /reminders/{id}/complete` | `id` (termin z kolejki) |
| `DismissReminder` | `POST /reminders/{id}/dismiss` | `id` |

Poza kolejką (wymagają połączenia, błąd od razu w formularzu): `PUT`/`DELETE` dowolnego zasobu, `PUT /reminders/{id}`
(„Przełóż”), `POST /horses` (dodanie konia), `DELETE /attachments/{id}`.

Zamiana `local:`: przed wysłaniem procesor podstawia `resultId` operacji poprzedzającej; jeśli poprzednik nie jest `Sent`,
operacja czeka.

## Zapytania dopasowania (licznik przed i po)

`preCount` = liczba rekordów spełniających **filtr API** i **predykat lokalny**, zliczona tuż przed wysłaniem. Po wyniku
nieznanym zapytanie jest powtarzane: `count > preCount` → `Sent` (`resultId` = najnowszy pasujący rekord wg `createdAt`),
w przeciwnym razie → `Pending` i ponowne wysłanie.

Porównania tekstu: dokładne po przycięciu białych znaków na końcach; kwoty jako `BigDecimal.compareTo`; brak wartości = `null`.

| Rodzaj | Filtr API (stronicowanie `pageSize=200` aż do końca) | Predykat lokalny |
|---|---|---|
| Wizyta weterynaryjna | `GET /vet-visits?horseId=&from=d&to=d` (d = data z `visitDateTime`) | `visitDateTime`, `visitTypeId`, `contactId`, `reason`, `diagnosis`, `cost` |
| Wizyta kowala | `GET /farrier-visits?horseId=&from=d&to=d` | `visitDate`, `serviceId`, `contactId`, `hoofNotes`, `cost` |
| Fizjoterapia | `GET /physio-visits?horseId=&from=d&to=d` | `visitDate`, `contactId`, `reason`, `observations`, `cost` |
| Specjalista | `GET /specialist-visits?horseId=&specialistTypeId=&from=d&to=d` | `visitDate`, `contactId`, `reason`, `description`, `cost` |
| Zawody | `GET /competitions?from=d&to=d&q=<name>` | `name`, `dateFrom`, `city` |
| Start | `GET /competitions/{id}/starts` | `horseId`, `startDate`, `className`, `riderContactId`, `placement`, `entryFee` |
| Zakup | `GET /purchases?from=d&to=d&q=<productName>` | `purchaseDate`, `productName`, `categoryId`, `totalAmount`, `deliveryCost`, `assignment`, zbiór `horseIds` |
| Notatka | `GET /notes?horseId=` (bez filtra dat — cała lista konia) | `noteDate`, `title`, `content` |
| Trening | `GET /trainings?horseId=&from=d&to=d&typeId=` | `trainingDate`, `trainingTypeId`, `durationMinutes`, `rating`, `description`, `riderContactId` |
| Termin | `GET /reminders?horseId=&kind=&dueFrom=d&dueTo=d&status=Open` | `dueDate`, `title`, `notes` |
| Kontakt | `GET /contacts?q=<name>&includeArchived=true` | `name`, `phone` |
| Załącznik | `GET /attachments?ownerType=&ownerId=` | `sha256` (pomocniczo `fileName`, `sizeBytes`) |
| Zrealizuj / Odrzuć termin | `GET /reminders/{id}` | wysłane = `status ∈ {Completed, Dismissed}` |

## Obsługa odpowiedzi

| Odpowiedź | Operacja tworząca | `CompleteReminder` / `DismissReminder` |
|---|---|---|
| `2xx` | `Sent`, `resultId` z treści/`Location`; odświeżenie danych | `Sent` |
| `400` | `NeedsFix` z `errors` (przy zapisie z połączeniem w ciągu 1 s — powrót do formularza) | `NeedsFix` |
| `404` | `NeedsFix` („Koń / rekord usunięty w międzyczasie”) | `AlreadyHandled` (termin usunięty) |
| `409` | `NeedsFix` z `reason` (`Unique` → komunikat przy polu) | `AlreadyHandled`, gdy termin już `Completed`/`Dismissed`; inaczej `NeedsFix` |
| `413`, `415` | `NeedsFix` (plik za duży / niedozwolony typ) | — |
| `401`, `403` | operacja zostaje `Pending`; adres wstrzymany (research R8) — **bez** ponowień | jw. |
| `429` | `Pending`, `nextAttemptAt = now + Retry-After`; adres wstrzymany | jw. |
| błąd sieci przed wysłaniem treści | `Pending`, ponowienie z rosnącym odstępem | jw. |
| zerwanie po wysłaniu / timeout odczytu | `Unknown` → licznik przed i po | `Unknown` → sprawdzenie statusu terminu |

Za „wysłanie treści” uznaje się zakończenie zapisu treści żądania (OkHttp `EventListener.requestBodyEnd` /
`requestHeadersEnd` dla żądań bez treści).

## Rozpoznanie stajni po ponownym parowaniu (FR-M-POL-08)

1. Zbiór `horseRefs` wszystkich operacji w stanach `Pending`, `NeedsFix`, `Unknown`.
2. `GET /horses?status=all` (wszystkie strony).
3. Zgodność: każdy `HorseRef` istnieje z tym samym `id`, `name` i `passportNumber` (źrebak bez paszportu: `null` = `null`).
   Pusty zbiór → zgodny co najmniej jeden koń z tabeli `horse` pamięci podręcznej.
4. Zgodne → kolejka rusza. Niezgodne → wszystkie te operacje `Held`; ekran: „Ten komputer nie wygląda na tę samą stajnię
   (<n> koni z kolejki nie znaleziono). Wyślij mimo to / Usuń kolejkę”.

## Testy wymagane (zasada VI)

- Dla każdego rodzaju: pozytywny `2xx`, `400` z mapowaniem pól, zerwanie po wysłaniu z `count` wzrósł / bez zmian,
  dwa identyczne wpisy w kolejce (oba wysłane, brak duplikatu trzeciego).
- Zależności: kontakt → trening → (brak załącznika — treningi bez plików); zawody → start; notatka → 2 załączniki;
  poprzednik `NeedsFix` blokuje zależne, niezależne idą dalej.
- `401` w trakcie kolejki 20 operacji → dokładnie 1 żądanie z odmową na adres (SC-M-08).
- Restart w stanie `Sending` → `Unknown` → licznik.
- Rozpoznanie stajni: zgodna, niezgodna, kolejka bez koni.
