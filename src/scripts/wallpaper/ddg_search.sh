#!/usr/bin/env bash

QUERY="$1"
SESSION_ID="${2:-0}"
ANIMATED_ONLY="${3:-0}"
MIN_WIDTH="${4:-1920}"
MIN_HEIGHT="${5:-1080}"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

source "$SCRIPT_DIR/../caching.sh"
qs_ensure_cache "wallpaper"

CACHE_DIR="$QS_CACHE_WALLPAPER"
SEARCH_DIR="$CACHE_DIR/search_thumbs"
MAP_FILE="$CACHE_DIR/search_map.txt"
CONTROL_FILE="$QS_RUN_WALLPAPER/ddg_search_control"
OFFSET_DIR="$CACHE_DIR/search_offsets"
MAX_PARALLEL=8

mkdir -p "$SEARCH_DIR" "$OFFSET_DIR"

echo "[ddg_search] start query='$QUERY' session=$SESSION_ID animated=$ANIMATED_ONLY min=${MIN_WIDTH}x${MIN_HEIGHT} control=$(cat "$CONTROL_FILE" 2>/dev/null)"

run_sources() {
    if [[ "$ANIMATED_ONLY" == "1" ]]; then
        local excl_motionbgs="" excl_moewalls=""
        if [ -f "$MAP_FILE" ]; then
            excl_motionbgs=$(grep -oP '\|motionbgs:\K\d+' "$MAP_FILE" 2>/dev/null | sort -u | paste -sd, -)
            excl_moewalls=$(grep -oP '\|moewalls:\K\d+' "$MAP_FILE" 2>/dev/null | sort -u | paste -sd, -)
        fi
        echo "[ddg_search] exclude motionbgs=$(echo -n "$excl_motionbgs" | tr -cd ',' | wc -c) moewalls=$(echo -n "$excl_moewalls" | tr -cd ',' | wc -c)"
        local offset_motionbgs="$OFFSET_DIR/${SESSION_ID}_motionbgs"
        local offset_moewalls="$OFFSET_DIR/${SESSION_ID}_moewalls"
        python3 -u "$SCRIPT_DIR/motionbgs_search.py" "$QUERY" "20" "$excl_motionbgs" "$offset_motionbgs" &
        local pid_motionbgs=$!
        python3 -u "$SCRIPT_DIR/moewalls_search.py" "$QUERY" "20" "$excl_moewalls" "$offset_moewalls" &
        local pid_moewalls=$!
        wait "$pid_motionbgs" "$pid_moewalls"
    else
        python3 -u "$SCRIPT_DIR/get_ddg_links.py" "$QUERY" "$SESSION_ID" "$ANIMATED_ONLY" "$MIN_WIDTH" "$MIN_HEIGHT"
    fi
}

process_item() {
    local thumb_url="$1" full_url="$2" fallback_url="$3" source_tag="${4:-web}"

    local state
    state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    if [[ "$state" == "stop" ]]; then return 0; fi
    while [[ "$state" == "pause" ]]; do
        sleep 1
        state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    done

    local target_headers target_type
    target_headers=$(curl -s -I -L -m 3 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$full_url")
    target_type=$(echo "$target_headers" | grep -i "content-type:" | tail -n 1 | tr -d '\r')
    if [[ ! "$target_type" =~ (image/|video/|application/octet-stream) ]]; then
        if [ -n "$fallback_url" ]; then
            target_headers=$(curl -s -I -L -m 3 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$fallback_url")
            target_type=$(echo "$target_headers" | grep -i "content-type:" | tail -n 1 | tr -d '\r')
            if [[ ! "$target_type" =~ (image/|video/|application/octet-stream) ]]; then return 0; fi
            full_url="$fallback_url"
        else
            return 0
        fi
    fi

    local uuid ext is_webp
    uuid="$(date +%s%N)_$$_${RANDOM}"
    if [[ "$ANIMATED_ONLY" == "1" ]]; then
        ext="mp4"
    else
        ext="${full_url##*.}"
        ext="${ext%%\?*}"
        ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$ext" =~ ^(jpg|jpeg|png|webp|gif|mp4)$ ]]; then ext="jpg"; fi
    fi

    is_webp=0
    if [[ "$ext" == "webp" ]]; then
        is_webp=1
        ext="jpg"
    fi

    local filename="ddg_${SESSION_ID}_${uuid}.${ext}"
    local filepath="$SEARCH_DIR/$filename"
    local tmppath="${filepath}.tmp"

    curl -s -L -m 5 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$thumb_url" -o "$tmppath"

    state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    if [[ "$state" == "stop" ]]; then
        rm -f "$tmppath"
        return 0
    fi

    if [ -s "$tmppath" ]; then
        local actual_mime
        actual_mime=$(file -b --mime-type "$tmppath")

        if [[ ! "$actual_mime" =~ ^image/ ]]; then
            rm -f "$tmppath"
        else
            if [[ "$actual_mime" == "image/webp" ]] || [ $is_webp -eq 1 ]; then
                if command -v magick >/dev/null 2>&1; then
                    magick "$tmppath" "$filepath" 2>/dev/null || mv "$tmppath" "$filepath"
                elif command -v ffmpeg >/dev/null 2>&1; then
                    ffmpeg -y -i "$tmppath" "$filepath" >/dev/null 2>&1 || mv "$tmppath" "$filepath"
                else
                    mv "$tmppath" "$filepath"
                fi
                rm -f "$tmppath"
            else
                mv "$tmppath" "$filepath"
            fi
            echo "$filename|$full_url|$source_tag" >> "$MAP_FILE"
        fi
    else
        rm -f "$tmppath"
    fi
}

START_TS=$(date +%s)
running=0
items_seen=0
while IFS='|' read -r thumb_url full_url fallback_url source_tag; do
    items_seen=$((items_seen + 1))
    state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    if [[ "$state" == "stop" ]]; then
        echo "[ddg_search] arret demande (control=stop) apres $items_seen items lus"
        break
    fi
    if [ -z "$thumb_url" ] || [ -z "$full_url" ]; then continue; fi

    process_item "$thumb_url" "$full_url" "$fallback_url" "$source_tag" &
    running=$((running + 1))
    if [ "$running" -ge "$MAX_PARALLEL" ]; then
        wait -n
        running=$((running - 1))
    fi
done < <(run_sources)

wait

SESSION_COUNT=$(grep -c "^ddg_${SESSION_ID}_" "$MAP_FILE" 2>/dev/null)
SESSION_COUNT="${SESSION_COUNT:-0}"
STATUS_FILE="$CACHE_DIR/search_batch_status.json"
printf '{"session":"%s","count":%s,"ts":%s}' "$SESSION_ID" "$SESSION_COUNT" "$(date +%s%N)" > "${STATUS_FILE}.tmp"
mv "${STATUS_FILE}.tmp" "$STATUS_FILE"

ELAPSED=$(( $(date +%s) - START_TS ))
echo "[ddg_search] fin query='$QUERY' items_seen=$items_seen final_count=$SESSION_COUNT elapsed=${ELAPSED}s control_final=$(cat "$CONTROL_FILE" 2>/dev/null)"
