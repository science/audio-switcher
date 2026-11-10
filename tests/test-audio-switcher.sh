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

# --- Jabra support removed (2026-11-06) ---
# The Jabra Evolve2 buds / Link 390 were retired; the daemon routes the
# Sennheiser BTD-800 dongle only. No Jabra code, files or subcommands remain.
if ! grep -qi 'jabra' "$DAEMON" 2>/dev/null; then
    test_result "daemon has no Jabra code" "pass"
else
    test_result "daemon has no Jabra code ($(grep -ci 'jabra' "$DAEMON") lines mention it)" "fail"
fi

# The typing filter (DeepFilterNet LADSPA) and the mic probe were Jabra-only.
if ! grep -qiE 'deep_?filter|ladspa|pw-record' "$DAEMON" 2>/dev/null; then
    test_result "daemon has no typing filter or mic probe code" "pass"
else
    test_result "daemon has no typing filter or mic probe code" "fail"
fi

if ! grep -q 'probe-mic' "$DAEMON" 2>/dev/null; then
    test_result "probe-mic subcommand removed" "pass"
else
    test_result "probe-mic subcommand removed" "fail"
fi

for f in 70-jabra.rules diag-jabra.sh JABRA-DEAD-MIC.md; do
    if [[ ! -e "$PROJECT_DIR/$f" ]]; then
        test_result "$f removed from the repo" "pass"
    else
        test_result "$f removed from the repo" "fail"
    fi
done

# --- Priority routing functions ---
for func in resolve_active_device apply_priority apply_spdif_sink set_device_state get_device_state ensure_btd_mic_volume; do
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

# install.sh no longer installs the Jabra udev rule or downloads DeepFilterNet
if ! grep -qiE 'jabra|deep_?filter|DFN_' "$INSTALL_SCRIPT" 2>/dev/null; then
    test_result "install.sh has no Jabra udev rule or DeepFilterNet download" "pass"
else
    test_result "install.sh has no Jabra udev rule or DeepFilterNet download" "fail"
fi

# The BTD-800 udev rule is still installed
if grep -q '70-btd800.rules' "$INSTALL_SCRIPT" 2>/dev/null; then
    test_result "install.sh references 70-btd800.rules" "pass"
else
    test_result "install.sh references 70-btd800.rules" "fail"
fi


# uninstall.sh exists and is executable
if [[ -f "$UNINSTALL_SCRIPT" && -x "$UNINSTALL_SCRIPT" ]]; then
    test_result "uninstall.sh exists and is executable" "pass"
else
    test_result "uninstall.sh exists and is executable" "fail"
fi

echo ""

# --- Unit: active-device resolver ---
echo "--- Unit: resolve_active_device ---"

# resolve_with <state-file-contents> -> echoes the resolved device
resolve_with() {
    local tmp
    tmp=$(mktemp)
    printf '%b' "$1" > "$tmp"
    STATE_FILE="$tmp" bash -c "source '$DAEMON'; resolve_active_device" 2>/dev/null
    rm -f "$tmp"
}

assert_eq "btd when the headset is linked"          "$(resolve_with 'btd=connected\n')"    "btd"
assert_eq "none when the headset is not linked"     "$(resolve_with 'btd=disconnected\n')" "none"
assert_eq "none when the state file is empty"       "$(resolve_with '')"                   "none"
# A state file written by the old Jabra-era daemon (it lives in
# $XDG_RUNTIME_DIR, so it survives a service restart until logout).
assert_eq "stale jabra=connected line is ignored"   "$(resolve_with 'jabra=connected\nbtd=disconnected\n')" "none"
assert_eq "stale jabra line + linked BTD -> btd"    "$(resolve_with 'jabra=connected\nbtd=connected\n')"    "btd"

echo ""

# --- Unit: BTD-800 HID parser ---
# Report ID 1; byte 19 (0-indexed, counting the report-id byte) is the link flag.
echo "--- Unit: monitor_hidraw parser ---"

