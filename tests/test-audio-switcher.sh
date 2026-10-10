#!/bin/bash
# Audio Switcher test suite
# Run: ./tests/test-audio-switcher.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DAEMON="$PROJECT_DIR/audio-switcher"
INSTALL_SCRIPT="$PROJECT_DIR/install.sh"
UNINSTALL_SCRIPT="$PROJECT_DIR/uninstall.sh"

PASS=0
FAIL=0

test_result() {
    local name="$1"
    local result="$2"
    if [[ "$result" == "pass" ]]; then
        echo "  ✓ $name"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $name"
        FAIL=$((FAIL + 1))
    fi
}

# Assert helper: pass if "$1" == "$2", else fail with detail
assert_eq() {
    local name="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        test_result "$name" "pass"
    else
        test_result "$name (got: '$got', want: '$want')" "fail"
    fi
}

echo "=== Audio Switcher Tests ==="
echo ""

# --- Static Checks ---
echo "--- Static Checks ---"

# Script exists
if [[ -f "$DAEMON" ]]; then
    test_result "audio-switcher script exists" "pass"
else
    test_result "audio-switcher script exists" "fail"
fi

# Script is executable
if [[ -x "$DAEMON" ]]; then
    test_result "audio-switcher is executable" "pass"
else
    test_result "audio-switcher is executable" "fail"
fi

# Correct shebang
if head -1 "$DAEMON" 2>/dev/null | grep -q '^#!/bin/bash'; then
    test_result "audio-switcher has bash shebang" "pass"
else
    test_result "audio-switcher has bash shebang" "fail"
fi

# Has set -euo pipefail
if grep -q 'set -euo pipefail' "$DAEMON" 2>/dev/null; then
    test_result "audio-switcher uses strict mode (set -euo pipefail)" "pass"
else
    test_result "audio-switcher uses strict mode (set -euo pipefail)" "fail"
fi

# BTD_USB_ID pattern constant
if grep -q 'BTD_USB_ID=.*usb-1395_Sennheiser_BTD_800_USB-00' "$DAEMON" 2>/dev/null; then
    test_result "BTD_USB_ID pattern constant present" "pass"
else
    test_result "BTD_USB_ID pattern constant present" "fail"
fi

# Dynamic discovery functions (BTD)
for func in find_btd_sink find_btd_source; do
    if grep -q "${func}()" "$DAEMON" 2>/dev/null; then
        test_result "${func}() function defined" "pass"
    else
        test_result "${func}() function defined" "fail"
    fi
done

# S/PDIF fallback sink constant
if grep -q 'alsa_output.pci-0000_00_1f.3.iec958-stereo' "$DAEMON" 2>/dev/null; then
    test_result "S/PDIF fallback sink constant present" "pass"
else
    test_result "S/PDIF fallback sink constant present" "fail"
fi

# --- Jabra static checks ---
# Jabra sink/source match pattern
if grep -q 'JABRA_SINK_MATCH=.*Jabra_Link_390' "$DAEMON" 2>/dev/null; then
    test_result "JABRA_SINK_MATCH pattern constant present" "pass"
else
    test_result "JABRA_SINK_MATCH pattern constant present" "fail"
fi

# Jabra USB vendor id for hidraw discovery
if grep -q 'JABRA_VID=.*0b0e' "$DAEMON" 2>/dev/null; then
    test_result "JABRA_VID constant present" "pass"
else
    test_result "JABRA_VID constant present" "fail"
fi

# Jabra HID report id constant
if grep -q 'JABRA_HID_REPORT_ID=' "$DAEMON" 2>/dev/null; then
    test_result "JABRA_HID_REPORT_ID constant present" "pass"
else
    test_result "JABRA_HID_REPORT_ID constant present" "fail"
fi

# Jabra discovery + monitor + profile functions
for func in find_jabra_hidraw find_jabra_sink find_jabra_source monitor_jabra_hidraw ensure_jabra_input_profile; do
    if grep -q "${func}()" "$DAEMON" 2>/dev/null; then
        test_result "${func}() function defined" "pass"
    else
        test_result "${func}() function defined" "fail"
    fi
done

# --- Jabra mic probe static checks ---
for const in JABRA_SOURCE_VOLUME JABRA_PROBE_DELAY JABRA_PROBE_SKIP JABRA_PROBE_LISTEN \
             JABRA_PROBE_RETRY_DELAY JABRA_PROBE_MIN_NONZERO_PCT JABRA_PROBE_VOLUME_SETTLE \
             JABRA_PROBE_ALERT_COOLDOWN JABRA_ALERT_COOLDOWN_FILE JABRA_ALERT_FLAG_FILE; do
    if grep -q "^${const}=" "$DAEMON" 2>/dev/null; then
        test_result "${const} constant present" "pass"
    else
        test_result "${const} constant present" "fail"
    fi
done

