# UI Automation helpers for the screenshots of the user manual (Windows PowerShell 5.1; save this file with a UTF-8 BOM).
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type -Namespace U -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r); public struct RECT { public int L, T, R, B; }'
Add-Type -Namespace U -Name M -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y); [DllImport("user32.dll")] public static extern void mouse_event(int f, int x, int y, int d, int e);'
$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$CT = [System.Windows.Automation.ControlType]

function Get-AppProcess { Get-Process ZarzadzanieKonmi -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1 }
function Get-AppWindow { $p = Get-AppProcess; if (-not $p) { return $null }; $AE::FromHandle($p.MainWindowHandle) }

function Find-All([string]$name, $type = $null) {
  if ($type -is [string]) { $type = $CT::$type }
  $cond = New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, $name)
  if ($type) { $cond = New-Object System.Windows.Automation.AndCondition($cond, (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $type))) }
  @((Get-AppWindow).FindAll($TS::Descendants, $cond))
}
function Find-One([string]$name, $type = $null, [int]$index = 0) { $all = Find-All $name $type; if ($all.Count -gt $index) { $all[$index] } else { $null } }

function Invoke-El($el) {
  $p = $null
  if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); return }
  if ($el.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p)) { $p.Select(); return }
  if ($el.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$p)) { $p.Toggle(); return }
  Click-El $el
}
function Click-El($el) {
  $r = $el.Current.BoundingRectangle; [U.M]::SetCursorPos([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)) | Out-Null
  Start-Sleep -Milliseconds 100; [U.M]::mouse_event(2, 0, 0, 0, 0); [U.M]::mouse_event(4, 0, 0, 0, 0); Start-Sleep -Milliseconds 300
}
function Set-Text($el, [string]$text) { $p = $null; if ($el -and $el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$p)) { $el.SetFocus(); $p.SetValue($text) } }
function Type-Keys([string]$keys) { [System.Windows.Forms.SendKeys]::SendWait($keys); Start-Sleep -Milliseconds 300 }
function Nav([string]$name) { Click-El (Find-One $name $CT::DataItem); Start-Sleep -Milliseconds 1500 }

# The page's vertical scroller (the NavigationView's ScrollViewer; the page's own one is laid out at full height).
function Get-PageScroller {
  $w = Get-AppWindow
  $c = New-Object System.Windows.Automation.PropertyCondition($AE::IsScrollPatternAvailableProperty, $true)
  $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
  foreach ($s in $w.FindAll($TS::Descendants, $c)) {
    if ($s.Current.ClassName -ne 'ScrollViewer') { continue }
    for ($e = $s; $e; $e = $walker.GetParent($e)) {
      $sp = $null
      if ($e.Current.ClassName -eq 'ScrollViewer' -and $e.TryGetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern, [ref]$sp) -and $sp.Current.VerticallyScrollable) { return $sp }
      if ($e.Current.ClassName -eq 'Frame') { break }
    }
  }
  $null
}

# Scrolls until the element named $name is near the top of the window (section headers of long pages).
function Scroll-ToTop([string]$name, $type = $null) {
  $scroller = Get-PageScroller; if (-not $scroller) { return }
  $win = (Get-AppWindow).Current.BoundingRectangle
  for ($pct = 0; $pct -le 100; $pct += 0.5) {
    $scroller.SetScrollPercent(-1, $pct); Start-Sleep -Milliseconds 60
    $el = Find-One $name $type
    if ($el) { $r = $el.Current.BoundingRectangle; if (-not $r.IsEmpty -and $r.Y -ge $win.Y + 60 -and $r.Y -le $win.Y + 140) { Start-Sleep -Milliseconds 300; return } }
  }
}
# Mouse wheel over the middle of the window: for pages whose list is taller than the window (the footer under a long list).
function Scroll-Wheel([int]$notches) {
  $r = (Get-AppWindow).Current.BoundingRectangle
  [U.M]::SetCursorPos([int]($r.X + $r.Width * 0.6), [int]($r.Y + $r.Height * 0.6)) | Out-Null; Start-Sleep -Milliseconds 200
  $step = if ($notches -lt 0) { 120 } else { -120 }
  for ($i = 0; $i -lt [Math]::Abs($notches); $i++) { [U.M]::mouse_event(0x0800, 0, 0, $step, 0); Start-Sleep -Milliseconds 25 }
  Start-Sleep -Milliseconds 600
}
function Scroll-Page([double]$percent) { $s = Get-PageScroller; if ($s) { $s.SetScrollPercent(-1, $percent); Start-Sleep -Milliseconds 500 } }

function Resize-AppWindow([int]$width, [int]$height) {
  $h = (Get-AppProcess).MainWindowHandle; [U.W]::MoveWindow($h, 40, 20, $width, $height, $true) | Out-Null; Start-Sleep -Milliseconds 800
}

# Rectangle of an element relative to the window (for the annotations).
function Get-Rect($el) {
  if (-not $el) { return $null }
  $win = (Get-AppWindow).Current.BoundingRectangle; $r = $el.Current.BoundingRectangle
  if ($r.IsEmpty) { return $null }
  [pscustomobject]@{ X = [int]($r.X - $win.X); Y = [int]($r.Y - $win.Y); W = [int]$r.Width; H = [int]$r.Height }
}

