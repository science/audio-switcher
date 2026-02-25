#!/usr/bin/env bash
# Convenience wrapper — runs install.sh --uninstall
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/install.sh" --uninstall
