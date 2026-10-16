# Przegląd dostępności (T135)

**Zakres**: wszystkie ekrany aplikacji iOS 2.0.1 wg zasad E1–E8 z contracts/android/screen-review.md, VoiceOver, Dynamic Type do
`accessibility5`, kontrast, cele dotyku ≥ 44 pt.
**Metoda**: przegląd kodu (etykiety, identyfikatory, cele dotyku), testy automatyczne w CI (migawki z tekstem 200 %, kontrast palety)
— bez Maca; elementy wymagające czytnika ekranu na urządzeniu są wypisane osobno na końcu.
**Data**: 2026-10-16, kompilacja 22.

## Sprawdzone w kodzie i testach

- [x] E1 Odstępy z `Spacing` (krawędź 16 pt, sekcje 16 pt, elementy 8 pt) i nagłówki sekcji przez `SectionHeader` na listach i kartach.
- [x] E2 Listy z liniami między wierszami (`DividedList`); obszary i kafle (`InfoCard`) bez linii.
- [x] E3 Wiersze i kafle wyglądające na klikalne otwierają szczegóły (konie, wpisy, terminy, zakupy, zawody, kontakty, załączniki, raporty, kosz).
- [x] E4 Główna akcja „+” nad paskiem kart; cele dotyku ≥ 44 pt (`Spacing.minTouchTarget`) w wierszach, przyciskach ikon, przełącznikach okresu raportu, kafelkach załączników (96 pt).
- [x] E5 Tekst 200 %: migawki `xxxl` (Pulpit, konie, karta konia, formularze, działy, raporty, karta wiersza raportu na 320 pt, załączniki) bez obcinania; nagłówki z przyciskiem przechodzą w układ pionowy (`ViewThatFits`).
- [x] E5 Kontrast palety ≥ 4,5:1 dla tekstu i ≥ 3:1 dla grafiki — `PaletteContrastTests` (jasny i ciemny motyw).
- [x] E6 Kolory: zieleń — główny, pomarańcz — ostrzeżenia (przeterminowane, konflikty, przypomnienie o kopii), czerwień — błędy.
- [x] E7 Formularze z sekcjami i nagłówkami, „Zapisz” w pasku tytułu i na dole formularza.
- [x] E8 Stany ładowania (`ProgressView`), pusto z podpowiedzią (`SectionEmpty`, „Brak załączników”, „Kosz jest pusty”, „Dziennik jest pusty.”), błąd z komunikatem.
- [x] Przyciski z samą ikoną mają `accessibilityLabel` (zamknij komunikat połączenia, wyczyść datę, kolejność adresów, kadrowanie zdjęcia, eksport raportu, menu wartości słownika, akcje załącznika, poprzedni/następny okres raportu); ikony dekoracyjne są ukryte przed VoiceOver (`accessibilityHidden`).
- [x] Wykresy raportów mają opis wartości dla VoiceOver (`ChartDescriptions`) — informacja nie tylko w kolorze; serie linii różnią się też kształtem znacznika i stylem linii.
- [x] Wiersze złożone (wiersz raportu etykieta—wartość, koń, wpis, termin) łączone w jeden element (`accessibilityElement(children: .combine)`), z podpowiedzią akcji tam, gdzie jest menu kontekstowe.
- [x] Blokada aplikacji: ekran „Aplikacja zablokowana” z przyciskiem „Odblokuj”; zasłona bez treści w przełączniku aplikacji jest ukryta przed VoiceOver.

## Do sprawdzenia na telefonie (VoiceOver, Dynamic Type `accessibility5`)

- Pulpit i formularz wpisu z VoiceOver: kolejność czytania, nagłówki, akcje „Cofnij” w komunikacie po zapisie.
- Raport z wykresem: czy opis wykresu jest czytany w całości.
- Podgląd załącznika (QuickLook) i arkusz dodawania pliku — systemowe komponenty.
- Ekran blokady z Face ID i powrót do aplikacji z VoiceOver.
