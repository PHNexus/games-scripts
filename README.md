 <!-- Badges -->
[![Platform](https://img.shields.io/badge/platform-Linux-FCC624?logo=linux&logoColor=black)](https://www.kernel.org/)
[![Shell](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/github/license/PHNexus/games-scripts?color=blue)](https://github.com/PHNexus/games-scripts/blob/main/LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/PHNexus/games-scripts?color=green)](https://github.com/PHNexus/games-scripts/commits/main)
[![Repo Size](https://img.shields.io/github/repo-size/PHNexus/games-scripts)](https://github.com/PHNexus/games-scripts)
[![Created At](https://img.shields.io/github/created-at/PHNexus/games-scripts?color=blue&label=created)](https://github.com/PHNexus/games-scripts)

---

## Games Scripts

A collection of game-specific shell scripts and launch configurations focused on Linux gaming, performance, and custom launch behavior.

These are personal scripts developed and maintained for my own gaming setup.

## Scripts

| Game | Script | Description |
|---|---|---|
| Albion Online | [`albion.sh`](albion.sh) | Custom Gamescope launch configuration with MangoHud, GameMode, NVIDIA environment settings, and clipboard integration. |
| Counter-Strike 2 | [`cs2.sh`](cs2.sh) | Steam launch script for the Linux game runtime environment. |
| The Elder Scrolls Online | [`eso.sh`](eso.sh) | Custom launch script for The Elder Scrolls Online. |

## Features

- **Gamescope** — Custom resolution, fullscreen, scaling, and display behavior where configured.
- **Performance monitoring** — MangoHud integration in the Albion Online launcher.
- **GameMode** — Performance optimization integration for Albion Online.
- **NVIDIA configuration** — GPU-related environment variables for the Albion Online launcher.
- **Clipboard integration** — Clipboard bridging between Wayland and X11 for Albion Online.
- **Game-specific launch behavior** — Separate scripts for each supported game.

Features vary by script and game.

## Requirements

Requirements depend on the script you want to use.

| Dependency | Purpose |
|---|---|
| Bash | Run the shell scripts |
| Steam | Required for Steam-managed games and their runtime |
| Gamescope | Nested compositor and display configuration |
| MangoHud | Performance monitoring overlay |
| GameMode | Game performance management |
| `wl-clipboard` | Wayland clipboard integration |
| `xclip` | X11 clipboard integration |

Not every dependency is required by every script. Review the individual script before running it.

## Usage

Clone the repository:

```bash
git clone --depth=1 https://github.com/PHNexus/games-scripts.git
cd games-scripts
```

Make the scripts executable:

```bash
chmod +x albion.sh cs2.sh eso.sh
```

### Albion Online

```bash
./albion.sh
```

The script installs its listed system dependencies through `pacman` and places a customized launcher in the detected Albion Online installation directory. If the default installation path is not found, it asks for the path.

### Counter-Strike 2

```bash
./cs2.sh
```

Launches Counter-Strike 2 using the script's configured Linux game runtime environment. Review the script before running it and follow any game-specific setup instructions.

### The Elder Scrolls Online

```bash
./eso.sh
```

Runs the custom launch script for The Elder Scrolls Online. Review the script for its expected environment, configuration, and usage before running it.

## Notes

- Scripts are game-specific and may depend on your distribution, desktop environment, GPU, and installation paths.
- Some configurations are tailored to a particular system and may require adjustments on other setups.
- Review scripts before executing them, especially those that install packages or modify game launch behavior.
- This repository is a personal collection, not a universal game optimization solution.

## License

See [LICENSE](LICENSE) for licensing information.