for func in jabra_mic_verdict record_jabra_mic jabra_probe_source jabra_mic_state \
            ensure_jabra_mic_live probe_jabra_mic_once probe_jabra_mic \
            start_jabra_probe stop_jabra_probe do_probe_mic; do
    if grep -q "^${func}()" "$DAEMON" 2>/dev/null; then
        test_result "${func}() function defined" "pass"
    else
        test_result "${func}() function defined" "fail"
    fi
done

# handle_event starts a probe on Jabra connect and cancels it on disconnect
if sed -n '/^handle_event()/,/^}/p' "$DAEMON" 2>/dev/null | grep -q 'start_jabra_probe'; then
    test_result "handle_event starts the mic probe on Jabra connect" "pass"
else
    test_result "handle_event starts the mic probe on Jabra connect" "fail"
fi
if sed -n '/^handle_event()/,/^}/p' "$DAEMON" 2>/dev/null | grep -q 'stop_jabra_probe'; then
    test_result "handle_event cancels the mic probe on Jabra disconnect" "pass"
else
    test_result "handle_event cancels the mic probe on Jabra disconnect" "fail"
fi

# probe-mic subcommand
if grep -q 'probe-mic)' "$DAEMON" 2>/dev/null; then
    test_result "probe-mic subcommand handled in argument parsing" "pass"
else
    test_result "probe-mic subcommand handled in argument parsing" "fail"
fi

# cleanup removes the mic-alert runtime files
if grep 'rm -f' "$DAEMON" 2>/dev/null | grep -q 'JABRA_ALERT_FLAG_FILE'; then
    test_result "cleanup removes JABRA_ALERT_FLAG_FILE" "pass"
else
    test_result "cleanup removes JABRA_ALERT_FLAG_FILE" "fail"
fi

# --- Priority routing functions ---
for func in resolve_active_device apply_priority apply_spdif_sink set_device_state get_device_state; do
    if grep -q "${func}()" "$DAEMON" 2>/dev/null; then
        test_result "${func}() function defined" "pass"
    else
        test_result "${func}() function defined" "fail"
    fi
done

# apply_spdif_sink retries on failure (PipeWire re-enumeration)
if sed -n '/apply_spdif_sink()/,/^}/p' "$DAEMON" 2>/dev/null | grep -q 'max_attempts'; then
    test_result "apply_spdif_sink retries S/PDIF sink on failure" "pass"
else
    test_result "apply_spdif_sink retries S/PDIF sink on failure" "fail"
fi

# Has BTD HID detection functions
for func in event_loop monitor_hidraw find_hidraw; do
    if grep -q "${func}()" "$DAEMON" 2>/dev/null; then
        test_result "${func}() function defined" "pass"
    else
        test_result "${func}() function defined" "fail"
    fi
done

# Has BTD HID report constants
for const in BTD_HID_REPORT_ID BTD_HID_CONNECT_BYTE; do
    if grep -q "${const}=" "$DAEMON" 2>/dev/null; then
        test_result "${const} constant present" "pass"
    else
        test_result "${const} constant present" "fail"
    fi
done

# Has PipeWire recovery functions
for func in check_pipewire_health pipewire_health_loop; do
    if grep -q "${func}()" "$DAEMON" 2>/dev/null; then
        test_result "${func}() function defined" "pass"
    else
        test_result "${func}() function defined" "fail"
    fi
done

# Has PipeWire recovery constants
for const in PW_ERROR_THRESHOLD PW_COOLDOWN_SECONDS; do
    if grep -q "${const}=" "$DAEMON" 2>/dev/null; then
        test_result "${const} constant present" "pass"
    else
        test_result "${const} constant present" "fail"
    fi
done

# State file IPC
if grep -q 'STATE_FILE=' "$DAEMON" 2>/dev/null; then
    test_result "STATE_FILE constant present" "pass"
else
    test_result "STATE_FILE constant present" "fail"
fi

# Has ensure_btd_input_profile function
if grep -q 'ensure_btd_input_profile()' "$DAEMON" 2>/dev/null; then
    test_result "ensure_btd_input_profile() function defined" "pass"
else
    test_result "ensure_btd_input_profile() function defined" "fail"
fi

# Has sleep_resume_loop function
if grep -q 'sleep_resume_loop()' "$DAEMON" 2>/dev/null; then
    test_result "sleep_resume_loop() function defined" "pass"
else
    test_result "sleep_resume_loop() function defined" "fail"
fi

# Daemon is sourceable (main guarded so tests can source it)
if grep -qE 'BASH_SOURCE\[0\].*==.*\$\{?0' "$DAEMON" 2>/dev/null; then
    test_result "daemon guards main() for sourceability" "pass"
else
    test_result "daemon guards main() for sourceability" "fail"
fi

# Has notify_user function
if grep -q 'notify_user()' "$DAEMON" 2>/dev/null; then
    test_result "notify_user() function defined" "pass"
else
    test_result "notify_user() function defined" "fail"
