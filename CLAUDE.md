# Audio Switcher Project

## What This Is

A PipeWire auto-routing and recovery daemon for Linux. Two jobs:

1. **HID-based headset detection** — Reads vendor HID reports from the Sennheiser BTD-800 USB dongle's hidraw device to detect headset connect/disconnect, then sets PipeWire audio defaults accordingly.
2. **PipeWire recovery** — Polls journalctl for broken-pipe errors and restarts PipeWire when a threshold is exceeded, then re-applies the correct audio defaults based on current headset state.

## Architecture

### Event Flow

```
find_hidraw() → monitor_hidraw() → event_loop()
                    ↓                    ↓
              python3 HID reader    write_state() → STATE_FILE
                    ↓                    ↓
              stdout: connected/    apply_defaults()  ← find_btd_sink()/find_btd_source()
                      disconnected       ↓
                                    pactl set-default-sink/source
                                         ↓ (on connect)
                                    rapid_health_check() (background, ~30s)
                                         ↓
                                    any broken pipe? → restart PipeWire → re-apply

pipewire_health_loop() (background, every 30s)
        ↓
  check_pipewire_health()
        ↓
  journalctl broken-pipe count ≥ PW_ERROR_THRESHOLD?
        ↓ yes
  systemctl restart pipewire pipewire-pulse wireplumber
        ↓
  read_state() → apply_defaults(connected|disconnected)
```

### HID Detection

The BTD-800 USB dongle handles Bluetooth internally — PipeWire/ALSA never see connection events. The dongle's HID interface sends vendor reports (Report ID 1) on connect/disconnect. Byte 19 is the connection flag: `0x01` = connected, `0x00` = disconnected.

`monitor_hidraw()` uses an embedded Python helper for binary HID report parsing (bash can't do binary I/O). It outputs `connected` or `disconnected` lines on stdout, consumed by `event_loop()`.

### State File IPC

Background subshells in bash can't share variables. The state file (`$XDG_RUNTIME_DIR/audio-switcher-state`) bridges the HID event loop and health check loop:
- `write_state "connected"` / `write_state "disconnected"` — written by `event_loop()` on each HID event
- `read_state` — read by `check_pipewire_health()` to know which defaults to re-apply after a PipeWire restart

### Audio Device Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `BTD_USB_ID` | `usb-1395_Sennheiser_BTD_800_USB-00` | Match pattern for BTD-800 sink/source (stable across profile changes) |
| `SPDIF_SINK` | `alsa_output.pci-0000_00_1f.3.iec958-stereo` | Motherboard S/PDIF (stable) |

BTD-800 sink and source names are **discovered at runtime** via `find_btd_sink()` / `find_btd_source()`. The actual PipeWire name depends on which profile is active (e.g. `analog-stereo` or `iec958-stereo`).

### PipeWire Recovery Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `PW_ERROR_THRESHOLD` | 5 | Broken-pipe errors needed to trigger restart |
| `PW_CHECK_WINDOW` | 30s | How far back to look in journalctl |
| `PW_COOLDOWN_SECONDS` | 300 | Minimum seconds between restarts (5 min) |

### Key Functions

| Function | Purpose |
|----------|---------|
| `find_hidraw()` | Scan /dev/hidraw* for BTD-800 by USB vendor:product ID |
| `find_btd_sink()` | Discover BTD-800 sink name from PipeWire (matches `BTD_USB_ID` pattern) |
| `find_btd_source()` | Discover BTD-800 source name from PipeWire (excludes `.monitor`) |
| `monitor_hidraw()` | Read HID reports via embedded Python, emit connected/disconnected |
| `event_loop()` | Main loop: read monitor output, write state, apply defaults, spawn rapid checks |
| `apply_defaults()` | Discover + set PipeWire default sink/source based on connected/disconnected |
| `write_state()` / `read_state()` | State file IPC between event loop and health check |
| `check_pipewire_health()` | Count broken-pipe errors, restart PipeWire if threshold met, re-apply defaults |
| `pipewire_health_loop()` | Background loop: sleep 30, check health, repeat |
| `rapid_health_check()` | Post-connect rapid checks (~10x at 3s intervals, threshold=1 broken pipe) |
| `cleanup()` | Signal handler: kill background jobs, remove runtime files |

## Development Rules

1. **TDD: Red -> Green -> Refactor** — Write or update tests FIRST, verify they fail, then implement. Every change must include tests.
2. **Run tests after every change** — `./tests/test-audio-switcher.sh`. Non-negotiable.
3. **Keep it bash-simple** — Pure bash daemon (with embedded Python for binary HID parsing). No external dependencies beyond `pactl`, `journalctl`, `systemctl`, `python3`, and standard coreutils.
4. **Don't break the event loop** — The HID monitor must handle device disconnects gracefully. No unhandled failures.
5. **Log sparingly** — Log routing changes, PipeWire restarts, and errors. Don't log every poll cycle.

## Key Files

| File | Purpose |
|------|---------|
| `audio-switcher` | Main daemon (bash) — HID event loop + PipeWire health monitor |
| `install.sh` | Install/uninstall systemd user service + udev rule |
| `uninstall.sh` | Convenience wrapper for `install.sh --uninstall` |
| `tests/test-audio-switcher.sh` | Test suite (static + installation + runtime) |
| `70-btd800.rules` | udev rule granting user access to BTD-800 hidraw device |
| `diag-btd800.sh` | Diagnostic: raw HID report monitor (run with sudo) |
| `CLAUDE.md` | This file — project rules for AI |
| `README.md` | User-facing documentation |
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
- **Static checks** — Script exists, executable, shebang, constants, functions (HID + recovery + state)
- **Installation checks** — Binary installed, service file exists, enabled, active
- **Runtime checks** — Default sink/source matches BTD-800 presence

### TDD Workflow
1. Add test to `tests/test-audio-switcher.sh` for the new behavior
2. Run tests — new test should fail
3. Implement the change
4. Run tests — all should pass
5. Commit both test and implementation together

## Common Tasks

### Run tests
```bash
./tests/test-audio-switcher.sh
```

### Run manually
```bash
./audio-switcher [-v|--verbose]
```

### Install as systemd user service
```bash
./install.sh
```

### Uninstall
```bash
./uninstall.sh
# or: ./install.sh --uninstall
```

### Check logs
```bash
journalctl --user-unit audio-switcher -f
```

### Diagnostics (raw HID monitoring)
```bash
sudo ./diag-btd800.sh
```
