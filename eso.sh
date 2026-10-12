#!/bin/bash

set -e

get_hz() {
    local max_hz=60
    if command -v hyprctl &>/dev/null && hyprctl monitors -j &>/dev/null; then
        local hz_list
        hz_list=$(hyprctl monitors -j | jq -r '.[].refreshRate' 2>/dev/null)
        for hz in $hz_list; do
            hz_int=$(printf "%.0f" "$hz")
            if [ "$hz_int" -gt "$max_hz" ]; then
                max_hz=$hz_int
            fi
        done
    else
        for card_dir in /sys/class/drm/card*-*/; do
            [[ -f "$card_dir/status" ]] || continue
            grep -q "^connected" "$card_dir/status" 2>/dev/null || continue
            if [[ -s "$card_dir/modes" ]]; then
                mode=$(head -n 1 "$card_dir/modes")
                if [[ "$mode" =~ @([0-9]+) ]]; then
                    hz="${BASH_REMATCH[1]}"
                    if [ "$hz" -gt "$max_hz" ]; then
                        max_hz=$hz
                    fi
                fi
            fi
        done
    fi
    echo "$max_hz"
}

target_hz=$(get_hz)

user_settings=""

known_patterns=(
    "compatdata/306130/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/UserSettings.txt"
    "compatdata/306130/pfx/drive_c/users/*/Documents/Elder Scrolls Online/live/UserSettings.txt"
)

for base in \
    "$HOME/.steam/steam/steamapps" \
    "$HOME/.local/share/Steam/steamapps" \
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps" \
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps"; do
    [[ -d "$base" ]] || continue
    for pattern in "${known_patterns[@]}"; do
        for f in "$base"/$pattern; do
            if [[ -f "$f" ]]; then
                user_settings="$f"
                break 3
            fi
        done
    done
done

if [[ -z "$user_settings" ]]; then
    search_roots=()
    for candidate in \
        "$HOME/.steam/steam" \
        "$HOME/.local/share/Steam" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
        [[ -d "$candidate" ]] && search_roots+=("$candidate")

        lib_file="$candidate/steamapps/libraryfolders.vdf"
        if [[ -r "$lib_file" ]]; then
            while IFS= read -r lib_path; do
                [[ -d "$lib_path" ]] && search_roots+=("$lib_path")
            done < <(sed -nE 's/^[[:space:]]*"path"[[:space:]]*"([^"]+)".*/\1/p; s/^[[:space:]]*"[0-9]+"[[:space:]]*"([^"]+)".*/\1/p' "$lib_file")
        fi
    done

    for root in "${search_roots[@]}"; do
        found=$(find "$root" -maxdepth 6 -type f -path "*/compatdata/306130/pfx/drive_c/users/*/Documents/Elder Scrolls Online/live/UserSettings.txt" 2>/dev/null | head -n 1)
        if [[ -n "$found" && -f "$found" ]]; then
            user_settings="$found"
            break
        fi
    done
fi

if [[ -z "$user_settings" || ! -f "$user_settings" ]]; then
    exit 1
fi

min_frame_time=$(awk -v hz="$target_hz" 'BEGIN { printf "%.8f", 1/hz }')

sed -i -E "s/SET BACKGROUND_FPS_LIMIT \"[0-9]+\"/SET BACKGROUND_FPS_LIMIT \"$target_hz\"/" "$user_settings"
sed -i -E "s/SET USE_BACKGROUND_FPS_LIMIT \"[0-9]+\"/SET USE_BACKGROUND_FPS_LIMIT \"1\"/" "$user_settings"

if grep -q "MinFrameTime.2" "$user_settings"; then
    sed -i -E "s/SET MinFrameTime.2 \"[0-9.]+\"/SET MinFrameTime.2 \"$min_frame_time\"/" "$user_settings"
else
    echo "SET MinFrameTime.2 \"$min_frame_time\"" >> "$user_settings"
fi