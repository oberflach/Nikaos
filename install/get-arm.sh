#!/usr/bin/env bash
# One-line installer for Nikaos on ARM (aarch64), e.g. Nikaos Linux, the
# Android app running Arch Linux ARM under proot:
#   curl -fsSL https://github.com/oberflach/Nikaos/releases/latest/download/get-arm.sh | bash
# Installs the latest release; NIKAOS_REF picks another tag or branch. The PC
# (x86_64) installer is get.sh.
set -e

main() {
    local slug="${REPO_SLUG:-oberflach/nikaos}"
    local ref="${NIKAOS_REF:-}"
    local arch dir

    if ! command -v pacman >/dev/null 2>&1; then
        echo "Nikaos s'installe sur Arch Linux ARM (pacman)."
        echo "Nikaos installs on Arch Linux ARM only (pacman)."
        exit 1
    fi

    arch="$(uname -m)"
    if [ "$arch" != "aarch64" ]; then
        echo "Cet installateur est pour ARM (aarch64), cette machine est en $arch."
        echo "Sur PC, utilisez : curl -fsSL https://github.com/oberflach/Nikaos/releases/latest/download/get.sh | bash"
        exit 1
    fi

    if [ -n "${DROIDDECK:-}" ] || [ "${NIKAOS_ANDROID:-}" = 1 ] || [ -x /usr/local/bin/droiddeck-desktop ]; then
        echo "Nikaos Linux détecté : installation avec Sway et le profil léger."
    fi
    echo "La première installation compile serpantinum-core (et Quickshell si besoin) : comptez plusieurs minutes."

    if [ -z "$ref" ]; then
        ref="$(curl -fsSL "https://api.github.com/repos/${slug}/releases/latest" 2>/dev/null \
            | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
        ref="${ref:-master}"
    fi
    export NIKAOS_REF="$ref"
    echo "Nikaos: installation de ${ref}..."

    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' EXIT
    curl -fsSL "https://raw.githubusercontent.com/${slug}/${ref}/install/install.sh" -o "$dir/install.sh"
    if [ -t 0 ]; then
        bash "$dir/install.sh" "$@"
    elif { exec 3</dev/tty; } 2>/dev/null; then
        bash "$dir/install.sh" "$@" <&3
        exec 3<&-
    else
        bash "$dir/install.sh" "$@"
    fi

    echo
    echo "Pour démarrer Nikaos : nikaos session"
}

main "$@"
