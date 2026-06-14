' Launches Clawd Pet without a visible PowerShell window.
' Paths are computed relative to this file's location — safe to move/clone anywhere.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)

' On the first run the official sprites don't exist yet and must be downloaded from
' claude.ai (takes a few seconds). The PowerShell window is hidden, so without this
' message the screen looks "frozen" and people assume it failed. This popup auto-closes.
firstRun = Not fso.FileExists(dir & "\assets\Clawd-Still.png")
If firstRun Then
  ' 2nd argument = 4 seconds then auto-closes; does not block the launch.
  sh.Popup "Clawd is waking up — grabbing his sprites from claude.ai first." & vbCrLf & _
           "Takes a few seconds on the first run, hang tight. 🦀", _
           4, "Clawd Pet", 64
End If

sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\clawd-pet.ps1""", 0, False
