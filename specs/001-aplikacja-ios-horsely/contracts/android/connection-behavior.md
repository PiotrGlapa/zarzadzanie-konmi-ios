# Kontrakt: zachowanie połączenia (US1, FR-POL2-01…10)

Uzupełnia [pairing-and-connection.md](../../001-aplikacja-mobilna/contracts/pairing-and-connection.md) z wersji 1.0;
odmowy programu (401, 403, 429, certyfikat) — bez zmian. Model stanu: [data-model.md §1](../data-model.md).

## 1. Ponawianie żądań (bramka `AddressGateway`)

| Żądanie | Błąd sieci (timeout, reset, koniec strumienia, odmowa połączenia) | Wynik |
|---|---|---|
| GET (odczyt) | 1× ponowienie na tym samym adresie (nowe połączenie), potem kolejne adresy w kolejności z FR-M-POL-07 | sukces z dowolnej próby = sukces; po wszystkich próbach — `NetworkError(idempotent = true)` |
| POST / PUT / DELETE, treść **nie** wysłana | kolejny adres (jak w 1.0) | jak w 1.0 |
| POST / PUT / DELETE, treść wysłana | bez ponowienia; wynik nieznany → kolejka (FR-M-SYN-06) | jak w 1.0 |
| Odpowiedź programu z dowolnym kodem HTTP | bez ponowienia | wynik przekazany dalej; dla stanu połączenia = „komputer odpowiada” |

Limity: połączenie 3 s/adres; odpowiedź (odczyt) 30 s; zapis treści (pliki) — przerwanie po 60 s bez postępu.
Czas oczekiwania w ograniczniku tempa (80 żądań / 10 s) nie wlicza się do limitów.

## 2. Stan połączenia — kiedy się zmienia

| Zdarzenie | Stan po zdarzeniu |
|---|---|
| Dowolne żądanie zakończone odpowiedzią programu (2xx–5xx), z dowolnego ekranu, odświeżania w tle, kolejki | brak problemu „offline” (pasek znika na wszystkich ekranach w ≤ 1 s) |
| `NetworkError` / `NoUsableAddress` po ponowieniu i wszystkich adresach | `Offline(dataFrom)` |
| Telefon traci ostatnią sieć | `NoNetwork` (żądania nie są wysyłane) |
| Telefon odzyskuje sieć | natychmiastowe sprawdzenie (§3) |
| Powrót aplikacji na pierwszy plan w stanie `Offline` | natychmiastowe sprawdzenie (§3) |
| Co 30 s, gdy aplikacja jest na pierwszym planie i stan = `Offline` | sprawdzenie (§3) |
| Odmowy 401/403/certyfikat/blokada 429 | jak w 1.0 — mają pierwszeństwo przed `Offline` i `NoNetwork` |

Zmiana zakładki ani ekranu **nie** zmienia stanu i nie wywołuje komunikatu (FR-POL2-09).

## 3. Sprawdzenie połączenia („Odśwież” i samoczynne)

1. Jeśli sprawdzanie już trwa — dołącz do niego (jedno naraz; FR-POL2-08).
2. `checking = true` → pasek pokazuje „Sprawdzam połączenie…” ze wskaźnikiem; przycisk nieaktywny.
3. Zwolnij wstrzymania czasowe adresów (nie dotyczy odrzuconego klucza ani zmienionego certyfikatu).
4. `GET /system/info` po kolei na adresach (zasady §1).
5. Sukces → stan online; pełne odświeżenie pamięci (zawsze, bez progu 5 min); bieżący ekran przeładowuje dane.
6. Porażka → stan `Offline`; dla „Odśwież” (wywołanego przez użytkownika) pasek pokazuje „Komputer nadal nie odpowiada
   (sprawdzono HH:mm)” i wskazówki (FR-POL2-04).

„Pociągnij, aby odświeżyć” w trakcie trwającego odświeżania czeka na jego zakończenie (nie jest pomijane).

## 4. Komunikaty (teksty w `strings.xml`)

| Stan | Tekst paska | Przycisk |
|---|---|---|
| `NoNetwork` | „Telefon nie ma połączenia z siecią. Dane z {data}.” | — (wznowienie samoczynne; ikonka — §4a) |
| `Offline` | „Komputer nie odpowiada — dane z {data}.” + dotychczasowe wskazówki (`connection_offline_hints`) | „Odśwież” |
| `Offline` + sprawdzanie | „Sprawdzam połączenie…” | nieaktywny |
| `Offline` po nieudanym „Odśwież” | „Komputer nadal nie odpowiada (sprawdzono {HH:mm}).” | „Odśwież” |
| Wolna odpowiedź (< 30 s) | — (wskaźnik ładowania na ekranie, bez paska) | — |

Komunikat globalny jest jedynym miejscem informacji o braku połączenia. Datę danych pokazuje podtytuł paska tytułu
(§4a), a nie pasek nad treścią.

## 4a. Zwijanie komunikatu i ikonka w pasku tytułu (FR-POL2-11…14)

Komunikat (§4) jest **nakładką** u góry obszaru treści (pod paskiem tytułu, nad treścią; nie zmienia układu ekranu),
z animacją rozwinięcia/zwinięcia. Stan widoku (`ConnectionIndicatorState`):

