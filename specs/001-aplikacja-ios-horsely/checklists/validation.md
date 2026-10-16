# Walidacja wydania 2.0.1

## Zrzuty iOS a Android (T138, T140)

Porównanie zrzutów iOS z zrzutami Androida na tych samych danych zostało **pominięte na prośbę właściciela** (2026-10-16):
właściciel sprawdza całą funkcjonalność na zainstalowanej aplikacji; rozbieżności trafią do wydania poprawkowego. Zrzuty iOS
(jasny, ciemny, tekst 200 %) są w testach migawkowych (`Tests/AppSnapshotTests/__Snapshots__`).

## Kopia zapasowa Android ↔ iOS (T123, T139)

- Android → iOS: pliki utworzone kodem `BackupWriter` Androida 2.0.1 (bez hasła i z hasłem) odtwarzają się w iOS z tymi samymi
  rekordami, koszem i sumami `sha256` plików — test `BackupTests` w CI.
- iOS → Android: kopie z iOS (artefakt CI `ios-backup`, przebieg 38965677621) odtworzone kodem `BackupReader` Androida 2.0.1
  jednorazowym testem JVM (2026-10-16): `ios-2.0.1.zkkopia` i `ios-2.0.1-haslo.zkkopia` — format 2, schemat 1.5, 73 rekordy
  (z koszem) i plik załącznika zgodne co do wersji, partii kosza i `sha256`. **OK**.

## Wydajność (T137) — do zmierzenia na iPhonie

Bez Maca nie ma Instruments; pomiar na telefonie wg quickstart.md §6 (start do Pulpitu < 2 s, raport dla 2 000 treningów < 3 s,
pierwsze pobranie 50 koni / 50 000 wpisów < 3 min, zapis < 1 s). Wynik zostanie dopisany po sprawdzeniu na urządzeniu.

## Program na komputerze (T096) — do sprawdzenia przez właściciela

Scenariusze quickstart.md §5 z programem 2.0.0 (i 1.6.1): domowe Wi‑Fi i dane komórkowe przez adres publiczny z HTTPS.

## Wydanie (T141)

Tag `v2.0.1` → kompilacja **2.0.1 (23)** wysłana do TestFlight 2026-10-16 (przebieg 38969761212). Kompilacja wygasa po 90 dniach —
przypomnienie o nowej od 2027-01-04. Punkty listy kontrolnej quickstart.md §7 wymagające telefonu (skan QR, połączenie spoza domu,
Face ID, aparat, powiadomienie o 08:00, VoiceOver, tekst 200 %) sprawdza właściciel na zainstalowanej aplikacji.
