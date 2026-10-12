#!/bin/bash

set -Eeuo pipefail

sudo pacman -S --needed --noconfirm gamescope gamemode xclip wl-clipboard jq

find_albion() {
    local roots=(
        "$HOME/.steam/steam/steamapps/common/Albion Online"
        "$HOME/.local/share/Steam/steamapps/common/Albion Online"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/Albion Online"
    )
    local r
    for r in "${roots[@]}"; do
        if [[ -x "$r/launcher/Albion-Online" ]]; then
            printf '%s\n' "$r"
            return 0
        fi
    done

    local vdf lib
    for vdf in \
        "$HOME/.steam/steam/steamapps/libraryfolders.vdf" \
        "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/libraryfolders.vdf"; do
        [[ -f "$vdf" ]] || continue
        while IFS= read -r lib; do
            [[ -n "$lib" ]] || continue
            if [[ -x "$lib/steamapps/common/Albion Online/launcher/Albion-Online" ]]; then
                printf '%s\n' "$lib/steamapps/common/Albion Online"
                return 0
            fi
        done < <(sed -nE 's/^[[:space:]]*"path"[[:space:]]*"([^"]+)".*/\1/p; s/^[[:space:]]*"[0-9]+"[[:space:]]*"([^"]+)".*/\1/p' "$vdf" | sort -u)
    done

    return 1
}

TARGET_DIR="$(find_albion)" || {
    printf 'Error: Albion Online not found.\n' >&2
    exit 1
}

TARGET_DIR="$(realpath -m -- "$TARGET_DIR")"
printf 'Found: %s\n' "$TARGET_DIR"

GAME_DIR="$TARGET_DIR/game_x64"
GAME="$GAME_DIR/Albion-Online"
REAL_GAME="$GAME_DIR/Albion-Online.real"

mkdir -p "$GAME_DIR"

if [[ -f "$GAME" ]] && ! head -c 200 "$GAME" 2>/dev/null | grep -aq 'ALBION_GAME_GAMESCOPE_WRAPPER'; then
    mv -f -- "$GAME" "$REAL_GAME"
fi

if [[ ! -f "$REAL_GAME" ]]; then
    printf 'Error: %s missing.\n' "$REAL_GAME" >&2
    exit 1
fi

chmod +x -- "$REAL_GAME"

[[ -d "$GAME_DIR/Albion-Online_Data" ]] && ln -sfn "Albion-Online_Data" "$GAME_DIR/Albion-Online.real_Data"

cat > "$GAME" <<'EOF'
#!/bin/bash
# ALBION_GAME_GAMESCOPE_WRAPPER
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
REAL_GAME="$SCRIPT_DIR/Albion-Online.real"

if [[ ! -x "$REAL_GAME" ]]; then
    printf 'Error: preserved Albion executable not found: %s\n' "$REAL_GAME" >&2
    exit 1
fi

GAME_WIDTH=1920
GAME_HEIGHT=1080
GAME_REFRESH=180

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

cd "$SCRIPT_DIR" || exit 1

exec gamescope \
    -w "$GAME_WIDTH" -h "$GAME_HEIGHT" \
    -W "$GAME_WIDTH" -H "$GAME_HEIGHT" \
    -r "$GAME_REFRESH" \
    -f \
    -S stretch \
    -- \
    gamemoderun "$REAL_GAME" "$@"
EOF

chmod +x "$GAME"

ROOT_ENTRY="$TARGET_DIR/Albion-Online"

cat > "$ROOT_ENTRY" <<'EOF'
#!/bin/sh
# ALBION_LAUNCHER_ROOT_WRAPPER
SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "$SCRIPT")"
cd "$SCRIPTPATH" || exit 1

PREFS="$HOME/.config/unity3d/Sandbox Interactive GmbH/Albion Online Client/prefs"
if [ -f "$PREFS" ]; then
    sed -i \
        -e '/Screenmanager Is Fullscreen mode/d' \
        -e '/Screenmanager Resolution Height/d' \
        -e '/Screenmanager Resolution Width/d' \
        "$PREFS"
fi

export QT_QPA_PLATFORM_PLUGIN_PATH="$SCRIPTPATH/launcher/plugins/platforms"
export QT_PLUGIN_PATH="$SCRIPTPATH/launcher/plugins/"
export QT_QPA_PLATFORM="xcb;eglfs"
export __GL_GlslUseCollapsedArrays=0
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export VK_LOADER_DEGUG=none
export mesa_glthread=true
export XKB_DEFAULT_LAYOUT=es
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

exec "$SCRIPTPATH/launcher/Albion-Online" "--no-sandbox" "$@"
EOF

chmod +x "$ROOT_ENTRY"

printf 'Done.\n'