#!/usr/bin/env bash
# playerctl wrapper: the player chosen in the music popup first, then music
# apps, then any player.
pref=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum/preferred_player" 2>/dev/null)
exec playerctl -p "${pref:+$pref,}tidal-hifi,youtube-music,pear-desktop,spotify,%any" "$@"
