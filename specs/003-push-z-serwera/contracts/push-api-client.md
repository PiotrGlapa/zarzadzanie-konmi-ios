# Kontrakt: API push po stronie iPhone'a (klient)

Źródło prawdy: `../zarzadzanie_konmi_java/specs/008-push-mobilny/contracts/api-push.md` §1 i „Capabilities” (wdrożone 2026-11-05).
Ten plik opisuje, **jak aplikacja iOS z niego korzysta**. Odpowiednik Androida: `specs/006-push-z-serwera/contracts/push-api-client.md`.
Ścieżki pod `/api/v1`, nagłówek `X-Api-Key`, ten sam `ApiClient` co reszta API (przypinanie certyfikatu, klucz z Keychain,
ogranicznik, `401/403/429`, dziennik połączeń — konstytucja III).

## Wykrywanie

`GET /system/info` → `capabilities` zawiera `push` → `ProgramCapabilities.push == true`. `pushAdmin` i inne nieznane nazwy —
pomijane. Brak `push` (program 1.x, push wyłączony w konfiguracji lub przez właściciela, brak konta usługi Firebase) → żadnego
wywołania poniżej i żadnego wywołania Firebase.

## Wywołania

| Kiedy | Żądanie (`ApiRequest`) | Obsługa wyniku |
|---|---|---|
| rejestracja (research R7) | `PUT push/device`, ciało `{"platform":"Ios","token":"…"}`, `forFile: false`, `retryOnDrop: 2` | `200 PushDevice` → `registered = true`, `registeredAt`, `tokenPrefix`, `failingSince = nil`, `permanentFailure = false`, przeliczenie powiadomień; `400` → `permanentFailure = true` (dziennik: nazwy pól z `errors`, bez tokenu); sieć / 5xx / brak tokenu → `failingSince` (gdy puste), ponowienie (30 s → 15 min w aplikacji, wejście na pierwszy plan, `BGAppRefreshTask`), po 24 h `permanentFailure = true`; `401/403/429` → istniejąca obsługa `ApiClient`, bez komunikatu push |
| wyrejestrowanie (R9) | `DELETE push/device`, `forFile: false`, `retryOnDrop: 2`, limit 5 s | `204` / `401` / sieć / 5xx — **wszystko ignorowane**; nigdy nie blokuje odparowania ani zmiany trybu |
| ekran „Powiadomienia” (otwarcie, „Odśwież”) | `GET push/device` | `200` → daty na ekranie; `404` → `registered = false`, `deviceRemovedNotice = true`, natychmiastowa rejestracja (FR-025); inny błąd → bez dat, stan push bez zmian |
| ekran „Powiadomienia” (otwarcie, „Odśwież”) | `GET push/rules` | `200 ClientPushRule[]` → lista `description`; pusta → ostrzeżenie (FR-024); błąd → „Nie udało się pobrać listy — spróbuj później.” bez zmiany stanu push (FR-026a) |

- `PUT` bez `Idempotency-Key`. `GET` tylko na żądanie ekranu (nie w tle).
- **Wszystkie** żądania push mają `forFile: false` — `ApiClient.execute` nie pomija wtedy adresu zewnętrznego na danych komórkowych
  przy „tylko przez Wi‑Fi” (błąd znaleziony na Androidzie 2026-11-05: `NoUsableAddress` i wieczne „Rejestruję…”).
- `retryOnDrop: 2` — przy `.network(sentBody: true)` do dwóch natychmiastowych ponowień na tym samym adresie, potem przejście na
  kolejny adres (żądanie idempotentne). Odczyty `GET` — jak dziś (jedno ponowienie).
- Token pojawia się **wyłącznie** w ciele `PUT`; `ConnectionLog.request` zapisuje tylko metodę, ścieżkę bez zapytania, adres i wynik.

## Modele (`HorselyCore`, `Codable`, dekodowanie tolerancyjne)

Ścieżki, metody i `DeviceRegistration` — z kopii OpenAPI serwera [openapi-server-push.json](openapi-server-push.json)
(`GET /openapi/v1.json`, kopia z repozytorium UI). Odpowiedzi `200` są tam opisane tylko jako `type: object`, a `400`/`404` nie są
wymienione, więc kształt pól odpowiedzi i kody błędów pochodzą z `api-push.md` §1 (odstępstwo w „Complexity Tracking” planu).
Kształt pól: [data-model.md](../data-model.md) §3–§5. Przykłady do testów dekodowania (przepisane z `api-push.md`), w
`Packages/HorselyCore/Tests/HorselyCoreTests/Resources/push/`:

```json
{ "platform": "Ios", "tokenPrefix": "dGhpcyBp", "registeredAt": "2026-11-04T10:15:00.0000000Z",
  "lastSeenAt": "2026-11-04T10:15:00.0000000Z", "lastDeliveredAt": null }
```

```json
[{ "id": "r1", "type": "Reminder", "reminderKind": "Farrier", "offsetDays": 1, "sendTime": "08:00", "repeatTime": "07:00",
   "description": "Kowal: dzień przed o 08:00, powtórka o 07:00", "futureField": true },
 { "id": "r2", "type": "SomethingNew", "description": "Nowy rodzaj" }]
```

```json
{ "type": "https://horsely/problems/validation", "title": "Błąd walidacji", "status": 400, "errors": { "token": ["…"] } }
```

## Zaślepka testowa

- `Packages/HorselyKit/Tests/HorselyKitTests/FakeProgram.swift`: gałęzie `push/device` (`PUT`/`DELETE`/`GET`) i `push/rules`;
  przełącznik `pushCapability` dopisujący `push` (i `pushAdmin`) do `capabilities`; stan: zarejestrowany token (pełny — do asercji,
  że trafił tylko do ciała), lista reguł; wymuszenie `400` / `404` / `5xx` / zerwania połączenia N razy.
- `App/Shell/DemoProgram.swift` (`DemoProgramTransport`, testy UI): scenariusz `push` z dwiema regułami i scenariusz `pushNoRules`.
- Test zgodności (konstytucja V/VI): każda ścieżka i metoda push obsłużona przez zaślepkę i używana przez `PushApi` istnieje
  w `openapi-server-push.json` (kopia w zasobach testów `HorselyKit`), a ciało `PUT` zawiera wyłącznie pola `DeviceRegistration`.
  Gdy serwer otypuje odpowiedzi, kopię odświeża się z **lokalnego** serwera (`GET /openapi/v1.json`), a test obejmuje schematy.
