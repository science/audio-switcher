# audio-switcher

PipeWire auto-routing and recovery daemon for Linux. Built for Sennheiser (now EPOS) headsets that connect through the BTD-800 USB Bluetooth dongle. It keeps the default speaker and mic matched to the headset whenever the headset is linked, and falls back to S/PDIF speakers when it is not.

## What It Does

- **Headset detection via HID** — Reads vendor HID reports from the BTD-800 USB dongle to detect headset connect/disconnect. When the headset links, the daemon sets the PipeWire default **sink and source together** to the headset. When it unlinks, the default sink falls back to the S/PDIF speakers (which have no mic, so the default source is left to PipeWire). A dongle being plugged in does *not* count — the headset must be linked to it. Keeping sink and source matched is the point: the OS and apps routinely split a headset's speaker and mic onto different devices.
- **Mic volume reset on connect** — Each time the headset links, its mic input volume is set to 100%. Apps can turn the mic down during a call (browsers' automatic gain control does this), and PipeWire remembers that level, so without the reset the next call would start quiet. It happens only on connect, so if you change the level during a call it stays until the next connect.
- **PipeWire crash recovery** — Monitors journalctl for PipeWire broken-pipe errors. When a threshold is exceeded, restarts PipeWire and re-applies the correct audio defaults based on the current headset state. Enters "hunt mode" after connect and resume events for aggressive monitoring.
- **Desktop notifications** — Sends a persistent (critical) desktop notification when PipeWire is restarted, warning that apps like Slack may need restarting. Cooldown-guarded to max one notification per 5 minutes.
- **Sleep/resume recovery** — Monitors systemd-logind D-Bus signals for system wake events. On resume, re-applies audio defaults and enters hunt mode (PipeWire streams often break when USB devices lose power during suspend).
- **Volume-key resync** — Cinnamon's volume keys keep their own copy of which output is the default, updated only when PipeWire announces a change. During some screen locks every sound card disappears; at unlock they all return at once, and PipeWire can settle on the right default without announcing it. The volume keys then move a headset while the speakers play. The daemon watches for the default output being re-created (same name, new index) and, 2 seconds later, switches the default to a throwaway silent output and straight back. That produces the announcement, and a split second of silence.

## Why HID?

The BTD-800 dongle handles Bluetooth internally. PipeWire and ALSA always see the dongle's USB audio interface as present, regardless of whether a headset is linked — the sink even goes RUNNING when you play to an unlinked dongle (into silence). The only reliable presence signal is the dongle's HID interface: Report ID 1, byte 19 is `0x01` when connected and `0x00` when disconnected.

## Hardware

- **Dongle HID interface** — found by USB vendor:product `1395:002d` (the BTD-800) among `/dev/hidraw*`.
- **Headset output and mic** — discovered at runtime by matching `usb-1395_Sennheiser_BTD_800_USB-00` in `pactl list sinks/sources short`. The full name varies with the active card profile, so the daemon looks it up by this pattern on every event.
- **S/PDIF speakers (fallback)** — `alsa_output.pci-0000_00_1f.3.iec958-stereo` (motherboard, stable).

### Using more than one headset

Nothing in the daemon is tied to a particular headset or dongle unit. It matches the dongle *model* (USB `1395:002d` and the PipeWire name pattern above), and the BTD-800 reports no USB serial number, so every BTD-800 dongle looks identical to the daemon.

- **Several headsets paired to one dongle** — works as is. The daemon only sees the dongle, and the dongle reports "linked" for whichever headset is on.
- **Swapping dongles** — works as is, as long as the replacement is also a BTD-800 (`lsusb` shows `1395:002d`). Unplug one, plug in the other; the daemon re-discovers it within about 10 seconds.
- **Two dongles plugged in at once** — not supported. The daemon watches the first BTD-800 it finds and ignores the other.
- **A dongle that is not a BTD-800** (for example an EPOS-branded dongle with a different product ID or name) — not recognised. Check `lsusb` and `pactl list sinks short`. If the ID or name differs, `find_hidraw`, `BTD_USB_ID` and `70-btd800.rules` need extending, and its HID link report needs confirming with `diag-btd800.sh`.

## Install

```bash
./install.sh
```

This will:
1. Install the udev rule `70-btd800.rules` granting user access to the dongle's hidraw device (requires sudo)
2. Install the WirePlumber ALSA buffer tuning (`51-alsa-tuning.lua`)
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
```

## Logs

```bash
journalctl --user-unit audio-switcher -f
```

Example output:
```
10:30:15: audio-switcher starting (verbose=false)
10:30:15:   BTD-800 match:   *usb-1395_Sennheiser_BTD_800_USB-00*
10:30:15:   BTD-800 hidraw:  /dev/hidraw0
10:30:15: Starting HID monitor on /dev/hidraw0
10:30:42: EVENT: btd connected
10:30:42: SWITCH sink → BTD-800 headset (alsa_output.usb-1395_Sennheiser_BTD_800_USB-00.iec958-stereo)
10:30:42: SWITCH source → BTD-800 headset (alsa_input.usb-1395_Sennheiser_BTD_800_USB-00.mono-fallback)
10:30:42: MIC: BTD-800 mic volume 47% -> 100%
10:45:01: PW-RECOVERY: 7 broken-pipe errors in last 30s, restarting PipeWire
10:45:03: PW-RECOVERY: defaults re-applied (active=btd)
10:48:10: EVENT: btd disconnected
10:48:10: SWITCH sink → S/PDIF speakers
11:20:00: RESUME: system woke from sleep, re-applying defaults
12:05:33: RESYNC: default sink alsa_output.pci-0000_00_1f.3.iec958-stereo was re-created; re-announced it so volume keys follow it
```

## Diagnostics

Monitor raw HID reports from the dongle (useful for debugging, or for checking a new dongle's link signature):

```bash
sudo ./diag-btd800.sh
```

## Troubleshooting

**Audio never switches, and the log has no "Starting HID monitor" line** — The daemon can't find the dongle. It keeps checking every 10 seconds. Check that `lsusb` lists `1395:002d`, and that the udev rule is installed (`./install.sh`).

**"ERROR: cannot read /dev/hidrawN (permission denied)"** — The udev rule isn't active. Try:
```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```
Then unplug and replug the dongle.

**Audio doesn't switch** — Check if the daemon is running:
```bash
systemctl --user status audio-switcher
```

**Volume keys show the change but the wrong output moves** — Cinnamon's copy of the default output is stale. The daemon fixes the known cause (an unlock re-creating every sound card; look for a `RESYNC:` line). To see which output the keys move, without changing anything overall (it pops the volume display twice):
```bash
D="gdbus call --session --dest org.cinnamon.SettingsDaemon.KeybindingHandler --object-path /org/cinnamon/SettingsDaemon/KeybindingHandler --method org.cinnamon.SettingsDaemon.KeybindingHandler.HandleKeybinding"
pactl list sinks | grep -E '^\s*(Name|Volume):'; $D 5; pactl list sinks | grep -E '^\s*(Name|Volume):'; $D 3
```
Any change of the default output's name re-syncs it, e.g. pick another output in the sound applet and pick the speakers again.

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
