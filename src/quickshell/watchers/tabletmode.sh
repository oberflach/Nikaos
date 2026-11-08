#!/usr/bin/env bash

# Watches the convertible's tablet-mode hinge switch (SW_TABLET_MODE) and
# prints "tabletmode 0" / "tabletmode 1" once at startup (current state)
# and again on every change. The event device path isn't guaranteed
# stable across reboots, so it's found by name each run instead of being
# hardcoded.

ACTION="${1:-watch}"

watch_tabletmode() {
    exec python3 -u -c '
import fcntl, glob, os, re, select, struct, sys

is_64bit = struct.calcsize("P") == 8
event_fmt = "qqHHi" if is_64bit else "iiHHi"
event_size = struct.calcsize(event_fmt)

EV_SW = 0x05
SW_TABLET_MODE = 0x01
EVIOCGSW_1 = 0x8001451B  # EVIOCGSW(1): read 1 byte of current switch state

def find_device():
    try:
        with open("/proc/bus/input/devices", "r") as f:
            blocks = f.read().split("\n\n")
    except Exception:
        return None
    # The kernel-native lenovo_ymc switch exists on this model but its
    # notify event never fires (a known upstream bug), so prefer the
    # yoga-usage-mode driver'"'"'s device ("Yoga tablet switch input"),
    # falling back to any other "tablet"-named switch if that one is
    # missing.
    candidates = []
    for block in blocks:
        if "tablet" not in block.lower():
            continue
        m = re.search(r"Handlers=.*?(event\d+)", block)
        if not m:
            continue
        name_m = re.search(r"Name=\"(.*?)\"", block)
        name = name_m.group(1) if name_m else ""
        candidates.append((name, "/dev/input/" + m.group(1)))
    for name, path in candidates:
        if "yoga tablet switch" in name.lower():
            return path
    return candidates[0][1] if candidates else None

path = find_device()
if not path:
    sys.exit(1)

try:
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
except Exception:
    sys.exit(1)

last = 0
try:
    buf = bytearray(1)
    fcntl.ioctl(fd, EVIOCGSW_1, buf, True)
    last = (buf[0] >> SW_TABLET_MODE) & 1
except Exception:
    pass

sys.stdout.write(f"tabletmode {last}\n")
sys.stdout.flush()

while True:
    try:
        select.select([fd], [], [])
        while True:
            try:
                data = os.read(fd, event_size)
                if not data or len(data) < event_size:
                    break
                _, _, ev_type, ev_code, ev_val = struct.unpack(event_fmt, data)
                if ev_type == EV_SW and ev_code == SW_TABLET_MODE:
                    val = 1 if ev_val else 0
                    if val != last:
                        last = val
                        sys.stdout.write(f"tabletmode {val}\n")
                        sys.stdout.flush()
            except (BlockingIOError, InterruptedError):
                break
            except Exception:
                break
    except Exception:
        break
'
}

case "$ACTION" in
    watch)
        watch_tabletmode
        ;;
    *)
        watch_tabletmode
        ;;
esac
