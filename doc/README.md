# Vein Miner Mod for Minetest

## Overview

Vein Miner is a powerful mining tool mod that lets players dig entire veins or clusters of nodes automatically. It intelligently manages mining regions, supports light-aware scanning, and handles liquids and falling nodes gracefully.

---

## Features

- Supports configurable mining modes with small and large scan sizes.
- Manages dig queue with position hashing to avoid duplicates.
- Handles sticky nodes and liquids properly to avoid unwanted breaks.
- Supports node group targeting and filtering.
- Integrates light scanning to detect and notify about lighting gaps.
- Player-specific mining mode configuration and chat commands.
- Teleports players safely around the mining region to enable seamless mining.
- Includes lit cobble variants with crafting recipes.
- Debug and utility commands like `yaw` and `pos`.

---

## Installation

1. Place the `vein_miner` mod folder into your Minetest `mods` directory.
2. Enable the mod in your world’s configuration (`world.mt`).
3. Restart Minetest or your server.

---

## Configuration

Configuration is handled per-player and is mostly accessible via chat commands. Key configurable options include:

- **Mining Mode**: Determines the scan size.
  - `small`: Scans 8x8x8 nodes.
  - `large`: Scans 32x32x32 nodes (only available above Y = -32.5).
- **Scan Layers**: Control vertical scanning layers with `/mine` command.
- **Light Debugging**: Toggle visualization of light scan regions with `/toggle_light_debug`.

Advanced configurations (e.g., custom node groups) require editing the mod’s `config.lua` file.

---

## Chat Commands

- `/mining_mode [small|large]`
  Change the mining range mode. Defaults to `small`.

- `/mine [get|set|up|down|reset] [min|max|both] [value]`
  Get or set the vertical scanning layers.

- `/toggle_light_debug`
  Toggle debug visualization for light scan regions.

- `/yaw [get|set <degrees>]`
  View or set your player's yaw (horizontal look angle).

- `/pos`
  Show your current position with high precision.

---

## Usage Tips

- Ensure you have an empty slot in your main inventory to allow vein mining to proceed.
- Use `/mining_mode large` for mining large veins deep underground.
- Use the `toggle_light_debug` command to visualize areas that need light placement.
- When digging near liquids or falling nodes, the mod handles those safely without breaking your vein mine.
- Watch the chat for status messages about your inventory or mining state.

---

## Troubleshooting

- **Mining doesn’t start?**
  Check if your wielded tool supports mining the target node.

- **Mining stops unexpectedly?**
  Ensure you have free inventory space. The mod pauses until there is a free slot.

- **Light gaps not showing?**
  Enable light debug mode with `/toggle_light_debug` and watch for particle outlines.

- **Mod doesn’t respond to commands?**
  Verify you have the `vein_miner_config` privilege for commands requiring config access.

---

## Planned Features

- HUD feedback for mining mode, dig queue, and lighting status.
- Sneak-tap toggle to switch mining modes without commands.
- Visual indicators for dig bounds and light gaps.
- Cooldowns and sound feedback.
- Better stuck detection and automatic light placement.
- Support for more modded nodes and mesecon integration.

---

## License

MIT License

---

## Contact

For issues or suggestions, please open an issue or contribute via pull requests.
