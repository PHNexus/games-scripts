#!/bin/bash

set -Eeuo pipefail

sudo pacman -S --needed --noconfirm gamescope gamemode xclip wl-clipboard jq

STEAM_PATH="$HOME/.steam/steam/steamapps/common/Albion Online"
LOCAL_PATH="$HOME/.local/share/Steam/steamapps/common/Albion Online"

if [[ -d "$STEAM_PATH" ]]; then
    TARGET_DIR="$STEAM_PATH"
elif [[ -d "$LOCAL_PATH" ]]; then
    TARGET_DIR="$LOCAL_PATH"
else
    read -r -p "Path to Albion Online installation: " TARGET_DIR
fi

TARGET_DIR="${TARGET_DIR/#\~/$HOME}"
TARGET_DIR="$(realpath -m "$TARGET_DIR")"

ROOT_ENTRY="$TARGET_DIR/Albion-Online"
LAUNCHER="$TARGET_DIR/launcher/Albion-Online"
GAME_DIR="$TARGET_DIR/game_x64"
GAME="$GAME_DIR/Albion-Online"
REAL_GAME="$GAME_DIR/Albion-Online.real"

if [[ ! -x "$LAUNCHER" ]]; then
    printf 'Error: original graphical launcher not found or not executable:\n%s\n' "$LAUNCHER" >&2
    exit 1
fi

if [[ ! -e "$ROOT_ENTRY" ]]; then
    printf 'Error: Albion entry point not found:\n%s\n' "$ROOT_ENTRY" >&2
    exit 1
fi

if ! grep -aEq 'ALBION_GAMESCOPE_ROOT_WRAPPER|ALBION_LAUNCHER_ROOT_WRAPPER' "$ROOT_ENTRY"; then
    printf 'Error: unexpected root entry; refusing to overwrite:\n%s\n' "$ROOT_ENTRY" >&2
    exit 1
fi

if [[ ! -e "$GAME" ]]; then
    printf 'Error: game executable not found:\n%s\n' "$GAME" >&2
    exit 1
fi

if grep -aFq 'ALBION_GAME_GAMESCOPE_WRAPPER' "$GAME"; then
    if [[ ! -x "$REAL_GAME" ]]; then
        printf 'Error: preserved original game executable is missing:\n%s\n' "$REAL_GAME" >&2
        exit 1
    fi
else
    if [[ -e "$REAL_GAME" ]]; then
        printf 'Error: preserved game executable already exists:\n%s\n' "$REAL_GAME" >&2
        exit 1
    fi
    mv -- "$GAME" "$REAL_GAME"
fi

if [[ -d "$GAME_DIR/Albion-Online_Data" && ! -e "$GAME_DIR/Albion-Online.real_Data" && ! -L "$GAME_DIR/Albion-Online.real_Data" ]]; then
    ln -s "Albion-Online_Data" "$GAME_DIR/Albion-Online.real_Data"
fi

cat > "$GAME" <<'GAME_WRAPPER'
#!/bin/bash
# ALBION_GAME_GAMESCOPE_WRAPPER

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
REAL_GAME="$SCRIPT_DIR/Albion-Online.real"

if [[ ! -x "$REAL_GAME" ]]; then
    printf 'Error: preserved Albion executable not found:\n%s\n' "$REAL_GAME" >&2
    exit 1
fi

GAME_WIDTH=1920
GAME_HEIGHT=1080
GAME_REFRESH=180
MODE_DETECTED=0