# btd_report <report-id> <flag-byte> -> hex of a 32-byte report
btd_report() {
    python3 -c "
r = bytearray(32); r[0] = $1; r[19] = $2
print(r.hex())"
}
# btd_parse <hex> -> runs the parser against a one-report binary file
btd_parse() {
    local tmp
    tmp=$(mktemp)
    python3 -c "import sys; sys.stdout.buffer.write(bytes.fromhex('$1'))" > "$tmp"
    STATE_FILE=/dev/null bash -c "source '$DAEMON'; monitor_hidraw '$tmp'" 2>/dev/null
    rm -f "$tmp"
}

assert_eq "parser: report 1, byte 19 = 01 -> connected"    "$(btd_parse "$(btd_report 1 1)")" "connected"
assert_eq "parser: report 1, byte 19 = 00 -> disconnected" "$(btd_parse "$(btd_report 1 0)")" "disconnected"
assert_eq "parser: other report id ignored"                "$(btd_parse "$(btd_report 2 1)")" ""
assert_eq "parser: report too short ignored"               "$(btd_parse "0101")"              ""

echo ""

# --- Unit: event_loop with an unreadable dongle ---
# Without the udev rule the hidraw node is root-only. The loop must say so and
# back off, not restart the monitor (4 log lines) every 2 seconds.
echo "--- Unit: event_loop permission check ---"
perm_run() {
    local run
    run=$(mktemp -d)
    : > "$run/hidraw"; chmod 000 "$run/hidraw"
    STATE_FILE=/dev/null HIDRAW="$run/hidraw" RUN="$run" timeout 5 bash -c '
        source "'"$DAEMON"'"
        find_hidraw() { echo "$HIDRAW"; }
        monitor_hidraw() { echo started >> "$RUN/monitor"; }
        show_status() { :; }
        n=0
        sleep() { n=$((n + 1)); echo "$1" >> "$RUN/sleeps"; (( n < 2 )) || exit 0; }
        event_loop
    ' > "$run/out" 2>/dev/null
    echo "$(cat "$run/monitor" 2>/dev/null | wc -l)|$(head -1 "$run/sleeps" 2>/dev/null)|$(grep -c 'cannot read' "$run/out")"
    chmod 600 "$run/hidraw"; rm -rf "$run"
}
if [[ $EUID -eq 0 ]]; then
    test_result "event_loop permission check (skipped: root can read anything)" "pass"
else
    assert_eq "event_loop: unreadable hidraw -> no monitor, 10 s back-off, one log line per try" \
        "$(perm_run)" "0|10|2"
fi

echo ""

# --- Unit: routing (apply_priority) ---
echo "--- Unit: apply_priority ---"

ROUTE_TMP=$(mktemp -d)
BTD_SINK_NAME="alsa_output.usb-1395_Sennheiser_BTD_800_USB-00.iec958-stereo"
BTD_SRC_NAME="alsa_input.usb-1395_Sennheiser_BTD_800_USB-00.mono-fallback"
SPDIF_NAME="alsa_output.pci-0000_00_1f.3.iec958-stereo"

# route_harness <btd-state> [command] -> runs <command> (default apply_priority)
# against a stubbed pactl.
# Inputs (env): DEF_SINK / DEF_SRC current defaults; PROFILE BTD card profile;
#   SRC_VOL the BTD mic's current volume (pactl get-source-volume).
# Outputs in $ROUTE_TMP/run: calls (pactl set-*), out (stdout)
route_harness() {
    local run="$ROUTE_TMP/run"
    rm -rf "$run"; mkdir -p "$run"
    printf 'btd=%s\n' "$1" > "$run/state"
    STATE_FILE="$run/state" RUN="$run" DEF_SINK="${DEF_SINK:-$SPDIF_NAME}" \
    DEF_SRC="${DEF_SRC:-other-mic}" PROFILE="${PROFILE:-output:iec958-stereo+input:mono-fallback}" \
    SRC_VOL="${SRC_VOL:-100%}" CMD="${2:-apply_priority}" \
    BTD_SINK_NAME="$BTD_SINK_NAME" BTD_SRC_NAME="$BTD_SRC_NAME" SPDIF_NAME="$SPDIF_NAME" bash -c '
        source "'"$DAEMON"'"
        sleep() { :; }
        pactl() {
            case "$1 ${2:-} ${3:-}" in
                "list sinks short")   printf "25\t%s\n47\t%s\n" "$SPDIF_NAME" "$BTD_SINK_NAME" ;;
                "list sources short") printf "47\t%s.monitor\n48\t%s\n" "$BTD_SINK_NAME" "$BTD_SRC_NAME" ;;
                "list cards ")        printf "Card #41\n\tName: alsa_card.usb-1395_Sennheiser_BTD_800_USB-00\n\tActive Profile: %s\n\n" "$PROFILE" ;;
                "get-default-sink  ")   echo "$DEF_SINK" ;;
                "get-default-source  ") echo "$DEF_SRC" ;;
                "get-source-volume $BTD_SRC_NAME ")
                    echo "Volume: mono: 30802 / $SRC_VOL / -19.68 dB" ;;
                set-*)                echo "$*" >> "$RUN/calls" ;;
            esac
            return 0
        }
        PW_COOLDOWN_FILE="$RUN/cooldown"
        $CMD
    ' > "$run/out" 2>/dev/null
    touch "$run/calls"
}
R="$ROUTE_TMP/run"

