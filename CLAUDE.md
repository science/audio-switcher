# Audio Switcher Project

## What This Is

A PipeWire auto-routing and recovery daemon for Linux. Two jobs:

1. **HID-based headset detection + priority routing** — Reads vendor HID reports from each headset dongle's hidraw device to detect connect/disconnect, then routes PipeWire defaults by a priority ladder. Keeping the default **sink and source matched to the same device** is the core job — the OS/apps routinely mismatch headset speaker/mic on their own.

   Priority ladder: **Jabra Evolve2 buds (Link 390) > Sennheiser BTD-800 > S/PDIF speakers**. A dongle merely being plugged in does *not* count — the headset must be linked to it. When the active headset disconnects, routing falls through to the next-highest connected device, or to S/PDIF (sink only — no matching mic).
2. **PipeWire recovery** — Polls journalctl for broken-pipe errors and restarts PipeWire when a threshold is exceeded, then re-applies the correct audio defaults based on the current priority resolution.

## Architecture

### Event Flow

```
event_loop() discovers + monitors BOTH dongles concurrently:

  monitor_hidraw(btd)      ─┐                      set_device_state(btd, …)
  monitor_jabra_hidraw(jabra)┼─ tagged events ──→  set_device_state(jabra, …)
                            ─┘  (btd:… / jabra:…)        ↓
                                                   resolve_active_device()  jabra>btd>none
                                                         ↓
                                                   apply_priority()
                                                         ↓
                              ┌──────────────────────────┼───────────────────────┐
                          active=jabra               active=btd               active=none
                    find_jabra_sink/source     find_btd_sink/source        apply_spdif_sink()
                              └─── pactl set-default-sink AND -source (matched pair) ───┘

pipewire_health_loop() (background, every 30s; hunt mode every 10s)
        ↓
  check_pipewire_health()
        ↓
  journalctl broken-pipe count ≥ PW_ERROR_THRESHOLD?
        ↓ yes
  systemctl restart pipewire pipewire-pulse wireplumber
        ↓
  apply_priority()   (re-resolves ladder from per-device state)
```

### HID Detection

Both dongles handle their wireless link internally — PipeWire/ALSA never see connect/disconnect, only the dongle. Each emits an HID report on link change. PipeWire *cannot* tell "dongle plugged" from "headset linked" (the sink exists and goes RUNNING either way), so hidraw is the only reliable presence signal.

| Headset | hidraw match | Report | Connect flag |
|---------|--------------|--------|--------------|
| BTD-800 | vid `1395` pid `002d` | ID 1 | byte 19: `0x01`/`0x00` |
| Jabra Link 390 | vid `0b0e` pid `2e50` | ID 5, header `05 00 01 00 08 0d` | byte 6: `0x01` conn / `0x02` disc |

The Jabra header match is required to reject lookalike reports that begin `05 00 04 ..` and also contain `08 0d`. Each monitor (`monitor_hidraw`, `monitor_jabra_hidraw`) uses an embedded Python helper (bash can't do binary I/O) and emits `connected`/`disconnected`; `event_loop()` prefixes each with a device tag (`btd:` / `jabra:`). Signature reverse-engineered via `diag-jabra.sh`.

### State File IPC

Background subshells in bash can't share variables. The state file (`$XDG_RUNTIME_DIR/audio-switcher-state`) holds **per-device** state as `key=value` lines (`jabra=connected` / `btd=disconnected`), so the priority resolver and the recovery loop see the same picture:
- `set_device_state <device> <state>` — written by `event_loop()` on each HID event (preserves the other device's line)
- `get_device_state <device>` — defaults to `disconnected` when absent
- `resolve_active_device` — echoes `jabra|btd|none`; used by `apply_priority()` and `check_pipewire_health()`

### Audio Device Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `BTD_USB_ID` | `usb-1395_Sennheiser_BTD_800_USB-00` | Match pattern for BTD-800 sink/source (stable across profile changes) |
| `JABRA_SINK_MATCH` | `Jabra_Link_390` | Match pattern for Jabra sink/source/card |
| `JABRA_VID` | `0b0e` | Jabra/GN Netcom USB vendor id (hidraw discovery) |
| `SPDIF_SINK` | `alsa_output.pci-0000_00_1f.3.iec958-stereo` | Motherboard S/PDIF (stable) |

Sink/source names are **discovered at runtime** (`find_btd_sink/source`, `find_jabra_sink/source`). The Jabra name carries the dongle serial and can gain a suffix on re-plug (e.g. `…99AB` → `…99AB2`), so matching is by the `JABRA_SINK_MATCH` pattern, never the exact string.

### PipeWire Recovery Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `PW_ERROR_THRESHOLD` | 5 | Broken-pipe errors needed to trigger restart |
| `PW_CHECK_WINDOW` | 30s | How far back to look in journalctl |
| `PW_COOLDOWN_SECONDS` | 300 | Minimum seconds between restarts (5 min) |

### Key Functions

| Function | Purpose |
|----------|---------|
| `find_hidraw()` / `find_jabra_hidraw()` | Scan /dev/hidraw* for BTD-800 (vid:pid) / Jabra (vid `0b0e`) |
| `find_btd_sink/source()` / `find_jabra_sink/source()` | Discover sink/source names from PipeWire by match pattern |
| `find_jabra_card()` | Discover Jabra card name (for profile management) |
| `ensure_btd_input_profile()` / `ensure_jabra_input_profile()` | Switch card to a profile with mic input if output-only |
| `monitor_hidraw()` / `monitor_jabra_hidraw()` | Read HID reports via embedded Python, emit connected/disconnected |
| `event_loop()` | Discover + monitor both dongles concurrently; merge tagged events → `handle_event()` |
| `handle_event(device, state)` | Update device state, re-resolve priority, apply, hunt-mode on connect |
| `set_device_state()` / `get_device_state()` | Per-device state file IPC (key=value lines) |
| `resolve_active_device()` | Priority resolver → `jabra\|btd\|none` |
| `apply_priority()` | Resolve ladder + set matched default sink **and** source for the winner |
| `apply_sink_source()` | Set a matched sink+source pair (logs changes only) |
| `apply_spdif_sink()` | S/PDIF fallback sink with retry (output only) |
| `check_pipewire_health()` | Count broken-pipe errors, restart PipeWire if threshold met, `apply_priority` |
| `pipewire_health_loop()` | Background loop: sleep 30 (hunt: 10), check health, repeat |
| `sleep_resume_loop()` | Re-apply defaults + hunt mode on wake from suspend |
| `cleanup()` | Signal handler: kill background jobs, remove runtime files |
| `main()` | Arg parse + startup; guarded by `BASH_SOURCE`==`$0` so tests can source the daemon |

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
| `70-jabra.rules` | udev rule granting user access to Jabra Link 390 hidraw device |
| `diag-btd800.sh` | Diagnostic: raw BTD-800 HID report monitor (run with sudo) |
| `diag-jabra.sh` | Diagnostic: raw Jabra HID report monitor — used to RE the link signature (run with sudo) |
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

Categories:
- **Static checks** — Script exists, executable, shebang, constants, functions (HID + recovery + state + Jabra + priority)
- **Unit checks** — Source the daemon (guarded `main()`) and call functions directly: `resolve_active_device` truth table (jabra×btd combos) and the `monitor_jabra_hidraw` parser (connect/disconnect/lookalike).
- **Installation checks** — Binary installed, service file exists, enabled, active; both udev rules
- **Runtime checks** — Default sink/source matches the priority resolution (jabra → btd → S/PDIF)

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
