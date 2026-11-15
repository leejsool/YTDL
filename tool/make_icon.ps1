# YTDL 앱 아이콘 원본(PNG) 생성기. System.Drawing 만 사용한다.
#   .\tool\make_icon.ps1  ->  assets\icon\icon.png / icon_fg.png / icon_bg.png
# 이후 `dart run flutter_launcher_icons` 가 Android/Windows 아이콘을 만든다.
#
# 디자인: 보라색 바탕 위에서 빨간 재생 표시가 있는 카드가 다운로드함으로 들어간다.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$out = Join-Path $PSScriptRoot '..\assets\icon'
New-Item -ItemType Directory -Force $out | Out-Null
$S = 1024

function New-RoundRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($r -le 0) {
        $p.AddRectangle((New-Object System.Drawing.RectangleF $x, $y, $w, $h))
        return $p
    }
    $d = [Math]::Min($r * 2, [Math]::Min($w, $h))
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-Canvas {
    $bmp = New-Object System.Drawing.Bitmap $S, $S, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)
    return @{ Bmp = $bmp; G = $g }
}

function Fill-Gradient($g, $path) {
    $rect = New-Object System.Drawing.RectangleF 0, 0, $S, $S
    $c1 = [System.Drawing.ColorTranslator]::FromHtml('#9974FA')
    $c2 = [System.Drawing.ColorTranslator]::FromHtml('#442B9D')
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $c1, $c2, 61.0)
    try { $g.FillPath($brush, $path) } finally { $brush.Dispose() }
}

function Fill-RoundedRect($g, [string]$color, [float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $path = New-RoundRectPath $x $y $w $h $r
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($color))
    try { $g.FillPath($brush, $path) } finally { $brush.Dispose(); $path.Dispose() }
}

function Fill-Polygon($g, [string]$color, [float[]]$coordinates) {
    $points = for ($i = 0; $i -lt $coordinates.Length; $i += 2) {
        [System.Drawing.PointF]::new($coordinates[$i], $coordinates[$i + 1])
    }
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($color))
    try { $g.FillPolygon($brush, [System.Drawing.PointF[]]$points) } finally { $brush.Dispose() }
}

# 100×100 좌표의 다운로드함. $scale 은 가운데를 기준으로 전경을 축소하는 배율.
function Draw-Art($g, [float]$scale) {
    $artState = $g.Save()
    $unit = $S / 100
    $g.ScaleTransform($unit, $unit)
    $g.TranslateTransform(50, 50)
    $g.ScaleTransform($scale, $scale)
    $g.TranslateTransform(-50, -50)

    $cardState = $g.Save()
    $g.TranslateTransform(51, 48)
    $g.RotateTransform(-11)
    $g.TranslateTransform(-51, -48)
    Fill-RoundedRect $g '#5133A6' 29 26 46 42 8
    Fill-RoundedRect $g '#FAF6FF' 27 22 46 42 8
    Fill-Polygon $g '#F14962' @(45, 32, 45, 52, 61, 42)
    $g.Restore($cardState)

    Fill-RoundedRect $g '#442C94' 20 59 60 25 9
    Fill-RoundedRect $g '#CAB3FF' 19 56 62 25 9
    Fill-Polygon $g '#E7DBFF' @(20, 61, 37, 61, 43, 68, 57, 68, 63, 61, 80, 61, 80, 73, 75, 80, 25, 80, 20, 73)
    Fill-RoundedRect $g '#916ACE' 42.85 72.85 14.3 2.3 1.15
    $g.Restore($artState)
}

# 1) icon.png : 둥근 사각형 바탕 + 심볼 (Windows·구형 Android 용)
$c = New-Canvas
$bg = New-RoundRectPath ($S * 0.01) ($S * 0.01) ($S * 0.98) ($S * 0.98) ($S * 0.23)
Fill-Gradient $c.G $bg
$rim = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#8C70E6'), [float]($S * 0.0075))
$c.G.DrawPath($rim, $bg)
$rim.Dispose(); $bg.Dispose()
Draw-Art $c.G 1.0
$c.Bmp.Save((Join-Path $out 'icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$c.G.Dispose(); $c.Bmp.Dispose()

# 2) icon_bg.png : 어댑티브 아이콘 배경(전체 채움 그라데이션)
$c = New-Canvas
$full = New-RoundRectPath 0 0 $S $S 0
Fill-Gradient $c.G $full
$full.Dispose()
$c.Bmp.Save((Join-Path $out 'icon_bg.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$c.G.Dispose(); $c.Bmp.Dispose()

# 3) icon_fg.png : 어댑티브 아이콘 전경(투명 바탕, 안전 영역에 맞게 축소)
$c = New-Canvas
Draw-Art $c.G 0.74
$c.Bmp.Save((Join-Path $out 'icon_fg.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$c.G.Dispose(); $c.Bmp.Dispose()

Write-Host "아이콘 원본 생성 완료: $out"
