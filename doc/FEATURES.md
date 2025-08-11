# Vein Miner Mod — Features

A dynamic and configurable Minetest mod for intelligent vein mining, region scanning, and light-aware digging.

## Implemented Features

### Core Functionality
- Async-safe dig start using `register_on_dignode`.
- Automatic multi-node mining based on player-configurable scan sizes.
- Queue system for dig positions.
- Target node group support (`stone`, `ore`, etc.).
- Per-player mining mode config (`small` or `large`).
- Wielded item check for node diggability.
- Light-scanning logic integrated into mining queue.
- Support for liquids and falling nodes.
- Teleportation queue to move player around the dig area.

### Node Behavior & Filtering
- Sticky node detection.
- Liquid filtering (`water`, `lava`).
- Graceful fallback for unexpected nodes.
- Dynamic target node groups via `mine_only_groups`.

### Inventory Management
- Waits until empty main inventory slot is available before digging.

### Light & Region Scanning
- AABB-based region tracking and volume threshold.
- Compacting and merging scan regions.
- Light placement notifications for missing light coverage.
- Drawn regions (via particles) for light scanning boundaries.

### Player Configuration & Chat Commands
- `mining_mode`: Change mining range.
- `mine`: Adjust scanning layer range.
- `toggle_light_debug`: Toggle light scan debug view.
- `yaw`: View/set player look angle.
- `pos`: Show player coordinates.

### Node & Item Definitions
- Lit cobble node variants (`lit_cobble_1` to `lit_cobble_14`).
- Crafting recipes for lit cobble variants.
- Tool range override.
