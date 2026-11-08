#!/usr/bin/env bash
# Native background transparency for applications whose own renderer supports
# it.  This deliberately never uses Hyprland opacity: that would fade text and
# images after the application has already painted them.
set -euo pipefail

app="${1:?application required}"

if [[ "$app" == "reset-all" ]]; then
  # Restore native renderers too; a Hyprland reload only clears compositor
  # rules and cannot change Kitty or Vesktop's own background opacity.
  "$0" vesktop 100 || true
  "$0" kitty 100 || true
  while IFS= read -r kitty_pid; do
    [[ -n "$kitty_pid" ]] && "$0" kitty 100 "$kitty_pid" || true
  done < <(hyprctl clients -j | jq -r '.[] | select((.class | ascii_downcase) == "kitty") | .pid')
  exit 0
fi

percent="${2:?percentage required}"
pid="${3:-}"

case "$percent" in
  *[!0-9]*|'') exit 2 ;;
esac
(( percent >= 30 && percent <= 100 )) || exit 2

alpha="$(awk -v p="$percent" 'BEGIN { printf "%.2f", p / 100 }')"

case "$app" in
  kitty)
    kitty_config="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
    # Wallpaper/theme changes reload kitty.conf. Keep its configured value in
    # sync with Super+G so that reload cannot restore an older opacity.
    prefix='background_opacity '
    start="$(grep -bo -- "$prefix" "$kitty_config" | head -n1 | cut -d: -f1)"
    [ -n "$start" ] || exit 1
    seek=$(( start + ${#prefix} ))
    printf '%s' "$alpha" | dd of="$kitty_config" bs=1 seek="$seek" conv=notrunc status=none

    # With no PID this is a config-only update, used when resetting while no
    # Kitty window is currently open.
    [ -n "$pid" ] || exit 0

    # kitty appends its process id to a configured unix socket path, so each
    # OS window gets an isolated endpoint (…/kitty-serpantinum-<pid>).
    # The socket is already per OS window.  Hyprland reports Kitty's server
    # PID while kitty's `pid:` matcher sees the shell child PID, so matching by
    # PID would never select the target window.
    kitten @ --to "unix:/tmp/kitty-serpantinum-$pid" set-background-opacity --all "$alpha"
    ;;
  vesktop)
    css="${XDG_CONFIG_HOME:-$HOME/.config}/vesktop/settings/quickCss.css"
    # The Super+G slider starts at 30.  The CSS applies this alpha to one root
    # surface only, so the full 30–100 range remains readable.
    vesktop_alpha="$(awk -v p="$percent" 'BEGIN { printf "%.2f", (p - 30) / 70 }')"
    # Do not use `sed -i` here.  It replaces the file's inode, which makes
    # Vesktop's fs.watch stop receiving later Super+G changes.  The alpha is
    # always four bytes (e.g. .30), so overwrite just those bytes in place.
    prefix='--serpantinum-surface-alpha: '
    start="$(grep -bo -- "$prefix" "$css" | head -n1 | cut -d: -f1)"
    [ -n "$start" ] || exit 1
    seek=$(( start + ${#prefix} ))
    printf '%s' "$vesktop_alpha" | dd of="$css" bs=1 seek="$seek" conv=notrunc status=none
    ;;
  *) exit 2 ;;
esac
