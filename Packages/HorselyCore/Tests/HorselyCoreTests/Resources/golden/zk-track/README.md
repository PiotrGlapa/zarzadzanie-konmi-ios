# Format trasy `zk-track/1`

Umowa między Androidem (Kotlin), iOS (Swift) i UI webowym (JS) o tym, jak zapisane są punkty trasy nagrania jazdy.
Serwer (`zarzadzanie_konmi_java`, kontrakt `api-v3-recordings.md`, rozdz. 10) **nie interpretuje** punktów: trzyma `trackData`
bez zmian i sprawdza tylko: poprawny base64, `trackFormat` = `zk-track/1`, rozmiar ≤ 5 242 880 B **po zdekodowaniu base64**
oraz `pointCount ≥ 2`. Odczyt i zapis punktów robią wyłącznie klienci — dlatego ten dokument jest jedynym źródłem prawdy.

Kod odniesienia: `core/src/main/kotlin/pl/glapa/zk/core/ride/ZkTrack.kt`; test: `ZkTrackTest.kt`.

## Warstwy

```
trackData (pole JSON nagrania)  =  base64 (RFC 4648, alfabet standardowy, z dopełnieniem „=”)
          └─ bajty              =  gzip (RFC 1952) 
                └─ bajty        =  dokument JSON (UTF-8, bez BOM)
```

* W pamięci aplikacji (tabela `local_track`, pole `format` = `"zk-track/1"`) leżą bajty gzip, bez base64; base64 powstaje dopiero
  przy wysyłce (`trackData`) i znika przy odbiorze.
* Poziom kompresji dowolny (Android: 9). Dokładne bajty gzip **zależą od implementacji zlib** (nagłówek, bajt systemu OS) — nie
  porównuj ich bajt w bajt, porównuj dokument po rozpakowaniu. Czytnik musi akceptować każdy poprawny gzip.
* Rozmiar po zdekodowaniu base64 (to znaczy: bajty gzip) ≤ 5 242 880 B — inaczej serwer odrzuca nagranie
  („Trasa jest za duża (najwięcej 5 MB).”). Godzina jazdy w 1 Hz to ok. 25–35 KB po gzip.
* Czytnik powinien chronić się przed „bombą” gzip (Android: ≤ 64 MiB po rozpakowaniu).

## Dokument JSON

Obiekt z polami w **tej** kolejności (zapis zawsze w tej kolejności; czytnik nie może jej zakładać):

```json
{"v":1,"t0":<epoka ms>,"n":<liczba punktów>,"dt":[…],"lat":[…],"lon":[…],"alt":[…],"spd":[…],"acc":[…],"cad":[…],"int":[…],"pauses":[[…],…]}
```

Bez białych znaków poza zawartością (zapis zwarty). Wszystkie liczby to **liczby całkowite** zapisane dziesiętnie (bez kropki, bez
wykładnika, bez `+`); `null` to JSON-owe `null`. Pole `n` jest liczbą punktów; każda z ośmiu kolumn (`dt`…`int`) ma dokładnie `n`
elementów (dla `n = 0` — puste tablice). Zapisujący musi mieć `n ≥ 2` w nagraniu wysyłanym na serwer (`pointCount ≥ 2`),
sam kodek dopuszcza `n = 0`.

| Pole | Znaczenie | Jednostka zapisu | Kodowanie | `null` |
|---|---|---|---|---|
| `v` | wersja dokumentu | — | stała `1` | nie |
| `t0` | początek nagrania (`startedAt`) | ms od 1970-01-01 UTC | wartość | nie |
| `n` | liczba punktów | — | wartość | nie |
| `dt` | czas punktu | ms | **przyrost**: pierwszy punkt = `t − t0`, kolejne = `t − t poprzedniego` | nie |
| `lat` | szerokość geograficzna | 10⁻⁷ stopnia | **przyrost** wartości bezwzględnej zaokrąglonej (pierwszy = wartość od 0) | nie |
| `lon` | długość geograficzna | 10⁻⁷ stopnia | **przyrost** jak `lat` | nie |
| `alt` | wysokość | dm (0,1 m) | wartość bezwzględna | tak |
| `spd` | prędkość | cm/s (0,01 m/s) | wartość bezwzględna | tak |
| `acc` | dokładność pozioma | m (całe) | wartość bezwzględna | tak |
| `cad` | rytm (kroki/min) | 0,1/min | wartość bezwzględna | tak |
| `int` | intensywność ruchu | mm/s² | wartość bezwzględna | tak |
| `pauses` | pauzy | ms od `t0` | lista par `[start, koniec]`, wartości bezwzględne względem `t0` (nie przyrosty) | — |

