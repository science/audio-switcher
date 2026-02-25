#!/bin/bash
# Diagnostic: monitor BTD-800 hidraw for telephony HID reports
#
# The BTD-800 HID descriptor contains a Telephony/Headset report (ID 3)
# with Hook Switch usage — likely the headset BT connection state.
# PipeWire/ALSA/evdev don't expose this, but hidraw should.
#
# Run: sudo ./diag-btd800.sh
# Then power on/off the headset and watch for reports.

set -euo pipefail

HIDRAW="/dev/hidraw1"

# Verify it's the BTD-800
if ! udevadm info -a "$HIDRAW" 2>/dev/null | grep -q "Sennheiser"; then
    echo "ERROR: $HIDRAW doesn't appear to be the BTD-800"
    echo "Checking all hidraw devices..."
    for h in /dev/hidraw*; do
        if udevadm info -a "$h" 2>/dev/null | grep -q "Sennheiser"; then
            echo "  Found BTD-800 at $h"
            HIDRAW="$h"
            break
        fi
    done
fi

echo "BTD-800 HID raw device: $HIDRAW"
echo "Monitoring for HID input reports..."
echo "Power on/off the headset. Ctrl+C to stop."
echo ""

python3 -c "
import os, select, struct, time

fd = os.open('$HIDRAW', os.O_RDONLY)

# Report ID 3 = Telephony/Headset (from HID descriptor analysis):
#   Bit 0: Hook Switch (off-hook = connected?)
#   Bits 1-4: Flash, Redial, Phone Mute, Drop (relative)
#   Other bits: Ring Enable, etc.
TELEPHONY_REPORT_ID = 3

print('Waiting for HID reports...')
print('(If no output appears after toggling headset, hidraw is also a dead end)')
print()

try:
    while True:
        r, _, _ = select.select([fd], [], [], 1.0)
        if r:
            data = os.read(fd, 256)
            ts = time.strftime('%H:%M:%S')
            report_id = data[0]
            payload = data[1:]
            print(f'[{ts}] Report ID={report_id} len={len(data)} hex={data.hex()}')

            if report_id == TELEPHONY_REPORT_ID:
                # Parse telephony bits
                if len(payload) >= 1:
                    hook_switch = payload[0] & 0x01
                    phone_mute = (payload[0] >> 3) & 0x01
                    print(f'  -> TELEPHONY: hook_switch={hook_switch} phone_mute={phone_mute}')
                    if hook_switch:
                        print(f'  -> Headset appears CONNECTED (off-hook)')
                    else:
                        print(f'  -> Headset appears DISCONNECTED (on-hook)')
            elif report_id == 1:
                print(f'  -> Vendor report (proprietary data)')
            elif report_id == 2:
                # Consumer Control report (from HID descriptor)
                print(f'  -> Consumer Control report')
            else:
                print(f'  -> Unknown report type')
            print()
except KeyboardInterrupt:
    print('Stopped.')
finally:
    os.close(fd)
"
