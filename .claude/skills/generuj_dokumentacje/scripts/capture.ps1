# Screenshots of the user manual, in the order of the application menu, with numbered frames around the features
# described in the text (template/instrukcja.html refers to the file names and the numbers).
# Usage: capture.ps1 -Exe <ZarzadzanieKonmi.exe> -DataDir <folder with demo data> -OutDir <folder for PNG> [-Dump]
param(
  [Parameter(Mandatory)] [string]$Exe,
  [Parameter(Mandatory)] [string]$DataDir,
  [Parameter(Mandatory)] [string]$OutDir,
  [switch]$Dump
)
. "$PSScriptRoot\uia.ps1"
New-Item -ItemType Directory -Force $OutDir | Out-Null

function Dump-Names([string]$scene) {
  if (-not $Dump) { return }
  $win = (Get-AppWindow).Current.BoundingRectangle
  $lines = foreach ($el in (Get-AppWindow).FindAll($TS::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
    $c = $el.Current
    $r = $c.BoundingRectangle
    if ($c.Name -and -not $c.IsOffscreen -and -not $r.IsEmpty -and -not [double]::IsInfinity($r.X)) {
      "{0}`t{1}`t{2},{3},{4},{5}" -f ($c.ControlType.ProgrammaticName -replace 'ControlType\.', ''), $c.Name, [int]($r.X - $win.X), [int]($r.Y - $win.Y), [int]$r.Width, [int]$r.Height
    }
  }
  $lines | Select-Object -Unique | Set-Content (Join-Path $OutDir "$scene.txt") -Encoding UTF8
}

function Scene([string]$name, [scriptblock]$prepare, $marks) {
  Write-Host "Scena $name"
  try { & $prepare } catch { Write-Host "  przygotowanie: $($_.Exception.Message)" }
  Start-Sleep -Milliseconds 700
  Dump-Names $name
  Save-AnnotatedShot (Join-Path $OutDir "$name.png") $marks
}

Get-Process ZarzadzanieKonmi -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 1
Start-Process $Exe -ArgumentList '--data-dir', $DataDir | Out-Null
for ($i = 0; $i -lt 60 -and -not (Get-AppProcess); $i++) { Start-Sleep -Milliseconds 500 }
Start-Sleep 3
Resize-AppWindow 1400 900
# Tile of a horse: its name for a screen reader is "Name" or, since 1.6, "Name, ""StableName""" (the demo data gives some horses a stable name).
function Find-Tile([string]$name) {
  $tile = Find-One $name $CT::Button
  if ($tile) { return $tile }
  $buttons = (Get-AppWindow).FindAll($TS::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Button)))
  foreach ($b in $buttons) { if ($b.Current.Name -like "$name, *") { return $b } }
  $null
}
$navNames = 'Pulpit', 'Konie', 'Terminy', 'Zawody', 'Treningi', 'Zakupy', 'Kontakty', 'Raporty', 'Słowniki', 'Kosz', 'Ustawienia'

# --- Okno główne ------------------------------------------------------------------------------------------------------
Scene '01-okno' { Nav 'Pulpit' } @(
  @{ N = 1; Items = @($navNames | ForEach-Object { , @($_, 'DataItem') }) },
  @{ N = 2; Items = @(, @('Wyszukiwanie globalne', 'Edit')) },
  @{ N = 3; Rect = @(236, 54, 1138, 826); Pad = 0 }
)

# --- Pulpit -----------------------------------------------------------------------------------------------------------
Scene '02-pulpit' { Nav 'Pulpit'; Scroll-Page 0 } @(
  @{ N = 1; Items = @(@('Weterynarz', 'Button'), @('Notatka', 'Button')) },
  @{ N = 2; Items = @(@('Przeterminowane', 'Text'), @('Przeterminowane', 'Custom')) },
  @{ N = 3; Items = @(@('Nadchodzące (najbliższe 7 dni)', 'Text'), @('Nadchodzące (najbliższe 7 dni)', 'Custom')) },
  @{ N = 4; Items = @(@('Zarejestruj wizytę', 'Button'), @('Odrzuć', 'Button')); Pad = 4 }
)
Scene '03-pulpit-dol' { Scroll-ToTop 'Koszty bieżącego miesiąca' 'Text' } @(
  @{ N = 1; Items = @(, @('Koszty bieżącego miesiąca', 'Button')); Grow = @(0, 22, 0, 0) },
  @{ N = 2; Items = @(, @('Konie', 'Custom')); Grow = @(0, 22, 0, 0) },
  @{ N = 3; Items = @(, @('Iskierka', 'Button')); Pad = 3 }
)

