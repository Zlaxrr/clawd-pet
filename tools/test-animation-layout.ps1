# Render actual production code without launching a desktop window.
param([string]$PreviewPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repo = Split-Path $PSScriptRoot -Parent
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'clawd-pet.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($fn in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Render-Pet', 'Get-GifSrc') }, $true)) {
    Invoke-Expression $fn.Extent.Text
}
$layout = $ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -in @('$script:destH', '$script:margin', '$script:formW', '$script:crabH') }, $true)
$script:gifStates = @{}; $script:gifSrc = @{}
# Load the production source rectangles, scale nudges and head anchors.
$setup = $ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and ($n.Left.Extent.Text -like '$script:gif*') }, $true)
$script:imgDance = [Drawing.Image]::FromFile((Join-Path $repo 'assets\Clawd-Dancing.gif'))
$script:imgWork = [Drawing.Image]::FromFile((Join-Path $repo 'assets\Clawd-Working.gif'))
$script:imgCook = [Drawing.Image]::FromFile((Join-Path $repo 'assets\Clawd-Cooking.gif'))
foreach ($assignment in $setup) {
    if ($assignment.Left.Extent.Text -notin @('$script:gifHeadX', '$script:gifHeadTop')) { Invoke-Expression $assignment.Extent.Text }
}
$script:imgCookIntro = [Drawing.Image]::FromFile((Join-Path $repo 'assets\Clawd-CookIntro.gif'))
$script:imgCookIntroFD = New-Object Drawing.Imaging.FrameDimension($script:imgCookIntro.FrameDimensionsList[0])
$script:imgCookIntroN = $script:imgCookIntro.GetFrameCount($script:imgCookIntroFD)
$still = [Drawing.Image]::FromFile((Join-Path $repo 'assets\Clawd-Still.png'))
$sheet = New-Object Drawing.Bitmap 990,680
$sg = [Drawing.Graphics]::FromImage($sheet)
$sg.Clear([Drawing.Color]::FromArgb(35,35,38))
$sg.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$font = New-Object Drawing.Font 'Segoe UI',14
try {
    foreach ($size in @(48,80,120,200)) {
        $script:destW = $size
        foreach ($assignment in $layout) { Invoke-Expression $assignment.Extent.Text }
        $column = 0
        foreach ($pose in @('idle','intro first','intro last','cook','work','dance')) {
            $bmp = New-Object Drawing.Bitmap $script:formW,$script:destH
            $g = [Drawing.Graphics]::FromImage($bmp)
            try {
                if ($pose -eq 'idle') {
                    $g.DrawImage($still, (New-Object Drawing.Rectangle $script:margin,0,$size,$script:destH), (New-Object Drawing.Rectangle 736,351,1200,1499), [Drawing.GraphicsUnit]::Pixel)
                } else {
                    $script:state = if ($pose -like 'intro*') { 'cook-intro' } else { $pose }
                    $script:cookIntroFrame = if ($pose -eq 'intro last') { $script:imgCookIntroN - 1 } else { 0 }
                    Render-Pet $g
                    if ($pose -in @('cook','work','intro first','intro last') -and [Math]::Abs($script:gifHeadX - $script:formW / 2.0) -gt 1) {
                        throw "$pose head shifts away from centre at size $size"
                    }
                }
                # A clipped prop would leave visible pixels on a side of the window.
                for ($y = 0; $y -lt $bmp.Height; $y++) {
                    if ($bmp.GetPixel(0,$y).A -gt 0 -or $bmp.GetPixel(($bmp.Width-1),$y).A -gt 0) { throw "$pose clipped at size $size" }
                }
                if ($size -eq 80 -and $PreviewPath) {
                    $x = ($column % 3) * 330; $y0 = [int][Math]::Floor($column / 3) * 340
                    $sg.DrawString($pose,$font,[Drawing.Brushes]::White,$x+10,$y0+5)
                    $sg.DrawImage($bmp, ($x + [int]((330-$bmp.Width*2)/2)), ($y0+35), ($bmp.Width*2), ($bmp.Height*2))
                }
            } finally { $g.Dispose(); $bmp.Dispose() }
            $column++
        }
        Write-Host "PASS size $size`: character anchors centred; pan, laptop and poses fit"
    }
    if ($PreviewPath) { $sheet.Save($PreviewPath); Write-Host "Preview: $PreviewPath" }
} finally {
    $font.Dispose(); $sg.Dispose(); $sheet.Dispose(); $still.Dispose()
    $script:imgDance.Dispose(); $script:imgWork.Dispose(); $script:imgCook.Dispose(); $script:imgCookIntro.Dispose()
}
