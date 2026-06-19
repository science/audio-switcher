#!/bin/bash
# Diagnostic: monitor Jabra Link 390 hidraw for vendor/telephony HID reports
#
# The Jabra Link 390 dongle handles the Bluetooth link to the earbuds
# internally — PipeWire/ALSA never see bud connect/disconnect. The dongle's
# HID interface exposes a USB Telephony page (0x0B) plus a Jabra vendor page
# (0xFF00, report IDs 4/5). One of these reports should change when the buds
# link/unlink. This tool dumps every HID report so we can find that flag.
#
# Run: sudo ./diag-jabra.sh
# Then power the earbuds on/off (or in/out of the case) and watch the reports.
# Diff a "connected" report against a "disconnected" one to find the link byte.

set -euo pipefail

JABRA_VID="0b0e"   # GN Netcom / Jabra

# Find the Jabra hidraw device by USB vendor ID
HIDRAW=""
for h in /dev/hidraw*; do
    [[ -e "$h" ]] || continue
    sysdev="/sys/class/hidraw/$(basename "$h")/device"
    [[ -d "$sysdev" ]] || continue
    vid=$(cat "$sysdev/../../idVendor" 2>/dev/null || true)
    if [[ "$vid" == "$JABRA_VID" ]]; then
        HIDRAW="$h"
        break
    fi
done

if [[ -z "$HIDRAW" ]]; then
    echo "ERROR: No Jabra (vid $JABRA_VID) hidraw device found. Is the dongle plugged in?"
    exit 1
fi

echo "Jabra HID raw device: $HIDRAW"
echo "Monitoring for HID input reports..."
echo "Power earbuds on/off (or in/out of case). Ctrl+C to stop."
echo ""

python3 -u -c "
import os, select, time

fd = os.open('$HIDRAW', os.O_RDONLY)
print('Waiting for HID reports... (toggle the buds now)')
print()
try:
    while True:
        r, _, _ = select.select([fd], [], [], 1.0)
        if r:
            data = os.read(fd, 256)
            if not data:
                break
            ts = time.strftime('%H:%M:%S')
            report_id = data[0]
            # Print full report as space-separated hex with byte indices for diffing
            hexbytes = ' '.join(f'{b:02x}' for b in data)
            print(f'[{ts}] ID={report_id} len={len(data)}  {hexbytes}', flush=True)
except KeyboardInterrupt:
    print('Stopped.')
finally:
    os.close(fd)
"
