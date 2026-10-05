# Windows PowerShell 5.1; isolated downloads with mocked HTTP 200 responses.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'asset-validation.ps1')
function Assert($Value, [string]$Message) { if (-not $Value) { throw $Message }; Write-Host "PASS $Message" }
$repo = Split-Path $PSScriptRoot -Parent
$root = Join-Path ([IO.Path]::GetTempPath()) ('clawd-assets-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $root 'tools'))
[void][IO.Directory]::CreateDirectory((Join-Path $root 'assets'))
try {
    Copy-Item (Join-Path $repo 'download-assets.ps1') $root
    Copy-Item (Join-Path $PSScriptRoot 'asset-validation.ps1') (Join-Path $root 'tools')
    $html = '<!doctype html>' + ('not an image ' * 1000)
    $bad = Join-Path $root 'assets\Clawd-Working.gif'
    [IO.File]::WriteAllText($bad, $html)
    Assert (-not (Test-ClawdAsset $bad)) 'Reject HTML larger than the old 5 KB threshold'
    Assert (-not (Test-ClawdAsset (Join-Path $root 'missing.gif'))) 'Reject missing files'
    $truncated = Join-Path $root 'truncated.gif'
    [IO.File]::WriteAllText($truncated, 'GIF89a')
    Assert (-not (Test-ClawdAsset $truncated)) 'Reject a GIF header without image data'
    $wrong = Join-Path $root 'wrong.gif'
    Copy-Item (Join-Path $repo 'assets\Clawd-Still.png') $wrong
    Assert (-not (Test-ClawdAsset $wrong)) 'Reject PNG content named as GIF'
    $tiny = Join-Path $root 'tiny.png'
    $bitmap = New-Object System.Drawing.Bitmap 1, 1
    $bitmap.Save($tiny, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    Assert (Test-ClawdAsset $tiny) 'Accept a real image smaller than 5 KB'
    [IO.File]::Delete($tiny)
    Assert (-not (Test-Path $tiny)) 'Validation releases its file handle'

    $runner = Join-Path $root 'run-download.ps1'
    @'
param([string]$Fixtures, [switch]$RejectWorking)
function Save-Fixture($Dest, $Url) {
    [IO.File]::AppendAllText((Join-Path $PSScriptRoot 'requests.txt'), "$Url`n")
    $name = [IO.Path]::GetFileName($Dest)
    if ($RejectWorking -and $name -eq 'Clawd-Working.gif') {
        [IO.File]::WriteAllText($Dest, '<!doctype html>' + ('error page ' * 1000))
    } else { Copy-Item -LiteralPath (Join-Path $Fixtures $name) -Destination $Dest -Force }
}
function curl.exe {
    $index = [Array]::IndexOf($args, '-o')
    Save-Fixture $args[$index + 1] $args[-1]
    $global:LASTEXITCODE = 0
}
function Invoke-WebRequest { param($Uri, $OutFile) Save-Fixture $OutFile $Uri }
& (Join-Path $PSScriptRoot 'download-assets.ps1')
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $runner -Encoding UTF8
    $fixtures = Join-Path $repo 'assets'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Fixtures $fixtures
    Assert ($LASTEXITCODE -eq 0) 'Fresh install downloads all assets and repairs cached HTML'
    $files = Get-ChildItem (Join-Path $root 'assets') -File
    Assert ($files.Count -eq 10) 'All ten required assets, including Cook Intro, are present'
    foreach ($file in $files) { Assert (Test-ClawdAsset $file.FullName) ("Valid " + $file.Name) }
    $requests = @(Get-Content (Join-Path $root 'requests.txt'))
    foreach ($name in @('Clawd-Dancing.gif','Clawd-CookIntro.gif','Clawd-Working.gif','Clawd-Cooking.gif','Clawd-Loading.gif')) {
        Assert ($requests -contains ('https://raw.githubusercontent.com/Zlaxrr/clawd-pet/main/assets/' + $name)) ("Preserved source for " + $name)
    }
    $before = (Get-FileHash $bad).Hash
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Fixtures $fixtures
    Assert ($LASTEXITCODE -eq 0 -and (Get-FileHash $bad).Hash -eq $before) 'Valid cached assets are kept'
    Assert (@(Get-Content (Join-Path $root 'requests.txt')).Count -eq $requests.Count) 'Valid cache needs no downloads'
    [IO.File]::WriteAllText($bad, $html)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Fixtures $fixtures -RejectWorking
    Assert ($LASTEXITCODE -eq 1) 'HTTP 200 HTML from both download methods fails installation'
    Assert (-not (Test-Path $bad)) 'Failed download does not leave a fake GIF in the cache'
} finally {
    # This exact GUID-named directory is created above, under the OS temp directory.
    if ((Split-Path $root -Parent) -eq [IO.Path]::GetTempPath().TrimEnd('\')) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
