---
name: generuj_dokumentacje
description: Generuje instrukcję obsługi programu Zarządzanie końmi w PDF — przyjazna kolorystyka, prosty język, część ogólna, rozdziały w kolejności menu z ikonami programu i zrzutami ekranu z ponumerowanymi zaznaczeniami, wersja w nazwie pliku i treści, autor programu. Użyj, gdy użytkownik prosi o instrukcję obsługi, podręcznik użytkownika lub dokumentację PDF programu.
---

# Generowanie instrukcji obsługi (PDF)

Wynik: `docs/Instrukcja-obslugi-Zarzadzanie-konmi-v<wersja>.pdf`. Wersja pochodzi z `Directory.Build.props`,
autor programu: **Piotr Glapa**.

## Krok 1. Zapytaj, co uwydatnić i co jeszcze opisać

Zanim cokolwiek zbudujesz, zadaj użytkownikowi **dwa pytania** narzędziem **AskUserQuestion** (w jednym wywołaniu, oba `multiSelect: true`).

### Pytanie 1 — wyróżnienia

> Które funkcjonalności mają być uwydatnione w dokumentacji?

Opcje (maks. 4 w jednym pytaniu — jeśli użytkownik chce innych, wybierze „Other” i wpisze je):

| Etykieta | Klucz `-Highlight` | Co wyróżnia |
|---|---|---|
| Zawody (Recommended) | `zawody` | rozdział Zawody |
| Terminarz (Recommended) | `terminy` | Pulpit i Terminy |
| Konfiguracja systemu (Recommended) | `konfiguracja` | Słowniki i Ustawienia |
| Raporty (Recommended) | `raporty` | Raporty |

Dodatkowe klucze, które użytkownik może podać w „Other”: `treningi`, `konie`, `zakupy`, `kontakty`, `kosz`.
Wyróżniony rozdział dostaje pomarańczowy nagłówek, wstążkę „★ WARTO POZNAĆ”, ramkę „Dlaczego warto”,
gwiazdkę w spisie treści i pomarańczowy kafel w części ogólnej.

### Pytanie 2 — dodatkowe funkcje do opisania

> Jakie dodatkowe funkcjonalności muszą się znaleźć w instrukcji — oprócz rozdziałów, które odpowiadają pozycjom menu?

Chodzi o funkcje „ukryte” w oknach i przyciskach, których zwykły rozdział z menu nie pokazuje. Zaproponuj w opcjach (maks. 4) najczęstsze:
„Klucz API dla telefonu z kodem QR” (Ustawienia → API → Generuj klucz, okno z kodem QR), „Zmiana statusu konia i pieniądze konia”
(sprzedaż, padnięcie, ceny), „Przywracanie z kopii i import danych”, „Raport — eksport CSV/PDF”. Użytkownik dopisze własne w „Other”
(może podać kilka, po przecinku).

Dla **każdej** wskazanej funkcji, zanim zbudujesz PDF:
1. Znajdź ją w programie (kod `src/ZarzadzanieKonmi.Desktop` albo uruchom program i obejrzyj okno), ustal nazwy kontrolek (`-Dump`).
2. Dodaj scenę w `scripts/capture.ps1` (zrzut samego okna/okienka z numerowanymi ramkami; gdy okno otwiera się przyciskiem — wywołaj go w
   sekcji `prepare`, a po zrzucie zamknij: `Close-Drawer` albo klawisz Esc).
3. Dodaj w `template/instrukcja.html` podrozdział w odpowiednim rozdziale (figura, legenda numerów, ewentualnie ramka „rada”) — albo osobny
   rozdział, jeśli funkcja nie pasuje do żadnego z menu. Funkcja, która już ma opis, ma go zachować lub zyskać zrzut.
4. Jeśli funkcja wymaga danych (np. klucz API), pamiętaj, że zrzuty powstają na danych pokazowych — **nie pokazuj prawdziwego klucza**;
   wygeneruj klucz testowy w danych pokazowych albo zasłoń wartość na zrzucie.
5. Po zbudowaniu obejrzyj zrzuty tych funkcji (krok 4) i powiedz użytkownikowi, które zostały dodane.


## Krok 2. Sprawdź warunki

- Windows, Windows PowerShell 5.1, .NET SDK, Microsoft Edge.
- Zainstalowany program w bieżącej wersji (`%LOCALAPPDATA%\Programs\ZarzadzanieKonmi\ZarzadzanieKonmi.exe`) albo
  ścieżka do zbudowanego `ZarzadzanieKonmi.exe` przekazana w `-Exe`. Wersja programu musi być zgodna z wersją
  w `Directory.Build.props` — jeśli nie jest, zbuduj instalator (`installer/`) i zapytaj użytkownika o instalację.
