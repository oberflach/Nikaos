#!/usr/bin/env bash
# One-line installer for Nikaos:
#   curl -fsSL https://raw.githubusercontent.com/oberflach/nikaos/master/install/get.sh | bash
# Downloads the installer of the latest release and runs it. NIKAOS_REF picks
# another tag or branch (e.g. NIKAOS_REF=master to test unreleased code).
set -e

main() {
    local slug="${REPO_SLUG:-oberflach/nikaos}"
    local ref="${NIKAOS_REF:-}"
    local latest_ref
    local dir

    if ! command -v pacman >/dev/null 2>&1; then
        echo "Nikaos s'installe sur Arch Linux et ses dérivées (EndeavourOS, CachyOS, Manjaro, Garuda...)."
        echo "Nikaos installs on Arch Linux and its derivatives only."
        exit 1
    fi

    latest_ref="$(curl -fsSL "https://api.github.com/repos/${slug}/releases/latest" 2>/dev/null \
            | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
    latest_ref="${latest_ref:-master}"

    if [ -z "$ref" ]; then
        choose_install_ref "$latest_ref"
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

choose_install_ref() {
    local latest_ref="$1"
    local input_fd=0
    local choice custom_ref

    # A one-line installation is often piped into bash, so read choices from
    # the terminal when it is available. Non-interactive runs keep the default.
    if [ ! -t 0 ]; then
        if { exec 3</dev/tty; } 2>/dev/null; then
            input_fd=3
        else
            ref="$latest_ref"
            return
        fi
    fi

    printf '\nVersion à installer :\n'
    printf '  1) Dernière version stable (%s) — recommandée, choix par défaut\n' "$latest_ref"
    printf '  2) Version de développement (master) — pour tester les nouveautés\n'
    printf '  3) Entrer une version ou une branche — option avancée\n'
    printf 'Choix [1] : '
    read -r choice <&"$input_fd" || choice=""

    case "${choice:-1}" in
        1)
            ref="$latest_ref"
            ;;
        2)
            ref="master"
            ;;
        3)
            printf 'Version ou branche (ex. v2.6.1) : '
            read -r custom_ref <&"$input_fd" || custom_ref=""
            if [[ "$custom_ref" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
                ref="$custom_ref"
            else
                echo "Version invalide. La dernière release sera installée."
                ref="$latest_ref"
            fi
            ;;
        *)
            echo "Choix invalide. La dernière release sera installée."
            ref="$latest_ref"
            ;;
    esac

    [ "$input_fd" = 3 ] && exec 3<&-
}

main "$@"
