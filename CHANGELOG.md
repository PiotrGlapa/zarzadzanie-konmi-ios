# Zmiany

Format: [Keep a Changelog](https://keepachangelog.com/pl/1.1.0/). Wersje zgodne z aplikacją na Androida o tym samym zakresie.

## [2.1.0] — 2026-11-05

Powiadomienia push z serwera w trybie z serwerem ([specs/003-push-z-serwera](specs/003-push-z-serwera/spec.md)).

### Dodano

- Powiadomienia push z serwera (Firebase Cloud Messaging → APNs) w trybie z serwerem: telefon rejestruje swój token na serwerze
  po wyrażeniu zgody, pokazuje powiadomienia wysłane przez serwer i nie planuje wtedy własnych powiadomień o terminach —
  bez dubli i bez utraconych przypomnień (lokalne działają do udanej rejestracji).
- Ekran **Ustawienia → Powiadomienia**: sekcja „Powiadomienia z serwera” ze stanem, datami rejestracji i ostatniego powiadomienia
  oraz listą reguł przypisanych telefonowi przez właściciela; komunikat, gdy właściciel usunął telefon z listy urządzeń.
- Tryb awaryjny z podaniem powodu (serwer bez push, telefon nie może odbierać powiadomień zdalnych, odrzucona rejestracja):
  powiadomienia planuje telefon, jak dotąd.
- Karta Pulpitu „Powiadomienia o terminach są wyłączone” (oba tryby) i pytanie o zgodę na powiadomienia z Pulpitu.
- Ekran „Kopia zapasowa na serwerze” po dotknięciu powiadomienia o nieudanej kopii (`horsely://server-backup`).
- Wyrejestrowanie telefonu na serwerze przy „Rozłącz”, przejściu w tryb samodzielny, ponownym parowaniu i cofnięciu zgody.
- Manifest prywatności (`PrivacyInfo.xcprivacy`), uprawnienie `aps-environment`, tryb tła `remote-notification`, kontrola uprawnień
  `.ipa` przed wysyłką do TestFlight.

### Zmieniono

- W trybie z serwerem, który wysyła powiadomienia, powiadomienia lokalne o terminach i dzienne podsumowanie są wyłączone
  (ustawienia lokalne są wtedy ukryte); tryb samodzielny bez zmian i bez żadnego połączenia z Google.
- Treść dziennego podsumowania: „Przeterminowane: 2, na dziś i jutro: 3” (jak w Androidzie 2.1.0).
- Sparowanie telefonu włącza powiadomienia o terminach, gdy telefon ma już zgodę na powiadomienia.
- Żądania `PUT`/`DELETE` rejestracji push są ponawiane po zerwanym połączeniu (do dwóch razy) i wychodzą także przez dane
  komórkowe przy włączonym „tylko przez Wi‑Fi”.

### Prywatność

- Jedyna nowa zależność: Firebase iOS SDK 12.17.0, tylko moduł Messaging, tylko w aplikacji (nie w rozszerzeniu udostępniania).
  Do serwera trafia wyłącznie platforma i token; dziennik zawiera 8 znaków tokenu, nigdy tytuły ani treści.

## [2.0.2]

- Blokada aplikacji nie blokuje ponownie po odblokowaniu; miniatury zdjęć koni z programu na listach; raport „Treningi jeźdźca”
  z sumami na górze, wykresem grup i zwijaną listą treningów ([specs/002-poprawki-2-0-2](specs/002-poprawki-2-0-2/spec.md)).

## [2.0.1]

- Pełny zakres aplikacji na Androida 2.0.1.
