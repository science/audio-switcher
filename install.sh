#!/usr/bin/env bash
set -euo pipefail

INSTALL_BIN="$HOME/.local/bin/audio-switcher"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/audio-switcher.service"
UDEV_RULE="/etc/udev/rules.d/70-btd800.rules"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 [--uninstall]"
    echo ""
    echo "  Install:    $0"
    echo "  Uninstall:  $0 --uninstall"
}

do_install() {
    echo "Installing audio-switcher..."

    # Install udev rule for hidraw access (needs sudo)
    if [[ ! -f "$UDEV_RULE" ]]; then
        echo "  Installing udev rule for BTD-800 hidraw access (requires sudo)..."
        sudo cp "$SCRIPT_DIR/70-btd800.rules" "$UDEV_RULE"
        sudo udevadm control --reload-rules
        sudo udevadm trigger
        echo "  Installed $UDEV_RULE"
    else
        echo "  udev rule already installed"
    fi

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

    if [[ -f "$UDEV_RULE" ]]; then
        echo "  Removing udev rule (requires sudo)..."
        sudo rm "$UDEV_RULE"
        sudo udevadm control --reload-rules
        echo "  Removed $UDEV_RULE"
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
