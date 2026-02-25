#!/bin/bash
# Audio Switcher test suite
# Run: ./tests/test-audio-switcher.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DAEMON="$PROJECT_DIR/audio-switcher"
INSTALL_SCRIPT="$PROJECT_DIR/install.sh"

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

# BTD-800 sink constant
if grep -q 'alsa_output.usb-1395_Sennheiser_BTD_800_USB-00.analog-stereo' "$DAEMON" 2>/dev/null; then
    test_result "BTD-800 sink constant present" "pass"
else
    test_result "BTD-800 sink constant present" "fail"
fi

# BTD-800 source constant
if grep -q 'alsa_input.usb-1395_Sennheiser_BTD_800_USB-00.mono-fallback' "$DAEMON" 2>/dev/null; then
    test_result "BTD-800 source constant present" "pass"
else
    test_result "BTD-800 source constant present" "fail"
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

# Has subscribe_loop function
if grep -q 'subscribe_loop()' "$DAEMON" 2>/dev/null; then
    test_result "subscribe_loop() function defined" "pass"
else
    test_result "subscribe_loop() function defined" "fail"
fi

# Has signal handling (trap)
if grep -q 'trap' "$DAEMON" 2>/dev/null; then
    test_result "signal handling (trap) present" "pass"
else
    test_result "signal handling (trap) present" "fail"
fi

# Uses pactl subscribe
if grep -q 'pactl subscribe' "$DAEMON" 2>/dev/null; then
    test_result "uses pactl subscribe for event monitoring" "pass"
else
    test_result "uses pactl subscribe for event monitoring" "fail"
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

# Check default sink matches BTD-800 presence
BTD_SINK="alsa_output.usb-1395_Sennheiser_BTD_800_USB-00.analog-stereo"
SPDIF_SINK="alsa_output.pci-0000_00_1f.3.iec958-stereo"

btd_present=false
if pactl list sinks short 2>/dev/null | grep -q "$BTD_SINK"; then
    btd_present=true
fi

current_default=$(pactl get-default-sink 2>/dev/null || true)

if [[ "$btd_present" == "true" ]]; then
    if [[ "$current_default" == "$BTD_SINK" ]]; then
        test_result "default sink is BTD-800 (headset present)" "pass"
    else
        test_result "default sink is BTD-800 (headset present, got: $current_default)" "fail"
    fi
else
    if [[ "$current_default" == "$SPDIF_SINK" ]]; then
        test_result "default sink is S/PDIF (headset absent)" "pass"
    else
        test_result "default sink is S/PDIF (headset absent, got: $current_default)" "fail"
    fi
fi

# Check default source matches BTD-800 presence (when BTD-800 present)
BTD_SOURCE="alsa_input.usb-1395_Sennheiser_BTD_800_USB-00.mono-fallback"

btd_source_present=false
if pactl list sources short 2>/dev/null | grep -q "$BTD_SOURCE"; then
    btd_source_present=true
fi

current_default_source=$(pactl get-default-source 2>/dev/null || true)

if [[ "$btd_source_present" == "true" ]]; then
    if [[ "$current_default_source" == "$BTD_SOURCE" ]]; then
        test_result "default source is BTD-800 mic (present)" "pass"
    else
        test_result "default source is BTD-800 mic (present, got: $current_default_source)" "fail"
    fi
else
    test_result "BTD-800 source not present — skipping source check" "pass"
fi

echo ""

# --- Summary ---
TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL) ==="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