- Pakiety NuGet przywrócone (`dotnet restore`) — z `Wpf.Ui.dll` wyciągana jest czcionka ikon programu.
- Podczas robienia zrzutów skrypt steruje oknem programu (UI Automation, mysz). Uprzedź użytkownika, żeby
  przez ok. 3 minuty nie używał myszy ani klawiatury. Uruchomiona kopia programu zostanie zamknięta.

## Krok 3. Zbuduj PDF

Z katalogu repozytorium:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .claude\skills\generuj_dokumentacje\scripts\build.ps1 -Highlight zawody,terminy,treningi,konfiguracja,raporty
```

Skrypt:
1. zasiewa dane pokazowe w `%TEMP%\zk-docs\dane` (`tools/ZarzadzanieKonmi.Seed`: 8 koni, 400 wpisów) i uzupełnia je
   `tools/DemoData` (`demo-data.sql`: terminy przeterminowane i nadchodzące, źrebię „Iskierka” bez paszportu,
   zakup z dostawą, pensjonat, dwa wpisy w koszu) — prawdziwe dane użytkownika nie są dotykane;
2. uruchamia program z `--data-dir` i robi zrzuty `scripts/capture.ps1` (35 scen w kolejności menu, pomarańczowe
   ramki z numerami);
3. wyciąga czcionkę Fluent System Icons z `Wpf.Ui.dll`, dzięki czemu ikony w tekście wyglądają jak w programie;
4. wypełnia `template/instrukcja.html` (`{{WERSJA}}`, `{{AUTOR}}`, `{{DATA}}`, wyróżnienia) i drukuje PDF przez Edge.

Parametry: `-Highlight`, `-Exe`, `-Author`, `-Version`, `-OutDir` (domyślnie `docs`), `-SkipCapture` (tylko HTML → PDF z istniejących
zrzutów, np. po poprawce tekstu), `-Dump` (obok zrzutów zapisuje `<scena>.txt` z nazwami i położeniem kontrolek).

## Krok 4. Sprawdź wynik

- Obejrzyj zrzuty w `%TEMP%\zk-docs\shots` (narzędziem Read) — każda ramka ma obejmować opisywany element, a numery
  muszą zgadzać się z legendą pod obrazkiem w `template/instrukcja.html`. Log `capture.ps1` wypisuje
  „(brak elementu: …)”, gdy nazwa kontrolki się zmieniła.
- Obejrzyj PDF (np. `pdftoppm` albo otwórz w przeglądarce): okładka z wersją i autorem, spis treści, podziały stron.
- Przekaż użytkownikowi ścieżkę pliku PDF.

## Gdy program się zmienił

- **Nowy ekran lub funkcja**: dodaj scenę w `scripts/capture.ps1` (w kolejności menu) i rozdział/legendę w
  `template/instrukcja.html`. Ikony: `<span class="ic">&#xKOD;</span>` — kod glifu odczytasz z UIA
  (`-Dump`, nazwa elementu `SymbolIcon`/`Text`) albo z tabeli w `scripts/uia.ps1` i szablonu.
- **Zmieniona nazwa kontrolki**: uruchom z `-Dump`, znajdź nową nazwę w `<scena>.txt` i popraw znacznik.
  Znacznik: `@{ N = 1; Items = @(@('Nazwa', 'Typ', indeks), ...); Pad = 5; Grow = @(l, t, r, b); Rect = @(x, y, w, h) }`
  — ramka obejmuje sumę prostokątów elementów.
- **Nowe dane potrzebne na zrzucie**: dopisz je do `tools/DemoData/demo-data.sql` (daty względne `date('now', …)`,
  kwoty w groszach).
- Pliki `.ps1` z polskimi znakami zapisuj w UTF-8 **z BOM** (inaczej PowerShell 5.1 nie znajdzie kontrolek po nazwie).

## Styl tekstu

Prosty język, zwracanie się do czytelnika na „Ty”, krótkie zdania, bez żargonu technicznego (zamiast „rekord”
— „wpis”, zamiast „walidacja” — „program sprawdzi”). Każdy rozdział: jedno zdanie wprowadzenia, zrzut, legenda
numerów, ewentualnie ramka „rada”. Nazwy przycisków pogrubione, z ikoną z programu.
