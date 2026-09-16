# Codex Watch verification

Implementation and interactive tests: 15 September 2026. Final regression and
real configuration restore check: 16 September 2026. Times below are Jakarta
(UTC+7). No commit or push was made.

## Environment

- Windows PowerShell 5.1; existing WinForms UI and animation assets.
- Claude Code 2.1.199.
- Terminal `codex` resolved to 0.144.6; the installed desktop-bundled executable
  was 0.154.0-alpha.6.2. The older CLI rejected the configured `gpt-6-astra` model
  with a request to upgrade. Interactive tool tests used the already-installed
  0.154 executable; no upgrade or persistent model change was made.
- `features list` reported hooks enabled. Existing Codex `notify` was retained.
- Both agents initially had Clawd hooks pointing at the nonexistent
  `C:\Users\lucit\ClawdPet`. Codex setup migrated only its Clawd hooks. The
  existing Claude setup script was rerun to point Claude hooks at this checkout.

## Manual tests

| Test | Observed result |
|---|---|
| Claude compatibility | Real Claude CLI used Read and Bash, returned `claude-smoke-done`. Render diagnostics recorded Claude `think` at 15:02:24, `read` at 15:02:38, `bash` at 15:02:41. A later real long command completed and rendered Claude `done` at 15:20:13. |
| Interactive Codex, hooks disabled | Started the interactive TUI with `--disable hooks`, submitted a prompt to read README, create a temporary smoke file with `apply_patch`, and run an 8-second shell command. It created `smoke-ok` and returned `smoke-done`. |
| JSONL fallback reactions | Actual render pipeline recorded Codex `think` at 15:01:00, `read` at 15:01:09, `edit` at 15:01:23, and `bash` at 15:01:39, with the status overlay visible. |
| Official hooks | Reviewed and trusted the adapter's PreToolUse and PermissionRequest hooks in the CLI. A second real task patched the smoke file to `hooks-ok` and requested approval for a harmless 30-second shell command. `bash` rendered at 15:08:26 and `notify` at 15:08:28 while the TUI displayed its approval prompt. Other untrusted lifecycle hooks were covered by the fallback rather than claimed as live-hook tests. |
| Completion and idle | Codex `done` rendered at 15:12:02. In a subsequent turn, completion timestamp was 15:15:44.011; polling selected `done` through 15:15:51.512 and no state from 15:15:52.523 onward, matching the 8-second done lifetime. |
| Concurrent agents | While Codex waited for approval, a real Claude turn rendered `think` at 15:09:52 and finished. The selected state returned to Codex `notify` at 15:09:55, not done/idle. At 15:18:33.367 a separate live poll selected Claude `bash` while the latest Codex state remained an older `done`. Fresh completion in both directions and multiple Codex sessions are also covered by deterministic checks. |
| Restart | Clawd and its worker were restarted during the interactive tests. Subsequent Codex `bash` at 15:11:58 and `done` at 15:12:02 rendered successfully. Hook-only approval checkpoint recovery was separately tested with isolated files. |
| Configuration validity | Codex loaded the installed configuration and reported `hooks stable true` via `codex features list`. `--strict-config features list` is unsupported by this version; it was not counted as a validation pass. |
| Real uninstall/re-enable | Ran the off script against the actual Codex home. SHA-256 of restored `hooks.json` exactly matched the pre-install baseline. Ran the on script again. SHA-256 of `config.toml` was unchanged across both operations. Codex's own earlier hook trust decisions added its normal trust metadata; the installer did not edit TOML. |

The visual evidence consists of PNGs saved from the actual rendered bubble
buffers and source/token/state/overlay-visible diagnostics. It is not a desktop
screen recording. Test artifacts are outside the repository, beside it, named
`ClawdPet-watch-test.jsonl*` and `ClawdPet-live-audit.jsonl`.

## Automated checks

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-agent-watch.ps1`.
The final run passed every assertion, including:

- Token mapping, conservative shell-read classification, unknown-tool handling,
  and distinguishing code-mode `wait` from delegated-agent waits.
- Active agent priority, delayed/out-of-order completion, closed-turn protection,
  multiple Codex sessions, expiry, and the unchanged Claude-only 15-second timeout.
- Partial JSONL, metadata arriving after an empty file is discovered, restart
  replay, approval checkpoint recovery, and PowerShell 5.1 timestamp serialization.
- Real concurrent hook subprocesses producing separate complete event files.
- A transient empty Claude token file retaining the previous valid state.
- Idempotent setup, mixed hook entries, exact original restoration, preservation
  of subsequent user edits, and no TOML creation/modification by setup.

All PowerShell files parsed successfully; `git diff --check` passed. Sprite
generation with `clawd-pet.ps1 -TestBlink` also passed.

## Fixes found by testing and remaining limits

- An existing call referenced a nonexistent `ClawdChime` class. It was removed.
  The user's pre-existing custom sound-generation changes remain intact.
- The existing cached WAV failed playback. Audio exceptions previously prevented
  applying `done`; playback is now isolated so visual completion still succeeds.
  Repairing the sound file itself is outside this change.
- An early test incorrectly labelled a code-mode wait as `task`; that mapping was
  corrected and regression-tested. The old diagnostic artifact remains evidence
  of the test iteration, not evidence of a delegated task.
- Live web-search and delegated-agent turns were not run. Their supported event
  mappings are implemented; no claim of live end-to-end coverage is made.
- JSONL can report code-mode tool activity only after the completed item arrives.
  Approval resolution can remain unobservable until the next event. Unknown
  events are ignored rather than inferred from assistant prose.
- Idle/crash detection uses an explicit 30-minute inactivity bound in dual-agent
  mode. Claude-only mode remains at 15 seconds. Startup replay is bounded to
  512 KiB per recent session. See README for the full operational limits.
