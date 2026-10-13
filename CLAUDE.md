# Audio Switcher Project

## What This Is

A PipeWire auto-routing and recovery daemon for Linux. Its jobs:

1. **HID-based headset detection + priority routing** — Reads vendor HID reports from each headset dongle's hidraw device to detect connect/disconnect, then routes PipeWire defaults by a priority ladder. Keeping the default **sink and source matched to the same device** is the core job — the OS/apps routinely mismatch headset speaker/mic on their own.

   Priority ladder: **Jabra Evolve2 buds (Link 390) > Sennheiser BTD-800 > S/PDIF speakers**. A dongle merely being plugged in does *not* count — the headset must be linked to it. When the active headset disconnects, routing falls through to the next-highest connected device, or to S/PDIF (sink only — no matching mic).
2. **Jabra mic probe** — On each Jabra connect, listens to the mic for a few seconds in the background. The buds can relink delivering only exact digital zeros (mic dead, speaker fine; a full power-off plus a few minutes in the case clears it, a quick case-cycle often does not; see `JABRA-DEAD-MIC.md`). Pure zeros, confirmed by one retry, raise a critical desktop popup; the next healthy probe replaces it with "working again". The probe also unmutes the mic and forces `JABRA_SOURCE_VOLUME` (a muted or turned-down source delivers zeros too).
3. **Jabra typing filter** — The bud mics pick up typing nearly as loud as speech. When the Jabra is active, the daemon loads DeepFilterNet (a speech-enhancement neural net, LADSPA build) as a virtual source fed by the raw mic, and makes that the default source. See "Jabra Typing Filter" below.
4. **PipeWire recovery** — Polls journalctl for broken-pipe errors and restarts PipeWire when a threshold is exceeded, then re-applies the correct audio defaults based on the current priority resolution.

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
| `JABRA_PROFILE` | `output:analog-stereo+input:mono-fallback` | Card profile forced on Jabra connect. WirePlumber prefers the `iec958` output by priority, which is **silent** on the buds |
| `SPDIF_SINK` | `alsa_output.pci-0000_00_1f.3.iec958-stereo` | Motherboard S/PDIF (stable) |

Sink/source names are **discovered at runtime** (`find_btd_sink/source`, `find_jabra_sink/source`). The Jabra name carries the dongle serial and can gain a suffix on re-plug (e.g. `…99AB` → `…99AB2`), so matching is by the `JABRA_SINK_MATCH` pattern, never the exact string.

### Jabra Mic Probe

A working bud never delivers pure zeros: even in a silent room it emits a faint noise floor (~85% non-zero samples). Its only block of zeros is ~1 s at stream start while the dongle switches the bud into call mode, so the first `JABRA_PROBE_SKIP` seconds are discarded. A stuck bud measured 0.0–0.4% non-zero. The verdict is the share of non-zero samples, not "any sample non-zero" (rounding blips and switch clicks exist).

Recording uses `pw-record` against the source by name. PipeWire shares capture, so apps already using the mic are unaffected. Opening the mic puts the dongle in call mode, and it sends volume-key presses on entering and leaving it (typically 2 presses each way, in both the working and stuck states) that Cinnamon applies to the default sink; the probe snapshots the sink's raw volume and restores it `JABRA_PROBE_VOLUME_SETTLE` seconds after the last take.