fi

# Has notify_pw_restart function for PipeWire restart notifications
if grep -q 'notify_pw_restart()' "$DAEMON" 2>/dev/null; then
    test_result "notify_pw_restart() function defined" "pass"
else
    test_result "notify_pw_restart() function defined" "fail"
fi

# PW restart notification has cooldown guard (PW_NOTIFY_COOLDOWN_SECONDS)
if grep -q 'PW_NOTIFY_COOLDOWN_SECONDS=' "$DAEMON" 2>/dev/null; then
    test_result "PW_NOTIFY_COOLDOWN_SECONDS constant present" "pass"
else
    test_result "PW_NOTIFY_COOLDOWN_SECONDS constant present" "fail"
fi

# PW restart notification cooldown file
if grep -q 'PW_NOTIFY_COOLDOWN_FILE=' "$DAEMON" 2>/dev/null; then
    test_result "PW_NOTIFY_COOLDOWN_FILE constant present" "pass"
else
    test_result "PW_NOTIFY_COOLDOWN_FILE constant present" "fail"
fi

# notify_pw_restart is called after PipeWire restart in check_pipewire_health
if sed -n '/^check_pipewire_health()/,/^}/p' "$DAEMON" 2>/dev/null | grep -q 'notify_pw_restart'; then
    test_result "notify_pw_restart called after PipeWire restart" "pass"
else
    test_result "notify_pw_restart called after PipeWire restart" "fail"
fi

# cleanup removes the notification cooldown file
if grep 'rm -f' "$DAEMON" 2>/dev/null | grep -q 'PW_NOTIFY_COOLDOWN_FILE'; then
    test_result "cleanup removes PW_NOTIFY_COOLDOWN_FILE" "pass"
else
    test_result "cleanup removes PW_NOTIFY_COOLDOWN_FILE" "fail"
fi

# Has fix subcommand
if grep -q 'fix)' "$DAEMON" 2>/dev/null; then
    test_result "fix subcommand handled in argument parsing" "pass"
else
    test_result "fix subcommand handled in argument parsing" "fail"
fi

# Hunt mode constants
for const in PW_HUNT_DURATION PW_HUNT_INTERVAL; do
    if grep -q "${const}=" "$DAEMON" 2>/dev/null; then
        test_result "${const} constant present" "pass"
    else
        test_result "${const} constant present" "fail"
    fi
done

# Has signal handling (trap)
if grep -q 'trap' "$DAEMON" 2>/dev/null; then
    test_result "signal handling (trap) present" "pass"
else
    test_result "signal handling (trap) present" "fail"
fi

# install.sh exists and is executable
if [[ -f "$INSTALL_SCRIPT" && -x "$INSTALL_SCRIPT" ]]; then
    test_result "install.sh exists and is executable" "pass"
else
    test_result "install.sh exists and is executable" "fail"
fi

# install.sh has --uninstall support
if grep -q '\-\-uninstall' "$INSTALL_SCRIPT" 2>/dev/null; then
    test_result "install.sh supports --uninstall" "pass"
else
    test_result "install.sh supports --uninstall" "fail"
fi

# install.sh installs the Jabra udev rule
if grep -q '70-jabra.rules' "$INSTALL_SCRIPT" 2>/dev/null; then
    test_result "install.sh references 70-jabra.rules" "pass"
else
    test_result "install.sh references 70-jabra.rules" "fail"
fi

# Jabra udev rule file exists and grants hidraw access for vid 0b0e
if [[ -f "$PROJECT_DIR/70-jabra.rules" ]] && grep -q '0b0e' "$PROJECT_DIR/70-jabra.rules" 2>/dev/null; then
    test_result "70-jabra.rules exists and matches vid 0b0e" "pass"
else
    test_result "70-jabra.rules exists and matches vid 0b0e" "fail"
fi

# uninstall.sh exists and is executable
if [[ -f "$UNINSTALL_SCRIPT" && -x "$UNINSTALL_SCRIPT" ]]; then
    test_result "uninstall.sh exists and is executable" "pass"
else
    test_result "uninstall.sh exists and is executable" "fail"
fi

echo ""

# --- Unit: priority resolver truth table ---
echo "--- Unit: resolve_active_device ---"

# resolve_for <jabra-state> <btd-state> -> echoes resolved device
resolve_for() {
    local tmp
    tmp=$(mktemp)
    printf 'jabra=%s\nbtd=%s\n' "$1" "$2" > "$tmp"
    STATE_FILE="$tmp" bash -c "source '$DAEMON'; resolve_active_device" 2>/dev/null
    rm -f "$tmp"
}

assert_eq "Jabra wins when both connected"          "$(resolve_for connected connected)"       "jabra"
assert_eq "Jabra wins when only Jabra connected"    "$(resolve_for connected disconnected)"    "jabra"
assert_eq "BTD wins when only BTD connected"        "$(resolve_for disconnected connected)"    "btd"
assert_eq "none when neither connected"             "$(resolve_for disconnected disconnected)" "none"

