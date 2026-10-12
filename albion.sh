#!/bin/bash

set -Eeuo pipefail

sudo pacman -S --needed --noconfirm gamescope gamemode xclip wl-clipboard jq

declare -a CANDIDATE_DIRS=()
declare -a SEARCH_ROOTS=()
declare -A SEEN_CANDIDATES=()
declare -A SEEN_ROOTS=()

add_candidate() {
    local path="$1"
    [[ -d "$path" ]] || return 0
    path="$(realpath -m -- "$path")"
    [[ -n "${SEEN_CANDIDATES[$path]:-}" ]] && return 0
    SEEN_CANDIDATES["$path"]=1
    CANDIDATE_DIRS+=("$path")
}

add_search_root() {
    local path="$1"
    [[ -d "$path" ]] || return 0
    path="$(realpath -m -- "$path")"
    [[ -n "${SEEN_ROOTS[$path]:-}" ]] && return 0
    SEEN_ROOTS["$path"]=1
    SEARCH_ROOTS+=("$path")
}

is_albion_install() {
    local path="$1"
    [[ -e "$path/Albion-Online" \
        && -x "$path/launcher/Albion-Online" \
        && ( -x "$path/game_x64/Albion-Online" || -x "$path/game_x64/Albion-Online.real" ) ]]
}

add_candidate "$HOME/.steam/steam/steamapps/common/Albion Online"
add_candidate "$HOME/.local/share/Steam/steamapps/common/Albion Online"
add_candidate "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/Albion Online"

for STEAM_ROOT in \
    "$HOME/.steam/steam" \
    "$HOME/.local/share/Steam" \
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    add_search_root "$STEAM_ROOT"

    for LIBRARY_FILE in \
        "$STEAM_ROOT/steamapps/libraryfolders.vdf" \
        "$STEAM_ROOT/config/libraryfolders.vdf"; do
        [[ -f "$LIBRARY_FILE" ]] || continue

        while IFS= read -r LIBRARY_ROOT; do
            [[ -n "$LIBRARY_ROOT" ]] || continue
            add_candidate "$LIBRARY_ROOT/steamapps/common/Albion Online"
            add_search_root "$LIBRARY_ROOT"
        done < <(sed -nE \
            -e 's/^[[:space:]]*"path"[[:space:]]*"([^"]+)".*/\1/p' \
            -e 's/^[[:space:]]*"[0-9]+"[[:space:]]*"([^"]+)".*/\1/p' \
            "$LIBRARY_FILE" | sort -u)
    done
done

TARGET_DIR=""
for CANDIDATE in "${CANDIDATE_DIRS[@]}"; do
    if is_albion_install "$CANDIDATE"; then
        TARGET_DIR="$CANDIDATE"
        break
    fi
done

if [[ -z "$TARGET_DIR" ]]; then
    add_search_root "$HOME"
    add_search_root "/run/media/$USER"
    add_search_root "/media/$USER"
    add_search_root "/mnt"
    add_search_root "/media"
    add_search_root "/srv"
    add_search_root "/games"
    add_search_root "/data"

    for SEARCH_ROOT in "${SEARCH_ROOTS[@]}"; do
        while IFS= read -r LAUNCHER_PATH; do
            [[ -n "$LAUNCHER_PATH" ]] || continue
            CANDIDATE="$(dirname -- "$(dirname -- "$LAUNCHER_PATH")")"
            add_candidate "$CANDIDATE"
        done < <(find "$SEARCH_ROOT" \
            -type f \
            -path '*/launcher/Albion-Online' \
            -executable \
            -not -path '*/.cache/*' \
            -not -path '*/.local/share/Trash/*' \
            -print 2>/dev/null)
    done

    for CANDIDATE in "${CANDIDATE_DIRS[@]}"; do
        if is_albion_install "$CANDIDATE"; then
            TARGET_DIR="$CANDIDATE"
            break
        fi
    done
fi

if [[ -z "$TARGET_DIR" ]]; then
    printf 'Error: could not automatically find an Albion Online installation in Steam libraries or common mounted-storage locations.\n' >&2
    exit 1
fi

TARGET_DIR="$(realpath -m -- "$TARGET_DIR")"
printf 'Found Albion Online: %s\n' "$TARGET_DIR"

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
                ([.[] | select((.width // 0) > 0 and (.height // 0) > 0)]
                 | max_by([((.width // 0) * (.height // 0)), (.refreshRate // 0)])) as $m
                | [($m.width // 0), ($m.height // 0), ($m.refreshRate // 0)] | @tsv
            ' <<<"$MONITORS_JSON" 2>/dev/null || true
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
            next
        }
        /^[^[:space:]]/ {
            connected = 0
        }
        connected && $1 ~ /^[0-9]+x[0-9]+$/ {
            split($1, dimensions, "x")
            refresh = 0
            for (i = 2; i <= NF; i++) {
                if ($i ~ /\*/) {
                    value = $i
                    gsub(/[^0-9.]/, "", value)
                    refresh = value + 0
                    break
                }
            }
            if (refresh > 0) {
                area = dimensions[1] * dimensions[2]
                if (!found || area > best_area || (area == best_area && refresh > best_refresh)) {
                    width = dimensions[1]
                    height = dimensions[2]
                    rate = refresh
                    best_area = area
                    best_refresh = refresh
                    found = 1
                }
            }
        }
        END {
            if (found) printf "%s %s %.3f\n", width, height, rate
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
