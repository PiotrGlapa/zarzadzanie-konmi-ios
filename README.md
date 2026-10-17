# Horsely – Zarządzanie Koniem, Trening i Budżet (iOS)

Aplikacja mobilna na iPhone'a — pomocnik w stajni dla programu „Zarządzanie końmi” (Horsely) na Windows.
Pozwala przy koniu sprawdzić terminy, zapisać wpis (trening, wizyta, kowal, zakup, zawody) ze zdjęciami,
przejrzeć historię, kontakty, koszty i raporty. Działa w trybie online (z programem na komputerze)
albo samodzielnie.

Odpowiednik na Androida ma osobny projekt i ten sam zakres funkcji.

## Dokumentacja

- [SPECYFIKACJA_MOBILE_IOS.md](SPECYFIKACJA_MOBILE_IOS.md) — specyfikacja funkcji i wymagań platformy iOS
  (wejście do `/speckit-specify`).

## Status

- **2.0.1** — wydana (TestFlight, kompilacja 23): pełny zakres aplikacji na Androida 2.0.1.
- **2.0.2** — w przygotowaniu, trzy poprawki ([specs/002-poprawki-2-0-2](specs/002-poprawki-2-0-2/spec.md)):
  blokada aplikacji nie blokuje ponownie po odblokowaniu, miniatury zdjęć koni z programu pojawiają się na listach,
  raport „Treningi jeźdźca” ma sumy na górze, wykres grup i zwijaną listę treningów. Wersja zostanie uznana
  za wydaną po ręcznej liście kontrolnej na iPhonie.

Budowanie, testy i wysyłka do TestFlight odbywają się wyłącznie w GitHub Actions (brak Maca).
