# YTDL 앱 아이콘 원본(PNG) 생성기. System.Drawing 만 사용한다.
#   .\tool\make_icon.ps1  ->  assets\icon\icon.png / icon_fg.png / icon_bg.png
# 이후 `dart run flutter_launcher_icons` 가 Android/Windows 아이콘을 만든다.
#
# 디자인: 붉은 그라데이션 바탕 위에 흰색 "음파 막대 + 아래 화살표 + 받침대"
#         = 소리를 받아서 저장한다는 뜻. 유튜브 로고와 겹치지 않게 재생 버튼은 쓰지 않는다.
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
    $c1 = [System.Drawing.Color]::FromArgb(255, 0xF0, 0x4A, 0x45)
    $c2 = [System.Drawing.Color]::FromArgb(255, 0xA9, 0x1B, 0x1B)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $c1, $c2, 55
    $g.FillPath($br, $path)
    $br.Dispose()
}

# 흰색 심볼. $k 는 중심(512,512) 기준 축소 배율.
function Draw-Art($g, [float]$k) {
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate(512, 512)
    $m.Scale($k, $k)
    $m.Translate(-512, -512 + 6)
    $g.Transform = $m

    # 음파 막대 7개 (높이를 불규칙하게 해서 손가락이 아니라 소리 파형처럼 보이게)
    $heights = 130, 270, 200, 420, 260, 340, 160
    $bw = 56; $gap = 34
    $n = $heights.Count
    $total = $n * $bw + ($n - 1) * $gap
    $x0 = (1024 - $total) / 2
    $cy = 380
    for ($i = 0; $i -lt $n; $i++) {
        $h = $heights[$i]
        $p = New-RoundRectPath ($x0 + $i * ($bw + $gap)) ($cy - $h / 2) $bw $h ($bw / 2)
        $g.FillPath($white, $p); $p.Dispose()
    }
    # 아래 화살표(삼각형)
    $tri = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF 352, 646),
        (New-Object System.Drawing.PointF 672, 646),
        (New-Object System.Drawing.PointF 512, 790))
    $g.FillPolygon($white, $tri)
    # 받침대
    $tray = New-RoundRectPath 290 836 444 56 28
    $g.FillPath($white, $tray); $tray.Dispose()
    $g.ResetTransform()
    $white.Dispose()
}

# 1) icon.png : 둥근 사각형 바탕 + 심볼 (Windows·구형 Android 용)
$c = New-Canvas
$bg = New-RoundRectPath 0 0 $S $S 230
Fill-Gradient $c.G $bg
Draw-Art $c.G 1.0
$c.Bmp.Save((Join-Path $out 'icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$c.G.Dispose(); $c.Bmp.Dispose()

# 2) icon_bg.png : 어댑티브 아이콘 배경(전체 채움 그라데이션)
$c = New-Canvas
$full = New-RoundRectPath 0 0 $S $S 0
Fill-Gradient $c.G $full
$c.Bmp.Save((Join-Path $out 'icon_bg.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$c.G.Dispose(); $c.Bmp.Dispose()

# 3) icon_fg.png : 어댑티브 아이콘 전경(투명 바탕, 안전 영역에 맞게 축소)
$c = New-Canvas
Draw-Art $c.G 0.74
$c.Bmp.Save((Join-Path $out 'icon_fg.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$c.G.Dispose(); $c.Bmp.Dispose()

Write-Host "아이콘 원본 생성 완료: $out"
