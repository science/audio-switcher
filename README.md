# audio-switcher

PipeWire auto-routing and recovery daemon for Linux. Routes audio across multiple headset dongles by a priority ladder, keeping the default speaker and mic matched to the same device.

## What It Does

- **Priority routing via HID** — Reads vendor HID reports from each headset dongle to detect connect/disconnect, then routes the PipeWire default **sink and source together** by priority:

  **Jabra Evolve2 buds (Link 390) → Sennheiser BTD-800 → S/PDIF speakers**

  A dongle being plugged in does *not* count — the headset must be linked to it. When the active headset disconnects, audio falls through to the next connected device, or to S/PDIF (speakers; no matching mic). Keeping sink+source matched is the point: the OS and apps routinely split a headset's speaker and mic onto different devices.
- **PipeWire crash recovery** — Monitors journalctl for PipeWire broken-pipe errors. When a threshold is exceeded, restarts PipeWire and re-applies the correct audio defaults based on the current headset state. Enters "hunt mode" after connect and resume events for aggressive monitoring.
- **Jabra mic check** — The Jabra buds can reconnect with a dead mic: the speaker works, but the mic sends pure digital silence and nobody on your call hears you. On every Jabra connect the daemon listens to the mic for a few seconds (alongside any app already using it) and, if it hears only exact zeros twice in a row, pops a persistent "Jabra mic is silent" notification telling you to case-cycle the bud. The next good connect replaces it with "Jabra mic working again". It also unmutes the Jabra mic and sets its input volume to 100% on connect, since a muted or turned-down mic looks the same as a dead one.
- **Jabra typing filter** — The buds' mics pick up keyboard clicks almost as loud as your voice, and some meeting apps (Teams in a browser) do nothing about it. When the Jabra is active the daemon routes your mic through [DeepFilterNet](https://github.com/Rikorose/DeepFilterNet), a speech-enhancement neural network that keeps speech and removes everything else, and makes that filtered mic ("Jabra buds mic (typing filtered)", node `jabra_clean_mic`) the default. Every app gets clean audio before its own noise suppression runs. In a recorded test, typing between words dropped by about 50 dB while speech was unchanged. It costs about 1.5% of one CPU core. The mic check above still listens to the raw mic, because the filter turns silence into exact zeros. If the plugin is missing, the daemon falls back to the raw mic.
- **Desktop notifications** — Sends a persistent (critical) desktop notification when PipeWire is restarted, warning that apps like Slack may need restarting. Cooldown-guarded to max one notification per 5 minutes.
- **Sleep/resume recovery** — Monitors systemd-logind D-Bus signals for system wake events. On resume, re-applies audio defaults and enters hunt mode (PipeWire streams often break when USB devices lose power during suspend).

## Why HID?

Both dongles handle their wireless link internally. PipeWire and ALSA always see the dongle's USB audio interface as present, regardless of whether a headset is actually linked — the sink even goes RUNNING when you play to an unlinked dongle (into silence). The only reliable presence signal is the dongle's HID interface:

| Headset | hidraw | Report | Connect flag |
|---------|--------|--------|--------------|
| BTD-800 | vid `1395` pid `002d` | Report ID 1 | byte 19: `0x01` conn / `0x00` disc |
| Jabra Link 390 | vid `0b0e` pid `2e50` | Report ID 5, header `05 00 01 00 08 0d` | byte 6: `0x01` conn / `0x02` disc |

The Jabra signature was reverse-engineered with `diag-jabra.sh` (header match rejects lookalike reports that begin `05 00 04 ..`).

## Hardware

| Device | Identification |
|--------|---------------|
| Jabra buds output/mic | Discovered at runtime by matching `Jabra_Link_390` in `pactl list sinks/sources short` |
| BTD-800 headset output/mic | Discovered at runtime by matching `usb-1395_Sennheiser_BTD_800_USB-00` |
| S/PDIF speakers (fallback) | `alsa_output.pci-0000_00_1f.3.iec958-stereo` (motherboard, stable) |

Sink/source names vary by active card profile and (for the Jabra) can gain a serial suffix on re-plug, so the daemon discovers them dynamically by pattern on each event.

On every Jabra connect the daemon forces the Link 390 card to the `output:analog-stereo+input:mono-fallback` profile. WirePlumber otherwise picks the higher-priority `iec958` (digital passthrough) output, which produces no sound on the buds.

> **Pairing the Jabra buds to the dongle is a one-time Windows/Mac step** (Jabra Direct) — the Link 390 presents to Linux only as USB audio + HID, not a Bluetooth controller, so BlueZ can't pair it. Once paired, the dongle remembers the buds and it's plug-and-play on Linux.