echo ""

# --- Unit: Jabra HID parser ---
echo "--- Unit: monitor_jabra_hidraw parser ---"

# jabra_parse <hex> -> runs the parser against a one-report binary file
jabra_parse() {
    local tmp
    tmp=$(mktemp)
    python3 -c "import sys; sys.stdout.buffer.write(bytes.fromhex('$1'))" > "$tmp"
    STATE_FILE=/dev/null bash -c "source '$DAEMON'; monitor_jabra_hidraw '$tmp'" 2>/dev/null
    rm -f "$tmp"
}

# Confirmed signatures: header 05 00 01 00 08 0d, byte[6] 01=connect / 02=disconnect
assert_eq "parser: 08 0d 01 -> connected"      "$(jabra_parse 05000100080d01010402)" "connected"
assert_eq "parser: 08 0d 02 -> disconnected"   "$(jabra_parse 05000100080d02010402)" "disconnected"
# Lookalike report (byte2=04, '05 00 04 ..') must NOT match
assert_eq "parser: 05 00 04 lookalike ignored" "$(jabra_parse 05000451080d010a0900)" ""

echo ""

# --- Unit: Jabra card profile enforcement ---
# The Link 390 exposes both an "iec958" (digital passthrough) and an
# "analog-stereo" output. WirePlumber picks iec958 by priority, which is
# SILENT on the buds. The daemon must force the analog+mic profile on connect.
echo "--- Unit: ensure_jabra_input_profile ---"

JABRA_WANT_PROFILE="output:analog-stereo+input:mono-fallback"
JABRA_TEST_CARD="alsa_card.usb-_Jabra_Link_390_6CFBED6C99AB2-00"

if grep -q "JABRA_PROFILE=\"$JABRA_WANT_PROFILE\"" "$DAEMON" 2>/dev/null; then
    test_result "JABRA_PROFILE constant is analog-stereo + mono input" "pass"
else
    test_result "JABRA_PROFILE constant is analog-stereo + mono input" "fail"
fi

# jabra_profile_run <active-profile> -> echoes "<card> <profile>" for each
# set-card-profile call the daemon issued against a stubbed pactl ("" if none)
jabra_profile_run() {
    local calls
    calls=$(mktemp)
    STATE_FILE=/dev/null CALLS="$calls" ACTIVE="$1" CARD="$JABRA_TEST_CARD" bash -c '
        source "'"$DAEMON"'"
        pactl() {
            case "$1 $2 ${3:-}" in
                "list cards short")   printf "99\t%s\talsa\n" "$CARD" ;;
                "list cards ")        printf "Card #99\n\tName: %s\n\tActive Profile: %s\n\n" "$CARD" "$ACTIVE" ;;
                "set-card-profile "*) echo "$2 $3" >> "$CALLS" ;;
            esac
        }
        ensure_jabra_input_profile >/dev/null
    ' 2>/dev/null
    cat "$calls"
    rm -f "$calls"
}

assert_eq "profile: iec958+input is switched to analog+input" \
    "$(jabra_profile_run 'output:iec958-stereo+input:mono-fallback')" \
    "$JABRA_TEST_CARD $JABRA_WANT_PROFILE"
assert_eq "profile: analog output-only is switched to analog+input" \
    "$(jabra_profile_run 'output:analog-stereo')" \
    "$JABRA_TEST_CARD $JABRA_WANT_PROFILE"
assert_eq "profile: analog+input left alone" \
    "$(jabra_profile_run "$JABRA_WANT_PROFILE")" \
    ""

# find_jabra_sink prefers the analog sink when PipeWire still lists both
# (transiently true right after a profile switch).
jabra_sink_pick() {
    STATE_FILE=/dev/null bash -c '
        source "'"$DAEMON"'"
        pactl() {
            printf "1\talsa_output.usb-_Jabra_Link_390_X-00.iec958-stereo\tPipeWire\n"
            printf "2\talsa_output.usb-_Jabra_Link_390_X-00.analog-stereo\tPipeWire\n"
        }
        find_jabra_sink
    ' 2>/dev/null
}
assert_eq "find_jabra_sink prefers analog-stereo over iec958" \
    "$(jabra_sink_pick)" "alsa_output.usb-_Jabra_Link_390_X-00.analog-stereo"

# wait_for_jabra_sink polls until the (re-created) sink appears.
jabra_sink_wait() {
    local counter
    counter=$(mktemp)
    echo 0 > "$counter"
    STATE_FILE=/dev/null COUNTER="$counter" bash -c '
        source "'"$DAEMON"'"
        pactl() {
            local n; n=$(cat "$COUNTER"); echo $((n+1)) > "$COUNTER"
            (( n >= 2 )) && printf "2\talsa_output.usb-_Jabra_Link_390_X-00.analog-stereo\tPipeWire\n"
            return 0
        }
        wait_for_jabra_sink
    ' 2>/dev/null
    rm -f "$counter"
}
assert_eq "wait_for_jabra_sink returns sink once it appears" \
    "$(jabra_sink_wait)" "alsa_output.usb-_Jabra_Link_390_X-00.analog-stereo"

