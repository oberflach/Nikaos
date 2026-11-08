#!/usr/bin/env bash
# Platform detection for the Nikaos installer: CPU architecture, init system
# and the Android "Nikaos Linux" environment (Arch Linux ARM under proot,
# DroidDeck-based app). Everything here can be simulated for --dry-run and
# the tests:
#   NIKAOS_SIMULATE_ARCH=aarch64   pretend uname -m prints this
#   NIKAOS_SIMULATE_NO_SYSTEMD=1   pretend systemd is not running
#   NIKAOS_SIMULATE_ANDROID=1      pretend to run inside Nikaos Linux

nikaos_arch() {
    echo "${NIKAOS_SIMULATE_ARCH:-$(uname -m)}"
}

# Prebuilt helper binaries exist for x86_64 only (audio also has aarch64).
nikaos_is_x86_64() {
    [ "$(nikaos_arch)" = "x86_64" ]
}

# Nikaos Linux (Android app, DroidDeck fork): DROIDDECK or NIKAOS_ANDROID=1 in
# the environment, or the app's desktop launcher in /usr/local/bin.
nikaos_is_android() {
    [ "${NIKAOS_SIMULATE_ANDROID:-}" = 1 ] && return 0
    [ -n "${DROIDDECK:-}" ] || [ "${NIKAOS_ANDROID:-}" = 1 ] || [ -x /usr/local/bin/droiddeck-desktop ]
}

# systemd counts only when it is really PID 1 (proot has systemctl installed
# but no running manager).
nikaos_has_systemd() {
    [ "${NIKAOS_SIMULATE_NO_SYSTEMD:-}" = 1 ] && return 1
    [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1
}

nikaos_cargo_jobs() {
    local jobs=$(( $(nproc 2>/dev/null || echo 2) / 2 ))
    [ "$jobs" -lt 1 ] && jobs=1
    [ "$jobs" -gt 4 ] && jobs=4
    echo "$jobs"
}

# Build a Rust helper (serpantinum-core / serpantinum-gamma) from its release
# tag and lay it out under $work/stage/usr like the prebuilt tarball, using
# the project's own packaging/stage.sh.
#   nikaos_build_rust_helper <owner/repo> <tag> <binary> <work dir>
nikaos_build_rust_helper() {
    local repo="$1" tag="$2" bin="$3" work="$4" src="$4/source"

    if ! command -v cargo >/dev/null 2>&1; then
        echo -e "\e[33m[ WARN ]\e[0m cargo not found: install 'rust' to build $bin."
        return 1
    fi
    echo -e "\e[36m[ INFO ]\e[0m Building $bin ${tag} from source for $(nikaos_arch) (this takes a few minutes)..."
    git clone -q --depth 1 --branch "$tag" "https://github.com/$repo.git" "$src" || return 1
    (
        cd "$src" || exit 1
        CARGO_BUILD_JOBS="$(nikaos_cargo_jobs)" cargo build --release --locked \
            || CARGO_BUILD_JOBS="$(nikaos_cargo_jobs)" cargo build --release
    ) || return 1
    if [ -f "$src/packaging/stage.sh" ]; then
        sh "$src/packaging/stage.sh" "$work/stage" || return 1
    else
        install -Dm755 "$src/target/release/$bin" "$work/stage/usr/bin/$bin" || return 1
        [ -f "$src/LICENSE" ] && install -Dm644 "$src/LICENSE" "$work/stage/usr/share/licenses/$bin/LICENSE"
    fi
    [ -x "$work/stage/usr/bin/$bin" ]
}

# Quickshell from source, when neither the repositories nor the AUR have it
# (Arch Linux ARM). Same version as the latest upstream release.
QUICKSHELL_BUILD_PKGS=(cmake ninja pkgconf qt6-base qt6-declarative qt6-svg qt6-wayland
    qt6-shadertools spirv-tools cli11 jemalloc wayland wayland-protocols libdrm mesa
    vulkan-headers libxcb pipewire pam polkit glib2)

nikaos_build_quickshell() {
    local work tag
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}"

    echo -e "\n\e[36m[ INFO ]\e[0m Quickshell is not packaged for $(nikaos_arch): building it from source."
    local pkg missing=()
    for pkg in "${QUICKSHELL_BUILD_PKGS[@]}"; do
        pm_is_installed "$pkg" || missing+=("$pkg")
    done
    for pkg in "${missing[@]}"; do
        pm_install_pkg "$pkg" 1 || echo -e "\e[33m[ WARN ]\e[0m $pkg is not available, continuing."
    done

    tag="$(curl -fsSL --connect-timeout 15 "https://api.github.com/repos/quickshell-mirror/quickshell/releases/latest" 2>/dev/null \
        | jq -r '.tag_name // empty')"
    tag="${tag:-master}"
    mkdir -p "$cache"
    work="$(mktemp -d "$cache/nikaos-quickshell.XXXXXX")"
    if git clone -q --depth 1 --branch "$tag" https://git.outfoxxed.me/quickshell/quickshell.git "$work/src" 2>/dev/null \
        || git clone -q --depth 1 --branch "$tag" https://github.com/quickshell-mirror/quickshell.git "$work/src"; then
        # The crash handler needs cpptrace, which Arch Linux ARM does not ship.
        if cmake -GNinja -S "$work/src" -B "$work/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
                -DCMAKE_INSTALL_PREFIX=/usr -DCRASH_HANDLER=OFF -DDISTRIBUTOR="Nikaos installer (source build)" \
            && cmake --build "$work/build" -j "$(nikaos_cargo_jobs)" \
            && sudo cmake --install "$work/build"; then
            hash -r
            echo -e "\e[32m[ OK ] Quickshell ${tag} built and installed.\e[0m"
            echo -e "\e[33m  Quickshell uses private Qt APIs: run the Nikaos installer again after a Qt update.\e[0m"
            rm -rf "$work"
            return 0
        fi
    fi
    rm -rf "$work"
    echo -e "\e[31m[ FAILED ] Quickshell could not be built.\e[0m"
    return 1
}

