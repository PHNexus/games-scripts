#!/bin/bash

set -Eeuo pipefail

declare -a lib_roots=()
declare -A seen_roots=()

add_root() {
    local path="$1"
    [[ -d "$path" ]] || return 0
    local resolved
    resolved="$(realpath -m -- "$path" 2>/dev/null || printf '%s' "$path")"
    [[ -n "${seen_roots[$resolved]:-}" ]] && return 0
    seen_roots["$resolved"]=1
    lib_roots+=("$resolved")
}

add_root "$HOME/.steam/steam"
add_root "$HOME/.local/share/Steam"
add_root "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
add_root "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"

while IFS= read -r vdf; do
    [[ -n "$vdf" ]] || continue
    while IFS= read -r lib; do
        [[ -n "$lib" ]] || continue
        add_root "$lib"
    done < <(sed -nE 's/^[[:space:]]*"path"[[:space:]]*"([^"]+)".*/\1/p; s/^[[:space:]]*"[0-9]+"[[:space:]]*"([^"]+)".*/\1/p' "$vdf" | sort -u)
done < <(find "$HOME" -maxdepth 5 -name "libraryfolders.vdf" -type f 2>/dev/null)

TARGET=""
for root in "${lib_roots[@]}"; do
    for pattern in \
        "$root/steamapps/common/Counter-Strike Global Offensive/game/cs2.sh" \
        "$root/steamapps/common/Counter-Strike Global Offensive/cs2.sh"; do
        if [[ -f "$pattern" ]]; then
            TARGET="$pattern"
            break 2
        fi
    done
done

[[ -n "$TARGET" ]] || exit 1

python3 - "$TARGET" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

content = re.sub(
    r'[ \t]*\.[ \t]+/etc/os-release[ \t]*\n(?:.*\n)*?[ \t]*fi[ \t]*\n',
    '',
    content,
    count=1,
)

if 'SDL_VIDEO_DRIVER' not in content:
    content = content.replace(
        'if [ "$UNAME" = "Linux" ]; then\n    export LD_LIBRARY_PATH=',
        'if [ "$UNAME" = "Linux" ]; then\n    export SDL_VIDEO_DRIVER=wayland\n    export LD_LIBRARY_PATH=',
        1,
    )

content = re.sub(
    r'export SDL_VIDEO_DRIVER=.*',
    'export SDL_VIDEO_DRIVER=wayland',
    content,
)

with open(path, 'w') as f:
    f.write(content)
PY

chmod +x -- "$TARGET"