# apply_priority must use the waiting lookup in the jabra branch (the profile
# switch re-creates the sink, so an immediate lookup can miss it).
if sed -n '/^apply_priority()/,/^}/p' "$DAEMON" 2>/dev/null | grep -q 'wait_for_jabra_sink'; then
    test_result "apply_priority waits for the Jabra sink after profile switch" "pass"
else
    test_result "apply_priority waits for the Jabra sink after profile switch" "fail"
fi

echo ""

# --- Unit: Jabra mic probe ---
echo "--- Unit: Jabra mic probe ---"

# Synthetic 48 kHz mono s16 recordings shaped like the real 2026-10-09 takes.
PROBE_TMP=$(mktemp -d)
python3 - "$PROBE_TMP" <<'PY'
import array, math, random, sys, wave
d, sr = sys.argv[1], 48000
n = int(6.5 * sr)
def write(name, samples):
    w = wave.open(f"{d}/{name}.wav", "wb")
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(array.array("h", samples).tobytes())
    w.close()
random.seed(1)
# Stuck bud: nothing but exact zeros.
write("dead", [0] * n)
# Stuck bud plus one 20 ms click (the hw mute switch flip seen in j2.wav).
click = [0] * n
for i in range(3 * sr, 3 * sr + sr // 50):
    click[i] = 600 if i % 2 else -600
write("click", click)
# Working bud in a silent room: ~0.9 s of startup zeros, then a faint noise
# floor of +/-3 with ~15% exact zeros scattered through it (w.wav shape).
start = int(0.9 * sr)
write("quiet", [0] * start + [random.choice((-3, -2, -1, 1, 2, 3)) if random.random() > 0.15 else 0
                              for _ in range(n - start)])
# Working bud, speaking: 1 s startup zeros, then a tone gated off every third 100 ms.
write("speech", [0] * sr + [int(3000 * math.sin(2 * math.pi * 300 * i / sr)) if (i // 4800) % 3 else 0
                            for i in range(n - sr)])
# Too short to judge (1 s).
write("short", [5] * sr)
PY
: > "$PROBE_TMP/empty.wav"

# mic_verdict <wav> -> full verdict line from jabra_mic_verdict
mic_verdict() {
    STATE_FILE=/dev/null bash -c "source '$DAEMON'; jabra_mic_verdict '$1'" 2>/dev/null
}

assert_eq "verdict: all zeros -> dead"            "$(mic_verdict "$PROBE_TMP/dead.wav"   | awk '{print $1}')" "dead"
assert_eq "verdict: zeros + one click -> dead"    "$(mic_verdict "$PROBE_TMP/click.wav"  | awk '{print $1}')" "dead"
assert_eq "verdict: silent-room noise floor -> ok" "$(mic_verdict "$PROBE_TMP/quiet.wav" | awk '{print $1}')" "ok"
assert_eq "verdict: gated speech -> ok"           "$(mic_verdict "$PROBE_TMP/speech.wav" | awk '{print $1}')" "ok"
assert_eq "verdict: empty file -> inconclusive"   "$(mic_verdict "$PROBE_TMP/empty.wav"  | awk '{print $1}')" "inconclusive"
assert_eq "verdict: 1 s file -> inconclusive"     "$(mic_verdict "$PROBE_TMP/short.wav"  | awk '{print $1}')" "inconclusive"
assert_eq "verdict: missing file -> inconclusive" "$(mic_verdict "$PROBE_TMP/nope.wav"   | awk '{print $1}')" "inconclusive"
if mic_verdict "$PROBE_TMP/quiet.wav" | grep -qE '^ok nonzero=[0-9.]+ rms=-?[0-9.inf]+ longest_zero=[0-9.]+ secs=[0-9.]+$'; then
    test_result "verdict line carries nonzero/rms/longest_zero/secs stats" "pass"
else
    test_result "verdict line carries nonzero/rms/longest_zero/secs stats ($(mic_verdict "$PROBE_TMP/quiet.wav"))" "fail"
fi

# probe_harness <mode> — runs probe_jabra_mic (mode=probe) or do_probe_mic
# (mode=subcommand) against stubbed pactl / recorder / notify / sleep / log.
# Inputs (env): SEQ   space-separated recordings returned by successive takes
#               MUTE  yes|no            SRCVOL  source volume line fragment
#               SINKVOL_AFTER  raw sink volume after the first reading
#               NOSRC=1  no Jabra source in PipeWire
#               FLAG=<id>  an earlier dead alert is outstanding (notification id)
#               COOLDOWN=1 a dead alert was sent just now
# Outputs in $PROBE_TMP/run: calls (pactl set-*), notify, log, rec (take count), out (stdout)
probe_harness() {
    local run="$PROBE_TMP/run"
    rm -rf "$run"; mkdir -p "$run/xdg"
    [[ -n "${FLAG:-}" ]] && echo "$FLAG" > "$run/xdg/audio-switcher-mic-alert"
    [[ -n "${COOLDOWN:-}" ]] && date +%s > "$run/xdg/audio-switcher-mic-alert-cooldown"
    STATE_FILE=/dev/null XDG_RUNTIME_DIR="$run/xdg" RUN="$run" WAVS="$PROBE_TMP" MODE="$1" \
    SEQ="${SEQ:-quiet}" MUTE="${MUTE:-no}" SRCVOL="${SRCVOL:-30802 /  47%}" \
    SINKVOL_AFTER="${SINKVOL_AFTER:-29484}" NOSRC="${NOSRC:-}" bash -c '
        source "'"$DAEMON"'"
        sleep() { :; }
        log() { echo "$*" >> "$RUN/log"; }
        notify_user() { echo "$1|$2|${4:-}" >> "$RUN/notify"; }
        notify_user_tracked() { echo "$1|$2|tracked" >> "$RUN/notify"; echo 777; }
        record_jabra_mic() {
            local n takes
            n=$(cat "$RUN/rec" 2>/dev/null || echo 0); echo $((n + 1)) > "$RUN/rec"
            read -ra takes <<< "$SEQ"
            cp "$WAVS/${takes[n]:-dead}.wav" "$3"
        }
        pactl() {
            local n v
            case "$1" in
                list) [[ -n "$NOSRC" ]] || printf "7\talsa_input.usb-_Jabra_Link_390_X-00.mono-fallback\tPipeWire\n" ;;
                get-source-mute)   echo "Mute: $MUTE" ;;
                get-source-volume) echo "Volume: mono: $SRCVOL / -19.69 dB" ;;
                get-default-sink)  echo "jabra-sink" ;;
                get-sink-volume)
                    n=$(cat "$RUN/sv" 2>/dev/null || echo 0); echo $((n + 1)) > "$RUN/sv"
                    if (( n == 0 )); then v=29484; else v=$SINKVOL_AFTER; fi
                    echo "Volume: front-left: $v /  45% / -20.81 dB,   front-right: $v /  45% / -20.81 dB" ;;
                get-sink-mute)     echo "Mute: no" ;;
                set-*)             echo "$*" >> "$RUN/calls" ;;
            esac
            return 0
        }
        if [[ "$MODE" == subcommand ]]; then do_probe_mic; else probe_jabra_mic; fi
    ' > "$run/out" 2>/dev/null
    touch "$run/calls" "$run/notify" "$run/log" "$run/rec"
}
P="$PROBE_TMP/run"
JSRC="alsa_input.usb-_Jabra_Link_390_X-00.mono-fallback"

