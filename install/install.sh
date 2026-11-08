#!/usr/bin/env bash

set -e

setterm -blank 0 -powerdown 0 2>/dev/null || true
printf '\033[9;0]' 2>/dev/null || true

# --dry-run prints the plan for this machine and changes nothing. The
# --simulate-* flags pretend to be another machine (see modules/platform.sh),
# e.g. the Android app: --dry-run --simulate-aarch64 --simulate-no-systemd --simulate-android
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --simulate-aarch64) export NIKAOS_SIMULATE_ARCH=aarch64 ;;
        --simulate-no-systemd) export NIKAOS_SIMULATE_NO_SYSTEMD=1 ;;
        --simulate-android) export NIKAOS_SIMULATE_ANDROID=1 ;;
    esac
done
if [ "$DRY_RUN" = true ]; then
    source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/modules/platform.sh"
    nikaos_print_plan
    exit 0
fi

# Nikaos supports Arch Linux and its derivatives only (pacman), including
# Arch Linux ARM (aarch64).
if ! command -v pacman &>/dev/null; then
    echo "Nikaos s'installe sur Arch Linux et ses dérivées (EndeavourOS, CachyOS, Manjaro, Garuda...)."
    echo "Nikaos installs on Arch Linux and its derivatives only."
    exit 1
fi

RAW_SLUG="${REPO_SLUG:-oberflach/nikaos}"
REPO_SLUG="$(printf '%s' "$RAW_SLUG" | tr -d '\r\n\t ' | sed 's/[^a-zA-Z0-9_\/-]//g')"
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/nikaos-installer"
export REPO_SLUG
export SERPANTINUM_INSTALLER=1

if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    INSTALL_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    PROJECT_ROOT="$(dirname "$INSTALL_DIR")"
else
    INSTALL_DIR=""
    PROJECT_ROOT=""
fi

if [[ -z "$PROJECT_ROOT" || ! -f "$PROJECT_ROOT/install/modules/deps.sh" || ! -d "$PROJECT_ROOT/src" ]]; then
    if ! command -v git &>/dev/null; then
        if command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm --needed git
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y git
        elif command -v xbps-install &>/dev/null; then
            sudo xbps-install -Suy xbps || true
            sudo xbps-install -Sy git
        fi
    fi
    if [ ! -d "$CACHE_BASE/.git" ]; then
        rm -rf "$CACHE_BASE"
        mkdir -p "$CACHE_BASE"
        git clone "https://github.com/${REPO_SLUG}.git" "$CACHE_BASE"
    else
        git -C "$CACHE_BASE" remote set-url origin "https://github.com/${REPO_SLUG}.git" 2>/dev/null || true
        git -C "$CACHE_BASE" fetch origin 2>/dev/null || true
        git -C "$CACHE_BASE" reset --hard origin/HEAD 2>/dev/null || git -C "$CACHE_BASE" reset --hard origin/main 2>/dev/null || git -C "$CACHE_BASE" reset --hard origin/master 2>/dev/null || true
    fi
    # Nikaos: install the latest release (tag vX.Y.Z), not whatever is on
    # master. NIKAOS_REF picks another tag or branch, e.g. NIKAOS_REF=master.
    git -C "$CACHE_BASE" fetch --tags origin 2>/dev/null || true
    TARGET_REF="${NIKAOS_REF:-$(git -C "$CACHE_BASE" tag --list 'v*' --sort=-v:refname | head -n1)}"
    if [ -n "$TARGET_REF" ]; then
        git -C "$CACHE_BASE" checkout -q --detach "$TARGET_REF" 2>/dev/null \
            || git -C "$CACHE_BASE" checkout -q --detach "origin/$TARGET_REF" 2>/dev/null || true
    fi
    INSTALL_DIR="$CACHE_BASE/install"
    PROJECT_ROOT="$CACHE_BASE"
fi

export SERPANTINUM_DIR="$PROJECT_ROOT/src"
export I18N_DIR="$PROJECT_ROOT/src/assets/languages"

MODULES_DIR="$INSTALL_DIR/modules"

