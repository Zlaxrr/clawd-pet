# Disable auto-start: removes the Clawd Pet shortcut from the Windows Startup folder
$startup = [Environment]::GetFolderPath('Startup')
foreach ($name in @('Clawd Pet.lnk', 'start-clawd.vbs')) {
    $p = Join-Path $startup $name
    if (Test-Path $p) {
        Remove-Item $p -Force
        Write-Host "Removed: $p"
    }
}
Write-Host 'Auto-start DISABLED.'
