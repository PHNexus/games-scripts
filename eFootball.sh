#!/usr/bin/env bash
# EFOOTBALL_ARCH_AUTOMATION
# Automatically configures Gamescope for eFootball only: render/output resolution,
# refresh rate, and fullscreen. It does not change FPS settings or game files.

set -Eeuo pipefail

readonly APP_ID="1665460"
readonly MARKER="EFOOTBALL_ARCH_AUTOMATED=1"

if [[ ! -x /usr/bin/pacman ]] && ! command -v pacman >/dev/null 2>&1; then
    printf 'Error: this script is intended for Arch Linux and pacman-based distributions.\n' >&2
    exit 1
fi

# Steam keeps LaunchOptions in memory. If it is running, close it cleanly before
# editing localconfig.vdf, then reopen the Steam client afterward. Restarting the
# client does not launch eFootball; the game is never started by this script.
STEAM_WAS_RUNNING=0
STEAM_LAUNCH_MODE="native"

# Find Steam roots and additional Steam libraries, including Flatpak.
declare -a steam_roots=()
declare -a library_roots=()
declare -A seen_steam_roots=()
declare -A seen_library_roots=()

add_steam_root() {
    local path="${1:-}" resolved
    [[ -d "$path" ]] || return 0
    resolved="$(realpath -m -- "$path" 2>/dev/null || printf '%s' "$path")"
    [[ -n "${seen_steam_roots[$resolved]:-}" ]] && return 0
    seen_steam_roots["$resolved"]=1
    steam_roots+=("$resolved")
}

add_library_root() {
    local path="${1:-}" resolved
    [[ -d "$path" ]] || return 0
    resolved="$(realpath -m -- "$path" 2>/dev/null || printf '%s' "$path")"
    [[ -n "${seen_library_roots[$resolved]:-}" ]] && return 0
    seen_library_roots["$resolved"]=1
    library_roots+=("$resolved")
}

for path in \
    "$HOME/.steam/steam" \
    "$HOME/.steam/root" \
    "$HOME/.local/share/Steam" \
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
    add_steam_root "$path"
    add_library_root "$path"
done

# Discover alternate Steam libraries from libraryfolders.vdf.
for root in "${steam_roots[@]}"; do
    vdf="$root/steamapps/libraryfolders.vdf"
    [[ -r "$vdf" ]] || continue
    while IFS= read -r lib; do
        [[ -n "$lib" ]] && add_library_root "$lib"
    done < <(
        sed -nE \
            -e 's/^[[:space:]]*"path"[[:space:]]*"([^"]+)".*/\1/p' \
            -e 's/^[[:space:]]*"[0-9]+"[[:space:]]*"([^"]+)".*/\1/p' \
            "$vdf" | sort -u
    )
done

GAME_MANIFEST=""
for root in "${library_roots[@]}"; do
    if [[ -f "$root/steamapps/appmanifest_${APP_ID}.acf" ]]; then
        GAME_MANIFEST="$root/steamapps/appmanifest_${APP_ID}.acf"
        break
    fi
done

if [[ -z "$GAME_MANIFEST" ]]; then
    printf 'Error: eFootball (Steam App ID %s) was not found in the detected Steam libraries.\n' "$APP_ID" >&2
    exit 1
fi
printf 'Found eFootball manifest: %s\n' "$GAME_MANIFEST"

# Install only the packages that are missing.
if ! command -v gamescope >/dev/null 2>&1; then
    printf 'Installing Gamescope...\n'
    sudo pacman -S --needed --noconfirm gamescope
fi

for cmd in gamescope python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'Error: required command "%s" is unavailable.\n' "$cmd" >&2
        exit 1
    fi
done

# Detect the largest active Hyprland monitor and its refresh rate.
GAME_WIDTH=1920
GAME_HEIGHT=1080
GAME_REFRESH=60

if command -v hyprctl >/dev/null 2>&1; then
    monitor_info="$(hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
try:
    monitors = json.load(sys.stdin)
    valid = [m for m in monitors if int(m.get("width", 0)) > 0 and int(m.get("height", 0)) > 0]
    if valid:
        m = max(valid, key=lambda x: (int(x.get("width", 0)) * int(x.get("height", 0)), float(x.get("refreshRate", 0))))
        hz = max(1, round(float(m.get("refreshRate", 60))))
        print(int(m["width"]), int(m["height"]), hz)
