# Jabra Evolve2 Buds: the dead-mic problem

A running log of what we know about the Jabra Evolve2 Buds (via the Link 390 USB dongle) connecting with a mic that sends nothing. Add each new occurrence and finding here. The daemon's automatic check (the "mic probe") is described in README.md and CLAUDE.md. This file holds the investigation behind it.

## The symptom

- **The speaker works, the mic doesn't.** Apps see the Jabra mic, can select it and record from it, but the people on your call hear nothing.
- **Nothing on the host shows a fault.** The card profile, device names, mute state, hardware gain and the dongle's status reports all look the same in the dead state and the working state.
- **The signature is exact digital zeros.** A recording from the Jabra mic is 100% samples of value `0`. That is different from "quiet":
  - A live mic is never all zeros, even in a silent room. The analog noise floor always produces some small values.
  - All zeros means no audio is arriving from the bud at all.
- **It starts when the bud connects.** Every case so far has been present from the moment the bud linked to the dongle. No mid-call failure has been observed with these buds yet. The older Sennheiser BTD-800 did fail mid-call; see the `silent-mic-death` memory note.

## Occurrence log

Each line is one bud connect. "Probe" means the daemon's automatic check, which only exists from 2026-10-09 evening onward.

- **2026-10-09 09:59: DEAD.** The bud was powered off and on after a Dialpad call. Confirmed by the participants on a Teams call, who couldn't hear the user.
- **2026-10-09 11:49:** the bud dropped the link on its own while still in the dead state.
- **2026-10-09 13:19: working.** After a case-cycle.
- **2026-10-09 16:40:** connected. Not checked; this was before the probe existed.
- **Between the morning and the evening of 2026-10-09:** the user updated the dongle and bud firmware to the latest versions with Jabra Direct. The failures below are on current firmware.
- **2026-10-09 22:08: DEAD.** Buds taken out of the case. Three manual probes and an independent `parecord` recording were all 0.0%. The user also counted out loud during a probe: still 0.0%, and Cinnamon's input meter showed nothing.
- **2026-10-09 22:17: DEAD.** After a quick case-cycle. The probe alerted at 22:18.
- **2026-10-09 22:34: DEAD.** After another quick case-cycle. The probe alerted at 22:35.
- **2026-10-09 22:38: working.** The bud was powered off by holding the button for 4 seconds, then left in the closed case for about 3 minutes. The probe read 97.5% non-zero.

Tally on current firmware: 3 dead and 1 working out of 4 connects.

## What it is not

All of these were tested while the mic was dead, on 2026-10-09:

- **Not Firefox, Teams or Dialpad.** PipeWire lets several programs record the same mic at once, so one browser tab cannot lock another out of it. Recording straight from `pw-record` and `parecord` gave the same zeros.
- **Not PipeWire.** Recording straight from the hardware with `arecord -D hw:<card>,0`, which bypasses PipeWire entirely, gave zeros.
- **Not gain or mute.** Raising PipeWire's mic volume to 100% and the dongle's hardware gain to maximum gave zeros. So did toggling the dongle's hardware mute switch.
- **Not the card profile.** The profile was `analog-stereo + mono-fallback` in both the dead and working states.
- **Not something the host can signal its way out of.** Telling the dongle "call active" over USB (the HID "off-hook" signal a desk phone app would send) didn't revive it. Neither did toggling the mute LED or an audible test tone.
- **Not old firmware.** It happened three times after the firmware update.

## What it most likely is

- **The fault is in the wireless link between the bud and the dongle,** which runs entirely inside their firmware. Linux sees only a USB sound card and a few HID buttons, and has no say in how the bud links.
- **The bud's microphones themselves work.** In the dead state the user heard room sound (keyboard typing) played into the bud for a couple of seconds at a time. That is the bud's own HearThrough or sidetone feature, which runs inside the bud and never passes through Linux. During that check, no app had the mic open and no PipeWire loopback existed. So the bud can hear, but isn't sending that audio over the radio to the dongle.
- **Leading theory:** the bud sometimes links in a playback-only mode and never switches into two-way call mode when the mic opens. Supporting evidence: in the dead state, the bud's button toggled ANC/HearThrough instead of muting the call. In the working state, the same button muted the call.

## Recovery

- **Works (1 of 1):** hold the bud button 4 seconds to power it off (fast red blinks confirm), leave it in the closed case for about 3 minutes, then take it out.
- **Unreliable:** a quick case-cycle (in the case, close the lid for a few seconds, take it out). It fixed the problem at 13:19, but failed at 22:17 and 22:34.
- **Not yet tried:** unplugging and replugging the dongle while the mic is dead. If that works, the daemon could reset the dongle automatically when the probe finds a dead mic.
- **Can't help:** anything done from the host's audio settings (see "What it is not").

## Detection: the mic probe

