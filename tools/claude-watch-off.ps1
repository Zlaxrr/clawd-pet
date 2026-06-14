<#
  Claude Watch - OFF
  Removes the Claude Watch hooks from ~/.claude/settings.json. Other hooks are left intact.
#>
$ErrorActionPreference = 'Stop'
$settings = Join-Path $env:USERPROFILE '.claude\settings.json'

if (-not (Test-Path $settings)) { Write-Host "No settings.json - nothing to remove." -ForegroundColor Yellow; exit 0 }

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
function Test-OursEntry($entry) {
    if ($entry -isnot [System.Collections.IDictionary] -or -not $entry.Contains('hooks')) { return $false }
    foreach ($hh in $entry['hooks']) {
        if ($hh -is [System.Collections.IDictionary] -and $hh.Contains('command') -and ($hh['command'] -match 'clawd-status\.txt|clawd-emit')) { return $true }
    }
    return $false
}

$cfg = ConvertTo-HashtableDeep (Get-Content $settings -Raw | ConvertFrom-Json)
if (-not ($cfg -is [System.Collections.IDictionary]) -or -not $cfg.Contains('hooks')) {
    Write-Host "No Claude Watch hooks are installed." -ForegroundColor Yellow; exit 0
}

$removed = 0
$hooks = $cfg['hooks']
foreach ($event in @($hooks.Keys)) {
    $arr = $hooks[$event]
    if ($arr -isnot [System.Collections.IEnumerable]) { continue }
    $keep = New-Object System.Collections.ArrayList
    foreach ($e in $arr) { if (Test-OursEntry $e) { $removed++ } else { [void]$keep.Add($e) } }
    if ($keep.Count -eq 0) { $hooks.Remove($event) } else { $hooks[$event] = $keep }
}
if ($hooks.Count -eq 0) { $cfg.Remove('hooks') }

$json = $cfg | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($settings, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "  Claude Watch disabled - removed $removed hook(s)." -ForegroundColor Green
Write-Host "  Restart your Claude Code session for the change to take effect."
Write-Host ""
