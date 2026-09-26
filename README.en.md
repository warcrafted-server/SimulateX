*Leer esto en otros idiomas: [Español](README.md).*

# SimulateX

**SimulateX** is an advanced, visually striking, and modern in-game assistant built for **World of Warcraft: Wrath of the Lich King (3.3.5a, Build 12340)** with strict support for the **Spanish client (esES)**.

The project is designed to completely transform how players evaluate their gear, offering real and accurate performance metrics instead of abstract or static stat calculations.

## Key Features

*   **Tooltip Upgrade Indicators:** Instantly see the actual performance delta when hovering over any piece of gear (e.g., `+145 DPS`).
*   **Visual Gear Comparator:** A modern, clean, and interactive interface to compare items side-by-side, analyzing the overall impact on your character.
*   **Upgrade Guide (Shopping List):** A visual guide showing you exactly which items to look for to upgrade your character and which raid bosses, dungeons, or quartermasters drop them.
*   **Modern UI Aesthetics:** A smooth and responsive user interface, moving away from the clunky and outdated look of classic addons.

## Repository Structure

This repository strictly contains the game-ready source code for the Addon:

```text
Addon/
├── SimulateX.toc        # Native game index and configuration
├── SimulateX.lua        # Main interface and tooltip logic
├── SimulateX_DB.lua     # Local optimized performance database
└── UI/                  # Interface layouts, frames, and visual elements
```

*Note: All automated data extraction tools, external calculation engines, and synchronization scripts run locally and privately to keep the repository focused purely on in-game performance.*

## Installation

1. Download the contents of the `Addon/` folder.
2. Copy the internal `SimulateX` folder into your game directory: `World of Warcraft/Interface/AddOns/`.
3. Make sure the addon is enabled in your character selection screen and launch the game.

## Credits and License

The performance statistics (DPS/HPS) used by this addon are generated through
offline simulations run with the open-source [**WowSims**](https://github.com/wowsims/wotlk)
engine (MIT license). SimulateX does not redistribute its source code; it only
uses its simulation results as a data source for the addon.

This project is distributed under the **GPL-3.0** license. See the
[LICENSE](LICENSE) file for details.
