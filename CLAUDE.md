# Audio Switcher Project

## What This Is

A PipeWire auto-routing and recovery daemon for Linux, built for Sennheiser/EPOS headsets on the BTD-800 USB Bluetooth dongle. Its jobs:

1. **HID-based headset detection + routing** — Reads the vendor HID report from the BTD-800 dongle's hidraw device to detect headset link/unlink. Linked → default sink **and** source set to the headset (a matched pair — the OS/apps routinely mismatch headset speaker/mic on their own). Unlinked → default sink falls back to the S/PDIF speakers (sink only; no matching mic). A dongle merely being plugged in does *not* count — the headset must be linked to it.
2. **PipeWire recovery** — Polls journalctl for broken-pipe errors and restarts PipeWire when a threshold is exceeded, then re-applies the correct audio defaults from the current headset state.
3. **Desktop default-sink resync** — Cinnamon's volume keys (`csd-media-keys`) and sound applet keep their own copy of the default sink (libcvc), updated only by pipewire-pulse change events. When a re-created default sink comes back without one, the daemon re-announces it. See "Desktop Default-Sink Resync" below.

### History: Jabra support removed (2026-11-06)

From June to November 2026 the daemon also supported Jabra Evolve2 buds on a Link 390 dongle (priority ladder Jabra > BTD-800 > S/PDIF, a dead-mic probe, a DeepFilterNet typing filter). The buds were retired: call quality varied between calls and the mic picked up typing and room sound. All of that was removed; it lives in git history from `d3cec59` through `fdc9505` (including the `JABRA-DEAD-MIC.md` investigation log). Kept from that period because they are not Jabra-specific: the sourceable `main()` guard, the strict-mode-safe retry counters, waiting for an absent dongle instead of exiting, and the default-sink resync.

## Architecture

### Event Flow

```
event_loop()  find_hidraw (1395:002d) — absent? re-check every 10 s; unreadable? log + re-check
     ↓
monitor_hidraw (embedded Python) → connected / disconnected
     ↓
handle_event btd <state> → set_device_state → apply_priority
                                                 ↓
                         resolve_active_device = btd ──→ ensure_btd_input_profile,
                                                 │        set-default-sink AND -source (matched pair)
                                                 └ none ─→ apply_spdif_sink (sink only, with retry)

pipewire_health_loop() (background, every 30s; hunt mode every 10s)
  → check_pipewire_health: journalctl broken-pipe count ≥ threshold?
  → systemctl --user restart pipewire pipewire-pulse wireplumber → apply_priority

sleep_resume_loop() (background): logind PrepareForSleep(false) → apply_priority + hunt mode

desktop_sync_loop() (background)
  pactl subscribe | grep "'new' on sink #" → desktop_sync_watch (one check per burst, 2 s quiet)
  → sync_desktop_default_sink: same name, new index? → resync_desktop_default_sink
```

### HID Detection

The dongle handles the Bluetooth link internally — PipeWire/ALSA never see connect/disconnect, only the dongle. PipeWire *cannot* tell "dongle plugged" from "headset linked" (the sink exists and goes RUNNING either way), so hidraw is the only reliable presence signal.