# A mark: @{ N = 1; Items = @(@('Nazwa', 'Button', 0), ...); Pad = 4 } or @{ N = 1; Rect = @(x, y, w, h) } - union of the items.
function Resolve-Mark($mark) {
  $rects = @()
  if ($mark.Rect) { $rects += [pscustomobject]@{ X = $mark.Rect[0]; Y = $mark.Rect[1]; W = $mark.Rect[2]; H = $mark.Rect[3] } }
  foreach ($item in @($mark.Items)) {
    if (-not $item) { continue }
    $type = if ($item.Count -gt 1 -and $item[1]) { $CT::($item[1]) } else { $null }
    $index = if ($item.Count -gt 2) { $item[2] } else { 0 }
    $r = Get-Rect (Find-One $item[0] $type $index)
    if ($r) { $rects += $r } else { Write-Host "  (brak elementu: $($item[0]))" }
  }
  if ($rects.Count -eq 0) { return $null }
  $pad = if ($null -ne $mark.Pad) { $mark.Pad } else { 5 }
  $grow = if ($mark.Grow) { $mark.Grow } else { @(0, 0, 0, 0) }   # extra space: left, top, right, bottom
  $x1 = ($rects | Measure-Object X -Minimum).Minimum - $pad - $grow[0]
  $y1 = ($rects | Measure-Object Y -Minimum).Minimum - $pad - $grow[1]
  $x2 = ($rects | ForEach-Object { $_.X + $_.W } | Measure-Object -Maximum).Maximum + $pad + $grow[2]
  $y2 = ($rects | ForEach-Object { $_.Y + $_.H } | Measure-Object -Maximum).Maximum + $pad + $grow[3]
  [pscustomobject]@{ N = $mark.N; X = [int]$x1; Y = [int]$y1; W = [int]($x2 - $x1); H = [int]($y2 - $y1) }
}

# Screenshot of the window with numbered frames around the marks.
function Save-AnnotatedShot([string]$path, $marks) {
  $resolved = @($marks | ForEach-Object { Resolve-Mark $_ } | Where-Object { $_ })
  $h = (Get-AppProcess).MainWindowHandle; [U.W]::SetForegroundWindow($h) | Out-Null
  [U.M]::SetCursorPos(5, 5) | Out-Null; Start-Sleep -Milliseconds 500
  $r = New-Object U.W+RECT; [U.W]::GetWindowRect($h, [ref]$r) | Out-Null
  $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
  $accent = [System.Drawing.Color]::FromArgb(255, 234, 88, 12)
  $pen = New-Object System.Drawing.Pen $accent, 3
  $fill = New-Object System.Drawing.SolidBrush $accent
  $font = New-Object System.Drawing.Font 'Segoe UI', 11, ([System.Drawing.FontStyle]::Bold)
  $format = New-Object System.Drawing.StringFormat; $format.Alignment = 'Center'; $format.LineAlignment = 'Center'
  foreach ($m in $resolved) {
    $x = [Math]::Max(2, $m.X); $y = [Math]::Max(2, $m.Y)
    $w = [Math]::Min($bmp.Width - $x - 3, $m.W); $hh = [Math]::Min($bmp.Height - $y - 3, $m.H)
    $path2 = New-Object System.Drawing.Drawing2D.GraphicsPath; $rad = 10
    $path2.AddArc($x, $y, $rad, $rad, 180, 90); $path2.AddArc($x + $w - $rad, $y, $rad, $rad, 270, 90)
    $path2.AddArc($x + $w - $rad, $y + $hh - $rad, $rad, $rad, 0, 90); $path2.AddArc($x, $y + $hh - $rad, $rad, $rad, 90, 90); $path2.CloseFigure()
    $g.DrawPath($pen, $path2)
    $size = 26; $bx = [Math]::Max(2, [Math]::Min($bmp.Width - $size - 2, $x - $size / 2)); $by = [Math]::Max(2, [Math]::Min($bmp.Height - $size - 2, $y - $size / 2))
    $g.FillEllipse($fill, $bx, $by, $size, $size)
    $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2), $bx, $by, $size, $size)
    $g.DrawString([string]$m.N, $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF $bx, ($by + 1), $size, $size), $format)
  }
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
  Write-Host ("  {0}: {1} zaznacze{2}" -f (Split-Path $path -Leaf), $resolved.Count, $(if ($resolved.Count -eq 1) { 'nie' } else { 'nia' }))
}

# Leaves an open form (drawer) without saving: "Anuluj", then "Odrzuć zmiany" when asked.
function Close-Drawer {
  $cancel = Find-One 'Anuluj' $CT::Button; if ($cancel) { Invoke-El $cancel; Start-Sleep -Milliseconds 800 }
  foreach ($name in @('Odrzuć zmiany', 'Nie zapisuj', 'Odrzuć')) { $b = Find-One $name $CT::Button; if ($b) { Invoke-El $b; Start-Sleep -Milliseconds 800; break } }
}
