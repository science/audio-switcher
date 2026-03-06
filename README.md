# audio-switcher

PipeWire auto-routing and recovery daemon for Linux. Built for the Sennheiser BTD-800 USB Bluetooth dongle.

## What It Does

- **Headset detection via HID** — Reads vendor HID reports from the BTD-800 USB dongle to detect headset connect/disconnect. When connected, routes audio to the headset. When disconnected, falls back to S/PDIF speakers.
- **PipeWire crash recovery** — Monitors journalctl for PipeWire broken-pipe errors. When a threshold is exceeded, restarts PipeWire and re-applies the correct audio defaults based on the current headset state. Enters "hunt mode" after connect and resume events for aggressive monitoring.
- **Desktop notifications** — Sends a persistent (critical) desktop notification when PipeWire is restarted, warning that apps like Slack may need restarting. Cooldown-guarded to max one notification per 5 minutes.
- **Sleep/resume recovery** — Monitors systemd-logind D-Bus signals for system wake events. On resume, re-applies audio defaults and enters hunt mode (PipeWire streams often break when USB devices lose power during suspend).

## Why HID?

The BTD-800 dongle handles Bluetooth internally. PipeWire and ALSA always see the dongle's USB audio interface as present, regardless of whether a headset is paired and connected. The only signal comes from the dongle's HID interface: Report ID 1, byte 19 is `0x01` when connected and `0x00` when disconnected.

## Hardware

| Device | Identification |
|--------|---------------|
| BTD-800 headset output | Discovered at runtime by matching `usb-1395_Sennheiser_BTD_800_USB-00` in `pactl list sinks short` |
| BTD-800 headset mic | Discovered at runtime by matching the same pattern in `pactl list sources short` |
| S/PDIF speakers (fallback) | `alsa_output.pci-0000_00_1f.3.iec958-stereo` (motherboard, stable) |

BTD-800 sink/source names vary by active card profile (e.g. `analog-stereo` vs `iec958-stereo`). The daemon discovers them dynamically on each connect event.

## Install

```bash
./install.sh
```

This will:
1. Install a udev rule (`70-btd800.rules`) granting user access to the BTD-800 hidraw device (requires sudo)
2. Symlink `audio-switcher` to `~/.local/bin/` (dev repo changes apply immediately)
3. Create and enable a systemd user service

## Uninstall

```bash
./uninstall.sh
```

## Usage

The daemon runs automatically via systemd. For manual/debug use:

```bash
./audio-switcher              # normal mode
./audio-switcher --verbose    # verbose logging
```

## Logs

```bash
journalctl --user-unit audio-switcher -f
```

Example output:
```
10:30:15: audio-switcher starting (verbose=false)
10:30:15:   BTD-800 match:   *usb-1395_Sennheiser_BTD_800_USB-00*
10:30:15:   BTD-800 sink:    alsa_output.usb-1395_Sennheiser_BTD_800_USB-00.analog-stereo
10:30:15:   BTD-800 source:  alsa_input.usb-1395_Sennheiser_BTD_800_USB-00.mono-fallback
10:30:15: Starting HID monitor on /dev/hidraw1...
10:30:42: EVENT: headset connected
10:30:42: PROFILE: switched to output:analog-stereo+input:mono-fallback (added mic input)
10:30:42: SWITCH sink → BTD-800 headset (alsa_output.usb-1395_Sennheiser_BTD_800_USB-00.analog-stereo)
10:30:42: SWITCH source → BTD-800 mic (alsa_input.usb-1395_Sennheiser_BTD_800_USB-00.mono-fallback)
10:45:01: PW-RECOVERY: 7 broken-pipe errors in last 30s, restarting PipeWire
10:45:03: PW-RECOVERY: defaults re-applied (state=connected)
11:20:00: RESUME: system woke from sleep, re-applying defaults
11:20:02: RESUME: entering hunt mode for post-resume monitoring
```

## Diagnostics

Monitor raw HID reports from the dongle (useful for debugging):

```bash
sudo ./diag-btd800.sh
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
