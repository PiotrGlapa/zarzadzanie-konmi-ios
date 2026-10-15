# Kontrakt: użycie API programu przez nowe działy (US2)

Źródło prawdy: [openapi.yaml](../../001-aplikacja-mobilna/contracts/openapi.yaml) (kopia kontraktu programu 1.6.1) —
**bez zmian**; wszystkie zasoby poniżej już w nim są. Minimalna wersja programu bez zmian (1.5.0; `trainerId` od 1.4,
`riderId` od 1.5, `totalCost` zakupów od 1.1, `totalCost` treningów od 1.4).

## 1. Odczyty działów (z połączeniem)

| Dział / ekran | Żądanie | Parametry | Używane pola odpowiedzi |
|---|---|---|---|
| Treningi | `GET /trainings` | `from`, `to`, `horseId?`, `typeId?`, `trainerId?`, `riderId?`, `page`, `pageSize=200` | `items[]` (`Training`), `totalCount`, `totalCost` |
| Zakupy | `GET /purchases` | `from`, `to`, `categoryId?`, `supplierId?`, `horseId?` **albo** `general=true`, `page`, `pageSize=200` | `items[]` (`PurchaseListItem`), `totalCount`, `totalCost` (= „Razem”) |
| Zawody | `GET /competitions` | `from`, `to`, `disciplineId?`, `horseId?`, `page`, `pageSize=200` | `items[]` (`CompetitionListItem`), `totalCount` |
| Szczegóły zawodów | `GET /competitions/{id}` + `GET /competitions/{id}/starts` | — | `Competition`, `CompetitionStart[]` |
| „Powtórz zakup” | `GET /purchases/{id}` | — | `Purchase` (całe dane wejściowe) |

## 2. Zapisy

| Akcja | Żądanie | Bez połączenia | Uwagi |
|---|---|---|---|
| Nowy trening / zakup / start | `POST /trainings`, `/purchases`, `/competitions/{id}/starts` | kolejka (jak w 1.0) | bez zmian |
| Nowe zawody | `POST /competitions` | kolejka (`CreateCompetition`, istnieje) | z formularza zawodów (nowy) |
| Edycja zawodów | `PUT /competitions/{id}` (`version`) | niedostępna | 409 → dialog konfliktu jak w 1.0 |
| Usunięcie zawodów | `DELETE /competitions/{id}` | niedostępne | potwierdzenie; błąd programu (np. zawody ze startami) pokazany bez zmian |
| Edycja / usunięcie treningu, zakupu, startu | jak w 1.0 | niedostępne | bez zmian |

## 3. Pełne odświeżanie pamięci (`RefreshPlan`) — nowe i zmienione zasoby

`from = dziś − 12 miesięcy` (stała, niezależna od ustawienia osi czasu); wszystkie strony (`pageSize=200`); równolegle
w istniejącej puli 4 żądań.

| Zasób | Żądanie | Tabela | Zmiana |
|---|---|---|---|
| Treningi | `GET /trainings?from=` (bez `horseId`) | `training` | było: osobno dla każdego aktywnego konia za okres osi czasu |
| Zakupy | `GET /purchases?from=` | `purchase` | **nowe** |
| Zawody | `GET /competitions?from=` | `competition` | **nowe** |
| Starty | `GET /competition-starts?from=` | `competition_start` | **nowe** (metoda dopisana do `ProgramApi`) |

Szacunek obciążenia (50 koni, 12 mies.): treningi ~1 000–2 000 pozycji = 5–10 stron (zamiast ≥ 50 żądań per koń), zakupy
i zawody po 1–3 strony — łącznie mniej żądań niż w 1.0.

## 4. Zaślepka programu (testy)

`FakeProgramServer` (`:core/src/testFixtures`) — nowe trasy: `GET /purchases` (filtry `general`, `categoryId`, `supplierId`,
`horseId`, sumy), `GET /competitions`, `GET/PUT/DELETE /competitions/{id}`, `GET /competition-starts`; walidacja
odpowiedzi schematami z `openapi.yaml` (jak w 1.0). Sumy z połączeniem pochodzą z programu, więc aplikacja tylko je
wyświetla (test: wartość z odpowiedzi zaślepki trafia do stopki bez zmian); sumy offline — testy jednostkowe na danych
z pamięci.
