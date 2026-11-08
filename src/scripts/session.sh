#!/usr/bin/env bash
# `nikaos session`: starts a compositor with Nikaos in it, for setups without
# a display manager, such as the Nikaos Linux Android app (Arch Linux ARM in
# proot), which calls this command.
#
# Order: $NIKAOS_SESSION if set, then sway, mango, hyprland, niri (the first one
# installed). Sway comes first because Hyprland does not start in the app yet.
# Without a session D-Bus (no systemd/logind), the compositor runs inside
# dbus-run-session: serpantinum-core, notifications, MPRIS and the tray need it.
set -u

pick_compositor() {
    local c
    for c in ${NIKAOS_SESSION:-} sway mango hyprland niri; do
        case "$c" in
            hyprland) command -v start-hyprland >/dev/null 2>&1 && { echo start-hyprland; return; }
                      command -v Hyprland >/dev/null 2>&1 && { echo Hyprland; return; } ;;
            *) command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; } ;;
        esac
    done
    return 1
}

comp="$(pick_compositor)" || {
    echo "nikaos session: no supported compositor found (install sway)." >&2
    exit 1
}

export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-$comp}"
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-$comp}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"

# Nikaos Linux (Android app): the compositor runs nested in the app's own
# Wayland compositor, which is not a DRM device, so wlroots only gets an
# allocator with the pixman (software) renderer. Same settings as the app's
# droiddeck-desktop; NIKAOS_WLR_RENDERER overrides the renderer.
if [ -n "${DROIDDECK:-}" ] || [ "${NIKAOS_ANDROID:-}" = 1 ] || [ -x /usr/local/bin/droiddeck-desktop ]; then
    export NIKAOS_ANDROID=1
    export WLR_BACKENDS="${WLR_BACKENDS:-wayland}"
    export WLR_RENDERER="${NIKAOS_WLR_RENDERER:-${WLR_RENDERER:-pixman}}"
    export WLR_NO_HARDWARE_CURSORS=1
    unset KDE_FULL_SESSION KDE_SESSION_VERSION KDE_APPLICATIONS_AS_SCOPE KWIN_COMPOSE
fi

cmd=("$comp")

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- "${cmd[@]}" "$@"
fi
exec "${cmd[@]}" "$@"
