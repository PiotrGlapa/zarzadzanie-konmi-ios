# Generuje ikonę aplikacji Horsely (SG 5.4): biała podkowa z 6 otworami na ukośnym gradiencie, 1024 x 1024 bez przezroczystości.
# Trzy warianty iOS 18: jasny (domyślny), ciemny i barwiony (skala szarości). Działa w Windows PowerShell 5.1 i pwsh (System.Drawing).
# Użycie: scripts\generate-app-icon.ps1 [-OutDir App\Resources\Assets.xcassets\AppIcon.appiconset]
param(
    [string]$OutDir = (Join-Path $PSScriptRoot '..\App\Resources\Assets.xcassets\AppIcon.appiconset')
)

Add-Type -AssemblyName System.Drawing

# Siatka 256 z ic_launcher_foreground.xml Androida; skala 4 daje podkowę o szerokości ok. 61 % obrazu (624 z 1024 px).
$scale = 4.0
$shoe = 'M78,198 C60,180 50,155 50,128 C50,84 85,50 128,50 C171,50 206,84 206,128 C206,155 196,180 178,198 C172,204 160,204 156,196 C168,178 176,154 176,130 C176,100 155,78 128,78 C101,78 80,100 80,130 C80,154 88,178 100,196 C96,204 84,204 78,198 Z'
$holes = @(@(67, 160), @(65, 128), @(74, 96), @(189, 160), @(191, 128), @(182, 96))
$holeRadius = 4.5

function New-ShoePath {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath([System.Drawing.Drawing2D.FillMode]::Alternate)
    $tokens = [regex]::Matches($shoe, '[MCZ]|-?\d+(\.\d+)?') | ForEach-Object { $_.Value }
    $i = 0
    $current = $null
    $startPoint = $null
    function Read-Point([ref]$index) {
        $x = [single]([double]::Parse($tokens[$index.Value], [Globalization.CultureInfo]::InvariantCulture) * $scale)
        $y = [single]([double]::Parse($tokens[$index.Value + 1], [Globalization.CultureInfo]::InvariantCulture) * $scale)
        $index.Value += 2
        New-Object System.Drawing.PointF($x, $y)
    }
    while ($i -lt $tokens.Count) {
        $cmd = $tokens[$i]; $i++
        switch ($cmd) {
            'M' { $current = Read-Point ([ref]$i); $startPoint = $current; $path.StartFigure() }
            'C' {
                # Po „C” może następować kilka trójek punktów (powtórzenie polecenia bez litery).
                while ($i -lt $tokens.Count -and $tokens[$i] -notmatch '^[MCZ]$') {
                    $p1 = Read-Point ([ref]$i); $p2 = Read-Point ([ref]$i); $p3 = Read-Point ([ref]$i)
                    $path.AddBezier($current, $p1, $p2, $p3)
                    $current = $p3
                }
            }
            'Z' { $path.CloseFigure() }
        }
    }
    foreach ($h in $holes) {
        $r = $holeRadius * $scale
        $path.AddEllipse([single]($h[0] * $scale - $r), [single]($h[1] * $scale - $r), [single]($r * 2), [single]($r * 2))
    }
    return $path
}

function Save-Icon([string]$file, [System.Drawing.Color]$from, [System.Drawing.Color]$to, [System.Drawing.Color]$shoeColor) {
    $bmp = New-Object System.Drawing.Bitmap(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rect = New-Object System.Drawing.Rectangle(0, 0, 1024, 1024)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $from, $to, 45.0)
    $bg.WrapMode = [System.Drawing.Drawing2D.WrapMode]::TileFlipXY   # bez ciemnej krawędzi na brzegu obrazu
    $g.FillRectangle($bg, -2, -2, 1028, 1028)
    $path = New-ShoePath
    $fill = New-Object System.Drawing.SolidBrush($shoeColor)
    $g.FillPath($fill, $path)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $fill.Dispose(); $path.Dispose(); $bg.Dispose(); $g.Dispose(); $bmp.Dispose()
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$c = [System.Drawing.ColorTranslator]
Save-Icon (Join-Path $OutDir 'AppIcon.png') $c::FromHtml('#2C7756') $c::FromHtml('#1D553E') ([System.Drawing.Color]::White)
Save-Icon (Join-Path $OutDir 'AppIcon-Dark.png') $c::FromHtml('#1B4A37') $c::FromHtml('#10301F') $c::FromHtml('#E8F1EC')
Save-Icon (Join-Path $OutDir 'AppIcon-Tinted.png') $c::FromHtml('#555555') $c::FromHtml('#2B2B2B') ([System.Drawing.Color]::White)

$contents = @'
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-Dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIcon-Tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $OutDir 'Contents.json'), $contents.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "Zapisano ikony w $OutDir"
