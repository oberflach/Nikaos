#!/usr/bin/env bash
# Tests the platform choices of the installer without installing anything:
# the --dry-run plan, with and without the simulated Nikaos Linux environment
# (aarch64, no systemd, Android), and the helpers behind it.
#   bash install/tests/platform_test.sh

set -u

REPO_ROOT="$(dirname "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")")"
INSTALLER="$REPO_ROOT/install/install.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

failures=0
check() {
    if eval "$2"; then
        echo "ok   - $1"
    else
        echo "FAIL - $1"
        failures=$((failures + 1))
    fi
}

# Never inherit the real environment's markers.
unset DROIDDECK NIKAOS_ANDROID NIKAOS_SIMULATE_ARCH NIKAOS_SIMULATE_NO_SYSTEMD NIKAOS_SIMULATE_ANDROID

android="$(bash "$INSTALLER" --dry-run --simulate-aarch64 --simulate-no-systemd --simulate-android 2>&1)"
echo "$android" > "$SANDBOX/android.txt"
check "android: architecture is aarch64" "grep -q 'architecture *: aarch64' '$SANDBOX/android.txt'"
check "android: no init system" "grep -q 'init system *: none' '$SANDBOX/android.txt'"
check "android: sway is the compositor" "grep -q 'compositor *: sway' '$SANDBOX/android.txt'"
check "android: core is built from source" "grep -q 'serpantinum-core *: built from source' '$SANDBOX/android.txt'"
check "android: gamma is skipped" "grep -q 'serpantinum-gamma *: skipped' '$SANDBOX/android.txt'"
check "android: services come from the compositor autostart" "grep -q 'user services *: compositor autostart' '$SANDBOX/android.txt'"
check "android: light profile announced" "grep -q 'light profile' '$SANDBOX/android.txt'"
check "android: session command announced" "grep -q 'nikaos session' '$SANDBOX/android.txt'"

arm="$(bash "$INSTALLER" --dry-run --simulate-aarch64 2>&1)"
echo "$arm" > "$SANDBOX/arm.txt"
check "aarch64 desktop: gamma is built, not skipped" "grep -q 'serpantinum-gamma *: built from source' '$SANDBOX/arm.txt'"
check "aarch64 desktop: no Android profile" "! grep -q 'light profile' '$SANDBOX/arm.txt'"

pc="$(NIKAOS_SIMULATE_ARCH=x86_64 bash "$INSTALLER" --dry-run 2>&1)"
echo "$pc" > "$SANDBOX/pc.txt"
check "x86_64: prebuilt helpers" "grep -q 'serpantinum-core *: prebuilt x86_64' '$SANDBOX/pc.txt'"
check "x86_64: no source build" "! grep -q 'built from source' '$SANDBOX/pc.txt'"
check "x86_64: no Android profile" "! grep -q 'light profile' '$SANDBOX/pc.txt'"

# Helpers.
# shellcheck source=../modules/platform.sh
source "$REPO_ROOT/install/modules/platform.sh"
filtered="$(NIKAOS_SIMULATE_ANDROID=1 nikaos_filter_android_pkgs kitty ddcutil sway power-profiles-daemon gpu-screen-recorder | tr '\n' ' ')"
check "android package filter keeps kitty and sway only" "[ '$filtered' = 'kitty sway ' ]"
check "simulated no-systemd is honoured" "! NIKAOS_SIMULATE_NO_SYSTEMD=1 nikaos_has_systemd"
check "android detected from NIKAOS_ANDROID=1" "NIKAOS_ANDROID=1 nikaos_is_android"

# The light profile merge keeps the user's own values.
if command -v jq >/dev/null 2>&1; then
    export HOME="$SANDBOX/home"
    mkdir -p "$HOME/.config/serpantinum" "$HOME/.config/sway/configDir"
    echo '{"theme":{"blurBackground":true,"font":"Iosevka"},"hardware":{"vpnConnection":"wg0"}}' > "$HOME/.config/serpantinum/settings.json"
    echo 'output * { resolution preferred }' > "$HOME/.config/sway/configDir/output"
    (
        CONFIG_DIR="$HOME/.config/serpantinum"
        source "$REPO_ROOT/install/modules/config.sh"
        export NIKAOS_SIMULATE_ANDROID=1
        apply_android_profile >/dev/null
    )
    cfg="$HOME/.config/serpantinum/settings.json"
    check "profile: blur off" "jq -e '.theme.blurBackground == false' '$cfg' >/dev/null"
    check "profile: font kept" "jq -e '.theme.font == \"Iosevka\"' '$cfg' >/dev/null"
    check "profile: VPN kept" "jq -e '.hardware.vpnConnection == \"wg0\"' '$cfg' >/dev/null"
    check "profile: tablet mode always on" "jq -e '.hardware.alwaysTablet == true and .hardware.tabletMode == true' '$cfg' >/dev/null"
    check "profile: screen control off" "jq -e '.hardware.displayControl == false' '$cfg' >/dev/null"
    check "profile: sway output not forced" "! grep -q '^output' '$HOME/.config/sway/configDir/output'"
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "All platform tests passed."
else
    echo "$failures platform test(s) failed."
    exit 1
fi
