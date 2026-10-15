# Quickstart: walidacja Horsely na iOS

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md) | **CI**: [contracts/ci-release.md](contracts/ci-release.md)

Rozwój na Windows bez Maca: wszystko, co wymaga Xcode, uruchamia GitHub Actions. Polecenia `gh` z PowerShell
(`C:\Program Files\GitHub CLI\gh.exe`, zalogowany kreatorem).

## 1. Wymagania wstępne

- Repozytorium `PiotrGlapa/zarzadzanie-konmi-ios` z sekretami i zmiennymi z [contracts/ci-release.md](contracts/ci-release.md) §1
  (`gh secret list`, `gh variable list`).
- Grupy TestFlight „Deweloper” (właściciel) i „Właściciele” (córka + właściciel); aplikacja TestFlight na iPhonie 15 Pro córki.
- Program Horsely 2.0.0 na komputerze z włączonym API, HTTPS, „Dostęp spoza sieci domowej” i adresem publicznym; osobny klucz
  API dla telefonu córki ze zgodą na dostęp spoza domu (kod QR). Do testów zgodności wstecz — program 1.6.1 (na osobnym
  komputerze lub maszynie wirtualnej).
- Repozytorium Androida obok (`../zarzadzanie_konmi_android`) — źródło `strings.xml`, plików wzorcowych i zrzutów.

## 2. Teksty (lokalnie, Windows)

```powershell
.\scripts\sync-strings.ps1 -AndroidRepo ..\zarzadzanie_konmi_android
git diff --stat App/Resources
```

Oczekiwane: `Localizable.xcstrings` i kopie `strings.xml`/`plurals.xml` zaktualizowane; test zgodności w CI zielony.

## 3. Przebieg CI (każdy push)

```powershell
gh run list --workflow ci.yml --limit 5
gh run watch
gh run download <id> --name screenshots
```

Oczekiwane: testy `HorselyCore` (w tym pliki wzorcowe `parity` i CSV `golden` bajt w bajt), `HorselyKit` (zaślepka API:
401/403/409/413/415/429, przerwanie połączenia, konflikt), zgodność tekstów, testy migawkowe — zielone; na `main` także testy UI
i zrzuty `screenshots/ios/*.png` do porównania z `Tests/Reference/android/*.png` ([contracts/test-fixtures.md](contracts/test-fixtures.md)).

## 4. Kompilacja częściowa dla właściciela

```powershell
gh workflow run release.yml -f group=Deweloper
gh run watch
```

Oczekiwane: podsumowanie przebiegu z wersją 2.0.1, numerem kompilacji i „wysłano do TestFlight”; po kilku–kilkunastu minutach
kompilacja w grupie „Deweloper”. Brak sekretu → przebieg czerwony z listą brakujących nazw.

## 5. Scenariusze akceptacyjne na telefonie (skrót)

| Przyrost | Scenariusz | Oczekiwany wynik |
|---|---|---|
| US1 | świeża instalacja, tryb samolotowy → tryb samodzielny → 2 konie + źrebak → zdjęcie z kadrowaniem → status „Kontuzjowany” | Pulpit, lista i karta jak na zrzutach Androida; ikona plastra; VoiceOver „<imię>, kontuzjowany” |
| US2 | kowal z następną wizytą, zakup 100,01 zł dla 2 koni, trening kontuzjowanemu | termin kowala na Pulpicie; 50,01 / 50,00 zł; pytanie „Koń jest kontuzjowany. Zapisać trening?” |
| US3 | Ustawienia → Tryb pracy → online (dwa ostrzeżenia) → skan QR → pełne pobranie | dane jak w programie; dane testowe z trybu samodzielnego usunięte dopiero po udanym parowaniu |
| US3 | tryb samolotowy: edycja wizyty, usunięcie treningu, „Przełóż”, nowy koń; w programie zmiana tej samej wizyty; sieć wraca | zmiany w programie, konflikt wizyty → „Zachowaj moją” → kolejka pusta, 0 duplikatów |
| US3 | dane komórkowe poza domem (Wi‑Fi wyłączone) → nowy wpis, odświeżenie | wpis w programie przez adres publiczny; dziennik pokazuje adres publiczny, IP i wynik 2xx |
| US4–US9 | scenariusze akceptacyjne spec.md | jak w spec.md i specyfikacji głównej |
| FR-KOP-09 | kopia z hasłem z Androida → „Odtwórz z kopii” na iPhonie; kopia z iPhone'a → Android | te same dane i załączniki w obu kierunkach |

## 6. Wydajność (iPhone 15 Pro)

Start do Pulpitu < 2 s, raport dla 2 000 treningów < 3 s, pierwsze pobranie 50 koni / 50 000 wpisów < 3 min (dane
`parity/duzy`), zapis < 1 s — pomiar Instruments niedostępny bez Maca: znaczniki czasu w dzienniku diagnostycznym
(`os_signpost` + wpis dziennika) odczytane z „Dziennik diagnostyczny → Wyślij”.

## 7. Lista kontrolna przed dodaniem kompilacji do grupy „Właściciele”

- [ ] CI zielone na `main` (testy jednostkowe, UI, migawkowe); zrzuty iOS przejrzane obok zrzutów Androida.
- [ ] Na iPhonie 15 Pro: skan QR, połączenie w domowym Wi‑Fi i spoza domu (adres publiczny, HTTPS), Face ID blokady,
      aparat i kadrowanie, powiadomienie o 08:00, VoiceOver na Pulpicie i w formularzu, tekst 200 % na Pulpicie i w raporcie.
- [ ] Scenariusze §5 dla przyrostów zawartych w kompilacji.
- [ ] Brak nazwy „Zarządzanie końmi” w interfejsie; „O aplikacji” pokazuje 2.0.1 i numer kompilacji.
- [ ] Kompilacja dodana do grupy „Właściciele” w App Store Connect; data zapisana (przypomnienie po 80 dniach).