On every Jabra connect, the daemon records the mic for 6.5 seconds in the background and alerts if it hears only zeros. This was committed in `11e4bd4`; README.md and CLAUDE.md cover how it works. The measurements that set its thresholds:

- **Working bud in a silent room (13:26, nobody talking):** 78–90% non-zero samples per second, after skipping the start of the recording. The longest run of consecutive zeros was under 5 ms.
- **Working bud with speech (13:20, 22:39):** 94.6% and 97.5% non-zero.
- **Dead bud:** 0.0% in every recording. One recording read 0.4% because of a single click when the hardware mute switch was flipped.
- **Startup zeros:** every working recording begins with 0.6–1.0 s of zeros while the dongle switches the bud into call mode. The probe throws away the first 1.5 s for this reason.
- **The threshold is 5% non-zero.**
- **Mic volume matters.** PipeWire scales the samples by the input volume before any recorder sees them. The silent-room noise floor is tiny, so at a low input volume it rounds to zeros and looks dead. Simulated on the silent-room recording:
  - 88–100% volume: 86% non-zero
  - 50%: 29%
  - 40%: 16%
  - 30%: 3%, which would read as dead
  This is why the daemon sets the Jabra mic to 100% on every connect (`JABRA_SOURCE_VOLUME`).
- **The probe only checks at connect.** A mic that dies mid-call would not be caught. A possible next step is to also listen whenever an app opens the mic (a new PipeWire capture stream appears). That would avoid the probe's own side effects, because the app, not the probe, puts the dongle into call mode.

## Side issues found along the way

- **The dongle sends volume key presses whenever anything opens or closes the mic.** It sends them when it enters call mode (about 0.5 s after the mic opens) and when it leaves it (about 5 s after the mic closes). Cinnamon applies them to the default output, which shows the volume popup and slowly drifts the volume.
  - Anything that opens the mic triggers this: the probe, Teams, and the Sound settings window (its input level meter opens the mic).
  - Observed patterns: 2 down on open and 2 up on close (22:34 and 22:38, in both dead and working states). Also 1 down and 2 up (22:28, Sound settings). The morning's dead state gave 3 down on open and 3 down on close.
  - **The direction of the presses does not indicate a dead mic.** Dead and working connects tonight produced identical patterns.
  - The probe saves the output volume before it runs and restores it afterwards. Other apps are not protected.
  - Possible fix: a udev/hwdb rule (needs sudo) that stops the dongle's volume and mute keys from reaching the desktop. The cost is that the bud's own volume and mute buttons would no longer control the PC.
- **The mute feedback loop.** This is a real host-side bug, seen 2026-10-09 morning:
  1. The dongle sends a "phone mute" button press.
  2. The kernel turns it into the keyboard's mic-mute key.
  3. Cinnamon's media-keys service (`csd-media-keys`) toggles mute on the default mic.
  4. PipeWire passes that to the dongle's hardware mute switch.
  5. The dongle reports another mute button press, and the cycle repeats.
  It ran at about 4 per second for 37 seconds and ended in a random mute state. The same hwdb rule would break it. The probe now unmutes the Jabra mic on connect and shows a popup when it does.
- **A daemon restart forgets which headset is connected.** After a restart the daemon thinks nothing is connected until the bud reconnects. If PipeWire crashes and gets restarted in that window, the daemon would route audio to the S/PDIF speakers. This predates the probe.

## Dongle USB HID reference

Link 390, USB vid `0b0e`, pid `2e50`. It shows up as `/dev/hidrawN`, and the user can read and write it.

- **Report 1 (consumer keys):** bit 0 = volume down, bit 1 = volume up, bit 2 = mute. A press is `01 01 00` (down) or `01 02 00` (up), each followed by `01 00 00` for the release.
- **Report 2 (telephony), input:** the low bits echo the hook/line state, `0x04` means a call is active, and bit `0x08` is a phone-mute button press. `02 04 00` means call mode and `02 00 00` means idle.
- **Report 2 (telephony), output (host to dongle):** byte 1 bits are 0 off-hook LED, 1 mute LED, 2 ring, 3 hold, 4 microphone. `~/temp/jabra-offhook.sh` writes this. **Don't send it during a call:** the "hang-up" write makes the dongle send volume-down presses.
- **Report 4 (vendor status):** `04 00 20` is idle, `04 08 20` is call mode. The dongle enters call mode by itself when an app opens the mic, and leaves about 5 s after the mic closes.
- **Report 5 (link events):** the header `05 00 01 00 08 0d`, then byte 6 = `01` connected or `02` disconnected. The daemon uses this to detect the buds.

## Open leads and next steps

In the order we'd try them:

