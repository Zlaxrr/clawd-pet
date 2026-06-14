' Stops Clawd Pet without a visible window
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ""Get-CimInstance Win32_Process -Filter \""Name='powershell.exe'\"" | Where-Object { $_.CommandLine -like '*clawd-pet.ps1*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }""", 0, False
