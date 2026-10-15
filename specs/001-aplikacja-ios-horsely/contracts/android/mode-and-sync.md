# Kontrakt: tryb pracy, pełne pobranie i synchronizacja zmian

Wymagania: FR-TRB-01…09, FR-SYN2-01…09. Decyzje: research R4–R7, R9, R10, R18, R19.

## 1. Tryb pracy

```text
            pierwsze uruchomienie
                    │
                 [Unset] ──"Nie, używaj samodzielnie"──▶ [Standalone]
                    │                                     │   ▲
   "Tak, połącz" + udane parowanie                        │   │ online→samodzielny (§5)
                    ▼                                     │   │
                 [Online] ◀──samodzielny→online (§4)──────┘   │
                    └─────────────────────────────────────────┘
Aktualizacja 1.x z parowaniem: Unset → Online bez pytania (FR-TRB-04).
```

Niezmienniki:

- `workMode` zmienia się wyłącznie w transakcji razem ze zmianą danych, której dotyczy (§4, §5).
- `Standalone`: brak klienta HTTP, workerów kolejki i odświeżania; „Więcej” bez Kolejki i Konfliktów (FR-TRB-08).
- Przerwane parowanie w `Unset` → powrót do wyboru trybu (FR-TRB-03).

## 2. Pełne pobranie (tryb online)

| Krok | Żądanie | Uwagi |
|---|---|---|
| 1 | `GET /system/info` | wersja ≥ 1.5.0 (jak 1.x) |
| 2 | `GET /export?scope=full` | strumieniowo; partie po 500 rekordów; postęp; brak `version` w rekordach → tryb zgodności 1.x (FR-SYN2-09) |
| 3 | `GET /trash` | partie usunięte w programie (do konfliktów §3) |
| 4 | `GET /attachments/{id}/thumbnail` dla `Horse.photoAttachmentId` bez lokalnej miniatury | ogranicznik tempa 1.x |
| 5 | (opcja „Pobieraj wszystkie załączniki”) `GET /attachments/{id}/content` | tylko Wi‑Fi wg ustawień 1.x |

Uzgadnianie (`SyncMerger`, `:core`) — dla każdego rekordu z eksportu `R` i lokalnego `L`:

| `L` | Warunek | Wynik |
|---|---|---|
| brak | — | wstaw `R` jako `Synced` |
| `Synced` | — | zastąp `R` |
| `Pending`/`Conflict` | `R.version == L.baseVersion` | bez zmian (moja zmiana czeka) |
| `Pending` | `R.version > L.baseVersion` | bez zmian; znacznik `remoteChanged` (konflikt rozstrzygnie wysyłka) |
| `Synced` | brak w eksporcie | usuń lokalnie (z plikami) |
| `Pending` (Update) | brak w eksporcie | konflikt `EditDelete` |
| `Pending` (Create) | — | bez zmian |
| `Projected` | — | usuń wszystkie przed uzgadnianiem |

Częstotliwość: start i powrót na pierwszy plan, gdy `lastFullSyncAt` > 15 min; ręcznie zawsze; w tle co ≥ 1 h.

## 3. Wysyłka zmian

Kolejność, zależności, ponawianie, „licznik przed i po” dla `Create*` — bez zmian względem 1.x
(`specs/001-aplikacja-mobilna/contracts/outbox-operations.md`). Nowe operacje:

| Operacja | Żądanie | Wynik → stan |
|---|---|---|
| `Update<T>` | `PUT /<zasób>/{id}`, `If-Match: "<baseVersion>"` | `200` → `Sent`, rekord `Synced` z odpowiedzią; `409` → `Conflict(EditEdit)` z rekordem z odpowiedzi; `404` → `GET /trash`: jest partia → `Conflict(EditDelete)` z `trashBatchId`; brak → `Conflict(EditDelete)` bez partii; `400` → `NeedsFix` |
| `Delete<T>` | najpierw `GET /<zasób>/{id}` | `404` → `AlreadyHandled`; `version > baseVersion` → `Conflict(DeleteEdit)`; inaczej `DELETE` → `204` → `Sent`; `409 InUse` → `NeedsFix` |
| `CreateHorse` | `POST /horses` | jak inne `Create*` (klucz dopasowania: imię + numer paszportu) |
| `UpdateHorse` | `PUT /horses/{id}` | jak `Update<T>`; zawiera `photoAttachmentId`, `finance` tylko gdy zmienione |
| `RescheduleReminder` | `PUT /reminders/{id}` | jak `Update<T>` |

Łączenie operacji przed wysyłką — tabela w research R5.

## 4. Samodzielny → online

1. Ostrzeżenie (liczba koni, wpisów, data ostatniej kopii, „Utwórz kopię zapasową”) → „Usuń dane i połącz”.
2. Kreator parowania (QR / ręcznie) w trybie `switching`.
3. Udane `GET /system/info` z kluczem → **jedna transakcja**: usuń `local_record`, `record_horse`, `local_file`
   (pliki usuwane po zatwierdzeniu), zapisz parowanie, `workMode = Online`.
4. Pełne pobranie (§2).

Anulowanie lub błąd w krokach 1–3 → dane i `Standalone` bez zmian (SC-2-08).

## 5. Online → samodzielny

1. Informacja: dane programu zostaną jako punkt startowy; liczba niewysłanych zmian i nierozstrzygniętych konfliktów.
2. Pełne pobranie (§2) + oryginały wszystkich załączników (praca pierwszoplanowa z postępem). Bez połączenia: lista
   braków (np. „brak 37 oryginałów załączników”) i osobne potwierdzenie.
3. **Jedna transakcja**: `Synced`/`Pending` → `Local`; `Conflict` → `Local` (moja wersja); `Projected` usunięte;
   kolejka i konflikty wyczyszczone; parowanie, adresy i klucz usunięte; `workMode = Standalone`.

## 6. Konflikty (FR-SYN2-06/07)

| Rodzaj | „Zachowaj moją” | „Przyjmij z programu” |
|---|---|---|
| `EditEdit` | `PUT` moja treść z `If-Match: theirsVersion` | lokalnie `theirs` jako `Synced` |
| `EditDelete` (w koszu) | `POST /trash/{type}/{batchId}/restore` (potwierdzenie, gdy partia > 1 rekord), potem `PUT` | lokalnie usuń rekord |
| `EditDelete` (poza koszem) | `POST` moja treść jako nowy rekord (nowe `id`), zależne operacje przepięte | lokalnie usuń rekord |
| `DeleteEdit` | `DELETE` | lokalnie `theirs` jako `Synced` |

Akcje zbiorcze: ten sam wybór dla wszystkich nierozstrzygniętych, po potwierdzeniu z ich liczbą. Operacje zależne od
rekordu w konflikcie czekają; po „Przyjmij z programu” dla usuniętego rekordu → `NeedsFix` z wyjaśnieniem.

## 7. Testy (FakeProgramServer)

- pełne pobranie 50 koni / 50 000 rekordów (czas, partie, przerwanie i ponowienie);
- każdy wiersz tabel §2, §3, §6;
- łączenie operacji (R5);
- przejścia §4 i §5 z przerwaniem w każdym kroku (SC-2-08);
- tryb zgodności: eksport bez `version` → edycja offline zablokowana (FR-SYN2-09);
- scenariusz SC-2-04.