except (ValueError, TypeError, KeyError, json.JSONDecodeError):
    pass
' 2>/dev/null || true)"
    if [[ "$monitor_info" =~ ^([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
        GAME_WIDTH="${BASH_REMATCH[1]}"
        GAME_HEIGHT="${BASH_REMATCH[2]}"
        GAME_REFRESH="${BASH_REMATCH[3]}"
    fi
fi

# Fallback for X11 sessions where Hyprland's IPC is unavailable.
if [[ "$GAME_WIDTH" == 1920 && "$GAME_HEIGHT" == 1080 && "$GAME_REFRESH" == 60 ]] && command -v xrandr >/dev/null 2>&1; then
    xrandr_info="$(xrandr --current 2>/dev/null | awk '/\*/ { res=$1; rate=$2; gsub(/[*+]/, "", rate); print res, rate; exit }' || true)"
    if [[ "$xrandr_info" =~ ^([0-9]+)x([0-9]+)[[:space:]]+([0-9]+([.][0-9]+)?)$ ]]; then
        GAME_WIDTH="${BASH_REMATCH[1]}"
        GAME_HEIGHT="${BASH_REMATCH[2]}"
        printf -v GAME_REFRESH '%0.f' "${BASH_REMATCH[3]}"
        (( GAME_REFRESH > 0 )) || GAME_REFRESH=60
    fi
fi

LAUNCH_PREFIX="$MARKER gamescope -w $GAME_WIDTH -h $GAME_HEIGHT -W $GAME_WIDTH -H $GAME_HEIGHT -r $GAME_REFRESH -f -- %command%"
printf 'Detected display: %sx%s @ %s Hz\n' "$GAME_WIDTH" "$GAME_HEIGHT" "$GAME_REFRESH"

# Close Steam only if needed, and only after confirming that eFootball and the
# required tools were found. Steam may overwrite direct edits to localconfig.vdf.
if pgrep -u "${UID}" -x steam >/dev/null 2>&1; then
    STEAM_WAS_RUNNING=1
    if command -v flatpak >/dev/null 2>&1 && \
       flatpak ps --columns=application 2>/dev/null | grep -Fxq 'com.valvesoftware.Steam'; then
        STEAM_LAUNCH_MODE="flatpak"
    fi

    printf '\nSteam is running. To save launch options safely, this script must briefly close and reopen the Steam client.\n'
    printf 'Steam and any running games will be closed; save your progress first.\n'
    read -r -p 'Close Steam now, apply the changes, and reopen Steam automatically? [y/N] ' answer || answer=""
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *)
            printf 'Cancelled; Steam was not changed.\n' >&2
            STEAM_WAS_RUNNING=0
            exit 1
            ;;
    esac

    if [[ "$STEAM_LAUNCH_MODE" == "flatpak" ]]; then
        flatpak run com.valvesoftware.Steam -shutdown >/dev/null 2>&1 || true
    elif command -v steam >/dev/null 2>&1; then
        steam -shutdown >/dev/null 2>&1 || true
    elif [[ -x "$HOME/.steam/root/steam.sh" ]]; then
        "$HOME/.steam/root/steam.sh" -shutdown >/dev/null 2>&1 || true
    else
        printf 'Error: Steam is running, but no safe shutdown command was found.\n' >&2
        STEAM_WAS_RUNNING=0
        exit 1
    fi

    for _ in {1..45}; do
        if ! pgrep -u "${UID}" -x steam >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    if pgrep -u "${UID}" -x steam >/dev/null 2>&1; then
        printf 'Error: Steam did not shut down within 45 seconds. No configuration was changed.\n' >&2
        exit 1
    fi
    printf 'Steam closed cleanly.\n\n'
fi

# Find the most recently used Steam user's existing localconfig.vdf.
declare -a localconfigs=()
for root in "${steam_roots[@]}"; do
    [[ -d "$root/userdata" ]] || continue
    while IFS= read -r config; do
        [[ -n "$config" ]] && localconfigs+=("$config")
    done < <(find "$root/userdata" -mindepth 3 -maxdepth 3 -type f -name localconfig.vdf 2>/dev/null)
done

if ((${#localconfigs[@]} == 0)); then
    printf 'Error: no Steam user localconfig.vdf was found. Sign into Steam once, exit Steam fully, and run this script again.\n' >&2
    exit 1
fi

CONFIG_FILE=""
NEWEST_MTIME=-1
for config in "${localconfigs[@]}"; do
    mtime="$(stat -c '%Y' "$config" 2>/dev/null || printf '0')"
    if [[ "$mtime" =~ ^[0-9]+$ ]] && (( mtime >= NEWEST_MTIME )); then
        NEWEST_MTIME="$mtime"
        CONFIG_FILE="$config"
    fi
done

if [[ -z "$CONFIG_FILE" ]]; then
    printf 'Error: could not select a Steam user configuration file.\n' >&2
    exit 1
fi

# Safely update just the eFootball LaunchOptions value in the existing VDF.
# A timestamped backup is made before changing Steam's config.
python3 - "$CONFIG_FILE" "$APP_ID" "$LAUNCH_PREFIX" <<'PY'
import datetime
import os
import re
import shutil
import sys
from dataclasses import dataclass, field

path, app_id, launch_prefix = sys.argv[1:]

@dataclass
class Token:
    raw: str
    value: str
    start: int
    end: int

@dataclass
class Node:
    key: str
    key_token: Token
    value: str | None = None
    value_token: Token | None = None
    children: list = field(default_factory=list)
    close_token: Token | None = None

def tokenize(source):
    pattern = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|[{}]|[^\s{}]+')
    out = []
    for match in pattern.finditer(source):
        raw = match.group(0)
        if raw.startswith('//') or raw == '\ufeff':
            continue
        if raw.startswith('"') and raw.endswith('"'):
            val = raw[1:-1].replace(r'\"', '"').replace(r'\\', '\\')
        else:
            val = raw
        out.append(Token(raw, val, match.start(), match.end()))
    return out

def parse_pairs(tokens, index=0, expects_close=False):
    nodes = []
    while index < len(tokens):
        if tokens[index].value == '}':
            if not expects_close:
                raise ValueError('Unexpected closing brace in Steam VDF')
            return nodes, index + 1, tokens[index]
        key_token = tokens[index]
        if key_token.value in ('{', '}'):
            raise ValueError('Unexpected brace where a key was expected')
        index += 1
        if index >= len(tokens):
            raise ValueError('Incomplete Steam VDF key/value pair')
        if tokens[index].value == '{':
            index += 1
            children, index, close_token = parse_pairs(tokens, index, True)
            nodes.append(Node(key_token.value, key_token, children=children, close_token=close_token))
        else:
            value_token = tokens[index]
            if value_token.value in ('{', '}'):
                raise ValueError('Invalid Steam VDF scalar value')
            nodes.append(Node(key_token.value, key_token, value=value_token.value, value_token=value_token))
            index += 1
    if expects_close:
        raise ValueError('Unclosed object in Steam VDF')
    return nodes, index, None

def child(node, key):
    return next((item for item in node.children if item.key == key), None)

def find_apps(nodes):
    # Prefer the exact UserLocalConfigStore/Software/Valve/Steam/apps path.
    root = next((n for n in nodes if n.key == 'UserLocalConfigStore'), None)
    cur = root
    for key in ('Software', 'Valve', 'Steam', 'apps'):
        cur = child(cur, key) if cur else None
        if cur is None:
            break
    if cur is not None:
        return cur
    # Some older Steam layouts differ slightly; find the first apps object.
    def walk(items):
        for item in items:
            if item.key == 'apps' and item.close_token is not None:
                return item
            found = walk(item.children)
            if found:
                return found
        return None
    return walk(nodes)

def indent_at(source, offset):
    line_start = source.rfind('\n', 0, offset) + 1
    prefix = source[line_start:offset]
    return prefix if prefix.strip() == '' else ''

def line_start_at(source, offset):
    return source.rfind('\n', 0, offset) + 1

def vdf_quote(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

def merge_options(old, prefix):
    old = (old or '').strip()
    marker = 'EFOOTBALL_ARCH_AUTOMATED=1'
    if marker in old:
        begin = old.index(marker)
        end = old.find('%command%', begin)
        if end != -1:
            return old[:begin] + prefix + old[end + len('%command%'):]
    if not old:
        return prefix
    if '%command%' in old:
        return old.replace('%command%', prefix, 1)
    # Preserve leading environment assignments, and leave existing game flags
    # after %command% so they still reach the game executable.
    parts = re.findall(r'"(?:\\.|[^"\\])*"|\S+', old)
    envs = []
    while parts and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*=.*', parts[0].strip('"')):
        envs.append(parts.pop(0))
    return ' '.join(envs + [prefix] + parts)

with open(path, 'r', encoding='utf-8-sig') as stream:
    source = stream.read()
tokens = tokenize(source)
nodes, _, _ = parse_pairs(tokens)
apps = find_apps(nodes)
if apps is None or apps.close_token is None:
    raise SystemExit('Error: the Steam apps section could not be located in localconfig.vdf.')

app_node = child(apps, app_id)
if app_node is None:
    old_options = ''
    new_options = launch_prefix
    close = apps.close_token
    line_start = line_start_at(source, close.start)
    apps_indent = indent_at(source, apps.key_token.start)
    child_indent = apps_indent + ('\t' if '\t' in apps_indent or not apps_indent else '    ')
    inner_indent = child_indent + ('\t' if '\t' in child_indent or not child_indent else '    ')
    block = (
        f'{child_indent}{vdf_quote(app_id)}\n'
        f'{child_indent}{{\n'
        f'{inner_indent}{vdf_quote("LaunchOptions")} {vdf_quote(new_options)}\n'
        f'{child_indent}}}\n'
    )
    updated_source = source[:line_start] + block + source[line_start:]
else:
    launch_node = child(app_node, 'LaunchOptions')
    old_options = launch_node.value if launch_node and launch_node.value is not None else ''
    new_options = merge_options(old_options, launch_prefix)
    if launch_node is not None and launch_node.value_token is not None:
        token = launch_node.value_token
        updated_source = source[:token.start] + vdf_quote(new_options) + source[token.end:]
    else:
        close = app_node.close_token
        line_start = line_start_at(source, close.start)
        app_indent = indent_at(source, app_node.key_token.start)
        body_indent = app_indent + ('\t' if '\t' in app_indent or not app_indent else '    ')
        insertion = f'{body_indent}{vdf_quote("LaunchOptions")} {vdf_quote(new_options)}\n'
        updated_source = source[:line_start] + insertion + source[line_start:]

if updated_source == source:
    print('Steam launch options are already up to date.')
else:
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = f'{path}.backup-{stamp}'
    shutil.copy2(path, backup)
    temporary = f'{path}.tmp-{os.getpid()}'
    with open(temporary, 'w', encoding='utf-8') as stream:
        stream.write(updated_source)
    os.chmod(temporary, os.stat(path).st_mode)
    os.replace(temporary, path)
    print(f'Updated Steam configuration: {path}')
    print(f'Backup: {backup}')
    if old_options:
        print(f'Previous LaunchOptions: {old_options}')
    print(f'New LaunchOptions: {new_options}')
PY

printf '\nDone. eFootball launch options were written directly to Steam configuration.\n'
printf 'No wrapper executable, FPS tweak, GameMode setting, or extra text file was created.\n'
printf 'Settings applied: Gamescope resolution %sx%s, %s Hz, fullscreen.\n' "$GAME_WIDTH" "$GAME_HEIGHT" "$GAME_REFRESH"
if [[ "$STEAM_WAS_RUNNING" == "1" ]]; then
    printf 'Reopening the Steam client (eFootball will NOT be launched)...\n'
    if [[ "$STEAM_LAUNCH_MODE" == "flatpak" ]]; then
        nohup flatpak run com.valvesoftware.Steam >/dev/null 2>&1 </dev/null &
    elif command -v steam >/dev/null 2>&1; then
        nohup steam >/dev/null 2>&1 </dev/null &
    elif [[ -x "$HOME/.steam/root/steam.sh" ]]; then
        nohup "$HOME/.steam/root/steam.sh" >/dev/null 2>&1 </dev/null &
    else
        printf 'Warning: settings were applied, but Steam could not be restarted automatically.\n' >&2
        exit 0
    fi
    printf 'Steam restart requested. eFootball was not launched.\n'
else
    printf 'Steam was not running initially, so it was left closed.\n'
fi
printf 'This script only configures eFootball launch options; it never launches eFootball.\n'
