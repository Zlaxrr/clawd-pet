<#
  Claude Watch - ON
  Installs Claude Code hooks that write Claude's current activity to a status file,
  which Clawd Pet reads and shows as a bubble above his head.

  The hooks are added to ~/.claude/settings.json (your other hooks are left untouched).
  Run claude-watch-off.ps1 to remove them. Safe to run multiple times.
#>
$ErrorActionPreference = 'Stop'

$emit     = Join-Path $PSScriptRoot 'clawd-emit.cmd'
$settings = Join-Path $env:USERPROFILE '.claude\settings.json'

if (-not (Test-Path $emit)) { Write-Host "clawd-emit.cmd not found in $PSScriptRoot" -ForegroundColor Red; exit 1 }

# PSCustomObject (from ConvertFrom-Json) -> mutable hashtable/arraylist
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

# Load the existing settings (or start empty)
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

# Token per event/tool. matcher = tool-name regex ('' = all / events without a tool).
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

# Clean out our own old hooks (recognized by 'clawd-status.txt' in the command)
function Test-OursEntry($entry) {
    if ($entry -isnot [System.Collections.IDictionary] -or -not $entry.Contains('hooks')) { return $false }
    foreach ($hh in $entry['hooks']) {
        if ($hh -is [System.Collections.IDictionary] -and $hh.Contains('command') -and ($hh['command'] -match 'clawd-status\.txt|clawd-emit')) { return $true }
    }
    return $false
}

# Pass 1: make sure each event is an ArrayList & drop our old entries (once per event)
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

# Pass 2: add our hooks (safe now, they no longer delete each other)
foreach ($o in $ours) {
    $arr = $hooks[$o.event]
    # On Windows, Claude Code already runs commands through cmd /c, so call the batch
    # file directly (another 'cmd /c' prefix would double the cmd and break quoting).
    $cmd = "`"$emit`" $($o.token)"
    $entry = [ordered]@{}
    if ($o.matcher -ne '') { $entry['matcher'] = $o.matcher }
    $entry['hooks'] = ,([ordered]@{ type = 'command'; command = $cmd })
    [void]$arr.Add($entry)
}

# Write it back. -Depth is deep enough for the nested hooks structure.
$json = $cfg | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($settings, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "  Claude Watch ENABLED." -ForegroundColor Green
Write-Host "  Hooks installed in: $settings"
if (Test-Path "$settings.clawd-backup") { Write-Host "  Backup saved: $settings.clawd-backup" -ForegroundColor DarkGray }
Write-Host ""
Write-Host "  Last steps:" -ForegroundColor Yellow
Write-Host "   1. Make sure clawd.json -> features.claudeWatch = true (true by default)."
Write-Host "   2. RESTART your Claude Code session so the hooks are picked up (Claude Code may"
Write-Host "      ask you to review the new hooks - that's normal for safety, just approve them)."
Write-Host "   3. Use Claude Code as usual - Clawd will show what it's working on."
Write-Host ""