| Stan | Co widać | Przejścia |
|---|---|---|
| `Hidden` | nic | pojawienie się problemu → `Expanded(auto)` |
| `Expanded(auto)` | nakładka z komunikatem i przyciskiem; ikonka w pasku tytułu | po `AUTO_COLLAPSE = 3 s` (lub czasie zalecanym przez `LocalAccessibilityManager.calculateRecommendedTimeoutMillis(3000, containsIcons = true, containsText = true, containsControls = true)`) → `Collapsed`; dotknięcie nakładki poza przyciskiem → `Collapsed`; problem ustąpił → `Hidden` |
| `Collapsed` | tylko ikonka w pasku tytułu | zmiana rodzaju problemu → `Expanded(auto)`; dotknięcie ikonki — patrz niżej; problem ustąpił → `Hidden` |
| `Expanded(pinned)` | nakładka z przyciskiem działania i ✕ | ✕ lub dotknięcie poza przyciskiem → `Collapsed`; problem ustąpił → `Hidden` (bez auto-zwijania) |

Dotknięcie ikonki:

- **pomarańczowa** (`Offline`, `NoNetwork`) → `ConnectionRecovery.checkNow()` + `Expanded(auto)` z „Sprawdzam
  połączenie…”; odliczanie 3 s startuje dopiero po wyniku (sukces → `Hidden`; porażka → „Komputer nadal nie odpowiada
  (sprawdzono HH:mm)” → po 3 s `Collapsed`). Dla `NoNetwork` sprawdzenie nie wysyła żądań — pokazuje „Telefon nie ma
  połączenia z siecią” i zwija.
- **czerwona** (`KeyRejected`, `CertificateChanged`, `KeyHomeOnly`, `RemoteAccessDisabled`, `AddressBlocked`) →
  `Expanded(pinned)` z przyciskiem „Połącz ponownie” (wymaga ponownego parowania) albo „Sprawdź połączenie”.

Ikonka: `Icons.Outlined.CloudOff` (pomarańczowa — `extraColors.warning`) lub `Icons.Outlined.ErrorOutline` (czerwona —
`colorScheme.error`), w `IconButton` (cel ≥ 48 dp) jako **ostatnia** akcja paska tytułu; `contentDescription` = treść
problemu + „Dotknij, aby odświeżyć” / „Dotknij, aby zobaczyć szczegóły”; podczas sprawdzania zamiast ikonki mały
wskaźnik postępu. Ikonka jest na każdym ekranie z paskiem tytułu po sparowaniu (nie na ekranach parowania ani w
`ShareTargetActivity`). Rozwinięcie komunikatu jest ogłaszane przez czytnik ekranu (`liveRegion = Polite`); zwinięcie — nie.

**Data danych (FR-POL2-15, konstytucja IV)**: gdy stan nie jest `Hidden` albo ostatnie odświeżenie było niepełne, pasek
tytułu ekranu z danymi pokazuje pod tytułem podtytuł „Dane z {dd.MM HH:mm}” (`bodySmall`, `onSurfaceVariant`) — z
`dataFrom` monitora lub `fetchedAt` ekranu. Zastępuje to pasek `StaleDataBanner` nad treścią (komponent usunięty z
ekranów). Podtytuł jest częścią etykiety tytułu dla czytnika ekranu.

Samoczynne rozwinięcie (`Expanded(auto)`) **tylko** przy przejściu `brak problemu → problem` albo zmianie wariantu
`ConnectionProblem` (porównanie klasy, nie danych — zmiana `dataFrom` nie rozwija). Zmiana ekranu, pętla co 30 s
i ponowne zgłoszenie tego samego problemu nie rozwijają komunikatu.

## 5. Testy kontraktu (zaślepka programu, `:core` i Robolectric)

- Zerwanie połączenia po nagłówkach GET (zaślepka zrywa połączenie po odebraniu 1. żądania — efekt gniazda `mockwebserver3`) → 1 ponowienie,
  sukces, stan online, pełne odświeżenie `complete = true`.
- To samo dla POST z wysłaną treścią → bez ponowienia, `NetworkError(sentBody = true)`, operacja w kolejce `Unknown`.
- Adres lokalny nie odpowiada (timeout połączenia), publiczny tak → sukces bez paska.
- Stan `Offline` + sukces dowolnego odczytu z ekranu (np. lista treningów) → pasek znika.
- „Odśwież” 3× szybko → jedno `GET /system/info` na adres.
- Offline, zegar wirtualny +30 s na pierwszym planie → sprawdzenie; w tle → brak żądań.
- Odpowiedź po 25 s → brak `Offline`; po 31 s (×2 próby) → `Offline`.
- Wskaźnik (czas wirtualny Compose): pojawienie się `Offline` → nakładka; +3 s → tylko ikonka; zmiana ekranu → ikonka bez
  rozwinięcia; `Offline` → `NoNetwork` → rozwinięcie; dotknięcie pomarańczowej ikonki → „Sprawdzam…” → porażka → +3 s
  zwinięte; dotknięcie czerwonej → rozwinięte bez auto-zwijania do ✕; problem ustąpił → nic nie widać.
