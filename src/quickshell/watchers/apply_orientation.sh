#!/usr/bin/env bash
# Applies a Hyprland monitor transform (0/1/2/3 = normal/90/180/270) to the
# built-in laptop panel, and the matching transform to the touchscreen
# digitizer so touch input follows the rotated image -- used to auto-rotate
# in tablet mode. This config uses Hyprland's Lua parser, which doesn't
# support `hyprctl keyword` -- `hyprctl eval` calling the same hl.monitor()/
# hl.device() used in the static config is the dynamic equivalent. Current
# mode/position/scale are read back from hyprctl so this doesn't drift from
# monitors.lua's values.
transform="$1"

python3 - "$transform" <<'EOF'
import json
import subprocess
import sys

transform = sys.argv[1]

mons = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"]))
mon = next((m for m in mons if m["name"].startswith("eDP")), mons[0] if mons else None)
if mon:
    lua = (
        "hl.monitor({{output = \"{name}\", mode = \"{w}x{h}@{rate}\", "
        "position = \"{x}x{y}\", scale = {scale}, transform = {transform}}})"
    ).format(
        name=mon["name"],
        w=mon["width"],
        h=mon["height"],
        rate=round(mon["refreshRate"]),
        x=mon["x"],
        y=mon["y"],
        scale=mon["scale"],
        transform=transform,
    )
    subprocess.run(["hyprctl", "eval", lua], check=False)

devices = json.loads(subprocess.check_output(["hyprctl", "devices", "-j"]))
for touch in devices.get("touch", []):
    lua = "hl.device({{name = \"{name}\", transform = {transform}}})".format(
        name=touch["name"], transform=transform
    )
    subprocess.run(["hyprctl", "eval", lua], check=False)
EOF
