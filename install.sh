#!/usr/bin/env bash
set -euo pipefail

INSTALL_BIN="$HOME/.local/bin/audio-switcher"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/audio-switcher.service"
UDEV_RULE="/etc/udev/rules.d/70-btd800.rules"
JABRA_UDEV_RULE="/etc/udev/rules.d/70-jabra.rules"
WP_CONF_DIR="$HOME/.config/wireplumber/main.lua.d"
WP_CONF_FILE="$WP_CONF_DIR/51-alsa-tuning.lua"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# DeepFilterNet LADSPA plugin: the Jabra typing filter. Pinned release + hash;
# the daemon falls back to the raw Jabra mic if it is missing.
DFN_URL="https://github.com/Rikorose/DeepFilterNet/releases/download/v0.5.6/libdeep_filter_ladspa-0.5.6-x86_64-unknown-linux-gnu.so"
DFN_SHA256="2ca3205c2911d389604a826a240e745597d50252b5cab81c8248252b335e2236"
DFN_PLUGIN="$HOME/.local/lib/audio-switcher/libdeep_filter_ladspa.so"

usage() {
    echo "Usage: $0 [--uninstall]"
    echo ""
    echo "  Install:    $0"
    echo "  Uninstall:  $0 --uninstall"
}

install_dfn_plugin() {
    if [[ -f "$DFN_PLUGIN" ]] && echo "$DFN_SHA256  $DFN_PLUGIN" | sha256sum -c --status; then
        echo "  DeepFilterNet plugin already installed"
        return
    fi
    local tmp
    tmp=$(mktemp)
    if ! curl -fsSL -o "$tmp" "$DFN_URL"; then
        echo "  WARNING: could not download the DeepFilterNet plugin; Jabra typing filter disabled"
        rm -f "$tmp"
        return
    fi
    if ! echo "$DFN_SHA256  $tmp" | sha256sum -c --status; then
        echo "  WARNING: DeepFilterNet plugin checksum mismatch; not installed (Jabra typing filter disabled)"
        rm -f "$tmp"
        return
    fi
    mkdir -p "$(dirname "$DFN_PLUGIN")"
    install -m 0644 "$tmp" "$DFN_PLUGIN"
    rm -f "$tmp"
    echo "  Installed $DFN_PLUGIN (DeepFilterNet 0.5.6, Jabra typing filter)"
}

do_install() {
    echo "Installing audio-switcher..."

    # Install udev rules for hidraw access (needs sudo)
    local reload_udev=false
    if [[ ! -f "$UDEV_RULE" ]]; then
        echo "  Installing udev rule for BTD-800 hidraw access (requires sudo)..."
        sudo cp "$SCRIPT_DIR/70-btd800.rules" "$UDEV_RULE"
        echo "  Installed $UDEV_RULE"
        reload_udev=true
    else
        echo "  BTD-800 udev rule already installed"
    fi
    if [[ ! -f "$JABRA_UDEV_RULE" ]]; then
        echo "  Installing udev rule for Jabra Link 390 hidraw access (requires sudo)..."
        sudo cp "$SCRIPT_DIR/70-jabra.rules" "$JABRA_UDEV_RULE"
        echo "  Installed $JABRA_UDEV_RULE"
        reload_udev=true
    else
        echo "  Jabra udev rule already installed"
    fi
    if [[ "$reload_udev" == true ]]; then
        sudo udevadm control --reload-rules
        sudo udevadm trigger
    fi

    # Install WirePlumber ALSA buffer tuning
    mkdir -p "$WP_CONF_DIR"
    cp "$SCRIPT_DIR/51-alsa-tuning.lua" "$WP_CONF_FILE"
    echo "  Installed $WP_CONF_FILE"

    install_dfn_plugin

    # Install binary (symlink so dev repo changes apply immediately)
    mkdir -p "$(dirname "$INSTALL_BIN")"
    ln -sf "$SCRIPT_DIR/audio-switcher" "$INSTALL_BIN"
    echo "  Installed $INSTALL_BIN → $SCRIPT_DIR/audio-switcher"

    # Install systemd user service
    mkdir -p "$SERVICE_DIR"
    cat > "$SERVICE_FILE" <<UNIT
[Unit]
Description=Audio switcher + PipeWire recovery daemon
After=pipewire-pulse.service

[Service]
Type=simple
ExecStart=$INSTALL_BIN
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
    echo "  Installed $SERVICE_FILE"

    systemctl --user daemon-reload
    systemctl --user enable audio-switcher.service
    systemctl --user start audio-switcher.service
    echo "  Service enabled and started"

    echo ""
    echo "Done."
    echo "  Status:  systemctl --user status audio-switcher"
    echo "  Logs:    journalctl --user-unit audio-switcher -f"
}

do_uninstall() {
    echo "Uninstalling audio-switcher..."

    if systemctl --user is-active --quiet audio-switcher.service 2>/dev/null; then
        systemctl --user stop audio-switcher.service
        echo "  Stopped service"
    fi

    if systemctl --user is-enabled --quiet audio-switcher.service 2>/dev/null; then
        systemctl --user disable audio-switcher.service
        echo "  Disabled service"
    fi

    if [[ -f "$SERVICE_FILE" ]]; then
        rm "$SERVICE_FILE"
        systemctl --user daemon-reload
        echo "  Removed $SERVICE_FILE"
    fi

    if [[ -f "$INSTALL_BIN" ]]; then
        rm "$INSTALL_BIN"
        echo "  Removed $INSTALL_BIN"
    fi

    if [[ -f "$WP_CONF_FILE" ]]; then
        rm "$WP_CONF_FILE"
        echo "  Removed $WP_CONF_FILE"
    fi

    # The daemon leaves the typing filter loaded on exit (apps keep their mic).
    local dfn_module
    dfn_module=$(pactl list modules short 2>/dev/null \
        | awk '$2 == "module-ladspa-source" && index($0, "source_name=jabra_clean_mic") {print $1; exit}' || true)
    if [[ -n "$dfn_module" ]]; then
        pactl unload-module "$dfn_module" 2>/dev/null || true
        echo "  Unloaded Jabra typing filter"
    fi
    if [[ -f "$DFN_PLUGIN" ]]; then
        rm "$DFN_PLUGIN"
        rmdir "$(dirname "$DFN_PLUGIN")" 2>/dev/null || true
        echo "  Removed $DFN_PLUGIN"
    fi

    local removed_udev=false
    if [[ -f "$UDEV_RULE" ]]; then
        echo "  Removing BTD-800 udev rule (requires sudo)..."
        sudo rm "$UDEV_RULE"
        echo "  Removed $UDEV_RULE"
        removed_udev=true
    fi
    if [[ -f "$JABRA_UDEV_RULE" ]]; then
        echo "  Removing Jabra udev rule (requires sudo)..."
        sudo rm "$JABRA_UDEV_RULE"
        echo "  Removed $JABRA_UDEV_RULE"
        removed_udev=true
    fi
    if [[ "$removed_udev" == true ]]; then
        sudo udevadm control --reload-rules
    fi

    echo ""
    echo "Done."
}

case "${1:-}" in
    --uninstall)
        do_uninstall
        ;;
    --help|-h)
        usage
        ;;
    "")
        do_install
        ;;
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
esac
