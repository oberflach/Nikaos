#!/usr/bin/env bash
# One-line installer for Nikaos:
#   curl -fsSL https://raw.githubusercontent.com/oberflach/nikaos/master/install/get.sh | bash
# Downloads the installer of the latest release and runs it. NIKAOS_REF picks
# another tag or branch (e.g. NIKAOS_REF=master to test unreleased code).
set -e

main() {
    local slug="${REPO_SLUG:-oberflach/nikaos}"
    local ref="${NIKAOS_REF:-}"
    local dir

    if ! command -v pacman >/dev/null 2>&1; then
        echo "Nikaos s'installe sur Arch Linux et ses dérivées (EndeavourOS, CachyOS, Manjaro, Garuda...)."
        echo "Nikaos installs on Arch Linux and its derivatives only."
        exit 1
    fi

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
    elif [ -r /dev/tty ]; then
        # A tty can be present but unavailable (for example from a service).
        # Open it first so we can still run non-interactively in that case.
        if { exec 3</dev/tty; } 2>/dev/null; then
            bash "$dir/install.sh" "$@" <&3
            exec 3<&-
        else
            bash "$dir/install.sh" "$@"
        fi
    else
        bash "$dir/install.sh" "$@"
    fi
}

main "$@"
