#!/usr/bin/env bash
# One-click setups behind Settings > General > Hardware, so nobody has to edit
# config files by hand.
#   integrations.sh status <kitty|vesktop|conservation>  -> ok | missing | unavailable
#   integrations.sh setup  <kitty|vesktop|conservation>  -> ok | failed
#
# kitty:        lets the Super+G card change a Kitty window's background opacity.
# vesktop:      adds the Quick CSS the Super+G card drives for Vesktop.
# conservation: installs a udev rule so the battery conservation switch can be
#               written without root (asks for the password through polkit).

set -u

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
HERE="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
KITTY_CONF="$CONFIG_HOME/kitty/kitty.conf"
VESKTOP_CSS="$CONFIG_HOME/vesktop/settings/quickCss.css"
UDEV_RULE="/etc/udev/rules.d/99-nikaos-conservation.rules"

conservation_file() {
    local f
    for f in /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode; do
        [ -e "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}

kitty_line() {
    # Sets "key value" in kitty.conf, replacing an existing setting.
    local key="$1" value="$2"
    if grep -qE "^[[:space:]]*$key[[:space:]]" "$KITTY_CONF"; then
        sed -i -E "s|^[[:space:]]*$key[[:space:]].*|$key $value|" "$KITTY_CONF"
    else
        printf '%s %s\n' "$key" "$value" >> "$KITTY_CONF"
    fi
}

status() {
    case "$1" in
        kitty)
            command -v kitty >/dev/null 2>&1 || { echo unavailable; return; }
            if grep -qE '^[[:space:]]*listen_on[[:space:]]+unix:/tmp/kitty-serpantinum' "$KITTY_CONF" 2>/dev/null \
                && grep -qE '^[[:space:]]*allow_remote_control[[:space:]]+(yes|socket-only)' "$KITTY_CONF" 2>/dev/null \
                && grep -qE '^[[:space:]]*dynamic_background_opacity[[:space:]]+yes' "$KITTY_CONF" 2>/dev/null; then
                echo ok
            else
                echo missing
            fi
            ;;
        vesktop)
            [ -d "$CONFIG_HOME/vesktop" ] || { echo unavailable; return; }
            grep -q -- '--serpantinum-surface-alpha:' "$VESKTOP_CSS" 2>/dev/null && echo ok || echo missing
            ;;
        conservation)
            local f
            f="$(conservation_file)" || { echo unavailable; return; }
            [ -w "$f" ] && echo ok || echo missing
            ;;
        *) echo unavailable ;;
    esac
}

setup() {
    case "$1" in
        kitty)
            mkdir -p "$(dirname "$KITTY_CONF")" && touch "$KITTY_CONF" || { echo failed; return; }
            [ -f "$KITTY_CONF.nikaos.bak" ] || cp -p "$KITTY_CONF" "$KITTY_CONF.nikaos.bak"
            kitty_line allow_remote_control yes
            kitty_line listen_on unix:/tmp/kitty-serpantinum
            kitty_line dynamic_background_opacity yes
            echo ok
            ;;
        vesktop)
            mkdir -p "$(dirname "$VESKTOP_CSS")" || { echo failed; return; }
            if [ -s "$VESKTOP_CSS" ] && ! grep -q -- '--serpantinum-surface-alpha:' "$VESKTOP_CSS"; then
                cp -p "$VESKTOP_CSS" "$VESKTOP_CSS.nikaos.bak"
                # Keep the user's own CSS below ours.
                { cat "$HERE/integrations/vesktop-transparency.css"; echo; cat "$VESKTOP_CSS.nikaos.bak"; } > "$VESKTOP_CSS"
            elif [ ! -s "$VESKTOP_CSS" ]; then
                cp "$HERE/integrations/vesktop-transparency.css" "$VESKTOP_CSS"
            fi
            echo ok
            ;;
        conservation)
            conservation_file >/dev/null || { echo failed; return; }
            local rule='ACTION=="add", SUBSYSTEM=="platform", DRIVER=="ideapad_acpi", RUN+="/bin/chmod a+w /sys%p/conservation_mode"'
            if pkexec sh -c 'printf "%s\n" "$1" > "$2" && chmod a+w /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode' \
                    sh "$rule" "$UDEV_RULE"; then
                echo ok
            else
                echo failed
            fi
            ;;
        *) echo failed ;;
    esac
}

case "${1:-}" in
    status) status "${2:-}" ;;
    setup) setup "${2:-}" ;;
    *) echo "usage: $0 status|setup kitty|vesktop|conservation" >&2; exit 2 ;;
esac
