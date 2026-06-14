# Menonaktifkan auto-start: menghapus shortcut Clawd Pet dari folder Startup Windows
$startup = [Environment]::GetFolderPath('Startup')
foreach ($name in @('Clawd Pet.lnk', 'start-clawd.vbs')) {
    $p = Join-Path $startup $name
    if (Test-Path $p) {
        Remove-Item $p -Force
        Write-Host "Dihapus: $p"
    }
}
Write-Host 'Auto-start NONAKTIF.'