SEQ="dead dead" probe_harness probe
assert_eq "probe: dead,dead -> one critical 'silent' alert" "$(cat "$P/notify")" "critical|Jabra mic is silent|tracked"
assert_eq "probe: dead,dead -> alert flag holds notification id" "$(cat "$P/xdg/audio-switcher-mic-alert" 2>/dev/null)" "777"
assert_eq "probe: dead,dead -> retried once (2 takes)" "$(cat "$P/rec")" "2"
if grep -q '^PROBE: jabra mic dead nonzero=0.0' "$P/log"; then
    test_result "probe: logs one PROBE line with the verdict stats" "pass"
else
    test_result "probe: logs one PROBE line with the verdict stats ($(cat "$P/log"))" "fail"
fi

SEQ="dead quiet" probe_harness probe
assert_eq "probe: dead,ok -> no notification" "$(cat "$P/notify")" ""
assert_eq "probe: dead,ok -> no alert flag" "$([[ -f "$P/xdg/audio-switcher-mic-alert" ]] && echo set)" ""

SEQ="quiet" probe_harness probe
assert_eq "probe: ok -> single take, no retry" "$(cat "$P/rec")" "1"
assert_eq "probe: ok -> no notification" "$(cat "$P/notify")" ""

SEQ="quiet" probe_harness probe
if grep -qx "set-source-volume $JSRC 100%" "$P/calls"; then
    test_result "probe: forces Jabra mic volume to JABRA_SOURCE_VOLUME (47% -> 100%)" "pass"
else
    test_result "probe: forces Jabra mic volume to JABRA_SOURCE_VOLUME ($(cat "$P/calls"))" "fail"
fi
SEQ="quiet" SRCVOL="65536 / 100%" probe_harness probe
assert_eq "probe: mic already at 100% -> no volume change" "$(grep -c 'set-source-volume' "$P/calls")" "0"