source "$PROJECT_ROOT/src/scripts/i18n.sh"
source "$MODULES_DIR/platform.sh"
source "$MODULES_DIR/pm.sh"
source "$MODULES_DIR/deps.sh"
source "$MODULES_DIR/ski.sh"
source "$MODULES_DIR/daemons.sh"
source "$MODULES_DIR/audio.sh"
source "$MODULES_DIR/gamma.sh"
source "$MODULES_DIR/core.sh"
source "$MODULES_DIR/state.sh"
source "$MODULES_DIR/migrate.sh"
source "$MODULES_DIR/deploy.sh"
source "$MODULES_DIR/version.sh"
source "$MODULES_DIR/config.sh"
source "$MODULES_DIR/service.sh"
source "$MODULES_DIR/ui.sh"

TELEMETRY_ID=$(get_telemetry_id)
ENABLE_TELEMETRY=$(get_telemetry_enabled)
OPT_SDDM=$(get_saved_preference OPT_SDDM "$OPT_SDDM")
SDDM_WAYLAND=$(get_saved_preference SDDM_WAYLAND "$SDDM_WAYLAND")
INSTALL_FULL_WALLPAPERS=$(get_saved_preference INSTALL_FULL_WALLPAPERS "$INSTALL_FULL_WALLPAPERS")

check_supported_os
bootstrap_installer_deps

INSTALL_STATE=$(detect_install_state)
OLD_VERSION=$(get_installed_version)
TARGET_VERSION=$(get_target_version "$PROJECT_ROOT" "$REPO_SLUG")
TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")
OLD_COMMIT=$(get_installed_commit)

init_compositor_detection
run_installer_ui

TARGET_VERSION=$(get_target_version "$PROJECT_ROOT" "$REPO_SLUG")
TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")

if [ "$ENABLE_TELEMETRY" = true ] && [ -f "$MODULES_DIR/telemetry.sh" ]; then
    bash "$MODULES_DIR/telemetry.sh" --mode init --version "$TARGET_VERSION" --id "$TELEMETRY_ID" --enabled "$ENABLE_TELEMETRY"
fi

if [[ "$INSTALL_STATE" == "legacy" ]]; then
    migrate_legacy "${SELECTED_COMPOSITORS[@]}"
elif [[ "$INSTALL_STATE" == "fresh" || "$IS_REINSTALL" == true ]]; then
    backup_compositors "${SELECTED_COMPOSITORS[@]}"
fi

install_dependencies "$INSTALL_STATE" "$IS_REINSTALL" "${SELECTED_COMPOSITORS[@]}"
install_ski
install_audio_daemon
install_gamma_daemon
install_core_daemon

deploy_package "$PROJECT_ROOT" "$OLD_COMMIT" "$TARGET_COMMIT" "$IS_REINSTALL" "$INSTALL_STATE" "${SELECTED_COMPOSITORS[@]}"
setup_sddm "$PROJECT_ROOT" "$INSTALL_STATE" "$IS_REINSTALL"
install_wallpapers "$INSTALL_FULL_WALLPAPERS"

WALLPAPER_DIR=$(get_wallpaper_dir)
init_serpantinum_config "$PROJECT_ROOT" "$WALLPAPER_DIR" "$INSTALL_STATE" "$IS_REINSTALL"
configure_ski_defaults
apply_android_profile

setup_services
hand_over_from_easyeffects
write_version_state "$TARGET_VERSION" "$TARGET_COMMIT" "$TELEMETRY_ID" "$ENABLE_TELEMETRY" "${SELECTED_COMPOSITORS[*]}" "$OPT_SDDM" "$SDDM_WAYLAND" "$INSTALL_FULL_WALLPAPERS"

if [[ "$INSTALL_STATE" == "legacy" || "$INSTALL_STATE" == "fresh" || "$IS_REINSTALL" == true ]]; then
    rm -f "$HOME/.local/state/serpantinum/first_launch.done" "$HOME/.local/state/quickshell/first_launch.done"
fi

if [ -f "$MODULES_DIR/telemetry.sh" ]; then
    bash "$MODULES_DIR/telemetry.sh" --mode done --version "$TARGET_VERSION" --old-version "$OLD_VERSION" --install-state "$INSTALL_STATE" --compositor "${SELECTED_COMPOSITORS[*]}" --id "$TELEMETRY_ID" --enabled "$ENABLE_TELEMETRY" --failed "${FAILED_PKGS[*]}"
fi

draw_completion_screen "$TARGET_VERSION" "$TARGET_COMMIT"
