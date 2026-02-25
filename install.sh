#!/usr/bin/env bash
set -euo pipefail

INSTALL_BIN="$HOME/.local/bin/audio-switcher"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/audio-switcher.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 [--uninstall]"
    echo ""
    echo "  Install:    $0"
    echo "  Uninstall:  $0 --uninstall"
}

do_install() {
    echo "Installing audio-switcher..."

    # Install binary
    mkdir -p "$(dirname "$INSTALL_BIN")"
    cp "$SCRIPT_DIR/audio-switcher" "$INSTALL_BIN"
    chmod 755 "$INSTALL_BIN"
    echo "  Installed $INSTALL_BIN"

    # Install systemd user service
    mkdir -p "$SERVICE_DIR"
    cat > "$SERVICE_FILE" <<UNIT
[Unit]
Description=Audio switcher: PipeWire auto-routing daemon
After=pipewire-pulse.service
Requires=pipewire-pulse.service

[Service]
Type=simple
ExecStart=$INSTALL_BIN
Restart=on-failure
RestartSec=3

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
