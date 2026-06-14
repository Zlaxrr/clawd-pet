# Panduan Edit Cepat — clawd-pet.ps1

Semua logika ada di satu file: `clawd-pet.ps1`. Peta bagiannya (cari teks judulnya dengan Ctrl+F):

| Bagian (cari teks ini) | Isi |
|---|---|
| `Add-Type -ReferencedAssemblies` (blok pertama) | Helper C#: animator GIF, deteksi window, input, olah piksel sprite |
| `# ---------- Konfigurasi` | Pembacaan clawd.json + nilai default |
| `# ---------- Aset resmi` | Pemuatan sprite + auto-download |
| `# ---------- Kaki jalan` | Ekstraksi frame kaki dari GIF CrabWalking |
| `# ---------- Ukuran tampil` | Skala, margin, geometri window |
| `# ---------- State` | Semua variabel runtime (posisi, mode, timer) |
| `function Set-State` / `Start-Fx` | Pengganti state & efek |
| `Start-Balloon` / `Start-StarShow` / `Start-Shadow` | Tiga momen langka |
| `$script:form.Add_Paint` | SEMUA penggambaran (urutan: drag → lurk → code → balon → normal → mata → gelembung) |
| `$script:timer.Add_Tick` | Mesin utama 60 fps (fisika, timeline, keputusan idle) |
| `# ---------- Interaksi mouse` | Klik, seret, lempar |
| `# ---------- Menu klik kanan` | Item menu |

## Resep umum

- **Ubah ukuran/kecepatan/teks terminal** → cukup edit `clawd.json`, restart.
- **Ubah peluang aksi idle** → cari `$r = $script:rand.NextDouble()` di blok `'idle'`; angka 0.26/0.42/… adalah ambang kumulatif.
- **Ubah durasi animasi** → angka tick pada `Set-State 'x' <tick>` (1 detik = 62,5 tick).
- **Ubah warna Si Bayangan** → cari `Darken($full, 0, 399, 330, 401,` — tiga angka pertama = badan (R,G,B), tiga berikutnya = mata.
- **Ubah ukuran Si Bayangan** → cari `$script:shDW` (pengali `* 1.5`).
- **Sprite terpotong saat beranimasi?** → window-nya kurang besar: perbesar margin pada `ClientSize` window terkait dan offset gambarnya (lihat komentar "margin window" di paint Si Bayangan sebagai contoh).
- **Tes tanpa menjalankan pet** → `powershell -File clawd-pet.ps1 -TestBlink` (kompilasi + uji sprite).
- **Terapkan perubahan** → jalankan `stop-clawd.vbs` lalu `start-clawd.vbs`.
