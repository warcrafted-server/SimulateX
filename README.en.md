*Leer esto en otros idiomas: [Español](README.md).*

# SimulateX

**SimulateX** is an advanced, visually striking, and modern in-game assistant built for **World of Warcraft: Wrath of the Lich King (3.3.5a, Build 12340)** with strict support for the **Spanish client (esES)**.

The project is designed to completely transform how players evaluate their gear, offering real and accurate performance metrics instead of abstract or static stat calculations.

## Key Features

*   **Real Data Per Spec and Level:** Each stat's weight comes from real combat simulations per specialization (WowSims engine), with level scaling calculated from the server's own tables: no generic approximations.
*   **Tooltip Upgrade Indicators:** Instantly see the actual performance delta when hovering over any piece of gear (e.g., `Feral (tu spec) +3.2 %`), with one line per specialization of your class.
*   **Visual Gear Comparator:** Put two items (drag them in or Shift-click) and compare them against each other, or against what you're wearing, with a breakdown of which stat makes the difference. Each item shows its stats, level, type and requirements; rings and trinkets are compared against both of the ones you're wearing, and it tells you which one to swap. The same window has a Settings tab. Available via `/simulatex comparar`, a button on the character sheet, the minimap, or the **wcdpanel** bar.
*   **Shopping List (Upgrades tab):** For each slot, the best upgrades for your spec and where to get them: boss and difficulty, chest, dungeon creatures, world rares, vendor (with its cost in gold, emblems or honor) or quest, with the drop chance. It also works while levelling and for items you've never seen. After you open a profession window once, it marks recipes you already know how to craft. Filters in the settings: upgrades per slot, heroic modes, 25-player raids, vendors, quests, faction and minimum drop chance.
*   **Recommended Enchants:** Upgrades recommends enchants for your gear at level 80, scored with your character's weights; you can toggle it in the settings.
*   **Talents and Glyphs:** The Talents tab shows all three trees, simulated variants and their results, including Level 3, alongside the major and minor glyphs for each build.
*   **Relic Scoring:** Idols, totems, librams and sigils are simulation-scored for Druids, Shamans, Paladins and Death Knights in tooltips, the comparator and Upgrades.
*   **More Accurate Scoring:** At level 80, hit, expertise and armor penetration stop contributing past their caps. Ideal gems and socket bonuses are included, and tooltips identify items that are BiS for a phase.
*   **Set Bonuses:** A notice shows when a gear change activates or removes a set bonus.
*   **More Upgrade Details:** Sources include their zone or instance; professions and reward bags are also shown. The list filters by armor type.
*   **Vendor:** Grey items can be sold automatically using a whitelist, repairs can be automatic, and tooltips can show the sale price. Each option can be configured.
*   **Settings:** The options panel scrolls to make all settings accessible, and the gear comparator includes a Settings tab.
*   **Modern UI Aesthetics:** A smooth and responsive user interface, moving away from the clunky and outdated look of classic addons.

## Commands

*   `/simulatex`: restore automatic build detection.
*   `/simulatex bolsas`: list the items in your bags that improve your gear for the active specialization.
*   `/simulatex comparar`: open or close the gear comparator.
*   `/simulatex debug [link]`: show debug details for the linked item; without a link, it asks you to paste one.
*   `/simulatex nivel <n>`: force a level for the current session; without a valid number, disable the forced level.
*   `/simulatex <build>`: force the specified build; `/simulatex` with no arguments restores automatic detection.
*   `/simulatexconfig`: open the SimulateX options.

Project: [portal.warcrafted.com](https://portal.warcrafted.com/).

## Repository Structure

This repository strictly contains the game-ready source code for the Addon:

```text
Addon/
├── SimulateX/              # Main addon: logic, UI, and shared data (all classes)
│   ├── SimulateX.toc
│   ├── SimulateX.lua
│   ├── SimulateX_DB.lua
│   ├── Data/                # Shared data only (levels, item types, item stats)
│   └── UI/
├── SimulateX_<Class>/       # One sub-addon per class (LoadOnDemand): that
│                             # class's simulation and talent data. SimulateX
│                             # loads only your own class's addon at login.
└── SimulateX_Origenes/      # Where each item comes from (LoadOnDemand):
                              # loaded when you open the Upgrades tab.
```

*Note: All automated data extraction tools, external calculation engines, and synchronization scripts run locally and privately to keep the repository focused purely on in-game performance.*

## Installation

1. Download the contents of the `Addon/` folder.
2. Copy **every** folder starting with `SimulateX` (`SimulateX`, `SimulateX_Origenes` and each `SimulateX_<Class>`) into `World of Warcraft/Interface/AddOns/`. The addon only loads your own class's data into memory; the other classes' sub-addons stay inactive even if installed.
3. Make sure the addon is enabled in your character selection screen and launch the game.

## Credits and License

The performance statistics (DPS/HPS) used by this addon are generated through
offline simulations run with the open-source [**WowSims**](https://github.com/wowsims/wotlk)
engine (MIT license). SimulateX does not redistribute its source code; it only
uses its simulation results as a data source for the addon.

This project is distributed under the **GPL-3.0** license. See the
[LICENSE](LICENSE) file for details.
