# Shared token/state helpers. No UI, agent processes, or configuration side effects.
$script:clawdLegacyState = @{}
function Read-ClawdJson([string]$Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader = New-Object IO.StreamReader($stream)
    try { return ($reader.ReadToEnd() | ConvertFrom-Json) }
    finally { $reader.Dispose() }
}

function Write-ClawdJson([string]$Path, $Value) {
    $tmp = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($tmp, ($Value | ConvertTo-Json -Depth 20 -Compress), (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) }
        else { [IO.File]::Move($tmp, $Path) }
    } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}

function Get-ClawdToolToken([string]$Name, $Arguments) {
    $name = ($Name -split '\.')[-1]
    if ($name -match '^(apply_patch|Edit|Write|MultiEdit|NotebookEdit)$|(^|__)(write_file|edit_file|patch_file)$') { return 'edit' }
    if ($name -match '^(Read|Grep|Glob|read_file|list_dir|search_files)$|(^|__)(read_file|search_files|list_directory)$') { return 'read' }
    if ($name -match '^(web_search|WebSearch|WebFetch)$|(^|__)web(__|$)') { return 'web' }
    if ($name -match '^(spawn_agent|Agent|Task|send_message|wait_agent|resume_agent|close_agent)$') { return 'task' }
    if ($name -eq 'wait' -and $Arguments.ids) { return 'task' } # Native subagent wait, not a code-mode cell wait.
    if ($name -match '^request_user_input(_async)?$') { return 'notify' }
    if ($name -match '^(Bash|shell|shell_command|exec_command|local_shell|write_stdin)$') {
        $cmd = [string]$Arguments.command
        if (-not $cmd) { $cmd = [string]$Arguments.cmd }
        # Only classify simple, entirely read-only PowerShell pipelines as file reads.
        # Never execute the command. Mixed/unknown commands remain bash.
        if ($cmd) {
            $parseErrors = $null; $tokens = $null
            $ast = [Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$tokens, [ref]$parseErrors)
            $commands = @($ast.FindAll({param($a) $a -is [Management.Automation.Language.CommandAst]}, $true))
            $names = @($commands | ForEach-Object { $_.GetCommandName() })
            $unknown = @($names | Where-Object { -not $_ -or $_ -notmatch '^(Get-Content|Get-ChildItem|Get-Item|Select-String|Test-Path|Resolve-Path|Get-Location|Select-Object|Sort-Object|Format-Table|cat|ls|dir|type|pwd|rg|grep|head|tail|findstr)$' })
            $redirects = @($ast.FindAll({param($a) $a -is [Management.Automation.Language.RedirectionAst]}, $true))
            if (-not $parseErrors -and $commands.Count -gt 0 -and $unknown.Count -eq 0 -and $redirects.Count -eq 0 -and ($names -match '^(Get-Content|Get-ChildItem|Get-Item|Select-String|cat|ls|dir|type|rg|grep|head|tail|findstr)$')) { return 'read' }
        }
        return 'bash'
    }
    return '' # Unknown tools do not invent an activity.
}

function Set-ClawdState($States, [string]$Key, [string]$Source, [string]$Token, [datetime]$At, [string]$Turn = '', [bool]$Closed = $false) {
    if ($Token -notin @('think','bash','edit','read','web','task','notify','done')) { return }
    $old = $States[$Key]
    if ($old -and $old.at -gt $At) { return }
    # A delayed completion from an earlier turn cannot finish a newer turn.
    if ($old -and $Token -eq 'done' -and $Turn -and $old.turn -and $old.turn -ne $Turn) { return }
    if ($old -and $old.closed -and $old.turn -eq $Turn) {
        if ($Token -ne 'done') { return }
        $Closed = $true
    }
    $States[$Key] = [pscustomobject]@{ source=$Source; token=$Token; at=$At; turn=$Turn; session=$Key; closed=$Closed }
}

function Select-ClawdState($States, [datetime]$Now = [datetime]::UtcNow, [int]$ClaudeTimeout = 15) {
    $fresh = @($States | Where-Object {
        $limit = if ($_.token -eq 'done') { 8 } elseif ($_.source -eq 'claude') { $ClaudeTimeout } else { 1800 }
        ($Now - [datetime]$_.at).TotalSeconds -lt $limit -and ($Now - [datetime]$_.at).TotalSeconds -ge -5
    })
    $active = @($fresh | Where-Object { $_.token -ne 'done' })
    if ($active.Count) { return $active | Sort-Object at -Descending | Select-Object -First 1 }
    return $fresh | Sort-Object at -Descending | Select-Object -First 1
}

