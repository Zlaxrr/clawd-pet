param(
    [switch]$FallbackOnly,
    [switch]$Disable,
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [string]$ClawdConfig = (Join-Path (Split-Path $PSScriptRoot) 'clawd.json')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'agent-state.ps1')
$settings = Join-Path $CodexHome 'hooks.json'
$backup = Join-Path $CodexHome 'hooks.json.clawd-codex-backup'
$adapter = Join-Path $PSScriptRoot 'codex-watch.ps1'

function Get-ClawdHooksHash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))) }
    finally { $sha.Dispose() }
}
function Remove-ClawdHooks($Cfg, [bool]$Legacy) {
    $removed = @()
    if ($Cfg.hooks) {
        foreach ($event in @($Cfg.hooks.PSObject.Properties)) {
            $entries = @()
            foreach ($entry in $event.Value) {
                $keep = @()
                foreach ($hook in $entry.hooks) {
                    $ours = [string]$hook.command -match 'codex-watch\.ps1.*-Hook'
                    if ($Legacy) { $ours = $ours -or [string]$hook.command -match 'clawd-emit|clawd-status\.txt' }
                    if ($ours) {
                        $copy = ($entry | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
                        $copy.hooks = @($hook)
                        $removed += [pscustomobject]@{event=$event.Name;entry=$copy}
                    } else { $keep += $hook }
                }
                if ($keep.Count) { $entry.hooks = @($keep); $entries += $entry }
            }
            if ($entries.Count) { $Cfg.hooks.($event.Name) = @($entries) }
            else { $Cfg.hooks.PSObject.Properties.Remove($event.Name) }
        }
    }
    return $removed
}

$clawd = [IO.File]::ReadAllText($ClawdConfig) | ConvertFrom-Json
if (-not $clawd.features) { $clawd | Add-Member features ([pscustomobject]@{}) }
if ($Disable) {
    if (Test-Path -LiteralPath $backup) {
        $saved = [IO.File]::ReadAllText($backup) | ConvertFrom-Json
        if (Test-Path -LiteralPath $settings) {
            $current = [IO.File]::ReadAllText($settings)
            if ((Get-ClawdHooksHash $current) -eq $saved.installedHash) {
                if ($saved.existed) { [IO.File]::WriteAllBytes($settings, [Convert]::FromBase64String($saved.original)) }
                else { [IO.File]::Delete($settings) }
            } else {
                # User edited hooks after installation: remove only ours, restore migrated hooks.
                $cfg = $current | ConvertFrom-Json
                $null = Remove-ClawdHooks $cfg $false
                if (-not $cfg.hooks) { $cfg | Add-Member hooks ([pscustomobject]@{}) -Force }
                foreach ($r in $saved.removed) {
                    $existing = @($cfg.hooks.($r.event) | Where-Object { $null -ne $_ })
                    $command = [string]$r.entry.hooks[0].command
                    if (-not @($existing | ForEach-Object { $_.hooks } | Where-Object { $_.command -eq $command }).Count) {
                        $cfg.hooks | Add-Member $r.event @($existing + $r.entry) -Force
                    }
                }
                Write-ClawdJson $settings $cfg
            }
        }
        [IO.File]::Delete($backup)
    }
    $clawd.features | Add-Member codexWatch $false -Force
    Write-ClawdJson $ClawdConfig $clawd
    Write-Host 'Codex Watch disabled. Restart Clawd and Codex. Other Codex settings preserved.'
    return
}

if (-not $FallbackOnly) {
    [void][IO.Directory]::CreateDirectory($CodexHome)
    $existed = Test-Path -LiteralPath $settings
    $original = if ($existed) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($settings)) } else { '' }
    $cfg = if ($existed) { [IO.File]::ReadAllText($settings) | ConvertFrom-Json } else { [pscustomobject]@{} }
    if ($cfg -isnot [pscustomobject]) { throw 'hooks.json must contain a JSON object; no changes made.' }
    $removed = @(Remove-ClawdHooks $cfg $true)
    if (-not $cfg.hooks) { $cfg | Add-Member hooks ([pscustomobject]@{}) -Force }
    foreach ($event in @('UserPromptSubmit','PreToolUse','PostToolUse','PermissionRequest','Stop','Interrupt','SessionEnd')) {
        $entry = [pscustomobject]@{hooks=@([pscustomobject]@{
            type='command'; command="powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$adapter`" -Hook"; timeout=3
        })}
        $existing = @($cfg.hooks.$event | Where-Object { $null -ne $_ })
        $cfg.hooks | Add-Member $event @($existing + $entry) -Force
    }
    $newText = $cfg | ConvertTo-Json -Depth 20 -Compress
    $saved = if (Test-Path -LiteralPath $backup) { [IO.File]::ReadAllText($backup) | ConvertFrom-Json } else {
        [pscustomobject]@{existed=$existed;original=$original;removed=$removed;installedHash=''}
    }
    $saved.installedHash = Get-ClawdHooksHash $newText
    Write-ClawdJson $backup $saved
    Write-ClawdJson $settings $cfg
}
$clawd.features | Add-Member codexWatch $true -Force
Write-ClawdJson $ClawdConfig $clawd
Write-Host 'Codex Watch enabled. Restart Clawd and Codex; review the new hooks when Codex asks.'
Write-Host 'JSONL fallback is always enabled. config.toml and its notify command were not modified.'
