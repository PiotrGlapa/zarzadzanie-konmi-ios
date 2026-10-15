# Kontrakt: parowanie i połączenie z programem

**Wymagania**: FR-M-POL-01…13, FR-M-UST-01, FR-M-UST-06 | **Model**: [data-model.md §2](../data-model.md#2-parowanie-i-adresy)
| **Research**: [R6–R9, R21](../research.md)

## Kod QR (wejście z programu)

Treść: JSON UTF‑8. Nieznane pola MUST być ignorowane.

```json
{ "url": "https://192.168.1.20:5080/api/v1", "key": "hk_…", "certSha256": "3F9A…C1",
  "remoteUrl": "https://stajnia.dyndns.org:48123/api/v1" }
```

| Pole | Wymagane | Walidacja w aplikacji |
|---|---|---|
| `url` | tak | `http`/`https`, ścieżka kończy się `/api/v1`; `http` tylko dla adresu lokalnego (literał prywatnego IP lub `.local`) |
| `key` | tak | prefiks `hk_`, niepusty |
| `certSha256` | nie (`null`) | 64 znaki `[0-9A-F]`; obecny → oba adresy z QR w trybie `PinnedFingerprint` |
| `remoteUrl` | nie | tylko `https`; dodawany jako drugi adres (`QrRemote`) |

Kod nieczytelny / niepoprawny JSON / brak `url` lub `key` → „To nie jest kod parowania z programu Zarządzanie końmi”.

## Przebieg parowania

1. Skan QR albo „Wpisz ręcznie” (adres, klucz, opcjonalnie odcisk; ekran z `FLAG_SECURE`).
2. Dla `http`: ostrzeżenie „Połączenie nie jest szyfrowane — bezpieczne tylko w zaufanej sieci domowej” → potwierdzenie.
3. Dla `https`: uzgodnienie TLS z zasadą zaufania (niżej); odmowa → komunikat, **klucz nie jest wysyłany**.
4. `GET /system/info` **z kluczem** → `appVersion < 1.5.0` → „Zaktualizuj program na komputerze do wersji 1.5.0 lub nowszej”.
5. `GET /dictionaries` i `GET /horses?status=all&pageSize=1` → pokazanie wersji programu i liczby koni (`totalCount`).
6. Zapis parowania; przy niepustej kolejce — rozpoznanie stajni ([outbox-operations.md](outbox-operations.md#rozpoznanie-stajni-po-ponownym-parowaniu-fr-m-pol-08)).
7. Zgoda na powiadomienia (+ optymalizacja baterii, FR-M-POW-05) → pulpit i pełne odświeżenie w tle.

## Zasady zaufania TLS (dla każdego adresu `https`)

| Sytuacja | Wynik |
|---|---|
| Certyfikat liścia ma SHA‑256 = odcisk z parowania | akceptacja (`PinnedFingerprint`), nazwa hosta nie jest sprawdzana |
| Adres z QR, odcisk znany, certyfikat inny | odmowa: „Certyfikat komputera się zmienił — zeskanuj nowy kod QR” (adres `CertificateChanged`) |
| Adres ręczny, certyfikat ważny wg systemowych urzędów certyfikacji, nazwa zgodna, brak potwierdzenia | sonda TLS bez żądania HTTP → ekran „Wystawca: <CN wystawcy>, dla: <nazwa>. Ufać temu adresowi?” → `TrustedIssuer` |
| Adres `TrustedIssuer`, certyfikat przestał być ważny / inna nazwa | odmowa z komunikatem i wskazówką sprawdzenia pośrednika |
| Samopodpisany bez znanego odcisku | odmowa |
| Certyfikaty dodane przez użytkownika w Androidzie | nie są zaufane |

## Wybór adresu i limity

- Kolejność: ostatnio działający → pozostałe wg `sortOrder`; połączenie ≤ 3 s na adres; adresy wstrzymane są pomijane.
- „Tylko przez Wi‑Fi” (FR-M-UST-03): przy sieci komórkowej adresy nielokalne nie są używane do odświeżania w tle i wysyłki
  załączników; wpisy bez załączników wysyłane zawsze.
- Ogranicznik: ≤ 80 żądań / 10 s (limit programu 100 / 10 s).

## Odpowiedzi odmowne (zero ponowień w pętli)

| Odpowiedź | Rozpoznanie | Komunikat | Stan adresu |
|---|---|---|---|
| `401` | dowolny adres | „Klucz został unieważniony — połącz aplikację ponownie” → ekran parowania (kolejka i pamięć zachowane) | `KeyRejected` |
| `403` z `type` `…/key-home-only` | adres nielokalny | „Ten klucz działa tylko w sieci domowej. Włącz dla niego dostęp spoza domu w programie (Ustawienia → API → klucz) albo połącz się przez domowe Wi‑Fi” | `KeyHomeOnly` |
| `403` bez treści | adres nielokalny | „Dostęp spoza domu jest wyłączony w programie. Włącz go na komputerze (Ustawienia → API → Dostęp spoza sieci domowej) albo połącz się przez domowe Wi‑Fi” — bez ponownego parowania | `RemoteAccessDisabled` |
| `429`, `Retry-After` ≤ 60 s | — | brak (ciche odczekanie) | `RateLimited(until)` |
| `429`, `Retry-After` > 60 s | — | „Program zablokował adres sieci, z której się łączysz, do <godzina>. Połącz się przez Wi‑Fi albo odblokuj adres w programie (Ustawienia → API → Zablokowane adresy)” | `AddressBlocked(until)` |
| brak odpowiedzi ze wszystkich adresów | — | „Brak połączenia z komputerem — dane z <data, godzina>” + wskazówki (US1/12) | bez zmian |

Zwolnienie wstrzymania: „Sprawdź połączenie” (jedno żądanie `GET /system/info` do adresu), ponowne parowanie, upływ `Retry-After`.

## Rozłączenie

„Rozłącz” → ostrzeżenie przy niepustej kolejce → usunięcie klucza, pamięci podręcznej, kolejki, plików i zaplanowanych
powiadomień → komunikat „Unieważnij klucz tego telefonu w programie (Ustawienia → API)”.

## Wersja programu (FR-M-UST-06)

`appVersion > 1.6.1` (najnowsza testowana) → jednorazowo dla tej wersji: „Program <wersja> — aplikacja testowana z 1.6.1;
sprawdź, czy jest nowa wersja aplikacji” (także w „O aplikacji”). Aplikacja działa dalej.
