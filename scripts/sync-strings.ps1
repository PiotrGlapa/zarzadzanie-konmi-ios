# Teksty interfejsu: strings.xml / plurals.xml z Androida -> App/Resources/Localizable.xcstrings (research R10).
#
# Tryby:
#   scripts\sync-strings.ps1 -AndroidRepo ..\zarzadzanie_konmi_android   kopiuje pliki z Androida do App/Resources/android/
#                                                                         i generuje Localizable.xcstrings
#   scripts\sync-strings.ps1                                              generuje Localizable.xcstrings z zatwierdzonych kopii
#   scripts\sync-strings.ps1 -Check                                       generuje w pamięci i porównuje z zatwierdzonym plikiem
#                                                                         (kod wyjścia 1 przy różnicy) — krok CI
#
# Działa w Windows PowerShell 5.1 i pwsh (macOS). Wynik jest bajt w bajt taki sam w obu (własny zapis JSON, UTF-8 bez BOM, LF).
#
# Reguły przeniesienia (jak w Androidzie / aapt):
#   - klucze = nazwy z Androida; polski jest językiem źródłowym
#   - %1$s -> %1$@, %1$d -> %1$lld, %s -> %@, %d -> %lld, %% bez zmian
#   - liczba mnoga PL: one / few / many / other (wariant plural w xcstrings)
#   - znaki specjalne Androida: \n, \t, \', \", \\, \@, \?, \uXXXX; białe znaki poza cudzysłowem scalane do jednej spacji
#   - odwołania @string/nazwa są podstawiane wartością
[CmdletBinding()]
param(
    [string]$AndroidRepo,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$copyDir = Join-Path $root 'App/Resources/android'
$outFile = Join-Path $root 'App/Resources/Localizable.xcstrings'
$sourceFiles = @('strings.xml', 'plurals.xml')

if ($AndroidRepo) {
    if ($Check) { throw 'Przełączniki -AndroidRepo i -Check wykluczają się: sprawdzenie porównuje z zatwierdzonymi kopiami.' }
    $resDir = Join-Path $AndroidRepo 'app/src/main/res/values'
    foreach ($f in $sourceFiles) {
        if (-not (Test-Path (Join-Path $resDir $f))) { throw "Brak pliku $f w $resDir" }
    }
    New-Item -ItemType Directory -Force -Path $copyDir | Out-Null
    foreach ($f in $sourceFiles) {
        Copy-Item -LiteralPath (Join-Path $resDir $f) -Destination (Join-Path $copyDir $f) -Force
    }
}

foreach ($f in $sourceFiles) {
    if (-not (Test-Path (Join-Path $copyDir $f))) {
        throw "Brak $copyDir\$f — uruchom z -AndroidRepo ..\zarzadzanie_konmi_android"
    }
}

function ConvertFrom-AndroidText([string]$raw) {
    $sb = New-Object System.Text.StringBuilder
    $inQuote = $false
    $pendingSpace = $false
    $i = 0
    while ($i -lt $raw.Length) {
        $c = $raw[$i]
        if ($c -eq '\' -and ($i + 1) -lt $raw.Length) {
            $n = $raw[$i + 1]
            $i += 2
            if ($pendingSpace -and $sb.Length -gt 0) { [void]$sb.Append(' ') }
            $pendingSpace = $false
            switch ($n) {
                'n' { [void]$sb.Append("`n") }
                't' { [void]$sb.Append("`t") }
                'u' {
                    $hex = $raw.Substring($i, 4)
                    [void]$sb.Append([char][Convert]::ToInt32($hex, 16))
                    $i += 4
                }
                default { [void]$sb.Append($n) }
            }
            continue
        }
        if ($c -eq '"') { $inQuote = -not $inQuote; $i++; continue }
        if (-not $inQuote -and ($c -eq ' ' -or $c -eq "`t" -or $c -eq "`r" -or $c -eq "`n")) {
            $pendingSpace = $true
            $i++
            continue
        }
        if ($pendingSpace -and $sb.Length -gt 0) { [void]$sb.Append(' ') }
        $pendingSpace = $false
        [void]$sb.Append($c)
        $i++
    }
    return $sb.ToString()
}

function ConvertTo-AppleFormat([string]$text) {
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        if ($m.Value -eq '%%') { return '%%' }
        $position = $m.Groups[1].Value
        $flags = $m.Groups[2].Value
        $width = $m.Groups[3].Value
        $precision = $m.Groups[4].Value
        switch ($m.Groups[5].Value) {
            's' { return "%$position$flags$width$precision@" }
            'd' { return "%$position$flags$width$precision" + 'lld' }
            default { return $m.Value }
        }
    }
    return [regex]::Replace($text, '%%|%(\d+\$)?([-+0 #]*)(\d*)(\.\d+)?([sdf])', $evaluator)
}

