# Pratinjau visual gelembung "Claude Watch" — render semua state ke satu PNG.
# Menyalin logika Build-StatusBubble dari clawd-pet.ps1 (titik denyut digambar statis di sini).
Add-Type -AssemblyName System.Drawing

$termBrush     = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40, 38, 35))
$termPen       = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(217, 119, 87))
$termTextBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, 238, 229))
$coral         = [System.Drawing.Color]::FromArgb(217, 119, 87)
$font          = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Regular)
$tail          = 7
$text = @{
    'think' = 'thinking...'; 'bash' = 'running a command...'; 'edit' = 'writing code...'
    'read' = 'reading files...'; 'web' = 'browsing the web...'; 'task' = 'spinning up an agent...'
    'notify' = 'needs your input...'; 'done' = 'brewed at 14:32'
}

$fmt = [System.Drawing.StringFormat]::GenericTypographic.Clone()
$fmt.FormatFlags = $fmt.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces
function New-RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc(($x + $w - $d), $y, $d, $d, 270, 90)
    $p.AddArc(($x + $w - $d), ($y + $h - $d), $d, $d, 0, 90); $p.AddArc($x, ($y + $h - $d), $d, $d, 90, 90)
    $p.CloseFigure(); return $p
}
function Draw-ClaudeSpark($g, [single]$cx, [single]$cy, [int]$alpha) {
    $col = [System.Drawing.Color]::FromArgb($alpha, 217, 119, 87)
    $br = New-Object System.Drawing.SolidBrush $col
    $st = $g.Save(); $g.SmoothingMode = 'AntiAlias'; $g.TranslateTransform($cx, $cy)
    $r=[single]5.0; $wid=[single]($r*0.26); $waist=[single]($r*0.34)
    $spike = New-Object 'System.Drawing.PointF[]' 4
    foreach ($ang in 90, 270, 45, 135, 225, 315) {
        $s=$g.Save(); $g.RotateTransform([single]$ang)
        $spike[0]=New-Object System.Drawing.PointF 0,0
        $spike[1]=New-Object System.Drawing.PointF $waist,(-$wid)
        $spike[2]=New-Object System.Drawing.PointF $r,0
        $spike[3]=New-Object System.Drawing.PointF $waist,$wid
        $g.FillPolygon($br,$spike); $g.Restore($s)
    }
    $g.Restore($st); $br.Dispose()
}
function Build([string]$tok) {
    $txt = $text[$tok]; $done = ($tok -eq 'done')
    $mB = New-Object System.Drawing.Bitmap 1, 1; $mG = [System.Drawing.Graphics]::FromImage($mB)
    $ts = $mG.MeasureString($txt, $font, [int]1000, $fmt); $mG.Dispose(); $mB.Dispose()
    $tw = [int][Math]::Ceiling($ts.Width); $th = [int][Math]::Ceiling($ts.Height)
    $padL = 27; $padR = 13; $padV = 5; $rad = 9
    $w = $tw + $padL + $padR; $h = $th + 2 * $padV
    $bmp = New-Object System.Drawing.Bitmap ([int]$w), ([int]($h + $tail)), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
    $rr = New-RoundRect 0.5 0.5 ([single]($w - 1)) ([single]($h - 1)) $rad
    $g.FillPath($termBrush, $rr); $g.DrawPath($termPen, $rr); $rr.Dispose()
    $cxq = [single]($w / 2.0)
    $tri = New-Object 'System.Drawing.PointF[]' 3
    $tri[0] = New-Object System.Drawing.PointF (($cxq - 6), ([single]($h - 1)))
    $tri[1] = New-Object System.Drawing.PointF (($cxq + 6), ([single]($h - 1)))
    $tri[2] = New-Object System.Drawing.PointF ($cxq, ([single]($h + $tail - 1)))
    $g.FillPolygon($termBrush, $tri); $g.DrawLine($termPen, $tri[0], $tri[2]); $g.DrawLine($termPen, $tri[1], $tri[2])
    $g.FillRectangle($termBrush, [single]($cxq - 5.5), [single]($h - 2), 11, 3)
    $iy = [single]($h / 2.0)
    if ($done) {
        $cp = New-Object System.Drawing.Pen $coral, 1.9
        $g.DrawLines($cp, @((New-Object System.Drawing.PointF 8, $iy), (New-Object System.Drawing.PointF 11, ($iy + 3)), (New-Object System.Drawing.PointF 16, ($iy - 4))))
        $cp.Dispose()
    } else {
        Draw-ClaudeSpark $g 14 $iy 255
    }
    $g.DrawString($txt, $font, $termTextBrush, [single]($padL - 2), [single](($h - $th) / 2.0), $fmt); $g.Dispose()
    return $bmp
}

$order = @('think', 'bash', 'edit', 'read', 'web', 'task', 'notify', 'done')
$bubbles = $order | ForEach-Object { Build $_ }
$maxW = ($bubbles | ForEach-Object { $_.Width } | Measure-Object -Maximum).Maximum
$gap = 14; $padOut = 24
$totalH = $padOut * 2 + (($bubbles | ForEach-Object { $_.Height } | Measure-Object -Sum).Sum) + $gap * ($bubbles.Count - 1)
$canvas = New-Object System.Drawing.Bitmap ([int]($maxW + $padOut * 2)), ([int]$totalH)
$cg = [System.Drawing.Graphics]::FromImage($canvas)
$cg.Clear([System.Drawing.Color]::FromArgb(28, 26, 24))   # latar gelap desktop
$y = $padOut
foreach ($b in $bubbles) {
    $cg.DrawImage($b, [int](($canvas.Width - $b.Width) / 2), [int]$y)
    $y += $b.Height + $gap
}
$cg.Dispose()
$outPath = Join-Path $env:TEMP 'clawd-bubble-preview.png'
$canvas.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output $outPath