route_harness connected
assert_eq "apply_priority (btd): matched BTD sink + mic set as defaults" "$(cat "$R/calls")" \
    "$(printf 'set-default-sink %s\nset-default-source %s' "$BTD_SINK_NAME" "$BTD_SRC_NAME")"

DEF_SINK="$BTD_SINK_NAME" DEF_SRC="$BTD_SRC_NAME" route_harness connected
assert_eq "apply_priority (btd): already the defaults -> no calls" "$(cat "$R/calls")" ""

PROFILE="output:iec958-stereo" DEF_SINK="$BTD_SINK_NAME" DEF_SRC="$BTD_SRC_NAME" route_harness connected
assert_eq "apply_priority (btd): output-only profile -> mic input added" "$(cat "$R/calls")" \
    "set-card-profile alsa_card.usb-1395_Sennheiser_BTD_800_USB-00 output:iec958-stereo+input:mono-fallback"

DEF_SINK="$BTD_SINK_NAME" route_harness disconnected
assert_eq "apply_priority (none): S/PDIF sink, source left alone" "$(cat "$R/calls")" "set-default-sink $SPDIF_NAME"

# Mic volume: forced to BTD_SOURCE_VOLUME when the headset links, so a level
# lowered by an app (e.g. a browser's auto gain control) on an earlier call
# does not carry over. Only on connect: apply_priority alone (resume, PipeWire
# restart) leaves the volume alone; the exact-call asserts above cover that.
DEF_SINK="$BTD_SINK_NAME" DEF_SRC="$BTD_SRC_NAME" SRC_VOL="47%" route_harness connected ensure_btd_mic_volume
assert_eq "ensure_btd_mic_volume: 47% -> raised to 100%" "$(cat "$R/calls")" \
    "set-source-volume $BTD_SRC_NAME 100%"
if grep -q "MIC: BTD-800 mic volume 47% -> 100%" "$R/out"; then
    test_result "ensure_btd_mic_volume: logs the change" "pass"
else
    test_result "ensure_btd_mic_volume: logs the change" "fail"
fi

DEF_SINK="$BTD_SINK_NAME" DEF_SRC="$BTD_SRC_NAME" SRC_VOL="100%" route_harness connected ensure_btd_mic_volume
assert_eq "ensure_btd_mic_volume: already 100% -> no calls" "$(cat "$R/calls")" ""
if [[ ! -s "$R/out" ]]; then
    test_result "ensure_btd_mic_volume: already 100% -> logs nothing" "pass"
else
    test_result "ensure_btd_mic_volume: already 100% -> logs nothing" "fail"
fi

DEF_SINK="$BTD_SINK_NAME" DEF_SRC="$BTD_SRC_NAME" SRC_VOL="47%" route_harness disconnected "handle_event btd connected"
assert_eq "handle_event btd connected: mic volume raised" "$(cat "$R/calls")" \
    "set-source-volume $BTD_SRC_NAME 100%"

DEF_SINK="$BTD_SINK_NAME" DEF_SRC="$BTD_SRC_NAME" SRC_VOL="47%" route_harness connected "handle_event btd disconnected"
assert_eq "handle_event btd disconnected: mic volume untouched" "$(cat "$R/calls")" \
    "set-default-sink $SPDIF_NAME"

