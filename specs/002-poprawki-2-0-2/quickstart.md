# Quickstart: weryfikacja poprawek 2.0.2

Budowanie i testy wyłącznie w GitHub Actions (brak Maca). Weryfikacja ręczna tylko raz — na kompilacji 2.0.2
z TestFlight.

## 1. Weryfikacja automatyczna (po każdej fazie)

```bash
git push origin main
```

```bash
gh run watch --exit-status $(gh run list --workflow ci.yml --branch main --limit 1 --json databaseId -q ".[0].databaseId")
```

Oczekiwane: zielony przebieg, w tym:

- `HorselyKitTests` — `AppLockMachineTests` (sekwencje z [data-model.md](data-model.md#applockmachine-horselykit-w-pamięci)),
  testy źródła miniatury (lokalna → z oryginału → z programu przez zaślepkę `URLProtocol`, 404, brak sieci, tryb
  samodzielny po przejściu).
- `HorselyCoreTests` — `GroupBarChart` (grupy, „Pozostałe” przy > 12, pusty raport), wzorce
  `golden/rider-trainings/*` i `training-summary/*` bez zmian.
- `AppSnapshotTests` — raporty (sumy na górze, „Treningi jeźdźca” z wykresem i zwiniętą listą; jasny, ciemny, tekst
  200 %), `StringsParityTests`.
- `AppUITests` — przepływ koni z miniaturą (zaślepka programu).

## 2. Wydanie (tylko faza końcowa)

Wg [contracts/release.md](contracts/release.md): `MARKETING_VERSION` 2.0.2 → zielone CI → tag `v2.0.2`.

## 3. Lista ręczna dla właściciela (iPhone 15 Pro, kompilacja 2.0.2)

1. **Blokada**: Ustawienia → Blokada aplikacji: włącz. Zamknij aplikację, otwórz, odblokuj kodem → Pulpit, bez ponownej
   blokady. Powtórz z Face ID. Wyjdź do ekranu głównego na > 5 min, wróć, odblokuj → ten sam ekran. Anuluj okno
   uwierzytelniania → zostaje ekran blokady z „Odblokuj”, okno nie wraca samo.
2. **Zdjęcia**: (tryb z programem) przeciągnij listę koni w dół lub otwórz aplikację po aktualizacji → miniatury koni
   ze zdjęciem w programie pojawiają się na liście, Pulpicie i w karcie konia w ciągu ok. 10 s. Włącz tryb samolotowy,
   uruchom ponownie → miniatury nadal widoczne. Karta konia → „Pokaż zdjęcie” → pełne zdjęcie.
3. **Raport**: Raporty → „Treningi jeźdźca” → bez przewijania widać sumy i wykres; przełącz „Liczba / Czas”; „Pokaż
   treningi (N)” rozwija listę. Eksport PDF zawiera wykres. „Podsumowanie treningów” — sumy nad wierszami.

Weryfikacja wydajności (NFR-M-01…03) — pominięta decyzją właściciela z 2026-10-17 (plan.md, „Complexity Tracking”).

## 4. Wynik listy ręcznej 2.0.2

_Do uzupełnienia po teście właściciela (T038)._
