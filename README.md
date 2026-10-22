 <div align="center">

# Games Scripts

**Linux gaming scripts for Wayland and Hyprland**

<p>
  <a href="https://www.kernel.org/"><img src="https://img.shields.io/badge/platform-Linux-FCC624?logo=linux&logoColor=black" alt="Platform"></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white" alt="Shell"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/PHNexus/games-scripts?color=blue" alt="License"></a>
  <a href="https://github.com/PHNexus/games-scripts/commits/main"><img src="https://img.shields.io/github/last-commit/PHNexus/games-scripts?color=green" alt="Last Commit"></a>
</p>

Automatically detect game installations and apply launch tweaks, configuration patches, and performance-related settings. No manual path hunting.

</div>

---

## Scripts

| Game | Script | Description |
|---|---|---|
| **Albion Online** | [`albion.sh`](albion.sh) | Sets up Gamescope and GameMode, matches display settings, and bridges the Wayland/X11 clipboard. |
| **Counter-Strike 2** | [`cs2.sh`](cs2.sh) | Patches the game launcher, enables the Wayland SDL backend, and restores executable permissions. |
| **The Elder Scrolls Online** | [`eso.sh`](eso.sh) | Updates Proton configuration settings to match the display refresh rate. |
| **eFootball** | [`eFootball.sh`](eFootball.sh) | Creates a Gamescope wrapper and automatically updates Steam launch options. |

## Requirements

- **OS:** Arch Linux recommended; `pacman` is required by `albion.sh`.
- **Steam:** Native or Flatpak.
- **Display:** Hyprland recommended; available `xrandr` or DRM fallbacks depend on the script.
- **Albion Online:** Required dependencies are installed automatically by `albion.sh`.
- **eFootball:** Python 3 is required to update Steam launch options.

## Installation

```bash
git clone --depth=1 https://github.com/PHNexus/games-scripts.git
cd games-scripts
chmod +x *.sh
```

## Usage

Run the script for your game:

```bash
./albion.sh
./cs2.sh
./eso.sh
./efootball-auto.sh
```