rm -rf "$ROUTE_TMP"

echo ""

# --- Unit: desktop default-sink resync ---
# Cinnamon's volume keys follow libcvc's cached default sink, which updates only
# on pipewire-pulse change events. When every card is re-created at once (some
# screen locks/unlocks), pulse can switch the default without an event, so the
# daemon re-announces a re-created default sink by switching to a throwaway
# null sink and straight back.
echo "--- Unit: desktop default-sink resync ---"

for const in DESKTOP_RESYNC_SINK DESKTOP_SYNC_SETTLE; do
    if grep -q "^${const}=" "$DAEMON" 2>/dev/null; then
        test_result "${const} constant present" "pass"
    else
        test_result "${const} constant present" "fail"
    fi
done

SYNC_TMP=$(mktemp -d)
SPDIF="alsa_output.pci-0000_00_1f.3.iec958-stereo"
JSINK="alsa_output.usb-1395_Sennheiser_BTD_800_USB-00.iec958-stereo"

# sync_harness <command> — runs <command> in the sourced daemon against a
# stubbed pactl. State lives in files the command may rewrite between calls:
#   $RUN/default  server default sink name
#   $RUN/sinks    "<index>\t<name>" lines (pactl list sinks short)
# Inputs (env): DEF default sink name; SINKS printf-ready sinks list;
#   STEAL=1 another writer moves the default to the headset while the resync
#   sink is the default (a routing switch racing the resync).
# Outputs in $SYNC_TMP/run: calls (pactl load/unload/set-*), out (stdout)
sync_harness() {
    local run="$SYNC_TMP/run"
    rm -rf "$run"; mkdir -p "$run"
    printf '%s\n' "${DEF:-$SPDIF}" > "$run/default"
    printf "${SINKS:-25\t$SPDIF\n6\t$JSINK\n}" > "$run/sinks"
    XDG_RUNTIME_DIR="$run" RUN="$run" STEAL="${STEAL:-}" JSINK="$JSINK" CMD="$1" bash -c '
        source "'"$DAEMON"'"
        sleep() { :; }
        pactl() {
            case "$1 ${2:-} ${3:-}" in
                "list sinks short") cat "$RUN/sinks" ;;
                "get-default-sink  ") cat "$RUN/default" ;;
                "load-module "*)   echo "$*" >> "$RUN/calls"; echo 536870999 ;;
                "unload-module "*) echo "$*" >> "$RUN/calls" ;;
                "set-default-sink "*)
                    echo "$*" >> "$RUN/calls"
                    if [[ -n "$STEAL" ]]; then echo "$JSINK" > "$RUN/default"
                    else echo "$2" > "$RUN/default"; fi ;;
            esac
            return 0
        }
        eval "$CMD"
    ' > "$run/out" 2>/dev/null
    touch "$run/calls"
}
S="$SYNC_TMP/run"
RESYNC_CALLS="load-module module-null-sink sink_name=audio_switcher_resync sink_properties=device.description=audio-switcher-resync
set-default-sink audio_switcher_resync
set-default-sink $SPDIF
unload-module 536870999"

sync_harness 'default_sink_identity'
assert_eq "default_sink_identity: '<name> <index>' of the default sink" "$(cat "$S/out")" "$SPDIF 25"
DEF="gone-sink" sync_harness 'default_sink_identity'
assert_eq "default_sink_identity: default sink not listed -> empty" "$(cat "$S/out")" ""

# First look only records the default sink.
sync_harness 'sync_desktop_default_sink; echo "$LAST_DEFAULT_SINK"'
assert_eq "resync: first check records the default, no calls" \
    "$(cat "$S/out")|$(cat "$S/calls")" "$SPDIF 25|"

# Same sink, same index -> nothing (e.g. only the HDMI sink was re-created).
sync_harness 'LAST_DEFAULT_SINK="'"$SPDIF"' 25"; sync_desktop_default_sink'
assert_eq "resync: default sink unchanged -> no calls" "$(cat "$S/calls")" ""

