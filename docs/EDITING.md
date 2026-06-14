# Quick Edit Guide — clawd-pet.ps1

All the logic lives in one file: `clawd-pet.ps1`. Here's a map of its sections (find a title with Ctrl+F):

| Section (search for this) | What's in it |
|---|---|
| `Add-Type -ReferencedAssemblies` (first block) | C# helpers: GIF animator, window detection, input, sprite pixel processing |
| `# ---------- Config (clawd.json)` | Reading clawd.json + default values |
| `# ---------- Official assets` | Sprite loading + auto-download |
| `# ---------- Walking legs` | Leg-frame extraction from the CrabWalking GIF |
| `# ---------- Display size` | Scaling, margins, window geometry |
| `# ---------- State` | All runtime variables (position, mode, timers) |
| `function Set-State` / `Start-Fx` | State & effect switching |
| `Start-Balloon` / `Start-StarShow` / `Start-Shadow` | The three rare moments |
| `$script:form.Add_Paint` | ALL drawing (order: drag → lurk → code → balloon → normal → eyes → bubble) |
| `$script:timer.Add_Tick` | The main 60 fps engine (physics, timeline, idle decisions) |
| `# ---------- Mouse interaction` | Click, drag, throw |
| `# ---------- Right-click menu` | Menu items |

## Common recipes

- **Change size/speed/terminal text** → just edit `clawd.json`, then restart.
- **Change idle action odds** → find the random roll `$script:rand.NextDouble()` in the `'idle'` block; the chain of cumulative thresholds picks the action.
- **Change animation duration** → the tick number in `Set-State 'x' <ticks>` (1 second = 62.5 ticks).
- **Change The Shadow's color** → find `Darken($full, 0, 399, 330, 401,` — the first three numbers are the body (R,G,B), the next three are the eyes.
- **Change The Shadow's size** → find `$script:shDW` (the `* 1.5` multiplier).
- **Sprite clipped while animating?** → its window is too small: grow the margin on that window's `ClientSize` and the image offset (see the "window margin" comment in The Shadow's paint as an example).
- **Test without running the pet** → `powershell -File clawd-pet.ps1 -TestBlink` (compile + sprite check).
- **Apply changes** → run `stop-clawd.vbs` then `start-clawd.vbs`.
