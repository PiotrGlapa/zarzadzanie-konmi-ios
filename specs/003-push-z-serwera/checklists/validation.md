# Walidacja ręczna: push z serwera (iOS 2.1.0)

Wyniki scenariuszy z [quickstart.md](../quickstart.md) §4 na iPhonie 15 Pro **z lokalnym serwerem** (nigdy `192.168.18.33`).
Kompilacja: ______ (wersja / numer) · Data: ______ · Serwer lokalny: ______ · Tester: ______

Stan na dziś: **automatyczne testy w CI** (pakiety, migawki, testy UI) są opisane w `tasks.md`; scenariusze poniżej wymagają
prawdziwego iPhone'a z TestFlight (push nie działa w symulatorze), więc czekają na wykonanie przez właściciela.

| # | Scenariusz | Wynik | Uwagi |
|---|---|---|---|
| 1 | Parowanie z lokalnym serwerem, zgoda z Pulpitu, telefon na liście urządzeń ≤ 1 min | ☐ | |
| 2 | „Wyślij test” przy zablokowanym ekranie i przy otwartej aplikacji (10/10, ≤ 30 s) | ☐ | |
| 3 | Reguła „Kowal: dzień przed o 08:00”, lista reguł w aplikacji, brak lokalnych `due-`/`daily-` | ☐ | |
| 4 | Dotknięcie powiadomienia: termin / lista terminów / Pulpit | ☐ | |
| 5 | Wyłączenie wysyłania na serwerze → tryb awaryjny z powodem, powrót po włączeniu | ☐ | |
| 6 | Rejestracja i test na danych komórkowych (przy „tylko przez Wi‑Fi”) | ☐ | |
| 7 | Usunięcie urządzenia w UI webowym → komunikat i ponowna rejestracja | ☐ | |
| 8 | Wyłączenie powiadomień w ustawieniach iOS → wyrejestrowanie; przywrócenie → rejestracja | ☐ | |
| 9 | „Rozłącz” → urządzenie znika z listy ≤ 1 min | ☐ | |
| 10 | „Rozłącz” bez sieci — najwyżej ~5 s dłużej niż w 2.0.2 | ☐ | |
| 11 | Tryb samodzielny: ekran jak w 2.0.2, brak sekcji serwera | ☐ | |
| 12 | Dziennik diagnostyczny: wpisy `push` słowami, prefiks tokenu 8 znaków, brak tytułów i treści | ☐ | |
