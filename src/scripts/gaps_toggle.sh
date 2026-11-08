#!/usr/bin/env bash
# Borderless mode: drop Hyprland gaps to 0 and bring the previous values
# back on the next call. The gaps live in the Hyprland config itself, so
# the current mode survives a reboot; the saved values sit in the state dir.
CONF="$HOME/.config/hypr/config/settings.lua"
SAVED="${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum/gaps_saved"

# Write the file for the next session and push the values live. No
# `hyprctl reload`: that would drop the per-window opacity rules set from
# the Super+G transparency card.
set_gaps() {
    sed -i -E "s/^(\s*gaps_in\s*=\s*)[0-9]+/\1$1/; s/^(\s*gaps_out\s*=\s*)[0-9]+/\1$2/" "$CONF"
    hyprctl eval "hl.config({ general = { gaps_in = $1, gaps_out = $2 } })" >/dev/null
}

cur_in=$(grep -oP '^\s*gaps_in\s*=\s*\K[0-9]+' "$CONF")
cur_out=$(grep -oP '^\s*gaps_out\s*=\s*\K[0-9]+' "$CONF")

if [ -f "$SAVED" ]; then
    read -r in out < "$SAVED"
    set_gaps "${in:-5}" "${out:-20}"
    rm -f "$SAVED"
elif [ "$cur_in" = "0" ] && [ "$cur_out" = "0" ]; then
    # Already at 0 with nothing saved: fall back to Hyprland's defaults.
    set_gaps 5 20
else
    mkdir -p "$(dirname "$SAVED")"
    echo "$cur_in $cur_out" > "$SAVED"
    set_gaps 0 0
fi