SEQ="quiet" MUTE=yes probe_harness probe
if grep -qx "set-source-mute $JSRC 0" "$P/calls"; then
    test_result "probe: muted mic is unmuted" "pass"
else
    test_result "probe: muted mic is unmuted ($(cat "$P/calls"))" "fail"
fi
assert_eq "probe: muted + ok -> one normal 'unmuted' notification" "$(cat "$P/notify")" "normal|Jabra mic unmuted|"

SEQ="dead dead" MUTE=yes probe_harness probe
assert_eq "probe: muted + dead -> unmuted notice AND silent alert" "$(cat "$P/notify")" \
    "$(printf 'normal|Jabra mic unmuted|\ncritical|Jabra mic is silent|tracked')"

SEQ="quiet" FLAG=4242 probe_harness probe
assert_eq "probe: ok after an alert -> 'working again' replaces it" "$(cat "$P/notify")" "normal|Jabra mic working again|4242"
assert_eq "probe: ok after an alert -> flag cleared" "$([[ -f "$P/xdg/audio-switcher-mic-alert" ]] && echo set)" ""

SEQ="dead dead" COOLDOWN=1 probe_harness probe
assert_eq "probe: dead within alert cooldown -> no second popup" "$(cat "$P/notify")" ""

NOSRC=1 probe_harness probe
assert_eq "probe: no Jabra source -> nothing recorded" "$(cat "$P/rec")" ""
assert_eq "probe: no Jabra source -> no notification" "$(cat "$P/notify")" ""

SEQ="dead dead" SINKVOL_AFTER=20000 probe_harness probe
assert_eq "probe: sink volume drift is restored to the snapshot" \
    "$(grep 'set-sink-volume' "$P/calls")" "set-sink-volume jabra-sink 29484 29484"
SEQ="quiet" probe_harness probe
assert_eq "probe: unchanged sink volume -> no restore" "$(grep -c 'set-sink' "$P/calls")" "0"

# probe-mic subcommand: report only, never change anything
SEQ="quiet" MUTE=yes probe_harness subcommand
assert_eq "probe-mic: muted mic -> reports muted" "$(awk '{print $1}' "$P/out")" "muted"
assert_eq "probe-mic: muted mic -> no recording" "$(cat "$P/rec")" ""
SEQ="quiet" probe_harness subcommand
assert_eq "probe-mic: live mic -> prints verdict" "$(awk '{print $1}' "$P/out")" "ok"
if grep -q 'vol=47%' "$P/out"; then
    test_result "probe-mic: verdict line reports the mic volume" "pass"
else
    test_result "probe-mic: verdict line reports the mic volume ($(cat "$P/out"))" "fail"
fi
assert_eq "probe-mic: changes nothing (no pactl set-*)" "$(cat "$P/calls")" ""

# stop_jabra_probe must end a running probe promptly (not after its current
# sleep/recording finishes) and the probe's trap must still restore volume.
probe_stop_run() {
    local run="$PROBE_TMP/stop"
    rm -rf "$run"; mkdir -p "$run/xdg"
    STATE_FILE=/dev/null XDG_RUNTIME_DIR="$run/xdg" RUN="$run" bash -c '
        source "'"$DAEMON"'"
        JABRA_PROBE_DELAY=0
        log() { :; }
        notify_user() { :; }
        record_jabra_mic() { command sleep 30; }
        pactl() {
            local n v
            case "$1" in
                list) printf "7\talsa_input.usb-_Jabra_Link_390_X-00.mono-fallback\tPipeWire\n" ;;
                get-source-mute)   echo "Mute: no" ;;
                get-source-volume) echo "Volume: mono: 65536 / 100% / 0.00 dB" ;;
                get-default-sink)  echo "jabra-sink" ;;
                get-sink-volume)
                    n=$(cat "$RUN/sv" 2>/dev/null || echo 0); echo $((n + 1)) > "$RUN/sv"
                    if (( n == 0 )); then v=29484; else v=20000; fi
                    echo "Volume: front-left: $v /  45% / -20.81 dB,   front-right: $v /  45% / -20.81 dB" ;;
                get-sink-mute)     echo "Mute: no" ;;
                set-*)             echo "$*" >> "$RUN/calls" ;;
            esac
            return 0
        }
        start_jabra_probe
        command sleep 1
        t0=$SECONDS
        stop_jabra_probe
        wait 2>/dev/null || true
        echo $(( SECONDS - t0 )) > "$RUN/elapsed"
    ' 2>/dev/null
}
probe_stop_run
if [[ -f "$PROBE_TMP/stop/elapsed" ]] && (( $(cat "$PROBE_TMP/stop/elapsed") <= 3 )); then
    test_result "stop_jabra_probe ends a mid-recording probe promptly" "pass"
else
    test_result "stop_jabra_probe ends a mid-recording probe promptly (took $(cat "$PROBE_TMP/stop/elapsed" 2>/dev/null || echo '?')s)" "fail"