# --- Konie ------------------------------------------------------------------------------------------------------------
Scene '04-konie' { Nav 'Konie' } @(
  @{ N = 1; Items = @(, @('Szukaj po imieniu lub numerze paszportu…', 'Edit')) },
  @{ N = 2; Items = @(@('Kafle', 'Button'), @('Tabela', 'Button')) },
  @{ N = 3; Items = @(, @('Pokaż wszystkie (także sprzedane, padłe, wydzierżawione)', 'CheckBox')) },
  @{ N = 3; Items = @(, @('Tylko źrebięta', 'CheckBox')) },
  @{ N = 4; Items = @(, @('Dodaj konia', 'Button')) },
  @{ N = 5; Items = @(, @('Iskierka', 'Button')) }
)
Scene '05-karta-konia' { Nav 'Konie'; Invoke-El (Find-Tile 'Grom'); Start-Sleep 4 } @(
  @{ N = 1; Items = @(@('Edytuj', 'Button'), @('Usuń', 'Button')) },
  @{ N = 2; Items = @(@('Najbliższe terminy', 'Text'), @("Koszty w $((Get-Date).Year) r.", 'Text')); Pad = 14; Grow = @(0, 12, 0, 60) },
  @{ N = 3; Items = @(@('Oś czasu', 'TabItem'), @('Załączniki', 'TabItem')) },
  @{ N = 4; Items = @(@('Wizyta weterynaryjna', 'Button'), @('Notatka', 'Button')) }
)
Scene '06-karta-zawody' { Invoke-El (Find-One 'Zawody' $CT::TabItem); Start-Sleep 2 } @(
  @{ N = 1; Items = @(, @('Zawody', 'TabItem')) },
  @{ N = 2; Items = @(@('Starty', 'Text'), @('Koszty', 'Text')); Pad = 8; Grow = @(0, 0, 90, 30) },
  @{ N = 3; Items = @(@('Miejsce', 'HeaderItem'), @('Ocena', 'HeaderItem')); Grow = @(0, 0, 0, 150) },
  @{ N = 4; Items = @(, @('Start', 'Button')) }
)
Scene '07-formularz-konia' { Nav 'Konie'; Invoke-El (Find-One 'Dodaj konia' $CT::Button); Start-Sleep 1.5
  Set-Text (Find-One 'Imię *' $CT::Edit) 'Luna'; Invoke-El (Find-One 'Źrebak' $CT::CheckBox); Start-Sleep 0.5 } @(
  @{ N = 1; Items = @(, @('Imię *', 'Edit')); Grow = @(0, 20, 0, 0) },
  @{ N = 2; Items = @(@('Numer paszportu', 'Edit'), @('Źrebak', 'CheckBox')); Grow = @(0, 20, 0, 0) },
  @{ N = 3; Items = @(, @('Zapisz', 'Button')) }
)
Close-Drawer

# --- Terminy ----------------------------------------------------------------------------------------------------------
Scene '08-terminy' { Nav 'Terminy' } @(
  @{ N = 1; Items = @(@('Koń', 'ComboBox'), @('Do', 'Edit')); Grow = @(0, 20, 0, 0) },
  @{ N = 2; Items = @(@('Zarejestruj wizytę', 'Button'), @('Usuń', 'Button')); Pad = 3 },
  @{ N = 3; Items = @(, @('Termin', 'Button')) }
)

# --- Zawody -----------------------------------------------------------------------------------------------------------
Scene '09-zawody' { Nav 'Zawody' } @(
  @{ N = 1; Items = @(@('Dyscyplina', 'ComboBox'), @('Do', 'Edit')); Grow = @(0, 20, 0, 0) },
  @{ N = 2; Items = @(@('Starty', 'HeaderItem'), @('Najlepsze miejsce', 'HeaderItem')); Grow = @(0, 0, 0, 40) },
  @{ N = 3; Items = @(, @('Zawody', 'Button')) },
  @{ N = 4; Items = @(@('Szczegóły', 'Button'), @('Edytuj', 'Button'), @('Usuń', 'Button')); Pad = 4 }
)
Scene '10-zawody-szczegoly' { Invoke-El (Find-One 'Szczegóły' $CT::Button); Start-Sleep 2 } @(
  @{ N = 1; Items = @(@('Ranga', 'Text'), @('Organizator', 'Text')); Grow = @(0, 0, 150, 22) },
  @{ N = 2; Items = @(@('Koń', 'HeaderItem'), @('Ocena', 'HeaderItem')); Grow = @(0, 0, 0, 175) },
  @{ N = 3; Items = @(, @('Start', 'Button')) }
)

