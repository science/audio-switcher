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

usage() {
    echo "Usage: $0 [--uninstall]"
    echo ""
    echo "  Install:    $0"
    echo "  Uninstall:  $0 --uninstall"
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
