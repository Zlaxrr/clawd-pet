# Downloads the official Clawd animation assets from claude.ai into the assets\ folder.
# The assets belong to Anthropic — this repo does not bundle them; this script
# pulls them straight from the official source at install time.

$ErrorActionPreference = 'Stop'
$assetDir = Join-Path $PSScriptRoot 'assets'
New-Item -ItemType Directory -Force $assetDir | Out-Null

$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
$base = 'https://claude.ai/images/clawd/core/'
$files = @('Clawd-Still.png', 'Clawd-CrabWalking.gif', 'Clawd-Waving.gif', 'Clawd-JumpingHappy.gif', 'Clawd-Lurking.gif',
           'Clawd-Dancing.gif', 'Clawd-Working.gif', 'Clawd-Loading.gif', 'Clawd-Cooking.gif')

$ok = 0
foreach ($f in $files) {
    $dest = Join-Path $assetDir $f
    if (Test-Path $dest) { Write-Host "[skip] $f already exists"; $ok++; continue }
    Write-Host "[download] $f ..."
    $done = $false
    # Try curl.exe first (built into Windows 10/11), then fall back to Invoke-WebRequest
    try {
        & curl.exe -s -S --max-time 40 -A $ua -o $dest ($base + $f)
        if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 5000) { $done = $true }
    } catch { }
    if (-not $done) {
        try {
            Invoke-WebRequest -Uri ($base + $f) -OutFile $dest -UseBasicParsing -TimeoutSec 40 -Headers @{ 'User-Agent' = $ua }
            if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 5000) { $done = $true }
        } catch { }
    }
    if ($done) {
        Write-Host "  OK ($([int]((Get-Item $dest).Length / 1KB)) KB)"
        $ok++
    } else {
        if (Test-Path $dest) { Remove-Item $dest -Force }
        Write-Host "  FAILED to download $f" -ForegroundColor Red
    }
}

Write-Host ""
if ($ok -eq $files.Count) {
    Write-Host "All assets ready ($ok/$($files.Count))." -ForegroundColor Green
    exit 0
} else {
    Write-Host "Partially done: $ok/$($files.Count). Re-run this script or check your internet connection." -ForegroundColor Yellow
    exit 1
}