# Same sink name, new index -> it was re-created: switch away and back.
SINKS="381\t$SPDIF\n383\t$JSINK\n" sync_harness \
    'LAST_DEFAULT_SINK="'"$SPDIF"' 25"; sync_desktop_default_sink; echo "$LAST_DEFAULT_SINK"'
assert_eq "resync: default sink re-created -> null sink, back, unload" "$(cat "$S/calls")" "$RESYNC_CALLS"
assert_eq "resync: re-created -> default restored" "$(cat "$S/default")" "$SPDIF"
assert_eq "resync: re-created -> new index recorded" "$(tail -1 "$S/out")" "$SPDIF 381"

# The daemon switched the default to another sink -> a real change event
# already went out; just record it.
sync_harness 'LAST_DEFAULT_SINK="'"$JSINK"' 6"; sync_desktop_default_sink; echo "$LAST_DEFAULT_SINK"'
assert_eq "resync: default name changed -> no calls, new default recorded" \
    "$(cat "$S/calls")|$(cat "$S/out")" "|$SPDIF 25"

# During the lock every card is gone and the default is auto_null: keep the
# last real sink, so the unlock is still seen as a re-creation.
DEF="auto_null" SINKS="378\tauto_null\n" sync_harness \
    'LAST_DEFAULT_SINK="'"$SPDIF"' 25"; sync_desktop_default_sink; echo "$LAST_DEFAULT_SINK"'
assert_eq "resync: auto_null default ignored, last real sink kept" \
    "$(cat "$S/calls")|$(cat "$S/out")" "|$SPDIF 25"

# Full lock/unlock sequence: cards vanish, then return with new indexes.
DEF="auto_null" SINKS="378\tauto_null\n" sync_harness '
    LAST_DEFAULT_SINK="'"$SPDIF"' 25"
    sync_desktop_default_sink
    echo "'"$SPDIF"'" > "$RUN/default"
    printf "381\t'"$SPDIF"'\n383\t'"$JSINK"'\n" > "$RUN/sinks"
    sync_desktop_default_sink'
assert_eq "resync: lock (auto_null) then unlock (new index) -> one resync" "$(cat "$S/calls")" "$RESYNC_CALLS"

# Default sink not listed (mid-enumeration) -> nothing, keep the last one.
DEF="gone-sink" sync_harness \
    'LAST_DEFAULT_SINK="'"$SPDIF"' 25"; sync_desktop_default_sink; echo "$LAST_DEFAULT_SINK"'
assert_eq "resync: default sink not listed -> no calls, last kept" \
    "$(cat "$S/calls")|$(cat "$S/out")" "|$SPDIF 25"

# The resync sink itself showing up as default (never record it).
DEF="audio_switcher_resync" SINKS="417\taudio_switcher_resync\n25\t$SPDIF\n" sync_harness \
    'LAST_DEFAULT_SINK="'"$SPDIF"' 25"; sync_desktop_default_sink; echo "$LAST_DEFAULT_SINK"'
assert_eq "resync: resync sink as default ignored" "$(cat "$S/calls")|$(cat "$S/out")" "|$SPDIF 25"

# A routing switch lands while the resync sink is the default -> don't
# overwrite it with the old sink; still unload the null sink.
STEAL=1 sync_harness "resync_desktop_default_sink $SPDIF"
assert_eq "resync: default changed by someone else mid-resync -> not restored" \
    "$(grep -c "^set-default-sink $SPDIF" "$S/calls")|$(grep -c '^unload-module 536870999' "$S/calls")" "0|1"
assert_eq "resync: default changed mid-resync -> the other writer's sink stays" "$(cat "$S/default")" "$JSINK"

# Log lines go to stdout (the journal), not into a captured value.
SINKS="381\t$SPDIF\n" sync_harness \
    'LAST_DEFAULT_SINK="'"$SPDIF"' 25"; sync_desktop_default_sink'
if grep -q "RESYNC:" "$S/out"; then
    test_result "resync: logs a RESYNC line" "pass"
else
    test_result "resync: logs a RESYNC line" "fail"
fi

