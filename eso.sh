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

search_roots=(
    "$HOME/.steam/steam"
    "$HOME/.local/share/Steam"
    "/media"
    "/mnt"
    "/home"
    "/run/media"
)

for root in "${search_roots[@]}"; do
    if [ -d "$root" ]; then
        found=$(find "$root" -maxdepth 10 -type f -path "*/compatdata/306130/pfx/drive_c/users/*/Documents/Elder Scrolls Online/live/UserSettings.txt" 2>/dev/null | head -n 1)
        if [ -n "$found" ] && [ -f "$found" ]; then
            user_settings="$found"
            break
        fi
    fi
done

if [ -z "$user_settings" ] || [ ! -f "$user_settings" ]; then
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