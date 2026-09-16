param(
    [switch]$Hook,
    [int]$ParentId = 0,
    [string]$OutputPath,
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [string]$StateDirectory = (Join-Path $env:TEMP 'clawd-codex'),
    [int]$Iterations = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'agent-state.ps1')
[void][IO.Directory]::CreateDirectory($StateDirectory)

if ($Hook) {
    # Advisory only: no stdout, decisions, prompt text, or command execution.
    try {
        $p = [Console]::In.ReadToEnd() | ConvertFrom-Json
        if ([string]$p.session_id -notmatch '^[a-zA-Z0-9_-]{1,100}$') { exit 0 }
        # Ignore Desktop hooks; lifecycle events have no originator in their payload.
        # The watcher accepts these records only after identifying a CLI transcript.
        $token = switch ($p.hook_event_name) {
            'UserPromptSubmit' { 'think' }
            'PreToolUse' { Get-ClawdToolToken $p.tool_name $p.tool_input }
            'PostToolUse' { 'think' }
            'PermissionRequest' { 'notify' }
            'Stop' { 'done' }
            'Interrupt' { 'done' }
            'SessionEnd' { 'done' }
        }
        if ($token) {
            # Unique immutable records: concurrent hook processes never share a write target.
            $record = [pscustomobject]@{source='codex';session=[string]$p.session_id;turn=[string]$p.turn_id;token=$token;at=[datetime]::UtcNow.ToString('o')}
            Write-ClawdJson (Join-Path $StateDirectory "$([Guid]::NewGuid().ToString('N')).json") $record
        }
    } catch { } # Observability must never block or fail the agent's tool call.
    exit 0
}

if (-not $OutputPath) { throw 'OutputPath is required for the watcher.' }
$states = @{}; $cursors = @{}; $files = @(); $cycle = 0
$checkpoint = Join-Path $StateDirectory 'checkpoint.state'
if ([IO.File]::Exists($checkpoint)) {
    try {
        $saved = [IO.File]::ReadAllText($checkpoint) | ConvertFrom-Json
        foreach ($s in $saved.states) { Set-ClawdState $states $s.session 'codex' $s.token ([datetime]$s.at).ToUniversalTime() $s.turn ([bool]$s.closed) }
    } catch { }
}
$sessionRoot = Join-Path $CodexHome 'sessions'
while (-not $ParentId -or (Get-Process -Id $ParentId -ErrorAction SilentlyContinue)) {
    # Discovery is off the WinForms thread. Resumed old sessions are found by mtime.
    if ($cycle % 6 -eq 0) {
        $files = @(Get-ChildItem -LiteralPath $sessionRoot -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -gt [datetime]::UtcNow.AddMinutes(-30) })
    }
    foreach ($file in $files) {
        $fs = $null; $reader = $null
        try {
            $fs = [IO.File]::Open($file.FullName, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $c = $cursors[$file.FullName]
            if (-not $c -or $fs.Length -lt $c.offset) {
                $c = @{offset=[long]0;session=$file.BaseName;turn='';cli=$false}
                $reader = New-Object IO.StreamReader($fs)
                $first = $reader.ReadLine()
                if (-not $first) { continue }
                Read-ClawdCodexEvent ($first | ConvertFrom-Json) $c $states
                $cursors[$file.FullName] = $c # Retry discovery if metadata is still being written.
                $reader.Dispose(); $reader = $null
                $fs = [IO.File]::Open($file.FullName, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                # ponytail: bounded 512 KiB restart replay; older silent turns expire after 30m.
                if ($fs.Length -gt 524288) {
                    $c.offset = $fs.Length - 524288
                    [void]$fs.Seek($c.offset, 'Begin')
                    while (($b = $fs.ReadByte()) -ge 0) { $c.offset++; if ($b -eq 10) { break } }
                }
            }
            if (-not $c.cli) { continue }
            [void]$fs.Seek($c.offset, 'Begin')
            $count = [int][Math]::Min(524288, $fs.Length - $c.offset)
            if ($count -le 0) { continue }
            $bytes = New-Object byte[] $count
            $read = $fs.Read($bytes, 0, $count)
            $last = $read - 1
            while ($last -ge 0 -and $bytes[$last] -ne 10) { $last-- }
            if ($last -lt 0) {
                # Skip an oversized complete line, never keep rereading it forever.
                if ($read -eq 524288) {
                    while (($b = $fs.ReadByte()) -ge 0) { if ($b -eq 10) { $c.offset = $fs.Position; break } }
                }
                continue
            }
            $text = [Text.Encoding]::UTF8.GetString($bytes, 0, $last + 1)
            foreach ($line in $text.Split([char]10)) {
                if (-not $line.Trim()) { continue }
                try { Read-ClawdCodexEvent ($line | ConvertFrom-Json) $c $states } catch { }
            }
            $c.offset += $last + 1 # Do not consume partial lines or split UTF-8 sequences.
        } catch { } finally { if ($reader) { $reader.Dispose() }; if ($fs) { $fs.Dispose() } }
    }
    $cliIds = @($cursors.Values | Where-Object { $_.cli } | ForEach-Object { $_.session })
    foreach ($file in @(Get-ChildItem -LiteralPath $StateDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $h = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
            if ($h.session -in $cliIds) {
                Set-ClawdState $states $h.session 'codex' $h.token ([datetime]$h.at).ToUniversalTime() $h.turn
                [IO.File]::Delete($file.FullName)
            } elseif ($file.LastWriteTimeUtc -lt [datetime]::UtcNow.AddMinutes(-2)) { [IO.File]::Delete($file.FullName) }
        } catch { }
    }
    foreach ($key in @($states.Keys)) {
        if (([datetime]::UtcNow - $states[$key].at).TotalMinutes -ge 30) { $states.Remove($key) }
    }
    $wireStates = @($states.Values | Select-Object source,token,turn,session,closed,@{n='at';e={$_.at.ToString('o')}})
    Write-ClawdJson $checkpoint @{states=$wireStates}
    Write-ClawdJson $OutputPath @{states=$wireStates}
    $cycle++
    if ($Iterations -gt 0 -and $cycle -ge $Iterations) { break }
    Start-Sleep -Milliseconds 500
}