# --- Treningi (1.3, trener i koszt 1.4) -----------------------------------------------------------------------------
Scene '23-treningi' { Close-Drawer; Nav 'Treningi' } @(
  @{ N = 1; Items = @(@('Rodzaj', 'ComboBox'), @('Do', 'Edit')); Grow = @(0, 20, 0, 0) },
  @{ N = 2; Items = @(@('Czas', 'HeaderItem'), @('Ocena', 'HeaderItem')); Grow = @(0, 0, 0, 40) },
  @{ N = 3; Items = @(@('Trener', 'HeaderItem'), @('Koszt', 'HeaderItem')); Pad = 2; Grow = @(0, 0, 0, 78) },
  @{ N = 4; Items = @(, @('Trening', 'Button')) }
)
Scene '29-treningi-podliczenie' { Scroll-Wheel 80 } @(
  @{ N = 1; Items = @(, @('Treningów', 'Text')); Pad = 6; Grow = @(0, 0, 130, 0) }
)
# The horse is chosen in the form: the trainer and the cost come from its last training (1.4).
Scene '24-formularz-treningu' { Scroll-Wheel -80; Invoke-El (Find-One 'Trening' $CT::Button); Start-Sleep 1.5
  Click-El (Find-One 'Koń *' $CT::ComboBox); Start-Sleep 1; Click-El (Find-One 'Sowa' $CT::ListItem); Start-Sleep 2 } @(
  @{ N = 1; Items = @(, @('Rodzaj treningu *', 'ComboBox')); Grow = @(0, 20, 0, 0) },
  @{ N = 2; Items = @(@('Czas (min)', 'Edit'), @('Intensywność', 'ComboBox')); Grow = @(0, 20, 0, 0) },
  @{ N = 3; Items = @(@('Jeździec', 'ComboBox', 1), @('Nowy kontakt', 'Button', 0)); Grow = @(0, 20, 0, 0) },
  @{ N = 4; Items = @(@('Trener', 'ComboBox', 1), @('Nowy kontakt', 'Button', 1)); Grow = @(0, 20, 0, 0) },
  @{ N = 5; Items = @(@('Koszt (PLN)', 'Edit'), @('Zapłacono w walucie obcej', 'Group')); Grow = @(0, 68, 0, 0) },
  @{ N = 6; Items = @(, @('Zapisz', 'Button')) }
)
Close-Drawer
Scene '25-karta-treningi' { Nav 'Konie'; Invoke-El (Find-Tile 'Grom'); Start-Sleep 4; Invoke-El (Find-One 'Treningi' $CT::TabItem); Start-Sleep 2 } @(
  @{ N = 1; Items = @(, @('Treningi', 'TabItem')) },
  @{ N = 2; Items = @(@('Rodzaj', 'ComboBox'), @('Trener', 'ComboBox')); Grow = @(0, 20, 0, 0) },
  @{ N = 3; Items = @(@('Łączny czas', 'Text'), @('Średnia ocena', 'Text')); Pad = 8; Grow = @(0, 0, 0, 30) },
  @{ N = 4; Items = @(, @('Podsumowanie', 'Button')) }
)
Scene '30-karta-treningi-podliczenie' { Scroll-Wheel 80 } @(
  @{ N = 1; Items = @(@('Trener', 'HeaderItem'), @('Koszt', 'HeaderItem')); Pad = 2; Grow = @(0, 0, 0, 40) },
  @{ N = 2; Items = @(, @('Treningów', 'Text')); Pad = 6; Grow = @(0, 0, 130, 0) }
)

