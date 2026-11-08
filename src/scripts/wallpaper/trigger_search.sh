#!/usr/bin/env bash
QUERY="$1"
SESSION="$2"
SEARCH_DIR="$3"
CACHE_DIR="$4"
RUN_DIR="$5"
LOG_DIR="$6"
DDG_SCRIPT="$7"
ANIMATED_ONLY="${8:-0}"
MIN_WIDTH="${9:-1920}"
MIN_HEIGHT="${10:-1080}"
LOAD_MORE="${11:-0}"

mkdir -p "$LOG_DIR" "$RUN_DIR" "$SEARCH_DIR" "$CACHE_DIR"

export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:$HOME/.local/bin

SEARCH_LOG="$LOG_DIR/wallpaper_search.log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] trigger query='$QUERY' session=$SESSION animated=$ANIMATED_ONLY load_more=$LOAD_MORE" >> "$SEARCH_LOG"

echo 'stop' > "$RUN_DIR/ddg_search_control"
for p in $(pgrep -f ddg_search.sh); do
    if [ "$p" != "$$" ] && [ "$p" != "$BASHPID" ]; then
        kill -9 "$p" 2>/dev/null || true
    fi
done
pkill -f "[g]et_ddg_links.py" 2>/dev/null || true
pkill -f "[m]otionbgs_search.py" 2>/dev/null || true
pkill -f "[m]oewalls_search.py" 2>/dev/null || true
sleep 0.8

if [[ "$LOAD_MORE" != "1" ]]; then
    rm -rf "${SEARCH_DIR:?}"/* 2>/dev/null || true
    rm -f "${CACHE_DIR:?}/search_map.txt" 2>/dev/null || true
    echo "$SESSION" > "${CACHE_DIR}/current_search_session"
fi
echo 'run' > "$RUN_DIR/ddg_search_control"

if [ -f "$DDG_SCRIPT" ]; then
    bash "$DDG_SCRIPT" "$QUERY" "$SESSION" "$ANIMATED_ONLY" "$MIN_WIDTH" "$MIN_HEIGHT" >> "$SEARCH_LOG" 2>&1 &
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERREUR: DDG_SCRIPT introuvable: $DDG_SCRIPT" >> "$SEARCH_LOG"
fi
