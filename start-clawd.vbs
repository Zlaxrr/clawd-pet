' Menjalankan Clawd Pet tanpa jendela PowerShell yang terlihat.
' Path dihitung relatif terhadap lokasi file ini — aman dipindah/clone ke mana pun.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)

' Pertama kali jalan, sprite resmi belum ada dan harus diunduh dari claude.ai
' (butuh beberapa detik). Window PowerShell disembunyikan, jadi tanpa pesan ini
' layar terlihat "diam" dan orang mengira gagal. Popup ini hilang sendiri.
firstRun = Not fso.FileExists(dir & "\assets\Clawd-Still.png")
If firstRun Then
  ' Argumen ke-2 = 4 detik lalu tutup sendiri; tidak memblokir peluncuran.
  sh.Popup "Clawd lagi bangun — sprite-nya diunduh dulu dari claude.ai." & vbCrLf & _
           "Butuh beberapa detik di run pertama, tunggu sebentar ya. 🦀", _
           4, "Clawd Pet", 64
End If

sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\clawd-pet.ps1""", 0, False