# --- Zakupy -----------------------------------------------------------------------------------------------------------
Scene '11-zakupy' { Close-Drawer; Nav 'Zakupy' } @(
  @{ N = 1; Items = @(@('Koń', 'ComboBox'), @('Wyczyść filtr', 'Button')); Grow = @(0, 20, 0, 0) },
  @{ N = 2; Items = @(, @('Kwota', 'HeaderItem')); Grow = @(0, 0, -10, 40) },
  @{ N = 3; Items = @(, @('Powtórz zakup', 'Button')); Pad = 3 },
  @{ N = 4; Items = @(, @('Zakup', 'Button')) }
)
Scene '12-formularz-zakupu' { Invoke-El (Find-One 'Zakup' $CT::Button); Start-Sleep 1.5
  Set-Text (Find-One 'Produkt / usługa *' $CT::Edit) 'Siano'; Set-Text (Find-One 'Ilość' $CT::Edit) '20'
  Set-Text (Find-One 'Cena jednostkowa (PLN)' $CT::Edit) '25'; Set-Text (Find-One 'Koszt dostawy (zł)' $CT::Edit) '150'; Start-Sleep 0.6 } @(
  @{ N = 1; Items = @(@('Ilość', 'Edit'), @('Cena jednostkowa (PLN)', 'Edit')); Grow = @(0, 20, 0, 0) },
  @{ N = 2; Items = @(, @('Koszt dostawy (zł)', 'Edit')); Pad = 4; Grow = @(0, 20, 0, 0) },
  @{ N = 3; Items = @(, @('Razem: 650,00 zł', 'Text')); Pad = 3; Grow = @(0, 0, -300, 0) },
  @{ N = 4; Items = @(@('Jeden koń', 'RadioButton'), @('Ogólny (cała stajnia)', 'RadioButton')) }
)
Close-Drawer

# --- Kontakty ---------------------------------------------------------------------------------------------------------
Scene '13-kontakty' { Nav 'Kontakty' } @(
  @{ N = 1; Items = @(@('Szukaj po nazwie, telefonie lub e-mailu…', 'Edit'), @('Pokaż zarchiwizowane', 'CheckBox')) },
  @{ N = 2; Items = @(@('Telefon', 'HeaderItem'), @('E-mail', 'HeaderItem')); Grow = @(0, 0, 0, 40) },
  @{ N = 3; Items = @(, @('Dodaj kontakt', 'Button')) }
)
# Trainers (1.4): the list narrowed to the contact type "Trener".
Scene '31-kontakty-trenerzy' { Click-El (Find-One 'Typ kontaktu *' $CT::ComboBox); Start-Sleep 1; Click-El (Find-One 'Trener' $CT::ListItem); Start-Sleep 2 } @(
  @{ N = 1; Items = @(, @('Typ kontaktu *', 'ComboBox')) },
  @{ N = 2; Items = @(, @('Typ', 'HeaderItem')); Grow = @(210, 0, 0, 76) }
)
# Riders (1.5): the list narrowed to the contact type "Jeździec".
Scene '33-kontakty-jezdzcy' { Click-El (Find-One 'Typ kontaktu *' $CT::ComboBox); Start-Sleep 1; Click-El (Find-One 'Jeździec' $CT::ListItem); Start-Sleep 2 } @(
  @{ N = 1; Items = @(, @('Typ kontaktu *', 'ComboBox')) },
  @{ N = 2; Items = @(, @('Typ', 'HeaderItem')); Grow = @(210, 0, 0, 76) }
)

# --- Raporty ----------------------------------------------------------------------------------------------------------
Scene '14-raporty' { Nav 'Raporty' } @(
  @{ N = 1; Items = @(@('Konie', 'ComboBox'), @('Grupowanie', 'ComboBox')); Grow = @(0, 20, 0, 0) },
  @{ N = 2; Items = @(, @('Kategorie', 'Group')) },
  @{ N = 3; Items = @(, @('Koszty miesięczne wg kategorii', 'Custom')); Grow = @(0, 24, 0, 0) },
  @{ N = 4; Items = @(, @('Udział kategorii', 'Custom')); Grow = @(0, 24, 0, 0) },
  @{ N = 5; Items = @(@('Eksport CSV', 'Button'), @('Eksport PDF', 'Button')) }
)

