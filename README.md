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
- **2.0.2** — wydana (TestFlight, kompilacja 24), trzy poprawki ([specs/002-poprawki-2-0-2](specs/002-poprawki-2-0-2/spec.md)):
  blokada aplikacji nie blokuje ponownie po odblokowaniu, miniatury zdjęć koni z programu pojawiają się na listach,
  raport „Treningi jeźdźca” ma sumy na górze, wykres grup i zwijaną listę treningów.
- **2.1.0** — wydanie do TestFlight: powiadomienia push z serwera w trybie z serwerem, jak w Androidzie 2.1.0
  ([specs/003-push-z-serwera](specs/003-push-z-serwera/spec.md), [CHANGELOG.md](CHANGELOG.md)).

Budowanie, testy i wysyłka do TestFlight odbywają się wyłącznie w GitHub Actions (brak Maca).

## Plik konfiguracyjny Firebase

`App/Resources/GoogleService-Info.plist` (projekt Firebase `horsely-41baf`, aplikacja `pl.glapa.horsely`) jest
w repozytorium celowo — **nie jest sekretem**: pozwala tylko odbierać powiadomienia push, nie wysyłać ich. Klucz API
w nim jest ograniczony w konsoli Google Cloud do aplikacji iOS `pl.glapa.horsely`. Dzięki temu budowanie z samego
repozytorium daje działający push. Sekretami są i **nigdy** nie trafiają do repozytorium: klucz APNs `.p8` (wgrany do
Firebase) oraz klucz konta usługi Firebase (używa go tylko serwer) — konstytucja, zasada II.