function Get-ClawdDisplayState([bool]$Claude, [bool]$Codex, [string]$CodexFile, [string]$LegacyFile = (Join-Path $env:TEMP 'clawd-status.txt')) {
    $states = @(); $now = [datetime]::UtcNow
    if ($Claude -and [IO.File]::Exists($LegacyFile)) {
        try {
            $token = [IO.File]::ReadAllText($LegacyFile).Trim().ToLowerInvariant()
            if ($token -in @('think','bash','edit','read','web','task','notify','done')) {
                $script:clawdLegacyState[$LegacyFile] = [pscustomobject]@{source='claude';token=$token;at=[IO.File]::GetLastWriteTimeUtc($LegacyFile)}
            }
        } catch { } # A legacy cmd writer can briefly hold the file exclusively.
        # Retain the last valid token during a legacy truncate/write, so another
        # agent's done cannot win just because Claude's file was briefly empty.
        if ($script:clawdLegacyState.ContainsKey($LegacyFile)) { $states += $script:clawdLegacyState[$LegacyFile] }
    }
    if ($Codex -and [IO.File]::Exists($CodexFile)) {
        try {
            if (($now - [IO.File]::GetLastWriteTimeUtc($CodexFile)).TotalSeconds -lt 5) {
                $snapshot = Read-ClawdJson $CodexFile
                foreach ($s in $snapshot.states) {
                    $s.at = ([datetime]$s.at).ToUniversalTime()
                    $states += $s
                }
            }
        } catch { }
    }
    # Preserve the legacy 15s behavior for Claude-only installations. In dual-agent
    # mode, a long Claude command needs the same activity lease as a Codex command.
    $claudeTimeout = if ($Codex) { 1800 } else { 15 }
    return Select-ClawdState $states $now $claudeTimeout
}

function Read-ClawdCodexEvent($Row, $Cursor, $States) {
    $p = $Row.payload
    $at = ([datetime]$Row.timestamp).ToUniversalTime()
    if ($Row.type -eq 'session_meta') {
        if ($p.id) { $Cursor.session = [string]$p.id }
        # CLI only: Desktop shares the same session directory and must not drive this adapter.
        $Cursor.cli = ($p.source -eq 'cli' -or $p.source -eq 'exec' -or $p.originator -match '^codex_(cli|exec)')
        return
    }
    if (-not $Cursor.cli) { return }
    $token = ''
    if ($Row.type -eq 'turn_context' -and $p.turn_id) { $Cursor.turn = [string]$p.turn_id; return }
    if ($Row.type -eq 'event_msg') {
        switch ($p.type) {
            'task_started' { $Cursor.turn = [string]$p.turn_id; $token = 'think' }
            'task_complete' { $token = 'done' }
            'turn_aborted' { $token = 'done' }
            'agent_reasoning' { $token = 'think' }
            'exec_approval_request' { $token = 'notify' }
            'apply_patch_approval_request' { $token = 'notify' }
            'request_user_input' { $token = 'notify' }
            'item_completed' {
                $item = $p.item
                switch ($item.type) {
                    'CommandExecution' {
                        $parsed = @($item.parsed_cmd)
                        $token = if ($parsed.Count -gt 0 -and @($parsed | Where-Object { $_.type -notin @('read','list_files','search') }).Count -eq 0) { 'read' } else { 'bash' }
                    }
                    'FileChange' { $token = 'edit' }
                    'Reasoning' { $token = 'think' }
                    'WebSearch' { $token = 'web' }
                    'CollabAgentToolCall' { $token = 'task' }
                    'Extension' { if ($item.kind -match 'web_search') { $token = 'web' } }
                }
            }
        }
    } elseif ($Row.type -eq 'response_item') {
        switch ($p.type) {
            'reasoning' { $token = 'think' }
            'web_search_call' { $token = 'web' }
            'function_call' {
                $argsObj = $null
                try { $argsObj = $p.arguments | ConvertFrom-Json } catch { }
                $token = Get-ClawdToolToken $p.name $argsObj
            }
            'custom_tool_call' { $token = Get-ClawdToolToken $p.name $null }
        }
    }
    $turn = $Cursor.turn
    if ($p.turn_id) { $turn = [string]$p.turn_id }
    if ($token) { Set-ClawdState $States $Cursor.session 'codex' $token $at $turn ($p.type -in @('task_complete','turn_aborted')) }
}
