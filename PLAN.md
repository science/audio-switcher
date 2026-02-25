# Plan: audio-switcher — PipeWire auto-routing daemon

## Context

The Sennheiser BTD-800 USB dongle is always physically plugged in. The user has two audio outputs: the headset (via dongle) and S/PDIF speakers. Currently, the default sink is set statically, which means either the headset or speakers are always favored. The user wants dynamic routing:
- When BTD-800 sink is available → default output to headset
- When BTD-800 sink disappears → fall back to S/PDIF speakers
- Microphone always defaults to BTD-800 when present

The earlier `pipewire-recovery` script hard-codes the BTD-800 as default sink after every PipeWire restart, which breaks the S/PDIF use case. That logic needs to move into this new daemon.

## Detection Mechanism: `pactl subscribe`

The user suggested inotify (like mouse-tools watches `/dev/input/`). For audio routing, `pactl subscribe` is better because it operates at the PipeWire layer — directly reports sink add/remove events, handles PipeWire restarts (connection breaks, daemon reconnects), and avoids correlating `/dev/snd/` nodes to PipeWire sinks. The daemon pipes `pactl subscribe` via process substitution and reacts to sink/source events.

## Project Structure — `~/dev/audio-switcher/`

```
audio-switcher         # Main daemon (bash) — pactl subscribe event loop
install.sh             # Deploy to ~/.local/bin + systemd user service
tests/
  test-audio-switcher.sh   # Static + runtime tests
CLAUDE.md              # AI dev conventions
.gitignore
```

## Files to Create

### 1. `audio-switcher` (main daemon)

Bash script with `set -euo pipefail`. Core logic:

- **Constants**: BTD-800 sink/source names, S/PDIF fallback sink, reconnect delay (2s), settle delay (0.5s)
- **`apply_defaults()`**: Checks current sink/source presence via `pactl list sinks short`, sets defaults with `pactl set-default-sink`/`set-default-source`. Only changes if not already correct (avoids log spam). No explicit fallback source — lets PipeWire choose when BTD-800 mic absent.
- **`subscribe_loop()`**: Outer `while true` with `pactl subscribe` via process substitution (`< <(pactl subscribe 2>&1)`). Parses for sink/source new/remove/change events. 0.5s settle delay batches rapid events. When `pactl subscribe` exits (PipeWire restart), waits 2s and reconnects.
- **Signal handling**: Trap SIGTERM/SIGINT, kill child processes on shutdown.

### 2. `install.sh`

Follows mouse-tools pattern but for a **user** service (no root needed):
- Copies script to `~/.local/bin/audio-switcher`
- Writes systemd service (`Type=simple`, `After=pipewire-pulse.service`, `Restart=on-failure`)
- `systemctl --user daemon-reload && enable --now`
- `--uninstall` flag for cleanup

### 3. `tests/test-audio-switcher.sh`

Static checks (script exists, has expected constants) + installation checks (service exists, enabled, active) + runtime checks (default sink matches BTD-800 presence).

### 4. `CLAUDE.md` and `.gitignore`

Dev conventions following mouse-tools pattern. TDD, run tests after changes, keep it bash-simple.

## Changes to Existing Files (yadm dotfiles)

### 5. `~/.local/bin/pipewire-recovery` — remove default sink logic

Remove `DEFAULT_SINK` constant and the post-restart `sleep 2 / pactl set-default-sink` block. The recovery script becomes purely a crash detector/restarter. Audio-switcher handles routing after PipeWire comes back.

### 6. `~/.config/yadm/test-dotfiles.sh` — add tests

- Audio-switcher service tests (installed, enabled, active) in `linux-bambam` block
- Regression guard: `pipewire-recovery` should NOT contain `set-default-sink`

## Implementation Order

1. Create `~/dev/audio-switcher/` with git init
2. Write tests first (TDD red) → write daemon → verify tests pass (TDD green)
3. Write install.sh → run it → verify service is running
4. Update pipewire-recovery (TDD: add negative test first, then remove sink logic)
5. Run full dotfiles test suite
6. Commit audio-switcher (git), commit dotfiles changes (yadm)

## Verification

1. `./tests/test-audio-switcher.sh` — all pass
2. `~/.config/yadm/test-dotfiles.sh` — all pass
3. `journalctl --user-unit audio-switcher -f` — shows correct routing on startup
4. `systemctl --user restart pipewire pipewire-pulse wireplumber` — audio-switcher detects disconnect, reconnects, re-applies correct defaults