Scene '26-raporty-bilans' { Nav 'Raporty'; Invoke-El (Find-One 'Bilans konia' $CT::TabItem); Start-Sleep 2 } @(
  @{ N = 1; Items = @(, @('Bilans konia', 'TabItem')) },
  @{ N = 2; Items = @(@('Status konia', 'ComboBox'), @('Koń', 'ComboBox')); Grow = @(0, 20, 0, 0) },
  @{ N = 3; Items = @(@('Zakup', 'HeaderItem'), @('Wynik', 'HeaderItem')); Grow = @(0, 0, 0, 40) },
  @{ N = 4; Items = @(@('Eksport CSV', 'Button'), @('Eksport PDF', 'Button')) }
)
Scene '27-raporty-treningi' { Nav 'Raporty'; Invoke-El (Find-One 'Podsumowanie treningów' $CT::TabItem); Start-Sleep 2
  Click-El (Find-One 'Koń' $CT::ComboBox); Start-Sleep 1; Click-El (Find-One 'Grom' $CT::ListItem); Start-Sleep 1
  Click-El (Find-One 'Okres' $CT::ComboBox); Start-Sleep 1; Click-El (Find-One 'Wszystko' $CT::ListItem); Start-Sleep 2 } @(
  @{ N = 1; Items = @(, @('Podsumowanie treningów', 'TabItem')) },
  @{ N = 2; Items = @(@('Koń', 'ComboBox'), @('Okres', 'ComboBox')); Grow = @(0, 20, 0, 0) },
  @{ N = 3; Items = @(@('Czas (min)', 'HeaderItem'), @('Wysokość (cm)', 'HeaderItem')); Grow = @(0, 0, 0, 40) },
  @{ N = 4; Items = @(, @('Koszt', 'HeaderItem')); Pad = 2; Grow = @(0, 0, 0, 40) },
  @{ N = 5; Items = @(@('Eksport CSV', 'Button'), @('Eksport PDF', 'Button')) }
)
Scene '28-raporty-treningi-wykres' { Scroll-Page 100; Start-Sleep 1 } @(
  @{ N = 1; Items = @(@('Parametr wykresu', 'ComboBox'), @('Rodzaj na wykresie', 'ComboBox')); Grow = @(0, 20, 0, 0) },
  @{ N = 2; Items = @(, @('Wykres postępów', 'Custom')); Grow = @(0, 24, 0, 0) }
)

# Rider reports (1.5): one rider, then the competitions of the same rider.
Scene '34-raporty-jezdzca-treningi' { Nav 'Raporty'; Invoke-El (Find-One 'Treningi jeźdźca' $CT::TabItem); Start-Sleep 2
  Start-Sleep 1; Click-El (Find-One 'Jeździec' $CT::ComboBox); Start-Sleep 1.5; Click-El (Find-One 'Anna Wrona' $CT::ListItem); Start-Sleep 3 } @(
  @{ N = 1; Items = @(, @('Treningi jeźdźca', 'TabItem')) },
  @{ N = 2; Items = @(@('Jeździec', 'ComboBox'), @('Koń', 'ComboBox')); Grow = @(0, 20, 0, 0) },
  @{ N = 3; Items = @(@('Treningów', 'Text', 0), @('Koszt', 'Text', 1)); Pad = 6; Grow = @(0, 0, 0, 0) },
  @{ N = 4; Items = @(@('Eksport CSV', 'Button'), @('Eksport PDF', 'Button')) }
)
Scene '35-raporty-jezdzca-zawody' { Invoke-El (Find-One 'Zawody jeźdźca' $CT::TabItem); Start-Sleep 2
  Start-Sleep 1; Click-El (Find-One 'Jeździec' $CT::ComboBox); Start-Sleep 1.5; Click-El (Find-One 'Anna Wrona' $CT::ListItem); Start-Sleep 3 } @(
  @{ N = 1; Items = @(, @('Zawody jeźdźca', 'TabItem')) },
  @{ N = 2; Items = @(@('Wpisowe', 'HeaderItem'), @('Nagroda', 'HeaderItem')); Grow = @(0, 0, 0, 40) },
  @{ N = 3; Items = @(@('Zawodów', 'Text', 0), @('Bilans', 'Text', 1)); Pad = 6; Grow = @(0, 0, 0, 0) },
  @{ N = 4; Items = @(@('Eksport CSV', 'Button'), @('Eksport PDF', 'Button')) }
)