# Packages that make no sense inside the Android proot (no DRM, no udev,
# no power or display control) or that Arch Linux ARM does not have.
ANDROID_SKIP_PKGS=(ddcutil power-profiles-daemon gpu-screen-recorder)

nikaos_filter_android_pkgs() {
    local pkg skip
    for pkg in "$@"; do
        for skip in "${ANDROID_SKIP_PKGS[@]}"; do
            [ "$pkg" = "$skip" ] && continue 2
        done
        printf '%s\n' "$pkg"
    done
}

# Prints what the installer will do on this machine, without changing it.
nikaos_print_plan() {
    local arch init android=no
    arch="$(nikaos_arch)"
    nikaos_has_systemd && init="systemd" || init="none (services started by the compositor)"
    nikaos_is_android && android=yes

    echo "Nikaos installer plan (dry run, nothing is changed)"
    echo "  architecture        : $arch"
    echo "  init system         : $init"
    echo "  Nikaos Linux/Android: $android"
    if nikaos_is_android; then
        echo "  compositor          : sway (Hyprland does not start in the Android app yet)"
        echo "  sway outputs        : left to the app (no output mode forced)"
        echo "  skipped packages    : ${ANDROID_SKIP_PKGS[*]}"
        echo "  light profile       : no blur, static wallpapers, reduced motion, no brightness/gamma control, tablet mode always on"
        echo "  session command     : nikaos session"
    fi
    if nikaos_is_x86_64; then
        echo "  serpantinum-core    : prebuilt x86_64 release"
        echo "  serpantinum-gamma   : prebuilt x86_64 release"
        echo "  serpantinum-audio   : prebuilt x86_64 release"
    else
        echo "  serpantinum-core    : built from source (cargo build --release)"
        if nikaos_is_android; then
            echo "  serpantinum-gamma   : skipped (Android controls the screen)"
        else
            echo "  serpantinum-gamma   : built from source (cargo build --release)"
        fi
        echo "  serpantinum-audio   : prebuilt $arch release, or built from source (make)"
        echo "  build dependencies  : rust base-devel git pkgconf"
        echo "  quickshell          : repository package, else AUR, else built from source"
    fi
    if nikaos_has_systemd; then
        echo "  user services       : systemctl --user (pipewire, wireplumber)"
    else
        echo "  user services       : compositor autostart (audio server only if none is running)"
    fi
}
