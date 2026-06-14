<#
  Claude Watch - ON
  Pasang hook Claude Code yang menulis aktivitas Claude saat ini ke file status,
  yang dibaca Clawd Pet dan ditampilkan sebagai gelembung di atas kepalanya.

  Hook ditambahkan ke ~/.claude/settings.json (hook milikmu yang lain tidak diutak-atik).
  Jalankan claude-watch-off.ps1 untuk mencabutnya. Aman dijalankan berkali-kali.
#>
$ErrorActionPreference = 'Stop'

$emit     = Join-Path $PSScriptRoot 'clawd-emit.cmd'
$settings = Join-Path $env:USERPROFILE '.claude\settings.json'

if (-not (Test-Path $emit)) { Write-Host "clawd-emit.cmd tidak ditemukan di $PSScriptRoot" -ForegroundColor Red; exit 1 }

# PSCustomObject (hasil ConvertFrom-Json) -> hashtable/arraylist yang bisa diubah-ubah
function ConvertTo-HashtableDeep($o) {
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableDeep $p.Value }
        return $h
    } elseif ($o -is [System.Collections.IEnumerable] -and $o -isnot [string]) {
        $a = New-Object System.Collections.ArrayList
        foreach ($i in $o) { [void]$a.Add((ConvertTo-HashtableDeep $i)) }
        return ,$a
    }
    return $o
}

# Muat settings yang ada (atau mulai kosong)
if (Test-Path $settings) {
    Copy-Item $settings "$settings.clawd-backup" -Force
    $cfg = ConvertTo-HashtableDeep (Get-Content $settings -Raw | ConvertFrom-Json)
    if ($cfg -isnot [System.Collections.IDictionary]) { $cfg = [ordered]@{} }
} else {
    New-Item -ItemType Directory -Force (Split-Path $settings) | Out-Null
    $cfg = [ordered]@{}
}
if (-not $cfg.Contains('hooks')) { $cfg['hooks'] = [ordered]@{} }
$hooks = $cfg['hooks']

# Token per event/tool. matcher = regex nama tool ('' = semua / event tanpa tool).
$ours = @(
    @{ event = 'UserPromptSubmit'; matcher = '';                                token = 'think'  },
    @{ event = 'PreToolUse';       matcher = 'Bash';                            token = 'bash'   },
    @{ event = 'PreToolUse';       matcher = 'Edit|Write|MultiEdit|NotebookEdit'; token = 'edit' },
    @{ event = 'PreToolUse';       matcher = 'Read|Grep|Glob';                  token = 'read'   },
    @{ event = 'PreToolUse';       matcher = 'WebFetch|WebSearch';              token = 'web'    },
    @{ event = 'PreToolUse';       matcher = 'Task';                            token = 'task'   },
    @{ event = 'Notification';     matcher = '';                                token = 'notify' },
    @{ event = 'Stop';             matcher = '';                                token = 'done'   }
)

# Bersihkan hook milik kita yang lama (dikenali dari 'clawd-status.txt' di command)
function Test-OursEntry($entry) {
    if ($entry -isnot [System.Collections.IDictionary] -or -not $entry.Contains('hooks')) { return $false }
    foreach ($hh in $entry['hooks']) {
        if ($hh -is [System.Collections.IDictionary] -and $hh.Contains('command') -and ($hh['command'] -match 'clawd-status\.txt|clawd-emit')) { return $true }
    }
    return $false
}

# Pass 1: pastikan tiap event jadi ArrayList & buang entri lama milik kita (sekali per event)
$events = @($ours | ForEach-Object { $_.event } | Select-Object -Unique)
foreach ($ev in $events) {
    if (-not $hooks.Contains($ev)) { $hooks[$ev] = (New-Object System.Collections.ArrayList) }
    $arr = $hooks[$ev]
    if ($arr -isnot [System.Collections.ArrayList]) {
        $tmp = New-Object System.Collections.ArrayList
        foreach ($e in $arr) { [void]$tmp.Add($e) }
        $hooks[$ev] = $tmp
    }
    $arr = $hooks[$ev]
    for ($i = $arr.Count - 1; $i -ge 0; $i--) { if (Test-OursEntry $arr[$i]) { $arr.RemoveAt($i) } }
}

# Pass 2: tambahkan hook kita (sekarang aman, tidak saling menghapus)
foreach ($o in $ours) {
    $arr = $hooks[$o.event]
    # Claude Code di Windows sudah menjalankan command lewat cmd /c, jadi panggil
    # batch-nya langsung (prefix 'cmd /c' lagi akan menyebabkan cmd ganda & quoting rusak).
    $cmd = "`"$emit`" $($o.token)"
    $entry = [ordered]@{}
    if ($o.matcher -ne '') { $entry['matcher'] = $o.matcher }
    $entry['hooks'] = ,([ordered]@{ type = 'command'; command = $cmd })
    [void]$arr.Add($entry)
}

# Tulis kembali. -Depth cukup dalam untuk struktur hooks bertingkat.
$json = $cfg | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($settings, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "  Claude Watch AKTIF." -ForegroundColor Green
Write-Host "  Hook dipasang di: $settings"
if (Test-Path "$settings.clawd-backup") { Write-Host "  Cadangan disimpan: $settings.clawd-backup" -ForegroundColor DarkGray }
Write-Host ""
Write-Host "  Langkah terakhir:" -ForegroundColor Yellow
Write-Host "   1. Pastikan clawd.json -> features.claudeWatch = true (default sudah true)."
Write-Host "   2. MULAI ULANG sesi Claude Code-mu agar hook terbaca (Claude Code mungkin"
Write-Host "      minta kamu meninjau hook baru - ini wajar untuk keamanan, setujui saja)."
Write-Host "   3. Pakai Claude Code seperti biasa - Clawd akan menampilkan apa yang sedang ia kerjakan."
Write-Host ""