if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    MONITORS_JSON="$(hyprctl monitors -j 2>/dev/null || true)"
    if [[ -n "$MONITORS_JSON" ]] && jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$MONITORS_JSON"; then
        read -r DETECTED_WIDTH DETECTED_HEIGHT DETECTED_REFRESH < <(
            jq -r '
                (([.[] | select(.focused == true)] | .[0]) // (sort_by((.width // 0) * (.height // 0)) | reverse | .[0])) as $m
                | [($m.width // 0), ($m.height // 0), ($m.refreshRate // 0)] | @tsv
            ' <<<"$MONITORS_JSON"
        )
        if [[ "${DETECTED_WIDTH:-}" =~ ^[0-9]+$ && "${DETECTED_HEIGHT:-}" =~ ^[0-9]+$ ]] && (( DETECTED_WIDTH > 0 && DETECTED_HEIGHT > 0 )); then
            GAME_WIDTH="$DETECTED_WIDTH"
            GAME_HEIGHT="$DETECTED_HEIGHT"
            if [[ "${DETECTED_REFRESH:-}" =~ ^[0-9]+([.][0-9]+)?$ ]] && [[ "$DETECTED_REFRESH" != "0" ]]; then
                printf -v GAME_REFRESH '%.0f' "$DETECTED_REFRESH"
            fi
            MODE_DETECTED=1
        fi
    fi
fi

if [[ "$MODE_DETECTED" -eq 0 ]] && command -v xrandr >/dev/null 2>&1; then
    XRANDR_MODE="$(xrandr --query 2>/dev/null | awk '
        / connected/ {
            connected = 1
            primary = ($0 ~ / connected primary /)
            next
        }
        /^[^[:space:]]/ {
            connected = 0
            primary = 0
        }
        connected && /\*/ {
            split($1, dimensions, "x")
            refresh = ""
            for (i = 2; i <= NF; i++) {
                if ($i ~ /\*/) {
                    refresh = $i
                    gsub(/[^0-9.]/, "", refresh)
                    break
                }
            }
            score = primary ? 1 : 0
            if (!found || score > best) {
                width = dimensions[1]
                height = dimensions[2]
                rate = refresh
                best = score
                found = 1
            }
        }
        END {
            if (found) printf "%s %s %s\n", width, height, (rate == "" ? 60 : rate)
        }
    ' || true)"
    if [[ "$XRANDR_MODE" =~ ^([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+([.][0-9]+)?)$ ]]; then
        GAME_WIDTH="${BASH_REMATCH[1]}"
        GAME_HEIGHT="${BASH_REMATCH[2]}"
        printf -v GAME_REFRESH '%.0f' "${BASH_REMATCH[3]}"
        MODE_DETECTED=1
    fi
fi

cd "$SCRIPT_DIR" || exit 1

clipboard_bridge() {
    local last=""
    local current=""

    while sleep 0.5; do
        current="$(wl-paste --type text/plain --no-newline 2>/dev/null || true)"
        if [[ -n "$current" && "$current" != "$last" ]]; then
            last="$current"
            printf '%s' "$current" | DISPLAY=:1 xclip -selection clipboard 2>/dev/null || true
            printf '%s' "$current" | DISPLAY=:1 xclip -selection primary 2>/dev/null || true
        fi
    done
}

BRIDGE_PID=""
cleanup() {
    if [[ -n "$BRIDGE_PID" ]]; then
        kill "$BRIDGE_PID" 2>/dev/null || true
        wait "$BRIDGE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

if command -v wl-paste >/dev/null 2>&1 && command -v xclip >/dev/null 2>&1; then
    clipboard_bridge &
    BRIDGE_PID=$!
fi

gamescope \
    -w "$GAME_WIDTH" -h "$GAME_HEIGHT" \
    -W "$GAME_WIDTH" -H "$GAME_HEIGHT" \
    -r "$GAME_REFRESH" \
    -f \
    -S stretch \
    -- \
    gamemoderun "$REAL_GAME" "$@" &
GAMESCOPE_PID=$!

wait "$GAMESCOPE_PID"
STATUS=$?
cleanup
exit "$STATUS"
GAME_WRAPPER

chmod +x "$GAME"

cat > "$ROOT_ENTRY" <<'LAUNCHER_WRAPPER'
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
export VK_LOADER_DEBUG=none
export mesa_glthread=true
export XKB_DEFAULT_LAYOUT=es
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

exec "$SCRIPTPATH/launcher/Albion-Online" "--no-sandbox" "$@"
LAUNCHER_WRAPPER

chmod +x "$ROOT_ENTRY"
