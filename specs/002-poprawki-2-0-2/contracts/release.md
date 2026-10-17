# Kontrakt procesu: jedno wydanie 2.0.2 na końcu

Wymóg właściciela (2026-10-17): brak weryfikacji między fazami, więc jedna kompilacja do TestFlight na końcu.

## Fazy pośrednie (każda historia, każda faza zadań)

- Commit(y) na `main` + push → `ci.yml` (kompilacja, testy pakietów, migawkowe, UI). Faza zakończona dopiero przy
  zielonym `ci.yml`.
- **Zabronione**: tag `v*`, ręczne uruchomienie `release.yml` (także kompilacja częściowa dla grupy „Deweloper”),
  zmiana `MARKETING_VERSION`.
- Nowe/zmienione zrzuty migawkowe: pobranie artefaktu `snapshots-*` z przebiegu CI, przejrzenie i commit referencji.

## Faza końcowa (jedyna z wysyłką)

Warunki wejścia: wszystkie zadania historii 1–3 ukończone, `ci.yml` zielony na `main`, zrzuty przejrzane, obie
specyfikacje zaktualizowane, wpis w `README.md`/historii zmian.

1. `project.yml`: `MARKETING_VERSION: "2.0.2"` → commit → zielony `ci.yml`.
2. `git tag v2.0.2` na tym commicie → push taga → `release.yml` (archiwum, podpis, wysyłka, grupa „Właściciele”).
3. Raport dla właściciela: wersja 2.0.2, numer kompilacji (`GITHUB_RUN_NUMBER`), wynik wysyłki, link `gh run`.
   Brak sekretów podpisywania lub klucza App Store Connect — zgłosić wprost, nie pomijać.
4. Aktualizacja pamięci „ostatnia kompilacja TestFlight” (data + 80 dni) i lista ręczna z `quickstart.md` dla
   właściciela.
5. Zapis wyniku listy ręcznej w `quickstart.md`; 2.0.2 uznana za wydaną dopiero po wyniku pozytywnym (negatywny →
   poprawka 2.0.3). Weryfikacja wydajności NFR-M-01…03 pominięta decyzją właściciela (plan.md, „Complexity Tracking”).
