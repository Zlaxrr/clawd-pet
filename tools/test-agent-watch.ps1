# Run with Windows PowerShell 5.1. Uses isolated temporary files; no real agent settings.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'agent-state.ps1')
function Assert($Value, [string]$Message) { if (-not $Value) { throw $Message }; Write-Host "PASS $Message" }
$root = Join-Path ([IO.Path]::GetTempPath()) "clawd-watch-test-$([Guid]::NewGuid().ToString('N'))"
[void][IO.Directory]::CreateDirectory((Join-Path $root 'sessions'))
$config = Join-Path $root 'clawd.json'; $hooks = Join-Path $root 'hooks.json'
$out = Join-Path $root 'output.json'; $events = Join-Path $root 'events'
$legacy = Join-Path $root 'clawd-status.txt'
try {
    foreach ($pair in @(@('apply_patch','edit'),@('Read','read'),@('exec_command','bash'),@('web_search','web'),@('spawn_agent','task'),@('request_user_input','notify'))) {
        Assert ((Get-ClawdToolToken $pair[0] $null) -eq $pair[1]) "map $($pair[0])"
    }
    Assert ((Get-ClawdToolToken 'exec_command' @{cmd='Get-Content README.md'}) -eq 'read') 'read-only shell maps to read'
    Assert ((Get-ClawdToolToken 'exec_command' @{cmd='Get-Content a > b'}) -eq 'bash') 'redirect is not classified read-only'
    Assert ((Get-ClawdToolToken 'exec_command' @{cmd='rg x; Set-Content a b'}) -eq 'bash') 'mixed shell is not classified read-only'
    Assert ((Get-ClawdToolToken 'unknown' $null) -eq '') 'unknown tool does not fabricate activity'
    Assert ((Get-ClawdToolToken 'functions.wait' @{cell_id='123'}) -eq '') 'code-mode wait is not mistaken for delegation'
    $now = [datetime]::UtcNow; $states = @{}
    Set-ClawdState $states 'claude' 'claude' 'bash' $now
    Set-ClawdState $states 'codex' 'codex' 'done' $now.AddMilliseconds(1) 'one'
    Assert ((Select-ClawdState $states.Values).source -eq 'claude') 'Codex done cannot stop Claude'
    Set-ClawdState $states 'codex' 'codex' 'think' $now.AddMilliseconds(2) 'two'
    Set-ClawdState $states 'claude' 'claude' 'done' $now.AddMilliseconds(3)
    Assert ((Select-ClawdState $states.Values).source -eq 'codex') 'Claude done cannot stop Codex'
    Set-ClawdState $states 'codex' 'codex' 'done' $now.AddMilliseconds(4) 'one'
    Assert ($states.codex.token -eq 'think') 'late completion from old turn ignored'
    Set-ClawdState $states 'codex' 'codex' 'edit' $now.AddSeconds(-1) 'two'
    Assert ($states.codex.token -eq 'think') 'out-of-order activity ignored'
    Set-ClawdState $states 'closed-test' 'codex' 'done' $now 'closed-turn' $true
    Set-ClawdState $states 'closed-test' 'codex' 'think' $now.AddMilliseconds(2) 'closed-turn'
    Assert ($states['closed-test'].token -eq 'done') 'late tool result cannot reopen completed turn'
    Set-ClawdState $states 'codex2' 'codex' 'read' $now 'three'
    Set-ClawdState $states 'codex' 'codex' 'done' $now.AddMilliseconds(5) 'two'
    Assert ((Select-ClawdState $states.Values).session -eq 'codex2') 'independent Codex sessions'
    Assert ($null -eq (Select-ClawdState $states.Values $now.AddMinutes(31))) 'abandoned states expire'
    $long = @([pscustomobject]@{source='claude';token='bash';at=$now.AddSeconds(-60)}, [pscustomobject]@{source='codex';token='done';at=$now})
    Assert ((Select-ClawdState $long $now 1800).token -eq 'bash') 'long Claude command survives Codex completion in dual-agent mode'
    Assert ((Select-ClawdState $long $now).token -eq 'done') 'Claude-only legacy timeout remains 15 seconds'
    $cursor = @{cli=$false;session='';turn=''}; $parsed = @{}
    Read-ClawdCodexEvent @{timestamp=$now;type='session_meta';payload=@{id='test';source='cli'}} $cursor $parsed
    foreach ($pair in @(@('task_started','think'),@('exec_approval_request','notify'),@('task_complete','done'))) {
        Read-ClawdCodexEvent @{timestamp=$now;type='event_msg';payload=@{type=$pair[0];turn_id='one'}} $cursor $parsed
        Assert ($parsed.test.token -eq $pair[1]) "JSONL $($pair[0])"
    }
    $cursor.cli=$false
    Read-ClawdCodexEvent @{timestamp=$now;type='event_msg';payload=@{type='task_started'}} $cursor $parsed
    Assert ($parsed.test.token -eq 'done') 'Desktop transcript ignored'

    [IO.File]::WriteAllText($legacy,'edit')
    Assert ((Get-ClawdDisplayState $true $false $out $legacy).token -eq 'edit') 'legacy Claude token pipeline'
    [IO.File]::WriteAllText($legacy,'')
    Assert ((Get-ClawdDisplayState $true $false $out $legacy).token -eq 'edit') 'transient legacy write cannot drop active Claude state'
    Assert ($null -eq (Get-ClawdDisplayState $false $false $out $legacy)) 'watch flags respected'

    $session = Join-Path $root 'sessions/rollout-test.jsonl'
    $rows = @(
        @{timestamp=$now;type='session_meta';payload=@{id='test';source='cli'}},
        @{timestamp=$now;type='event_msg';payload=@{type='task_started';turn_id='one'}},
        @{timestamp=$now;type='response_item';payload=@{type='function_call';name='apply_patch';arguments='{}'}}
    )
    [IO.File]::WriteAllText($session, (($rows | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress }) -join "`n") + "`n{partial")
    & (Join-Path $PSScriptRoot 'codex-watch.ps1') -CodexHome $root -StateDirectory $events -OutputPath $out -Iterations 1
    Assert ((([IO.File]::ReadAllText($out)|ConvertFrom-Json).states[0].token) -eq 'edit') 'fallback replays complete lines and tolerates partial JSON'
    Assert ((Get-ClawdDisplayState $false $true $out $legacy).token -eq 'edit') 'PowerShell 5.1 snapshot reaches UI selector'
    & (Join-Path $PSScriptRoot 'codex-watch.ps1') -CodexHome $root -StateDirectory $events -OutputPath $out -Iterations 1
    Assert ((([IO.File]::ReadAllText($out)|ConvertFrom-Json).states[0].token) -eq 'edit') 'restart reconstructs active state'
    $jobs = @()
    foreach ($event in @('PreToolUse','PermissionRequest')) {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = 'powershell.exe'
        $info.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'codex-watch.ps1')`" -Hook -StateDirectory `"$events`""
        $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.RedirectStandardInput=$true
        $p = New-Object Diagnostics.Process; $p.StartInfo=$info; [void]$p.Start()
        $p.StandardInput.WriteLine((@{session_id='test';turn_id='one';hook_event_name=$event;tool_name='apply_patch'}|ConvertTo-Json -Compress))
        $p.StandardInput.Close(); $jobs += $p
    }
    foreach($p in $jobs) { $p.WaitForExit(); Assert ($p.ExitCode -eq 0) 'hook process exits successfully'; $p.Dispose() }
    Assert (@(Get-ChildItem $events -Filter '*.json').Count -eq 2) 'simultaneous hook writers retain both complete records'
    # Feed a definite newest approval and confirm its checkpoint survives restart.
    Write-ClawdJson (Join-Path $events 'approval.json') @{session='test';turn='one';token='notify';at=[datetime]::UtcNow.AddMilliseconds(1).ToString('o')}
    & (Join-Path $PSScriptRoot 'codex-watch.ps1') -CodexHome $root -StateDirectory $events -OutputPath $out -Iterations 1
    & (Join-Path $PSScriptRoot 'codex-watch.ps1') -CodexHome $root -StateDirectory $events -OutputPath $out -Iterations 1
    Assert ((Get-ClawdDisplayState $false $true $out $legacy).token -eq 'notify') 'restart preserves hook-only approval state'

    $late = Join-Path $root 'sessions/late.jsonl'
    $lateOut = Join-Path $root 'late-output.json'
    [IO.File]::WriteAllText($late,'')
    $watcher = Join-Path $PSScriptRoot 'codex-watch.ps1'
    $worker = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$watcher`" -CodexHome `"$root`" -StateDirectory `"$root\late-events`" -OutputPath `"$lateOut`" -Iterations 8"
    try {
        $deadline = [datetime]::UtcNow.AddSeconds(10)
        while (-not [IO.File]::Exists($lateOut) -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
        Assert ([IO.File]::Exists($lateOut)) 'watcher starts with an empty new session'
        $stamp = [datetime]::UtcNow.ToString('o')
        $lateRows = @(
            @{timestamp=$stamp;type='session_meta';payload=@{id='late';source='cli'}},
            @{timestamp=$stamp;type='event_msg';payload=@{type='task_started';turn_id='late-turn'}}
        )
        [IO.File]::WriteAllText($late,(($lateRows | ForEach-Object {$_|ConvertTo-Json -Depth 8 -Compress}) -join "`n") + "`n")
        Assert ($worker.WaitForExit(10000)) 'bounded watcher finishes'
        $lateState = (Read-ClawdJson $lateOut).states | Where-Object {$_.session -eq 'late'}
        Assert ($lateState.token -eq 'think') 'metadata arriving after file creation is detected'
    } finally { if (-not $worker.HasExited) {$worker.Kill()}; $worker.Dispose() }

    [IO.File]::WriteAllText($config,'{"features":{"claudeWatch":false},"size":80}')
    $original = '{"custom":123,"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo unrelated"},{"type":"command","command":"clawd-emit.cmd done"}]}]}}'
    [IO.File]::WriteAllText($hooks,$original)
    & (Join-Path $PSScriptRoot 'codex-watch-on.ps1') -CodexHome $root -ClawdConfig $config
    & (Join-Path $PSScriptRoot 'codex-watch-on.ps1') -CodexHome $root -ClawdConfig $config
    $installed = [IO.File]::ReadAllText($hooks)|ConvertFrom-Json
    Assert (@($installed.hooks.Stop).Count -eq 2) 'install is idempotent and preserves mixed entries'
    Assert (([IO.File]::ReadAllText($config)|ConvertFrom-Json).features.claudeWatch -eq $false) 'Claude feature preserved'
    & (Join-Path $PSScriptRoot 'codex-watch-off.ps1') -CodexHome $root -ClawdConfig $config
    Assert ([IO.File]::ReadAllText($hooks) -ceq $original) 'uninstall restores exact original hooks'
    & (Join-Path $PSScriptRoot 'codex-watch-on.ps1') -CodexHome $root -ClawdConfig $config
    $edited = [IO.File]::ReadAllText($hooks)|ConvertFrom-Json
    $edited | Add-Member userEdit 'keep-me'
    Write-ClawdJson $hooks $edited
    & (Join-Path $PSScriptRoot 'codex-watch-off.ps1') -CodexHome $root -ClawdConfig $config
    $restored = [IO.File]::ReadAllText($hooks)|ConvertFrom-Json
    Assert ($restored.userEdit -eq 'keep-me') 'uninstall preserves subsequent user edits'
    Assert (@($restored.hooks.Stop | ForEach-Object {$_.hooks} | Where-Object {$_.command -eq 'clawd-emit.cmd done'}).Count -eq 1) 'migrated legacy hook restored once'
    Assert (-not (Test-Path (Join-Path $root 'config.toml'))) 'Codex TOML never created or modified'
    Write-Host 'ALL CHECKS PASSED'
} finally {
    $resolved = [IO.Path]::GetFullPath($root)
    if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) -and (Split-Path $resolved -Leaf) -like 'clawd-watch-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