# desktop_sync_watch: one check per burst of new-sink events, after the burst
# has been quiet for DESKTOP_SYNC_SETTLE seconds.
watch_count() {
    local feed="$1"
    FEED="$feed" bash -c '
        source "'"$DAEMON"'"
        DESKTOP_SYNC_SETTLE=0.3
        n=0
        sync_desktop_default_sink() { n=$((n + 1)); }
        desktop_sync_watch < <(eval "$FEED")
        echo "$n"
    ' 2>/dev/null
}
EV="Event '\''new'\'' on sink #"
assert_eq "watch: no events -> no check" "$(watch_count 'true')" "0"
assert_eq "watch: one burst of 5 new sinks -> one check" \
    "$(watch_count "for i in 1 2 3 4 5; do echo \"$EV\$i\"; done")" "1"
assert_eq "watch: two bursts 1 s apart -> two checks" \
    "$(watch_count "echo \"${EV}1\"; echo \"${EV}2\"; command sleep 1; echo \"${EV}3\"")" "2"

# The loop: subscribe to new-sink events only, re-check after resubscribing
# (sinks re-created while pipewire-pulse restarted send no event to us).
loop_body=$(sed -n '/^desktop_sync_loop()/,/^}/p' "$DAEMON" 2>/dev/null)
if [[ "$loop_body" == *"pactl subscribe"* && "$loop_body" == *"'new' on sink #"* \
      && "$loop_body" == *"sync_desktop_default_sink"* && "$loop_body" == *"desktop_sync_watch"* ]]; then
    test_result "desktop_sync_loop watches new-sink events and re-checks on resubscribe" "pass"
else
    test_result "desktop_sync_loop watches new-sink events and re-checks on resubscribe" "fail"
fi
if sed -n '/^main()/,/^}/p' "$DAEMON" | grep -q 'desktop_sync_loop &' \
   && sed -n '/^cleanup()/,/^}/p' "$DAEMON" | grep -q 'DESKTOP_SYNC_PID'; then
    test_result "main starts desktop_sync_loop; cleanup stops it" "pass"
else
    test_result "main starts desktop_sync_loop; cleanup stops it" "fail"
fi

rm -rf "$SYNC_TMP"

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

# BTD-800 udev rule installed
if [[ -f /etc/udev/rules.d/70-btd800.rules ]]; then
    test_result "BTD-800 udev rule installed" "pass"
else
    test_result "BTD-800 udev rule installed" "fail"
fi

# Leftovers from the Jabra era are gone from the machine
for f in /etc/udev/rules.d/70-jabra.rules "$HOME/.local/lib/audio-switcher/libdeep_filter_ladspa.so"; do
    if [[ ! -e "$f" ]]; then
        test_result "Jabra-era leftover removed: $f" "pass"
    else
        test_result "Jabra-era leftover removed: $f" "fail"
    fi
done

echo ""

# --- Runtime Checks ---
echo "--- Runtime Checks ---"

# pactl is available
if command -v pactl &>/dev/null; then
    test_result "pactl is available" "pass"
else
    test_result "pactl is available" "fail"
fi

BTD_USB_ID="usb-1395_Sennheiser_BTD_800_USB-00"
SPDIF_SINK="alsa_output.pci-0000_00_1f.3.iec958-stereo"
STATE_FILE="${XDG_RUNTIME_DIR}/audio-switcher-state"

# BTD state from the daemon state file (default disconnected)
btd_state="disconnected"
if [[ -f "$STATE_FILE" ]]; then
    line=$(grep "^btd=" "$STATE_FILE" 2>/dev/null | tail -1)
    [[ -n "$line" ]] && btd_state="${line#*=}"
fi

current_sink=$(pactl get-default-sink 2>/dev/null || true)
current_source=$(pactl get-default-source 2>/dev/null || true)

if [[ "$btd_state" == "connected" ]]; then
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
else
    if [[ "$current_sink" == "$SPDIF_SINK" ]]; then
        test_result "default sink is S/PDIF (headset not connected)" "pass"
    else
        test_result "default sink is S/PDIF (headset not connected, got: $current_sink)" "fail"
    fi
    test_result "headset not connected — source check skipped (PipeWire chooses)" "pass"
fi

echo ""

# --- Summary ---
TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL) ==="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
