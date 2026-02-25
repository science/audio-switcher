# Audio Switcher Project

## What This Is

A PipeWire auto-routing daemon for Linux. Monitors sink/source availability via `pactl subscribe` and dynamically sets audio defaults:
- When Sennheiser BTD-800 USB dongle sink is available, default output to headset
- When BTD-800 sink disappears, fall back to S/PDIF speakers
- Microphone always defaults to BTD-800 when present

## Architecture

### Event Loop

```
pactl subscribe → parse sink/source events → apply_defaults()
   ↑                                              ↓
   └── reconnect on PipeWire restart ←── pactl set-default-sink/source
```

The daemon runs `pactl subscribe` via process substitution. When PipeWire restarts (connection breaks), it waits and reconnects. A settle delay batches rapid events.

### Audio Device Constants

| Device | PipeWire Name |
|--------|---------------|
| BTD-800 sink (headset output) | `alsa_output.usb-1395_Sennheiser_BTD_800_USB-00.analog-stereo` |
| BTD-800 source (headset mic) | `alsa_input.usb-1395_Sennheiser_BTD_800_USB-00.mono-fallback` |
| S/PDIF fallback sink (speakers) | `alsa_output.pci-0000_00_1f.3.iec958-stereo` |

### Key Functions

- **`apply_defaults()`** — Checks sink/source presence, sets defaults only if change needed
- **`subscribe_loop()`** — Outer reconnect loop wrapping `pactl subscribe` event parsing
- **Signal handling** — Traps SIGTERM/SIGINT, kills child processes on shutdown

## Development Rules

1. **TDD: Red -> Green -> Refactor** — Write or update tests FIRST, verify they fail, then implement. Every change must include tests.
2. **Run tests after every change** — `./tests/test-audio-switcher.sh`. Non-negotiable.
3. **Keep it bash-simple** — Pure bash daemon, no external dependencies beyond `pactl` and standard coreutils.
4. **Don't break the event loop** — The subscribe loop must handle PipeWire restarts gracefully. No unhandled failures.
5. **Log sparingly** — Log routing changes and errors. Don't log every event in production.

## Key Files

| File | Purpose |
|------|---------|
| `audio-switcher` | Main daemon (bash) — pactl subscribe event loop |
| `install.sh` | Install/uninstall systemd user service |
| `tests/test-audio-switcher.sh` | Test suite (static + runtime) |
| `CLAUDE.md` | This file — project rules for AI |
| `PLAN.md` | Original design document |

## Testing Approach

Tests in `tests/test-audio-switcher.sh` use a pass/fail pattern:
```bash
if [[ some_condition ]]; then
    test_result "Description" "pass"
else
    test_result "Description" "fail"
fi
```

Three categories:
- **Static checks** — Script exists, executable, has expected constants, correct shebang
- **Installation checks** — Service file exists, enabled, active
- **Runtime checks** — Default sink matches BTD-800 presence, daemon responds to events

## Common Tasks

### Run tests
```bash
./tests/test-audio-switcher.sh
```

### Run manually
```bash
./audio-switcher
```

### Install as systemd user service
```bash
./install.sh                  # install + enable + start
./install.sh --uninstall      # stop + disable + remove
```

### Check logs
```bash
journalctl --user-unit audio-switcher -f
```

### Restart after PipeWire changes
The daemon auto-reconnects. To force restart:
```bash
systemctl --user restart audio-switcher
```
