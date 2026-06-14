# Clawd Pet

> [English version](README.md)

Kepiting kecil namanya **Clawd** yang tinggal di taskbar Windows-mu. Dia jalan-jalan, ngikutin kursor, dan bisa kamu angkat terus lempar. Gitu intinya. Aku bikin pakai PowerShell + WinForms biasa, jadi nggak ada yang perlu di-install dan nggak ada yang perlu di-build. Satu script, satu kepiting.

![demo](docs/demo.gif)

## Apa aja yang dia lakuin

Yang sehari-hari:

- Jalan di sepanjang taskbar dengan animasi kaki frame-by-frame (diambil dari sprite Clawd asli, bukan gambar ulang)
- Matanya ngikutin kursor, dan dia kedip sendiri
- Begitu kamu mulai ngetik, gelembung **"?"** bingung muncul di atas kepalanya
- Dia naik ke tepi atas jendela aplikasimu dan ikut kebawa ke mana window-nya pindah- terus terjun pas window-nya kamu tutup

Angkat dia, dia bakal nggantung di kursor dan ayun-ayun kayak digantung tali. Lempar dia, dia beneran kelempar- kecepatannya ngikutin seberapa cepat kamu sentak mouse, dia melengkung di udara, mantul dinding sama lantai, menggepeng pas nyentuh tanah, terus diam. Fisikanya bagian yang paling aku urusin, jadi mainin itu.

### Dan hal-hal yang dia lakuin diam-diam

Biarin dia jalan agak lama, dia mulai ngapa-ngapain sendiri. Tiba-tiba ada balon turun. Langit kadang bikin pertunjukan. Sesekali ada sesuatu yang *mirip* dia- tapi jelas bukan- nongol di tepi layar dan cuma… natap. Dia juga nyimpen satu rahasia kecil di balik taskbar.

Nggak aku bocorin semua di sini- separuh serunya justru pas kepergok momen yang nggak kamu duga. Tapi kalau nggak sabar, semuanya ada di **menu klik-kanan**, tinggal picu:

> *The Shadow · Climb the Wall · Drag the Window · Push a Window · Meteor Shower · Balloon Ride · Hello World! · Dance · Hide · Sleep · Wave*

(Coba **Dance**, terus perhatiin matanya.)

Dia juga merhatiin PC-mu: mondar-mandir keringetan pas CPU lagi berat, ketiduran kalau kamu pergi lama, terus kaget pas kamu balik.

## Claude Watch — dia nunjukin Claude Code lagi ngapain

Ini bagian yang paling aku banggain. Kalau kamu pakai **Claude Code**, Clawd bisa baca pikirannya: gelembung kecil muncul di atas kepalanya, ngasih tau Claude lagi ngapain *sekarang*

> *thinking… · running a command… · writing code… · reading files… · browsing the web… · needs your input…*

 lengkap sama spark kecil yang muter, sama persis kayak animasi loading punya Claude Code. Pas kelar, muncul **all done ✓**.

Jalannya lewat hooks Claude Code: Claude nulis token status kecil, Clawd baca terus nampilin gelembungnya. Nggak ada polling, nggak ada proses tambahan. Buat nyalainnya:

```
Klik kanan  tools\claude-watch-on.ps1  →  Run with PowerShell
```

Itu masang hooks ke setting Claude Code-mu — cuma nambahin hooks punya Clawd, setting lainnya nggak disentuh. Buat nyabutnya lagi, jalanin `tools\claude-watch-off.ps1` dengan cara yang sama. Di pet-nya sendiri udah nyala default (`features.claudeWatch`), jadi begitu hooks-nya kepasang, gelembungnya otomatis muncul tiap Claude lagi kerja.

## Cara jalanin

Butuh **Windows 10 atau 11** (PowerShell 5.1 udah ada di situ) sama internet pas pertama kali jalan.

1. Unduh atau clone repo ini ke folder mana aja
2. Dobel-klik **`start-clawd.vbs`** — pas pertama jalan dia ngambil sprite resmi Clawd dari claude.ai ke folder `assets/`
3. Mau dia nyala bareng Windows? Klik kanan `autostart-on.ps1` → **Run with PowerShell**

| Mau… | Lakuin ini |
|------|------------|
| Nutup dia | Klik kanan Clawd → *Bye Clawd (quit)*, atau jalanin `stop-clawd.vbs` |
| Nyalain dia | `start-clawd.vbs` |
| Atur autostart | `autostart-on.ps1` / `autostart-off.ps1` |
| Nampilin Claude Code lagi ngapain | `tools\claude-watch-on.ps1` (matiin: `claude-watch-off.ps1`) |

> **Kalau Windows atau antivirus-mu nge-block:** file `.vbs` yang diunduh dari internet kadang kena warning SmartScreen atau dikarantina — itu flag generik "ini script", bukan karena ada apa-apa di proyek ini. Isi `start-clawd.vbs` bisa kamu baca sendiri (cuma tiga baris). Kalau SmartScreen muncul, klik *More info → Run anyway*; kalau AV-nya ngarantina, restore aja dan izinin.

## Ngatur dia — `clawd.json`

Semua setting ada di satu file. Ubah, restart, kelar.

| Kunci | Default | Fungsinya |
|-------|---------|-----------|
| `size` | `80` | Lebar Clawd dalam px (48–200). Semuanya ikut nyekala dari sini. |
| `walkSpeed` / `gravity` | `1.0` | Pengali kecepatan & gravitasi |
| `idleSecondsMin/Max` | `5` / `10` | Lama dia diem antar aksi |
| `blinkSecondsMin/Max` | `2.5` / `5.5` | Seberapa sering dia kedip |
| `features.eyeTracking` | `true` | Mata ngikutin kursor |
| `features.windowPlatforms` | `true` | Berdiri & nebeng di jendela aplikasi |
| `features.typingReaction` | `true` | Gelembung "?" pas kamu ngetik |
| `features.edgeLurking` | `false` | Ngintip dari tepi layar |
| `features.systemAwareness` | `true` | Reaksi ke beban CPU / idle |
| `features.climbing` | `true` | Manjat tepi layar |
| `features.mischief` | `true` | Aksi-aksi langka tak terduga |
| `features.claudeWatch` | `true` | Gelembung status Claude Code |
| `terminal.command` / `output` | `clawd --hello` / `Hello, World!` | Teks di bagian terminal |

Kalau config-nya rusak atau ilang, dia tinggal balik ke default yang aman, jadi tenang aja nggak bakal bikin dia error.

## Soal sprite-nya

Clawd sama semua artwork-nya punya **Anthropic**, jadi mereka **nggak** ada di repo ini. `download-assets.ps1` ngambilnya langsung dari claude.ai pas pertama kali kamu jalanin, buat penggunaan pribadi. Ini proyek penggemar — nggak resmi, dan Anthropic nggak ada hubungannya sama ini.

## Lisensi

[MIT](LICENSE), tapi itu cuma nutupin **kodenya aja** — lihat catatan sprite di atas.