## Install

```bash
./install.sh
```

This will:
1. Install udev rules (`70-btd800.rules`, `70-jabra.rules`) granting user access to the dongle hidraw devices (requires sudo)
2. Download the DeepFilterNet 0.5.6 LADSPA plugin (pinned release, sha256-checked) to `~/.local/lib/audio-switcher/` for the Jabra typing filter
3. Symlink `audio-switcher` to `~/.local/bin/` (dev repo changes apply immediately)
4. Create and enable a systemd user service

## Uninstall

```bash
./uninstall.sh
```

## Usage

The daemon runs automatically via systemd. For manual/debug use:

```bash
./audio-switcher              # normal mode
./audio-switcher --verbose    # verbose logging
./audio-switcher fix          # restart PipeWire now if it is logging broken pipes
./audio-switcher probe-mic    # check the Jabra mic right now (report only)
```

`probe-mic` prints a verdict line such as `ok nonzero=85.7 rms=-72.0 longest_zero=0.00 secs=6.4 vol=100%`. `nonzero` is the share of samples that are not exactly zero after the first 1.5 s: a working bud reads tens of percent even in a silent room, a stuck one reads 0.

## Logs

```bash
journalctl --user-unit audio-switcher -f
```

Example output:
```
10:30:15: audio-switcher starting (verbose=false)
10:30:15:   Priority:        Jabra buds > BTD-800 > S/PDIF
10:30:15:   BTD-800 hidraw:  /dev/hidraw3
10:30:15:   Jabra hidraw:    /dev/hidraw1
10:30:15: Starting HID monitors (btd=/dev/hidraw3 jabra=/dev/hidraw1)
10:30:42: EVENT: jabra connected
10:30:42: SWITCH sink → Jabra buds (alsa_output.usb-_Jabra_Link_390_….analog-stereo)
10:30:42: FILTER: typing filter loaded on alsa_input.usb-_Jabra_Link_390_….mono-fallback
10:30:42: SWITCH source → Jabra buds (jabra_clean_mic)
10:48:10: EVENT: jabra disconnected
10:48:10: SWITCH sink → BTD-800 headset (alsa_output.usb-1395_Sennheiser_BTD_800_USB-00.analog-stereo)
10:48:10: SWITCH source → BTD-800 mic (alsa_input.usb-1395_Sennheiser_BTD_800_USB-00.mono-fallback)
10:45:01: PW-RECOVERY: 7 broken-pipe errors in last 30s, restarting PipeWire
10:45:03: PW-RECOVERY: defaults re-applied (active=jabra)
11:20:00: RESUME: system woke from sleep, re-applying defaults
```

## Diagnostics

Monitor raw HID reports from a dongle (useful for debugging or reverse-engineering a new device's link signature):

```bash
sudo ./diag-btd800.sh    # Sennheiser BTD-800
sudo ./diag-jabra.sh     # Jabra Link 390
```

## Troubleshooting

**"BTD-800 hidraw device not found"** — The dongle isn't plugged in, or the udev rule isn't installed. Run `./install.sh` to install the rule.

**"Cannot read /dev/hidrawN (permission denied)"** — The udev rule isn't active. Try:
```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```
Then unplug and replug the dongle.

**Audio doesn't switch** — Check if the daemon is running:
```bash
systemctl --user status audio-switcher
```

**"Jabra mic is silent" notification** — The buds linked without a working mic path. Hold the bud button 4 seconds to power it off, leave it in the closed case for about 3 minutes, then take it out. A quick case-cycle cleared it once but failed twice on 2026-10-09; the full power-off reset worked. Confirm with `./audio-switcher probe-mic` (`ok` with a non-zero percentage well above 5).

**People still hear typing on the Jabra** — Check that the app is using "Jabra buds mic (typing filtered)", not the raw "Jabra Link 390" mic: `pactl get-default-source` should print `jabra_clean_mic`, and an app that picked a specific mic instead of "default" needs changing in its own settings. If the filter is missing, check that `~/.local/lib/audio-switcher/libdeep_filter_ladspa.so` exists (re-run `./install.sh`) and look for `FILTER:` lines in the log.

**PipeWire keeps crashing** — The daemon will restart PipeWire automatically (up to once per 5 minutes). Check PipeWire logs:
```bash
journalctl --user -u pipewire -b
```

## Tests

```bash
./tests/test-audio-switcher.sh
```

## License

MIT