- hidraw match: USB vendor `1395`, product `002d` (walks `/sys/class/hidraw/*/device/../../idVendor`).
- Report: ID 1; byte 19 (0-indexed, counting the report-id byte) is `0x01` linked / `0x00` unlinked.
- `monitor_hidraw` uses an embedded Python helper (bash can't do binary I/O) and prints `connected` / `disconnected`.

### Multiple headsets / dongles

There is no unit-specific code. The dongle reports no USB serial, and every match is by model: hidraw by `1395:002d`, PipeWire names by `BTD_USB_ID`. So several headsets paired to one dongle, or swapping one BTD-800 dongle for another, need no changes (the dongle was swapped on 2026-11-06 and the daemon picked it up as is). Not supported: two dongles plugged in at once (the first found is watched), or a dongle with a different USB ID or PipeWire name (e.g. an EPOS-branded one) — that needs `find_hidraw`, `BTD_USB_ID` and `70-btd800.rules` extended, and its HID report confirmed with `diag-btd800.sh`.

### State File IPC

Background subshells in bash can't share variables. The state file (`$XDG_RUNTIME_DIR/audio-switcher-state`, overridable via `STATE_FILE` for tests) holds `key=value` lines (`btd=connected`), so the event loop, the recovery loop and the resume loop see the same picture.

- `set_device_state <device> <state>` — written by `handle_event` (atomic replace of that device's line).
- `get_device_state <device>` — defaults to `disconnected` when absent.
- `resolve_active_device` — echoes `btd|none`. Unknown keys (e.g. a stale `jabra=` line) are ignored.

### Audio Device Constants

- `BTD_USB_ID` = `usb-1395_Sennheiser_BTD_800_USB-00` — match pattern for the BTD-800 sink, source and card (stable across profile changes; the full sink/source names vary with the active profile, so they are discovered at runtime by `find_btd_sink` / `find_btd_source`).
- `SPDIF_SINK` = `alsa_output.pci-0000_00_1f.3.iec958-stereo` — motherboard S/PDIF (stable).
- `BTD_HID_REPORT_ID` = 1, `BTD_HID_CONNECT_BYTE` = 19.

### Desktop Default-Sink Resync

Found 2026-10-25: the mouse volume buttons moved a headset sink while S/PDIF was the default. The daemon's routing was right; Cinnamon's cached copy was wrong.

How it goes wrong:
- During some screen locks every sound card disappears (the default becomes `auto_null`; cause unknown, nothing is logged, the logind session stays active).
- At unlock all cards return at once. pipewire-pulse first reports the sink WirePlumber ranks highest as default, then the configured one, and sometimes sends no change event for the second step. libcvc clients (`csd-media-keys`, the sound applet) stay on the first sink. Seen twice on 2026-10-24; `~/.xsession-errors` shows `csd-media-keys: Unable to get default sink` at those moments.
- `pactl set-default-sink <same name>` sends no event, so it does not help. Switching to a throwaway null sink and straight back does.

How the daemon handles it:
- `desktop_sync_loop` subscribes to pulse events, keeps only new-sink lines, and checks once per burst after `DESKTOP_SYNC_SETTLE` (2 s) of quiet. It also checks after every (re)subscribe, since a pipewire-pulse restart ends the subscription.
- `sync_desktop_default_sink` compares the default's `"<name> <index>"` with `LAST_DEFAULT_SINK`. Same name with a new index means it was re-created, so it calls `resync_desktop_default_sink`. A changed name means a real event already went out. `auto_null`, the resync sink and an unlisted default are skipped, so the unlock compares against the sink from before the lock.
- `resync_desktop_default_sink` loads `module-null-sink` named `DESKTOP_RESYNC_SINK` (`audio_switcher_resync`), makes it the default, restores the old sink only if the default is still the resync sink (a routing switch may have landed), and unloads it. Streams following the default hear a split second of silence.
- Only the sink is handled. The default source could go stale the same way (it would affect the mic-mute key); not observed.

To see which sink the volume keys drive: `gdbus call --session --dest org.cinnamon.SettingsDaemon.KeybindingHandler --object-path /org/cinnamon/SettingsDaemon/KeybindingHandler --method org.cinnamon.SettingsDaemon.KeybindingHandler.HandleKeybinding 5` (volume-down, quiet) then the same with `3`, comparing `pactl list sinks` volumes in between.

### PipeWire Recovery Constants

- `PW_ERROR_THRESHOLD` = 5 — broken-pipe errors needed to trigger a restart.
- `PW_CHECK_WINDOW` = 30s — how far back to look in journalctl.
- `PW_COOLDOWN_SECONDS` = 300 — minimum seconds between restarts in normal mode.
- `PW_HUNT_DURATION` = 300 / `PW_HUNT_INTERVAL` = 10 — hunt mode (after connect, resume or a restart): check every 10 s with threshold 1, for 5 minutes.

### Key Functions

- `find_hidraw()` — scan `/dev/hidraw*` for the BTD-800 (vid:pid `1395:002d`).
- `find_btd_sink()` / `find_btd_source()` — discover sink/source names from PipeWire by `BTD_USB_ID`.
- `ensure_btd_input_profile()` — switch the BTD card to the `+input:mono-fallback` variant if the active profile is output-only.
- `monitor_hidraw()` — read HID reports via embedded Python, emit `connected` / `disconnected`.
- `event_loop()` — discover the dongle (wait if absent, back off if unreadable), monitor it, re-discover when the monitor exits.
- `handle_event(device, state)` — update state, `apply_priority`, enter hunt mode on connect.
- `set_device_state()` / `get_device_state()` / `resolve_active_device()` — state file IPC.
- `apply_priority()` — `btd` → matched sink + source; `none` → S/PDIF sink.
- `apply_sink_source()` — set a matched sink+source pair (logs changes only).
- `apply_spdif_sink()` — S/PDIF fallback sink with retry (output only).
- `check_pipewire_health()` / `pipewire_health_loop()` — broken-pipe watch and restart.
- `sleep_resume_loop()` — re-apply defaults + hunt mode on wake from suspend.
- `default_sink_identity()` / `sync_desktop_default_sink()` / `resync_desktop_default_sink(sink)` / `desktop_sync_watch()` / `desktop_sync_loop()` — the default-sink resync.
- `do_fix()` — `fix` subcommand: restart PipeWire now if it logged broken pipes in the last 120 s.
- `cleanup()` — signal handler: kill background jobs, remove runtime files.
- `main()` — arg parse + startup; guarded by `BASH_SOURCE`==`$0` so tests can source the daemon.

## Development Rules

1. **TDD: Red -> Green -> Refactor** — Write or update tests FIRST, verify they fail, then implement. Every change must include tests.
2. **Run tests after every change** — `./tests/test-audio-switcher.sh`. Non-negotiable.
3. **Keep it bash-simple** — Pure bash daemon (with embedded Python for binary HID parsing). No external dependencies beyond `pactl`, `journalctl`, `systemctl`, `gdbus`, `notify-send`, `python3`, and standard coreutils.
4. **Don't break the event loop** — The HID monitor must handle device disconnects gracefully. No unhandled failures.
5. **Log sparingly** — Log routing changes, PipeWire restarts, and errors. Don't log every poll cycle.

## Key Files

- `audio-switcher` — main daemon (bash).
- `install.sh` — install/uninstall the systemd user service, udev rule and WirePlumber tuning.
- `uninstall.sh` — convenience wrapper for `install.sh --uninstall`.
- `tests/test-audio-switcher.sh` — test suite (static + unit + installation + runtime).
- `70-btd800.rules` — udev rule granting the logged-in user access to the BTD-800 hidraw device.
- `51-alsa-tuning.lua` — WirePlumber ALSA buffer tuning.
- `diag-btd800.sh` — diagnostic: raw BTD-800 HID report monitor (run with sudo).
- `README.md` — user-facing documentation.
- `PLAN.md` — original design document.

## Testing Approach

Tests in `tests/test-audio-switcher.sh` use a pass/fail pattern:
```bash
if [[ some_condition ]]; then
    test_result "Description" "pass"
else
    test_result "Description" "fail"
fi
```
plus `assert_eq "Description" "$got" "$want"`.

Categories:
- **Static checks** — script exists, executable, shebang, strict mode, constants, functions; no Jabra code or files remain.
- **Unit checks** — source the daemon (guarded `main()`) and call functions directly against a stubbed `pactl` shell function (define `pactl() { … }` after sourcing to fake PipeWire): `resolve_active_device`, the `monitor_hidraw` parser, `event_loop`'s permission back-off, `apply_priority` routing, and the default-sink resync (re-created vs renamed vs `auto_null`, racing switch, burst debounce). Don't stub `log` where a function's stdout is captured as a value.
- **Installation checks** — binary installed, service file exists, enabled, active; BTD-800 udev rule installed; no Jabra-era leftovers on the machine.
- **Runtime checks** — default sink/source match the headset state (BTD-800 pair when linked, S/PDIF sink otherwise).

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
./audio-switcher fix
```

### Install as systemd user service
```bash
./install.sh
```
The installed binary is a symlink to the repo, so after editing the daemon run `systemctl --user restart audio-switcher` to pick up the change.

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
