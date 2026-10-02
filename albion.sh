#!/bin/bash
# Script de Automação e Otimização do Albion Online (Arch + Hyprland + NVIDIA)

set -e

echo "=== [1/3] Instalando pacotes necessários ==="
sudo pacman -S --needed --noconfirm gamescope mangohud gamemode xclip wl-clipboard

echo "=== [2/3] Localizando pasta do jogo ==="
DEFAULT_PATH="$HOME/.steam/steam/steamapps/common/Albion Online"

if [ -d "$DEFAULT_PATH" ]; then
    TARGET_DIR="$DEFAULT_PATH"
else
    echo "Pasta padrão da Steam não encontrada."
    read -p "Digite o caminho completo da pasta do Albion Online: " TARGET_DIR
fi

mkdir -p "$TARGET_DIR"
TARGET_SCRIPT="$TARGET_DIR/albion.sh"

echo "=== [3/3] Gerando o script albion.sh otimizado ==="
cat << 'EOF' > "$TARGET_SCRIPT"
#!/bin/sh
# Albion Online Launcher - NVIDIA / Wayland / Gamescope / MangoHud

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

# ── Configurações do Qt (Originais do Launcher) ─────────────────
export QT_QPA_PLATFORM_PLUGIN_PATH="$SCRIPTPATH/launcher/plugins/platforms"
export QT_PLUGIN_PATH="$SCRIPTPATH/launcher/plugins/"
export QT_QPA_PLATFORM="xcb;eglfs"
export __GL_GlslUseCollapsedArrays=0

# ── NVIDIA Offloading & Vulkan ───────────────────────────────────
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export VK_LOADER_DEBUG=none
export mesa_glthread=true

# ── MangoHud ─────────────────────────────────────────────────────
export MANGOHUD=1
export MANGOHUD_CONFIG="gpu_stats,gpu_temp,gpu_power,cpu_stats,cpu_temp,ram,vram,fps,frametime,frame_timing,position=top-left,font_size=20"

# ── XKB / Wayland ────────────────────────────────────────────────
export XKB_DEFAULT_LAYOUT=es
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

# ── Ponte de Copiar/Colar (Wayland para XWayland) ───────────────
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

# ── Execução com Gamescope, MangoHud e GameMode ──────────────────
exec gamescope \
  -W 1920 -H 1080 -r 180 \
  --backend wayland \
  --expose-wayland \
  --force-grab-cursor \
  --adaptive-sync \
  --immediate-flips \
  -f \
  -- \
  mangohud gamemoderun "$SCRIPTPATH/launcher/Albion-Online" "--no-sandbox" "$@"
EOF

chmod +x "$TARGET_SCRIPT"

echo ""
echo "✅ Sucesso! O Albion Online foi otimizado em: $TARGET_SCRIPT"