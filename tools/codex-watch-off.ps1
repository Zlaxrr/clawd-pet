param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [string]$ClawdConfig = (Join-Path (Split-Path $PSScriptRoot) 'clawd.json')
)
& (Join-Path $PSScriptRoot 'codex-watch-on.ps1') -Disable -CodexHome $CodexHome -ClawdConfig $ClawdConfig
