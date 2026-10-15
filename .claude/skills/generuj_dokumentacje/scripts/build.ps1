# Builds the user manual PDF: demo data -> annotated screenshots -> HTML from template/instrukcja.html -> PDF (Edge).
# Usage (repository root, Windows PowerShell 5.1):
#   build.ps1 [-Highlight terminy,treningi,zawody,konfiguracja,raporty] [-Exe <ZarzadzanieKonmi.exe>] [-Author 'Piotr Glapa'] [-SkipCapture]
# Highlight keys: terminy (Pulpit + Terminy), treningi, zawody, konfiguracja (Słowniki + Ustawienia), raporty, konie, zakupy, kontakty, kosz.
param(
  [string[]]$Highlight = @('terminy', 'treningi', 'zawody', 'konfiguracja', 'raporty'),
  [string]$Exe = "$env:LOCALAPPDATA\Programs\ZarzadzanieKonmi\ZarzadzanieKonmi.exe",
  [string]$Author = 'Piotr Glapa',
  [string]$Version,
  [string]$WorkDir = "$env:TEMP\zk-docs",
  [string]$OutDir,
  [switch]$SkipCapture,
  [switch]$Dump   # also writes <scene>.txt with the names and positions of the controls (for fixing the marks)
)
$ErrorActionPreference = 'Stop'
$skill = Split-Path $PSScriptRoot -Parent
$repo = (Resolve-Path (Join-Path $skill '..\..\..')).Path
if (-not $OutDir) { $OutDir = Join-Path $repo 'docs' }
if (-not $Version) { $Version = ([xml](Get-Content (Join-Path $repo 'Directory.Build.props') -Raw)).Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1 }
$Highlight = @($Highlight | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$demoProject = Join-Path $skill 'tools\DemoData\DemoData.csproj'
$shots = Join-Path $WorkDir 'shots'
New-Item -ItemType Directory -Force $WorkDir, $OutDir | Out-Null
Write-Host "Instrukcja obsługi $Version, wyróżnione: $($Highlight -join ', ')"

# 1. Demo data and screenshots ----------------------------------------------------------------------------------------
if (-not $SkipCapture) {
  if (-not (Test-Path $Exe)) { throw "Nie znaleziono programu: $Exe" }
  $data = Join-Path $WorkDir 'dane'
  Get-Process ZarzadzanieKonmi -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep 1
  if (Test-Path $data) { Remove-Item -Recurse -Force $data }
  dotnet run --project (Join-Path $repo 'tools\ZarzadzanieKonmi.Seed') -- --data-dir $data --horses 8 --entries 400 --backup-folder (Join-Path $data 'Kopie')
  if ($LASTEXITCODE) { throw 'Zasiew danych nie powiódł się.' }
  $db = Get-Item (Join-Path $data 'data\konie.db')
  dotnet run --project $demoProject -- $db.FullName
  if ($LASTEXITCODE) { throw 'Dane pokazowe nie zostały dodane.' }
  & (Join-Path $PSScriptRoot 'capture.ps1') -Exe $Exe -DataDir $data -OutDir $shots -Dump:$Dump
}
if (-not (Test-Path (Join-Path $shots '01-okno.png'))) { throw "Brak zrzutów w $shots (uruchom bez -SkipCapture)." }

# 2. Icon font and logo -----------------------------------------------------------------------------------------------
$fonts = Join-Path $WorkDir 'fonts'
if (-not (Test-Path (Join-Path $fonts 'fluentsystemicons-regular.ttf'))) {
  $wpfUi = Get-ChildItem "$env:USERPROFILE\.nuget\packages\wpf-ui" -Recurse -Filter Wpf.Ui.dll | Where-Object FullName -match 'net\d+\.0-windows' | Sort-Object FullName -Descending | Select-Object -First 1
  if (-not $wpfUi) { throw 'Nie znaleziono Wpf.Ui.dll w pakietach NuGet (zbuduj najpierw rozwiązanie).' }
  dotnet run --project $demoProject -- --fonts $wpfUi.FullName $fonts
  if ($LASTEXITCODE) { throw 'Nie udało się wyciągnąć czcionki ikon.' }
}
Add-Type -AssemblyName System.Drawing
$logo = Join-Path $WorkDir 'logo.png'
# The largest frame of app.ico (the 256 px one is stored as PNG, which System.Drawing.Icon cannot convert).
$ico = [System.IO.File]::ReadAllBytes((Join-Path $repo 'src\ZarzadzanieKonmi.Desktop\Resources\app.ico'))
$frames = for ($i = 0; $i -lt [BitConverter]::ToUInt16($ico, 4); $i++) {
  $e = 6 + 16 * $i; $size = if ($ico[$e] -eq 0) { 256 } else { $ico[$e] }
  [pscustomobject]@{ Size = $size; Length = [BitConverter]::ToInt32($ico, $e + 8); Offset = [BitConverter]::ToInt32($ico, $e + 12) }
}
$frame = $frames | Sort-Object Size -Descending | Select-Object -First 1
if ($ico[$frame.Offset] -eq 0x89) { [System.IO.File]::WriteAllBytes($logo, $ico[$frame.Offset..($frame.Offset + $frame.Length - 1)]) }
else { $icon = New-Object System.Drawing.Icon (Join-Path $repo 'src\ZarzadzanieKonmi.Desktop\Resources\app.ico'), 128, 128; $icon.ToBitmap().Save($logo, [System.Drawing.Imaging.ImageFormat]::Png); $icon.Dispose() }

# 3. HTML -------------------------------------------------------------------------------------------------------------
$uri = { param($p) ([System.Uri](Resolve-Path $p).Path).AbsoluteUri }
$html = [System.IO.File]::ReadAllText((Join-Path $skill 'template\instrukcja.html'), [System.Text.Encoding]::UTF8)
$html = $html.Replace('{{WERSJA}}', $Version).Replace('{{AUTOR}}', $Author).Replace('{{DATA}}', (Get-Date).ToString('d MMMM yyyy', [Globalization.CultureInfo]'pl-PL'))
$html = $html.Replace('{{FONT}}', (& $uri (Join-Path $fonts 'fluentsystemicons-regular.ttf'))).Replace('{{LOGO}}', (& $uri $logo)).Replace('{{IMG}}', (& $uri $shots))
# Highlighted chapters get the orange header and the "Dlaczego warto" box; the others lose the star in the table of contents.
$html = [regex]::Replace($html, 'data-feature="([a-z]+)"', { param($m) if ($Highlight -contains $m.Groups[1].Value) { $m.Value + ' data-highlight="true"' } else { $m.Value } })
$html = [regex]::Replace($html, '<span class="gwiazdka" data-star="([a-z]+)">[^<]*</span>', { param($m) if ($Highlight -contains $m.Groups[1].Value) { $m.Value } else { '' } })
$html = [regex]::Replace($html, 'class="kafel" data-tile="([a-z]+)"', { param($m) if ($Highlight -contains $m.Groups[1].Value) { 'class="kafel wyrozniony"' } else { 'class="kafel"' } })
$page = Join-Path $WorkDir 'instrukcja.html'
[System.IO.File]::WriteAllText($page, $html, (New-Object System.Text.UTF8Encoding $true))

# 4. PDF --------------------------------------------------------------------------------------------------------------
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'Nie znaleziono Microsoft Edge.' }
$pdf = Join-Path $OutDir "Instrukcja-obslugi-Zarzadzanie-konmi-v$Version.pdf"
if (Test-Path $pdf) { Remove-Item $pdf }
$profile = Join-Path $WorkDir 'edge-profile'
$edgeArgs = @('--headless', '--disable-gpu', '--no-first-run', "--user-data-dir=`"$profile`"", '--allow-file-access-from-files',
  '--no-pdf-header-footer', '--virtual-time-budget=5000', "--print-to-pdf=`"$pdf`"", "`"$(& $uri $page)`"")
Start-Process $edge -ArgumentList $edgeArgs -Wait -WindowStyle Hidden
if (-not (Test-Path $pdf)) { throw 'Edge nie utworzył pliku PDF.' }
Write-Host "Gotowe: $pdf ($([int]((Get-Item $pdf).Length / 1KB)) KB)"
