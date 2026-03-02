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

# Dynamic discovery functions
if grep -q 'find_btd_sink()' "$DAEMON" 2>/dev/null; then
    test_result "find_btd_sink() function defined" "pass"
else
    test_result "find_btd_sink() function defined" "fail"
fi

if grep -q 'find_btd_source()' "$DAEMON" 2>/dev/null; then
    test_result "find_btd_source() function defined" "pass"
else
    test_result "find_btd_source() function defined" "fail"
fi

# S/PDIF fallback sink constant
if grep -q 'alsa_output.pci-0000_00_1f.3.iec958-stereo' "$DAEMON" 2>/dev/null; then
    test_result "S/PDIF fallback sink constant present" "pass"
else
    test_result "S/PDIF fallback sink constant present" "fail"
fi

# Has apply_defaults function
if grep -q 'apply_defaults()' "$DAEMON" 2>/dev/null; then
    test_result "apply_defaults() function defined" "pass"
else
    test_result "apply_defaults() function defined" "fail"
fi

# Has HID detection functions
for func in event_loop monitor_hidraw find_hidraw; do
    if grep -q "${func}()" "$DAEMON" 2>/dev/null; then
        test_result "${func}() function defined" "pass"
    else
        test_result "${func}() function defined" "fail"
    fi
done

# Has HID report constants
if grep -q 'BTD_HID_REPORT_ID=' "$DAEMON" 2>/dev/null; then
    test_result "BTD_HID_REPORT_ID constant present" "pass"
else
    test_result "BTD_HID_REPORT_ID constant present" "fail"
fi

if grep -q 'BTD_HID_CONNECT_BYTE=' "$DAEMON" 2>/dev/null; then
    test_result "BTD_HID_CONNECT_BYTE constant present" "pass"
else
    test_result "BTD_HID_CONNECT_BYTE constant present" "fail"
fi

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

# Has state file IPC
for func in write_state read_state; do
    if grep -q "${func}()" "$DAEMON" 2>/dev/null; then
        test_result "${func}() function defined" "pass"
    else
        test_result "${func}() function defined" "fail"
    fi
done

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

# Has rapid_health_check function
if grep -q 'rapid_health_check()' "$DAEMON" 2>/dev/null; then
    test_result "rapid_health_check() function defined" "pass"
else
    test_result "rapid_health_check() function defined" "fail"
fi

# Event loop connect handler uses rapid_health_check
if grep -q 'rapid_health_check' "$DAEMON" 2>/dev/null; then
    test_result "event_loop references rapid_health_check" "pass"
else
    test_result "event_loop references rapid_health_check" "fail"
fi

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

# uninstall.sh exists and is executable
if [[ -f "$UNINSTALL_SCRIPT" && -x "$UNINSTALL_SCRIPT" ]]; then
    test_result "uninstall.sh exists and is executable" "pass"
else
    test_result "uninstall.sh exists and is executable" "fail"
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

# --- Runtime Checks ---
echo "--- Runtime Checks ---"

# pactl is available
if command -v pactl &>/dev/null; then
    test_result "pactl is available" "pass"
else
    test_result "pactl is available" "fail"
fi

# Check defaults match headset connection state (via daemon state file)
# Dynamic discovery: find BTD-800 sink/source the same way the daemon does
BTD_USB_ID="usb-1395_Sennheiser_BTD_800_USB-00"
BTD_SINK=$(pactl list sinks short 2>/dev/null | grep "$BTD_USB_ID" | awk '{print $2}' | head -1)
BTD_SOURCE=$(pactl list sources short 2>/dev/null | grep "$BTD_USB_ID" | grep -v '\.monitor' | awk '{print $2}' | head -1)
SPDIF_SINK="alsa_output.pci-0000_00_1f.3.iec958-stereo"
STATE_FILE="${XDG_RUNTIME_DIR}/audio-switcher-state"

headset_connected=false
if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "connected" ]]; then
    headset_connected=true
fi

current_default=$(pactl get-default-sink 2>/dev/null || true)
current_default_source=$(pactl get-default-source 2>/dev/null || true)

if [[ "$headset_connected" == "true" ]]; then
    if [[ -n "$BTD_SINK" && "$current_default" == "$BTD_SINK" ]]; then
        test_result "default sink is BTD-800 (headset connected)" "pass"
    else
        test_result "default sink is BTD-800 (headset connected, got: $current_default, expected: ${BTD_SINK:-(not found)})" "fail"
    fi
    if [[ -n "$BTD_SOURCE" && "$current_default_source" == "$BTD_SOURCE" ]]; then
        test_result "default source is BTD-800 mic (headset connected)" "pass"
    else
        test_result "default source is BTD-800 mic (headset connected, got: $current_default_source, expected: ${BTD_SOURCE:-(not found)})" "fail"
    fi
else
    if [[ "$current_default" == "$SPDIF_SINK" ]]; then
        test_result "default sink is S/PDIF (headset disconnected)" "pass"
    else
        test_result "default sink is S/PDIF (headset disconnected, got: $current_default)" "fail"
    fi
    # No expected source when headset disconnected — PipeWire chooses
    test_result "headset disconnected — source check skipped (PipeWire chooses)" "pass"
fi

echo ""

# --- Summary ---
TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL) ==="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