Odczyt punktu *i* (od 0): `t[i] = t[i-1] + dt[i]` (z `t[-1] = t0`), `latE7[i] = latE7[i-1] + lat[i]` (z `latE7[-1] = 0`), tak samo
`lon`. Wartość fizyczna: `lat = latE7 / 10⁷`, `lon = lonE7 / 10⁷`, `wysokość m = alt / 10`, `prędkość m/s = spd / 100`,
`dokładność m = acc`, `rytm 1/min = cad / 10`, `intensywność m/s² = int / 1000`. Pauza: `start = t0 + pauses[k][0]`,
`koniec = t0 + pauses[k][1]`.

Przyrosty liczone są od wartości **już zaokrąglonych** (nie od oryginałów), więc błąd się nie kumuluje: odczytana szerokość
różni się od zapisanej o najwyżej 0,5·10⁻⁷ stopnia.

`dt`, `lat`, `lon` nigdy nie są `null`. `cad` i `int` są niepuste tylko w punkcie zamykającym okno 5 s akcelerometru (zwykle co piąty
punkt przy 1 Hz); `cad` jest `null` także wtedy, gdy rytmu nie dało się wyznaczyć. Pozostałe kolumny są puste, gdy czujnik nie
podał wartości.

## Zaokrąglanie (HALF_UP)

Wartość bezwzględną (lat, lon, alt, spd, acc, cad, int) mnoży się przez 10^k (k: lat 7, lon 7, alt 1, spd 2, acc 0, cad 1, int 3)
i zaokrągla do liczby całkowitej regułą **HALF_UP w sensie `java.math.RoundingMode.HALF_UP`: połówka idzie „od zera”**, także
dla liczb ujemnych (`2,5 → 3`, `−2,5 → −3`). To **nie** jest `Math.round` z JS ani z Javy (te zaokrąglają połówki w stronę +∞:
`−2,5 → −2`) i nie „zaokrąglanie do parzystej” (Swift `.toNearestOrEven`); w Swifcie użyj `.toNearestOrAwayFromZero`.

Mnożenie wykonuje się na **dziesiętnym zapisie liczby** (najkrótsza reprezentacja, jak `Double.toString`), nie na liczbie
binarnej — tak `1,005 m/s · 100 = 100,5 → 101` (mnożenie w `double` dałoby 100,49999… → 100). W Kotlinie:
`BigDecimal.valueOf(x).scaleByPowerOfTen(k).setScale(0, RoundingMode.HALF_UP)`; w Swifcie `Decimal(string: "\(x)")`
albo `Double.description`; w JS `Number.toString()` rozbite na mantysę i wykładnik (albo biblioteka dziesiętna). Pole `acc`
zaokrągla się do pełnych metrów (4,5 → 5); przy odczycie wraca liczba całkowita.

Wartości nieskończone i `NaN` są niedozwolone (zapis ich odrzuca). Zapisujący powinien gwarantować niemalejący czas punktów
(`dt ≥ 0`); czytnik nie sprawdza monotoniczności i przyjmuje także przyrosty ujemne.

## Czytnik

Czytnik odrzuca dokument (Android: `ZkTrackException`), gdy: bajty nie są gzipem, nie jest obiektem JSON, `v ≠ 1`, brakuje pola,
kolumna ma inną długość niż `n`, w `dt`/`lat`/`lon` jest `null`, wartość nie jest liczbą całkowitą albo pauza nie jest parą.
Nieznane dodatkowe pola w obiekcie głównym dokumentu są ignorowane (zgodność w przód w obrębie `v = 1`).

## Pliki wzorcowe

| Plik | Zawartość |
|---|---|
| `krotka.json` | źródłowy, czytelny opis: `zrodlo` (co zapisuje aplikacja), `dokument` (dokument JSON po rozpakowaniu), `odczyt` (wartości po odczycie, już na siatce formatu) |
| `krotka.b64` | `trackData` wzorca: base64 z gzipu dokumentu z `krotka.json`; wygenerowany z implementacji Androida (`ZkTrackTest`, test-generator oznaczony `@Disabled`) |

Zawartość `krotka.json` obejmuje: 6 punktów, dwie pauzy, kolumny z `null`, połówki zaokrąglane HALF_UP (dodatnie i ujemne),
ujemną długość geograficzną, nierówny odstęp czasu (1500 ms) i rytm/intensywność w jednym punkcie.

Czego oczekuje test każdej platformy:

1. `krotka.b64` → base64 → gunzip → JSON jest równy sekcji `dokument` (porównanie drzewa JSON),
2. odczyt bajtów z `krotka.b64` daje punkty i pauzy z sekcji `odczyt`,
3. zapis sekcji `zrodlo` daje po rozpakowaniu ten sam **tekst** dokumentu co `krotka.b64` po rozpakowaniu (kolejność pól
   i zwarty zapis są częścią umowy); porównuj tekst po gunzipie, nie bajty gzipu.

Pliki mają atrybut `-text` w `.gitattributes` (`core/src/test/resources/golden/** -text`) — nie zmieniaj końców linii.
`krotka.b64` to jedna linia bez końcowego znaku nowej linii (czytnik powinien obciąć białe znaki).
