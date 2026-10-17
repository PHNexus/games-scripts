[![Platform](https://img.shields.io/badge/platform-Linux-FCC624?logo=linux&logoColor=black)](https://www.kernel.org/)
[![Shell](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/github/license/PHNexus/games-scripts?color=blue)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/PHNexus/games-scripts?color=green)](https://github.com/PHNexus/games-scripts/commits/main)

---

## Games Scripts

Linux scripts that **auto-detect** game installations and **patch or wrap** them for a better experience on Wayland + Hyprland. No manual path hunting, no editing config files by hand.

## Scripts

| Game | Script | What it does |
|---|---|---|
| **Albion Online** | [`albion.sh`](albion.sh) | Finds the Steam install and replaces the game/launcher binaries with wrappers that:<br>• Auto-detect monitor resolution + refresh rate (`hyprctl`, fallback to `xrandr`)<br>• Launch the game through **Gamescope** (fullscreen, matched resolution/refresh, stretch scaling) + **GameMode**<br>• Bridge the clipboard between Wayland and X11 (`wl-paste` → `xclip`)<br>• Inject Qt / NVIDIA / GL / Vulkan env vars and strip fullscreen prefs from Unity's `prefs` file |
| **Counter-Strike 2** | [`cs2.sh`](cs2.sh) | Locates CS2's `game/cs2.sh` inside the Steam library and patches it to:<br>• Remove the "sniper runtime" check that aborts outside Steam<br>• Force `SDL_VIDEO_DRIVER=wayland`<br>• Restore the executable bit |
| **The Elder Scrolls Online** | [`eso.sh`](eso.sh) | Finds ESO's `UserSettings.txt` inside the Steam Proton prefix and rewrites it to:<br>• Set `BACKGROUND_FPS_LIMIT` to your monitor's max refresh rate<br>• Enable `USE_BACKGROUND_FPS_LIMIT`<br>• Set `MinFrameTime.2` to `1 / Hz` (uncaps the framerate to match the display) |
| **eFootball** | [`efootball-auto.sh`](efootball-auto.sh) | Locates eFootball inside the Steam library and fully automates setup by:<br>• Auto-detecting monitor resolution and max refresh rate (`hyprctl` or DRM/sysfs)<br>• Creating a **Gamescope** wrapper script (fullscreen, stretch scaling, matched resolution/refresh) combined with **GameMode**<br>• Automatically injecting the wrapper into Steam's `localconfig.vdf` launch options for the game |

## Requirements

- Arch Linux (or any distro with `pacman` for `albion.sh`)
- Steam (native or Flatpak)
- Hyprland (for `hyprctl`-based auto-detection; `xrandr`/`drm` fallbacks exist)
- `jq`, `gamescope`, `gamemode`, `xclip`, `wl-clipboard` (installed automatically by `albion.sh`)
- Python 3 (required by `efootball-auto.sh` to update Steam launch options automatically)

## Usage

```bash
git clone --depth=1 [https://github.com/PHNexus/games-scripts.git](https://github.com/PHNexus/games-scripts.git)
cd games-scripts
chmod +x *.sh