fi
assert_eq "stop_jabra_probe: killed probe still restores sink volume" \
    "$(grep 'set-sink-volume' "$PROBE_TMP/stop/calls" 2>/dev/null)" "set-sink-volume jabra-sink 29484 29484"

rm -rf "$PROBE_TMP"

echo ""

# --- Installation Checks ---
echo "--- Installation Checks ---"

INSTALLED_BIN="$HOME/.local/bin/audio-switcher"
SERVICE_NAME="audio-switcher.service"

# Installed binary exists
if [[ -f "$INSTALLED_BIN" ]]; then
    test_result "audio-switcher installed to ~/.local/bin" "pass"
else
    test_result "audio-switcher installed to ~/.local/bin" "fail"
fi

# Systemd service file exists
if [[ -f "$HOME/.config/systemd/user/$SERVICE_NAME" ]]; then
    test_result "systemd user service file exists" "pass"
else
    test_result "systemd user service file exists" "fail"
fi

# Service is enabled
if systemctl --user is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    test_result "audio-switcher service is enabled" "pass"
else
    test_result "audio-switcher service is enabled" "fail"
fi

# Service is active
if systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    test_result "audio-switcher service is active" "pass"
else
    test_result "audio-switcher service is active" "fail"
fi

echo ""

# --- Runtime Checks (priority model) ---
echo "--- Runtime Checks ---"

# pactl is available
if command -v pactl &>/dev/null; then
    test_result "pactl is available" "pass"
else
    test_result "pactl is available" "fail"
fi

BTD_USB_ID="usb-1395_Sennheiser_BTD_800_USB-00"
JABRA_MATCH="Jabra_Link_390"
SPDIF_SINK="alsa_output.pci-0000_00_1f.3.iec958-stereo"
STATE_FILE="${XDG_RUNTIME_DIR}/audio-switcher-state"

# Read a device's state from the daemon state file (default disconnected)
rt_get_state() {
    local d="$1" line=""
    [[ -f "$STATE_FILE" ]] && line=$(grep "^${d}=" "$STATE_FILE" 2>/dev/null | tail -1)
    if [[ -n "$line" ]]; then echo "${line#*=}"; else echo "disconnected"; fi
}

active="none"
if [[ "$(rt_get_state jabra)" == "connected" ]]; then
    active="jabra"
elif [[ "$(rt_get_state btd)" == "connected" ]]; then
    active="btd"
fi

current_sink=$(pactl get-default-sink 2>/dev/null || true)
current_source=$(pactl get-default-source 2>/dev/null || true)

case "$active" in
    jabra)
        J_SINK=$(pactl list sinks short 2>/dev/null | grep "$JABRA_MATCH" | awk '{print $2}' | head -1)
        J_SRC=$(pactl list sources short 2>/dev/null | grep "$JABRA_MATCH" | grep -v '\.monitor' | awk '{print $2}' | head -1)
        if [[ -n "$J_SINK" && "$current_sink" == "$J_SINK" ]]; then
            test_result "default sink is Jabra (buds connected)" "pass"
        else
            test_result "default sink is Jabra (buds connected, got: $current_sink, expected: ${J_SINK:-(not found)})" "fail"
        fi
        if [[ -n "$J_SRC" && "$current_source" == "$J_SRC" ]]; then
            test_result "default source is Jabra mic (buds connected)" "pass"
        else
            test_result "default source is Jabra mic (buds connected, got: $current_source, expected: ${J_SRC:-(not found)})" "fail"
        fi
        ;;
    btd)
        BTD_SINK=$(pactl list sinks short 2>/dev/null | grep "$BTD_USB_ID" | awk '{print $2}' | head -1)
        BTD_SOURCE=$(pactl list sources short 2>/dev/null | grep "$BTD_USB_ID" | grep -v '\.monitor' | awk '{print $2}' | head -1)
        if [[ -n "$BTD_SINK" && "$current_sink" == "$BTD_SINK" ]]; then
            test_result "default sink is BTD-800 (headset connected)" "pass"
        else
            test_result "default sink is BTD-800 (headset connected, got: $current_sink, expected: ${BTD_SINK:-(not found)})" "fail"
        fi
        if [[ -n "$BTD_SOURCE" && "$current_source" == "$BTD_SOURCE" ]]; then
            test_result "default source is BTD-800 mic (headset connected)" "pass"
        else
            test_result "default source is BTD-800 mic (headset connected, got: $current_source, expected: ${BTD_SOURCE:-(not found)})" "fail"
        fi
        ;;
    none)
        if [[ "$current_sink" == "$SPDIF_SINK" ]]; then
            test_result "default sink is S/PDIF (no headset active)" "pass"
        else
            test_result "default sink is S/PDIF (no headset active, got: $current_sink)" "fail"
        fi
        test_result "no headset active — source check skipped (PipeWire chooses)" "pass"
        ;;
esac

echo ""

# --- Summary ---
TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL) ==="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
