CONFIG_DIR="$HOME/.config/serpantinum"
CONFIG_FILE="$CONFIG_DIR/settings.json"

init_serpantinum_config() {
    local project_root="$1"
    local wallpaper_dir="$2"
    local install_state="$3"
    local is_reinstall="$4"
    local template_json="$project_root/config/serpantinum/settings.json"
    local script_path="$project_root/src/scripts/location.sh"

    if [[ "$install_state" == "current" && "$is_reinstall" != "true" ]]; then
        return 0
    fi

    mkdir -p "$CONFIG_DIR"

    local sys_lang="en"
    command -v detect_system_language &>/dev/null && sys_lang="$(detect_system_language)"

    if [ -f "$template_json" ]; then
        if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ]; then
            local merged_json
            merged_json=$(jq -s --arg wp "$wallpaper_dir" --arg lang "$sys_lang" '
                (.[0] * .[1])
                * (if ($wp | length > 0) then {wallpaperDir: $wp} else {} end)
                * (if (.[1].general.language // null) == null then {general: {language: $lang}} else {} end)
            ' "$template_json" "$CONFIG_FILE" 2>/dev/null)
            if [ -n "$merged_json" ]; then
                echo "$merged_json" > "$CONFIG_FILE"
            fi
        else
            local initial_json
            initial_json=$(jq --arg wp "$wallpaper_dir" --arg lang "$sys_lang" '
                . * (if ($wp | length > 0) then {wallpaperDir: $wp} else {} end)
                  * {general: {language: $lang}}
            ' "$template_json" 2>/dev/null)
            if [ -n "$initial_json" ]; then
                echo "$initial_json" > "$CONFIG_FILE"
            else
                cp "$template_json" "$CONFIG_FILE"
            fi
        fi
    elif [ ! -f "$CONFIG_FILE" ]; then
        if [ -n "$wallpaper_dir" ]; then
            echo "{\"wallpaperDir\": \"$wallpaper_dir\"}" > "$CONFIG_FILE"
        else
            echo "{}" > "$CONFIG_FILE"
        fi
    fi

    if [[ "$is_reinstall" == "true" || "$install_state" == "fresh" || "$install_state" == "legacy" ]]; then
        if [ -f "$script_path" ]; then
            bash "$script_path" --refresh >/dev/null 2>&1 || true
        elif [ -f "$HOME/.local/share/serpantinum/src/scripts/location.sh" ]; then
            bash "$HOME/.local/share/serpantinum/src/scripts/location.sh" --refresh >/dev/null 2>&1 || true
        fi
    fi
}

# Nikaos Linux (Android): light defaults, applied once so later changes made
# in the settings are kept on the next install.
apply_android_profile() {
    nikaos_is_android || return 0
    [ -f "$CONFIG_FILE" ] || echo "{}" > "$CONFIG_FILE"
    if jq -e '.nikaosProfile == "android"' "$CONFIG_FILE" >/dev/null 2>&1; then
        return 0
    fi
    local merged
    merged=$(jq '
        . * {
            nikaosProfile: "android",
            theme: {blurBackground: false},
            performance: {reducedMotion: true, staticWallpapers: true},
            hardware: {displayControl: false, tabletMode: true, alwaysTablet: true},
            wallpaperSlideshow: {enabled: false}
        }' "$CONFIG_FILE" 2>/dev/null)
    [ -n "$merged" ] && echo "$merged" > "$CONFIG_FILE"
    echo -e "\e[36m[ INFO ]\e[0m Light profile for Nikaos Linux: no blur, static wallpapers, reduced motion, tablet mode (change them in Settings)."

    # The screen is a window of the app: let it pick the size, force nothing.
    local sway_output="$HOME/.config/sway/configDir/output"
    if [ -d "$(dirname "$sway_output")" ]; then
        printf '%s\n' "# Nikaos Linux: the output is a window of the Android app, so no" \
            "# mode, position or scale is forced here. Add 'output * scale 2' etc. if needed." > "$sway_output"
    fi
}