function ConvertTo-JsonString([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            '"' { [void]$sb.Append('\"') }
            '\' { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default {
                if ([int]$ch -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Zapis w stylu Xcode: wcięcie 2 spacje, „"klucz" : wartość”.
function ConvertTo-XcodeJson($node, [int]$level) {
    $pad = '  ' * ($level + 1)
    $padEnd = '  ' * $level
    if ($node -is [System.Collections.IDictionary]) {
        if ($node.Count -eq 0) { return '{' + "`n" + $padEnd + '}' }
        $parts = foreach ($k in $node.Keys) { $pad + (ConvertTo-JsonString $k) + ' : ' + (ConvertTo-XcodeJson $node[$k] ($level + 1)) }
        return '{' + "`n" + ($parts -join (",`n")) + "`n" + $padEnd + '}'
    }
    return (ConvertTo-JsonString ([string]$node))
}

function New-StringUnit([string]$value) {
    return [ordered]@{ stringUnit = [ordered]@{ state = 'translated'; value = $value } }
}

$strings = @{}
$plurals = @{}
foreach ($f in $sourceFiles) {
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $false
    $xml.Load((Join-Path $copyDir $f))
    foreach ($node in $xml.DocumentElement.ChildNodes) {
        if ($node.NodeType -ne 'Element') { continue }
        $name = $node.GetAttribute('name')
        if ($strings.ContainsKey($name) -or $plurals.ContainsKey($name)) { throw "Zdublowany klucz '$name' ($f)" }
        if ($node.LocalName -eq 'string') {
            $strings[$name] = ConvertFrom-AndroidText $node.InnerText
        } elseif ($node.LocalName -eq 'plurals') {
            $items = @{}
            foreach ($item in $node.ChildNodes) {
                if ($item.NodeType -ne 'Element') { continue }
                $items[$item.GetAttribute('quantity')] = ConvertFrom-AndroidText $item.InnerText
            }
            foreach ($q in @('one', 'few', 'many', 'other')) {
                if (-not $items.ContainsKey($q)) { throw "Liczba mnoga '$name' nie ma wariantu '$q' ($f)" }
            }
            $plurals[$name] = $items
        } else {
            throw "Nieobsługiwany element <$($node.LocalName)> '$name' ($f)"
        }
    }
}

# Odwołania @string/nazwa (np. mode_choice_title -> app_full_name)
foreach ($name in @($strings.Keys)) {
    $value = $strings[$name]
    $guard = 0
    while ($value -match '^@string/(.+)$') {
        $target = $Matches[1]
        if (-not $strings.ContainsKey($target)) { throw "Odwołanie @string/$target w '$name' nie istnieje" }
        $value = $strings[$target]
        if (++$guard -gt 5) { throw "Pętla odwołań w '$name'" }
    }
    $strings[$name] = $value
}

$keys = @($strings.Keys) + @($plurals.Keys)
[Array]::Sort($keys, [StringComparer]::Ordinal)

$entries = [ordered]@{}
foreach ($k in $keys) {
    if ($strings.ContainsKey($k)) {
        $localization = New-StringUnit (ConvertTo-AppleFormat $strings[$k])
    } else {
        $variants = [ordered]@{}
        foreach ($q in @('few', 'many', 'one', 'other')) { $variants[$q] = New-StringUnit (ConvertTo-AppleFormat $plurals[$k][$q]) }
        $localization = [ordered]@{ variations = [ordered]@{ plural = $variants } }
    }
    $entries[$k] = [ordered]@{
        extractionState = 'manual'
        localizations = [ordered]@{ pl = $localization }
    }
}

$document = [ordered]@{
    sourceLanguage = 'pl'
    strings = $entries
    version = '1.0'
}
$json = (ConvertTo-XcodeJson $document 0) + "`n"

if ($Check) {
    $current = if (Test-Path $outFile) { [System.IO.File]::ReadAllText($outFile, (New-Object System.Text.UTF8Encoding($false))) } else { '' }
    if ($current -ne $json) {
        Write-Error 'Localizable.xcstrings różni się od wyniku z App/Resources/android/*.xml — uruchom scripts/sync-strings.ps1 i zatwierdź zmianę.'
        exit 1
    }
    Write-Output "Localizable.xcstrings zgodny ($($strings.Count) tekstów, $($plurals.Count) liczb mnogich)."
    exit 0
}

[System.IO.File]::WriteAllText($outFile, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "Zapisano $outFile ($($strings.Count) tekstów, $($plurals.Count) liczb mnogich)."
