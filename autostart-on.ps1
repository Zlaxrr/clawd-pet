# Mengaktifkan auto-start: membuat shortcut ke start-clawd.vbs di folder Startup Windows
$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'Clawd Pet.lnk'
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = Join-Path $PSScriptRoot 'start-clawd.vbs'
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.Description = 'Clawd Pet - desktop crab'
$lnk.Save()
Write-Host "Auto-start AKTIF: $lnkPath"
