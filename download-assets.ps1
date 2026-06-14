# Mengunduh aset animasi resmi Clawd dari claude.ai ke folder assets\.
# Aset adalah milik Anthropic — repo ini tidak menyertakannya; script ini
# mengunduhnya langsung dari sumber resminya saat instalasi.

$ErrorActionPreference = 'Stop'
$assetDir = Join-Path $PSScriptRoot 'assets'
New-Item -ItemType Directory -Force $assetDir | Out-Null

$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
$base = 'https://claude.ai/images/clawd/core/'
$files = @('Clawd-Still.png', 'Clawd-CrabWalking.gif', 'Clawd-Waving.gif', 'Clawd-JumpingHappy.gif', 'Clawd-Lurking.gif')

$ok = 0
foreach ($f in $files) {
    $dest = Join-Path $assetDir $f
    if (Test-Path $dest) { Write-Host "[lewati] $f sudah ada"; $ok++; continue }
    Write-Host "[unduh] $f ..."
    $done = $false
    # Coba curl.exe dulu (bawaan Windows 10/11), lalu Invoke-WebRequest
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
        Write-Host "  GAGAL mengunduh $f" -ForegroundColor Red
    }
}

Write-Host ""
if ($ok -eq $files.Count) {
    Write-Host "Semua aset siap ($ok/$($files.Count))." -ForegroundColor Green
    exit 0
} else {
    Write-Host "Selesai sebagian: $ok/$($files.Count). Jalankan ulang script ini atau periksa koneksi internet." -ForegroundColor Yellow
    exit 1
}
