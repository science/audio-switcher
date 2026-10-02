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