1. **Unplug and replug the dongle** the next time the probe alerts. This costs nothing. If it brings the mic back, the daemon can do the reset itself.
2. **Re-pair the buds to the dongle in Jabra Direct** on the Windows laptop. This throws away the dongle's stored link record, in case that record has gone bad.
3. **Use the right bud alone for a few days.** If the right bud never fails, the left bud is probably faulty, which makes it a warranty claim. If it fails too, the model is.
4. **Open a Jabra support ticket.** Evidence: latest firmware, the mic sends pure digital silence on connect, and only a full power-off clears it.
5. **A possible clue in the connect messages (only 1 example of each so far).** At connect, the dongle sends a status message starting `05 00 01 00 0a 12 02 a4 64 10 XX`. The byte `XX` was `0x30` on the dead connect at 22:34 and `0x61` on the working one at 22:38. If more connects confirm the pattern, the daemon could spot a dead link without opening the mic. Next step: have the daemon log that byte next to each `PROBE:` line.
6. **Direct Bluetooth instead of the dongle.** Useful as a test of where the fault is, but probably not as the fix.
   - **Tried 2026-10-02 with the PC's built-in Intel AX201:** pairing took the buds' connection away from the dongle. The 16 kHz call mode (mSBC) didn't work properly, and the workaround was the 8 kHz mode (CVSD). The daemon couldn't see the buds. Undo it by removing the pairing in blueman.
   - **What it would gain:** Linux would manage the link itself, log failures, and could reconnect on command. The daemon could automate that reset.
   - **What it would cost:** Bluetooth's two-way headset mode is at most 16 kHz mono on any OS. Linux also has to switch the bud between listening mode and call mode every time an app opens the mic, which is flaky.
   - **The TP-Link BT 5.4 USB adapter is a better test bed than the AX201.** It might get 16 kHz working where the AX201 failed. Check its chip, driver firmware and wideband support first. Point only the bud's pairing at it (`bluetoothctl select`); the MX Anywhere mice stay on the AX201.
   - **Interpreting the result:** if the dead mic never appears over direct Bluetooth, the dongle is at fault, so ask Jabra for a replacement Link 390. If it does appear, the bud's firmware is at fault.
7. **A newer audio stack.** Only the direct-Bluetooth experiment would benefit; the dongle path doesn't depend on PipeWire's version. Options, from least to most disruptive:
   - **The 24.04 HWE kernel (7.0):** official, and gives newer Bluetooth drivers. Check NVIDIA's driver build and the tpm-pin boot measurements first.
   - **The `pipewire-debian/pipewire-upstream` PPA:** unofficial. Gives newer PipeWire and moves WirePlumber from 0.4 to 0.5. `ppa-purge` undoes it.
   - **An upgrade to Ubuntu 26.04 LTS:** touches everything, including the tpm-pin PAM configuration.

## When to replace them

Re-evaluate after steps 1–3 above. Replace the buds if any of these happen:

- About 1 in 10 connects or more come up dead, even after re-pairing.
- The full power-off reset stops working.
- The mic dies in the middle of a call. The probe only checks at connect, so this would be the worst case.

The constraint that makes replacing them expensive: the user needs a single left bud with a working mic, and no boom mic. The only other model found in the June 2026 research that does left-only with a working mic is the Poly Voyager Free 60 (with the BT700 dongle). Independent reviews rated its comfort 3/10 for all-day wear and reported firmware disconnect problems, and the user distrusts Poly.

## Commands

- **Check the mic now** (report only; opens the mic for about 7 s):
  `./audio-switcher probe-mic`
- **Probe history** (one line per connect):
  `journalctl --user-unit audio-switcher | grep PROBE`
- **Record 8 s and play it back** (talk during the recording):
  `src=$(pactl list short sources | awk '$2 ~ /^alsa_input\..*Jabra_Link_390/ {print $2; exit}'); timeout -s INT 8 pw-record --target "$src" --rate 48000 --channels 1 --format s16 ~/temp/jabra-test.wav; paplay ~/temp/jabra-test.wav`
- **Check the alert path against a source that is always silent:**
  `pactl load-module module-null-sink sink_name=probe-test`, then `JABRA_PROBE_SOURCE=probe-test.monitor ./audio-switcher probe-mic`, then `pactl unload-module <module id>`.
- **Older scripts in `~/temp`:**
  - `jabra-mic-gain-check.sh`: records, then reports level and gain.
  - `jabra-mic-live-watch.sh`: a live level meter, plus the dongle's HID messages.
  - `jabra-offhook.sh`: sends the HID off-hook signal. Not during calls.
- **Log the dongle's HID messages** (read-only, with timestamps):
  `python3 -c 'import os,sys,time; fd=os.open(sys.argv[1],os.O_RDONLY); [print(time.strftime("%H:%M:%S"), os.read(fd,64).hex(" "), flush=True) for _ in iter(int,1)]' /dev/hidrawN`
  Find N with `grep -l 0B0E /sys/class/hidraw/hidraw*/device/uevent`.
