#!/bin/bash

set -Eeuo pipefail

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

find_efootball() {
    local roots=(
        "$HOME/.steam/steam/steamapps"
        "$HOME/.local/share/Steam/steamapps"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps"
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps"
    )
    
    for base in "${roots[@]}"; do
        local vdf="$base/libraryfolders.vdf"
        [[ -f "$vdf" ]] || continue
        while IFS= read -r lib; do
            [[ -n "$lib" ]] || continue
            if [[ -d "$lib/steamapps/common/eFootball" ]]; then
                printf '%s\n' "$lib/steamapps/common/eFootball"
                return 0
            fi
        done < <(sed -nE 's/^[[:space:]]*"path"[[:space:]]*"([^"]+)".*/\1/p; s/^[[:space:]]*"[0-9]+"[[:space:]]*"([^"]+)".*/\1/p' "$vdf" | sort -u)
    done

    for r in "${roots[@]}"; do
        if [[ -d "$r/common/eFootball" ]]; then
            printf '%s\n' "$r/common/eFootball"
            return 0
        fi
    done

    return 1
}

# Find eFootball App ID or directory
TARGET_DIR="$(find_efootball)" || {
    printf 'Error: eFootball not found.\n' >&2
    exit 1
}

TARGET_DIR="$(realpath -m -- "$TARGET_DIR")"
printf 'Found eFootball at: %s\n' "$TARGET_DIR"

GAME_WIDTH=1920
GAME_HEIGHT=1080
GAME_REFRESH=$(get_hz)

if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    MONITORS_JSON="$(hyprctl monitors -j 2>/dev/null || true)"
    if [[ -n "$MONITORS_JSON" ]] && jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$MONITORS_JSON"; then
        read -r W H R < <(jq -r '([.[] | select((.width // 0) > 0 and (.height // 0) > 0)] | max_by([((.width // 0) * (.height // 0)), (.refreshRate // 0)])) as $m | [($m.width // 0), ($m.height // 0), ($m.refreshRate // 0)] | @tsv' <<<"$MONITORS_JSON" 2>/dev/null || true)
        if [[ "${W:-}" =~ ^[0-9]+$ && "${H:-}" =~ ^[0-9]+$ ]] && (( W > 0 && H > 0 )); then
            GAME_WIDTH="$W"
            GAME_HEIGHT="$H"
            if [[ "${R:-}" =~ ^[0-9]+([.][0-9]+)?$ ]] && [[ "$R" != "0" ]]; then
                printf -v GAME_REFRESH '%.0f' "$R"
            fi
        fi
    fi
fi

WRAPPER_PATH="$TARGET_DIR/efootball-gamescope.sh"

cat > "$WRAPPER_PATH" <<EOF
#!/bin/bash
exec gamescope \\
    -w "$GAME_WIDTH" -h "$GAME_HEIGHT" \\
    -W "$GAME_WIDTH" -H "$GAME_HEIGHT" \\
    -r "$GAME_REFRESH" \\
    -f \\
    -S stretch \\
    -- \\
    gamemoderun "\$@"
EOF

chmod +x "$WRAPPER_PATH"
printf 'Gamescope wrapper created: %s\n' "$WRAPPER_PATH"

# Automatically try to update Steam appinfo/launch options if python3 is available
# eFootball App ID is usually 1665460
EFOOTBALL_APPID="1665460"

STEAM_USER_DIRS=(
    "$HOME/.steam/steam/userdata"
    "$HOME/.local/share/Steam/userdata"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/userdata"
)

updated_steam=false
for udir in "${STEAM_USER_DIRS[@]}"; do
    [[ -d "$udir" ]] || continue
    for user_dir in "$udir"/*; do
        [[ -d "$user_dir" ]] || continue
        localcfg="$user_dir/config/localconfig.vdf"
        if [[ -f "$localcfg" ]]; then
            # Use python to safely update localconfig.vdf launch options for eFootball
            python3 - "$localcfg" "$EFOOTBALL_APPID" "$WRAPPER_PATH" << 'PY'
import sys
import re

config_path = sys.argv[1]
appid = sys.argv[2]
wrapper = sys.argv[3]

with open(config_path, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Check if app block exists in localconfig.vdf
pattern = rf'("{appid}"\s*\{{)(.*?)(\}})'

launch_string = f'\\t\\t\\t"LaunchOptions"		"{wrapper} %command%"\\n'

def replace_app(match):
    header = match.group(1)
    body = match.group(2)
    footer = match.group(3)
    
    if 'LaunchOptions' in body:
        body = re.sub(r'"LaunchOptions"\s*"[^"]*"]*', f'"LaunchOptions"\t\t"{wrapper} %command%"', body)
    else:
        body = body.rstrip() + f'\n\t\t\t"LaunchOptions"\t\t"{wrapper} %command%"\n\t\t'
    return header + body + footer

if re.search(pattern, content, re.DOTALL):
    new_content = re.sub(pattern, replace_app, content, flags=re.DOTALL)
    if new_content != content:
        with open(config_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print("Successfully updated Steam localconfig.vdf!")
        sys.exit(0)

sys.exit(1)
PY
            if [ $? -eq 0 ]; then
                updated_steam=true
            fi
        fi
    done
done

if [ "$updated_steam" = true ]; then
    printf 'Done! Steam launch options were configured automatically. Just restart Steam completely and play.\n'
else
    printf 'Note: Could not automatically update Steam config. Please paste this into eFootball launch options manually just once:\n'
    printf '%s %%command%%\n' "$WRAPPER_PATH"
fi