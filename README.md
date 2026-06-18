# Clawd Pet

A desktop pet for Windows built in plain PowerShell + WinForms — no installer, no build step. He walks along the taskbar, follows your cursor, blinks, and gets into all kinds of trouble on his own.

![demo](docs/demo.gif)

## What he does

Walks with real frame-by-frame animation, eyes track your cursor, a confused **"?"** floats up when you start typing, and he climbs onto open app windows and rides them around.

Pick him up and he dangles from the cursor. Throw him and he actually gets flung — speed matches how fast you flick, he arcs through the air, bounces off the walls, squashes on impact. The physics was the part I cared about most.

Leave him running and he starts doing his own thing. I won't spoil them, but they're all sitting in the right-click menu if you don't want to wait.

## Claude Watch — he shows what Claude Code is doing

This is the part I'm proudest of. Hook him into **Claude Code** and a small bubble shows up over his head telling you exactly what it's doing right now:

> *thinking… · running a command… · writing code… · reading files… · done ✓*

To turn it on:

```
Right-click  tools\claude-watch-on.ps1  →  Run with PowerShell
```

Installs the hooks into your Claude Code settings and leaves everything else alone. `tools\claude-watch-off.ps1` removes them.

## Getting started

Needs **Windows 10 or 11** (PowerShell 5.1 is already there) and internet on the first run.

1. Download or clone the repo
2. Double-click **`start-clawd.vbs`** — first launch pulls the sprites from claude.ai automatically
3. Want him to start with Windows? Right-click `autostart-on.ps1` → **Run with PowerShell**

> If SmartScreen warns about the `.vbs`, click **More info → Run anyway**. It's three lines — you can read the whole thing.

## Config — `clawd.json`

Change anything, restart, done.

| Key | Default | What it does |
|-----|---------|--------------|
| `size` | `80` | Width in px (48–200). Everything scales with it. |
| `walkSpeed` / `gravity` | `1.0` | Speed and gravity multipliers |
| `features.claudeWatch` | `true` | The Claude Code status bubble |
| `features.eyeTracking` | `true` | Eyes follow the cursor |
| `features.windowPlatforms` | `true` | Stand and ride on app windows |
| `features.mischief` | `true` | The rarer, unprompted antics |

## About the sprites

Clawd and his artwork belong to **Anthropic** — pulled from claude.ai on first run, never bundled here. Fan project, not official, Anthropic had nothing to do with it.

## License

[MIT](LICENSE) — code only. See above for the sprites.