| Constant | Value | Purpose |
|----------|-------|---------|
| `JABRA_SOURCE_VOLUME` | `100%` | Mic input level forced on every connect (also makes the quiet-room noise floor measurable) |
| `JABRA_PROBE_DELAY` | 5 | Seconds after connect before probing |
| `JABRA_PROBE_SKIP` / `JABRA_PROBE_LISTEN` | 1.5 / 5 | Startup seconds discarded / seconds judged |
| `JABRA_PROBE_RETRY_DELAY` | 10 | Wait before confirming "dead" (dongle leaves call mode ~5 s after mic close) |
| `JABRA_PROBE_MIN_NONZERO_PCT` | 5 | Below this share of non-zero samples = dead |
| `JABRA_PROBE_ALERT_COOLDOWN` | 300 | Max one "mic is silent" popup per 5 minutes |
| `JABRA_PROBE_SOURCE` | (env, empty) | Probe another source instead (testing, e.g. a null sink's `.monitor`) |

### Jabra Typing Filter

Measured 2026-10-13: typing peaks sat only ~14 dB below speech peaks on the raw bud mic. Teams in a browser passed it straight through; Dialpad removed it. Filtering on the host means every app gets clean audio before its own suppression runs.

How it is wired:
- `pactl load-module module-ladspa-source` runs inside `pipewire-pulse` and creates the virtual source `jabra_clean_mic` (description "Jabra buds mic (typing filtered)"). Its capture stream reads the raw Jabra mic and is passive, so it only opens the raw mic when something records from the filtered one. Cinnamon's sound-applet level meter records from the default source, so in practice it runs whenever the Jabra is the default (about 1.5% of one core).
- The name must not contain `JABRA_SINK_MATCH`, or `find_jabra_source` would return it.
- A profile switch re-creates the raw mic under a new name (`….mono-fallback.3`, `.5`, …). WirePlumber relinked the capture stream to the new raw mic in testing; `ensure_jabra_clean_source` moves it back with `pactl move-source-output` if not. It never reloads a loaded filter, because that would cut off apps recording from it.
- The filter stays loaded across a buds disconnect (apps keep their stream). It is unloaded only when the raw mic is gone, i.e. the dongle was unplugged: checked in `apply_priority` and when an HID monitor exits. The daemon leaves it loaded on exit; `install.sh --uninstall` unloads it.
- The dead-mic probe always records the RAW mic. The filter outputs exact zeros for silence, which would read as a dead bud. The probe also unmutes the filtered mic and forces `JABRA_SOURCE_VOLUME` on it, since apps record from it.
- The plugin is optional at runtime: if the file is missing or the load fails, the Jabra default source is the raw mic.
- `ensure_jabra_clean_source` prints the source name on stdout for capture, so its log lines go to stderr.

Constants:
- `JABRA_CLEAN_SOURCE` = `jabra_clean_mic` — node name of the filtered virtual mic.
- `JABRA_DFN_PLUGIN` = `~/.local/lib/audio-switcher/libdeep_filter_ladspa.so` (env-overridable) — installed by `install.sh` from the pinned DeepFilterNet v0.5.6 release, sha256-checked.
- `JABRA_DFN_LABEL` = `deep_filter_mono`.
- `JABRA_DFN_CONTROLS` = `100,-15,35,35,0,0.02` — control ports in order: attenuation limit dB (100 = no limit), min / max-ERB / max-DF processing thresholds dB (plugin defaults), min processing buffer, post-filter beta (0.02 = the `deep-filter --pf` setting, which won the listening test over the default, a stronger post-filter, and 20/30 dB attenuation caps).

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
| `ensure_btd_input_profile()` | Switch BTD card to a profile with mic input if output-only |
| `ensure_jabra_input_profile()` | Force Jabra card to exactly `JABRA_PROFILE` (any other profile, incl. iec958+input, is replaced) |
| `wait_for_jabra_sink()` | Poll for the Jabra sink after a profile switch re-creates it (used by `apply_priority`) |
| `monitor_hidraw()` / `monitor_jabra_hidraw()` | Read HID reports via embedded Python, emit connected/disconnected |
| `event_loop()` | Discover + monitor both dongles concurrently; merge tagged events → `handle_event()` |
| `handle_event(device, state)` | Update device state, re-resolve priority, apply, hunt-mode on connect; start/stop the Jabra mic probe |
| `jabra_mic_verdict(wav)` | Embedded Python: `ok\|dead\|inconclusive` + nonzero%/rms/longest zero run |
| `record_jabra_mic(src, secs, out)` | `timeout -s INT pw-record` (SIGINT so the WAV is finalised) |
| `ensure_jabra_mic_live(src)` | Unmute + force `JABRA_SOURCE_VOLUME`; prints changes made |
| `probe_jabra_mic_once(src)` | One take + verdict into global `PROBE_RESULT` (no subshell, so the recorder is a direct child) |
| `probe_jabra_mic()` | Background orchestrator: delay, live-ify, snapshot sink volume, probe, retry on dead, notify, restore volume |
| `start_jabra_probe()` / `stop_jabra_probe()` | One probe at a time; stop kills the probe AND its current child so its TERM trap (volume restore) runs at once |
| `find_jabra_clean_source()` / `jabra_clean_module_id()` | Typing filter's source name / its `module-ladspa-source` index |
| `jabra_clean_capture(module)` | `"<source-output> <source-id>"` of the filter's capture stream |
| `ensure_jabra_clean_source(raw)` | Load the filter on the raw mic or re-attach it; print `jabra_clean_mic` (status 1 = use raw) |
| `drop_jabra_clean_source()` | Unload the filter (raw mic gone) |
| `do_probe_mic()` | `probe-mic` subcommand: one immediate report-only probe (no unmute/volume change/notify) |
| `set_device_state()` / `get_device_state()` | Per-device state file IPC (key=value lines) |
| `resolve_active_device()` | Priority resolver → `jabra\|btd\|none` |
| `apply_priority()` | Resolve ladder + set matched default sink **and** source for the winner (Jabra source = typing-filtered mic); drop the filter if the raw Jabra mic is gone |
| `apply_sink_source()` | Set a matched sink+source pair (logs changes only) |
| `apply_spdif_sink()` | S/PDIF fallback sink with retry (output only) |
| `check_pipewire_health()` | Count broken-pipe errors, restart PipeWire if threshold met, `apply_priority` |
| `pipewire_health_loop()` | Background loop: sleep 30 (hunt: 10), check health, repeat |
| `sleep_resume_loop()` | Re-apply defaults + hunt mode on wake from suspend |
| `cleanup()` | Signal handler: stop probe, kill background jobs, remove runtime files |
| `main()` | Arg parse + startup; guarded by `BASH_SOURCE`==`$0` so tests can source the daemon |

## Development Rules

1. **TDD: Red -> Green -> Refactor** — Write or update tests FIRST, verify they fail, then implement. Every change must include tests.
2. **Run tests after every change** — `./tests/test-audio-switcher.sh`. Non-negotiable.
3. **Keep it bash-simple** — Pure bash daemon (with embedded Python for binary HID parsing). No external dependencies beyond `pactl`, `journalctl`, `systemctl`, `python3`, and standard coreutils. The one exception is the optional DeepFilterNet LADSPA plugin, which `install.sh` downloads (pinned, hash-checked) and the daemon can run without.
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
| `JABRA-DEAD-MIC.md` | Investigation log for the Jabra buds connecting with a mic that sends pure zeros: occurrences, ruled-out causes, recovery, HID reference, open leads. Add new occurrences here |

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
- **Unit checks** — Source the daemon (guarded `main()`) and call functions directly: `resolve_active_device` truth table (jabra×btd combos), the `monitor_jabra_hidraw` parser (connect/disconnect/lookalike), the Jabra profile enforcer / sink lookup, and the typing filter (load / re-attach / fall back / unload) against a stubbed `pactl` shell function (define `pactl() { … }` after sourcing to fake PipeWire). Don't stub `log` where a function's stdout is captured as a value — that is how the typing filter's log-on-stdout bug hid.
- **Installation checks** — Binary installed, service file exists, enabled, active; both udev rules; DeepFilterNet plugin present
- **Runtime checks** — Default sink/source matches the priority resolution (jabra → btd → S/PDIF; the Jabra source is `jabra_clean_mic` when the plugin is installed)

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

### Probe the Jabra mic now (calibration / diagnosis)
```bash
./audio-switcher probe-mic        # e.g. "ok nonzero=85.7 rms=-72.0 longest_zero=0.00 secs=6.4 vol=100%"
```
Opens the mic for ~7 s (bud enters call mode briefly). Every connect also logs one `PROBE:` line with the same stats.

### Check logs
```bash
journalctl --user-unit audio-switcher -f
```

### Diagnostics (raw HID monitoring)
```bash
sudo ./diag-btd800.sh
```