# --- Słowniki, Kosz ---------------------------------------------------------------------------------------------------
Scene '15-slowniki' { Nav 'Słowniki'; Invoke-El (Find-One 'Kategorie zakupów' $CT::ListItem); Start-Sleep 1 } @(
  @{ N = 1; Items = @(@('Dyscypliny', 'ListItem'), @('Usługi kowalskie', 'ListItem')) },
  @{ N = 2; Items = @(@('Nowa wartość…', 'Edit'), @('Dodaj', 'Button')) },
  @{ N = 3; Items = @(, @('Pensjonat', 'Edit')) },
  @{ N = 4; Items = @(@('Aktywna', 'Button'), @('Usuń', 'Button')); Pad = 4 }
)
Scene '16-kosz' { Nav 'Kosz' } @(
  @{ N = 1; Items = @(@('Przywróć', 'Button'), @('Usuń trwale', 'Button')); Pad = 4 },
  @{ N = 2; Items = @(, @('Opróżnij kosz', 'Button')) }
)

# --- Ustawienia -------------------------------------------------------------------------------------------------------
Scene '17-ustawienia' { Nav 'Ustawienia'; Scroll-Page 0 } @(
  @{ N = 1; Items = @(, @('Motyw', 'ComboBox')) },
  @{ N = 2; Items = @(@('Uruchamiaj z systemem Windows', 'Button'), @('Zamknięcie okna chowa aplikację do zasobnika', 'Button')) },
  @{ N = 3; Items = @(@('Powiadomienia Windows', 'Button'), @('Godzina dziennego powiadomienia', 'ComboBox'), @('Horyzont „nadchodzących” (dni)', 'Edit')) }
)
Scene '18-ustawienia-kopie' { Scroll-ToTop 'Kopie zapasowe' 'Text' } @(
  @{ N = 1; Items = @(@('Kopia przy zamknięciu', 'Button'), @('Kopia dzienna', 'Button')) },
  @{ N = 2; Items = @(, @('Folder kopii', 'Button')) },
  @{ N = 3; Items = @(@('Wykonaj kopię teraz', 'Button'), @('Przywróć z kopii…', 'Button')) }
)
Scene '19-ustawienia-eksport' { Scroll-ToTop 'Eksport / import' 'Text' } @(
  @{ N = 1; Items = @(@('Całość', 'RadioButton'), @('Eksportuj…', 'Button')); Grow = @(0, 22, 0, 0) },
  @{ N = 2; Items = @(, @('Importuj…', 'Button')) }
)
Scene '20-ustawienia-api' { Scroll-ToTop 'API' 'Text' } @(
  @{ N = 1; Items = @(, @('API w sieci lokalnej', 'Button')) },
  @{ N = 2; Items = @(@('Dodaj regułę zapory', 'Button'), @('Dokumentacja API', 'Button')) },
  @{ N = 3; Items = @(@('Nazwa urządzenia', 'Edit'), @('Generuj klucz', 'Button')) }
)
# The key and its QR code are those of the demo data folder - never of the user's real data.
Scene '32-klucz-api' { Scroll-ToTop 'Klucze API' 'Text'; Set-Text (Find-One 'Nazwa urządzenia' $CT::Edit) 'Telefon'; Start-Sleep 0.5
  Invoke-El (Find-One 'Generuj klucz' $CT::Button); Start-Sleep 3 } @(
  @{ N = 1; Items = @(@('Klucz API', 'Edit'), @('Kopiuj', 'Button')) },
  @{ N = 2; Items = @(, @('Kod QR z adresem i kluczem', 'Image')); Pad = 10 }
)
foreach ($name in @('Zamknij', 'OK', 'Gotowe')) { $b = Find-One $name $CT::Button; if ($b) { Invoke-El $b; Start-Sleep 1; break } }
Type-Keys '{ESC}'
Scene '21-ustawienia-autor' { Scroll-Page 100 } @(
  @{ N = 1; Items = @(, @('Autor: Piotr Glapa', $null)) },
  @{ N = 2; Items = @(, @('Przebuduj indeks wyszukiwania', 'Button')) }
)

# --- Wyszukiwanie -----------------------------------------------------------------------------------------------------
Scene '22-wyszukiwanie' { Nav 'Pulpit'; $box = Find-One 'Wyszukiwanie globalne' $CT::Edit; $box.SetFocus(); Type-Keys 'kulaw'; Start-Sleep 2 } @(
  @{ N = 1; Items = @(, @('Wyszukiwanie globalne', 'Edit')) },
  @{ N = 2; Rect = @(350, 46, 598, 568); Pad = 0 }
)
Type-Keys '{ESC}'

Get-Process ZarzadzanieKonmi -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "Zrzuty: $OutDir"
