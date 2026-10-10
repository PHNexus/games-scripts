#!/bin/sh
SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "$SCRIPT")"
cd "$SCRIPTPATH" || exit 1

export QT_QPA_PLATFORM_PLUGIN_PATH="$SCRIPTPATH/launcher/plugins/platforms"
export QT_PLUGIN_PATH="$SCRIPTPATH/launcher/plugins/"
export QT_QPA_PLATFORM="xcb;eglfs"
export __GL_GlslUseCollapsedArrays=0

export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export VK_LOADER_DEBUG=none
export mesa_glthread=true

export MANGOHUD=1
export MANGOHUD_CONFIG="gpu_stats,gpu_temp,gpu_power,cpu_stats,cpu_temp,ram,vram,fps,frametime,frame_timing,position=top-left,font_size=20"

export XKB_DEFAULT_LAYOUT=es
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

_clipboard_bridge() {
  last=""
  while sleep 0.5; do
    current="$(wl-paste --no-newline 2>/dev/null)"
    if [ "$current" != "$last" ] && [ -n "$current" ]; then
      last="$current"
      printf '%s' "$current" | DISPLAY=:1 xclip -selection clipboard 2>/dev/null
      printf '%s' "$current" | DISPLAY=:1 xclip -selection primary 2>/dev/null
    fi
  done
}
_clipboard_bridge &
BRIDGE_PID=$!
trap 'kill $BRIDGE_PID 2>/dev/null' EXIT

exec gamescope \
  -w 1920 -h 1080 \
  -W 1920 -H 1080 \
  -r 180 \
  -f \
  --fullscreen-state \
  -S stretch \
  --expose-wayland \
  --force-grab-cursor \
  --adaptive-sync \
  --immediate-flips \
  -- \
  gamemoderun "$SCRIPTPATH/launcher/Albion-Online" "--no-sandbox"