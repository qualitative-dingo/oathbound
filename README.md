# Oathbound

A 3D survival-crafting RPG built in **Godot 4** with GDScript. Explore a procedurally generated open world, harvest resources, craft gear, fight creatures, and build a base — solo or with friends via **Steam/LAN co-op multiplayer**.

## Art Direction

Oathbound targets a **low-poly, Valheim-inspired** visual style:

- **Textures:** Low-resolution (64-256px), nearest-neighbor filtering for a chunky pixelated look
- **Geometry:** Procedural meshes with deliberate low vertex counts — rocks, trees, terrain all favor readable silhouettes over smoothness
- **Colors:** Muted, earthy palettes with natural variation (per-instance tinting) rather than uniform flat colors
- **Environment:** Dense grass ground cover, slope-aware moss on rocks, subtle wind animation on foliage
- **Lighting:** Day/night cycle with sun arc, sky color gradients, and fog transitions. Minimal post-processing — depth comes from material work (normal maps, AO baked into shaders)

## Tech Stack

- **Engine:** Godot 4 (GDScript)
- **Rendering:** Forward+ with custom shaders (water, terrain, foliage wind, grass billboards, leaf billboards, rock moss, HUD bars)
- **World Gen:** Procedural zones with biomes, watershed rivers, noise-driven lakes, and caves
- **Networking:** ENetMultiplayerPeer (LAN) + GodotSteam (Steam lobbies/invites), RPCs, host-authoritative model
- **Assets:** 32x32 pixel art icons, GLB/GLTF 3D models (Tripo + Meshy AI pipelines)

## Project Structure

```
Oathbound/
├── scripts/
│   ├── autoloads/          # Singletons (ItemDatabase, Inventory, SaveManager, NetworkManager, SteamManager, WaterSystem, etc.)
│   ├── player/             # Player controller, combat, building, HUD, inventory UI, workbench UI, skill system
│   ├── creatures/          # Creature AI (host-authoritative), fish behavior
│   ├── items/              # LootDrop (host-authoritative pickup, 60s despawn)
│   ├── network/            # WorldStateSync, ChatManager
│   ├── world/              # WorldGenerator, ZonePopulator, CaveGenerator, VillageGenerator, DayNightCycle
│   ├── combat/             # CombatController, DamageSystem
│   ├── building/           # Player-built structures
│   ├── interactables/      # Workstations, chests, harvestable resources
│   ├── debug/              # Debug panel (Esc key toggle)
│   └── data/               # Biome data, workstation data
├── textures/
│   └── items/              # 32x32 pixel art icons (all items)
├── models/                 # 3D models (player, armor, creatures, village assets)
├── scenes/                 # Game scenes, UI
└── shaders/                # Terrain, water, foliage, grass, bar HUD, creature rendering
```

### Key Files

| File | Purpose |
|------|---------|
| `player/player_controller.gd` | Main player logic (~10k+ lines): movement, combat, animations, HUD, weapons, bow, inventory, crafting, minimap, map, chest UI |
| `player/player_combat.gd` | Combat logic (attacks, damage, affix processing) |
| `player/player_inventory_ui.gd` | Inventory UI, crafting grid, tooltips |
| `player/player_workbench_ui.gd` | Workbench UI (category tabs, star tiers, building tab) |
| `player/player_building.gd` | Building system (placement, snapping, ghost preview, cost checks) |
| `world/world_generator.gd` | Terrain generation, zone loading/unloading, watershed rivers, biomes, floating origin |
| `world/zone_populator.gd` | Object spawning (trees, rocks, grass, creatures), procedural meshes |
| `world/village_generator.gd` | Abandoned village generation (huts, chests, hero assets) |
| `world/day_night_cycle.gd` | Sun arc, sky colors, ambient light, fog across day/night |
| `creatures/creature_ai.gd` | Creature behavior, HP, animations, floating UI, death, status effects |
| `autoloads/item_database.gd` | Item definitions, star IDs, crafting, affix registry + roll ranges |
| `autoloads/save_manager.gd` | Save/load, settings persistence, item ID migration |
| `autoloads/network_manager.gd` | Host/join, player spawn/despawn, chest sharing, Steam integration |
| `network/world_state_sync.gd` | World mutations, creature sync, loot replication, damage routing |

## AI Agent MCP Access

AI agents have direct tool access to these MCP servers:

- **Godot Editor MCP** (`user-godot-*`): Full read/write access to the running editor and game — editor control, scene tree, 3D spatial info, animations, resources, input injection, and Godot docs lookup. Use `get_log_messages`/`get_debug_output` for console output, `screenshot_game` for visual state, `get_errors`/`get_stack_trace` for crash info.
- **PixelLab MCP** (`user-pixellab-*`): AI pixel art generation — characters, tilesets, map objects. Async jobs.
- **Meshy AI MCP** (`user-meshy-*`): 3D model generation — text-to-3D, image-to-3D, rigging, animation. Async tasks.
- **Gemini Image MCP** (`user-gemini-image-*`): AI image generation, editing, compositing, style transfer.

## World Generation

### Zone System
- Circular map (~10,000 unit radius) divided into 64x64 unit zones (`ZONE_SIZE`)
- Zones load/unload around the player; ~25 zones active at once (5x5 grid)
- Terrain mesh: 33x33 vertices per zone (2m spacing), height from layered `FastNoiseLite`
- **Floating origin** keeps scene coordinates near (0,0,0) for GPU performance — shifts every 512 units of travel

### Rivers & Water
- **Watershed rivers** using D8 flow accumulation on a 48m grid. Accumulation above threshold carves terrain below `WATER_LEVEL` (0.0). Depth ranges 1.5-8m with noise-based bank widening for natural shapes.
- **Lakes** generated from offset continental noise
- **Global water plane** follows the player; custom shader with Fresnel reflections, depth tinting, foam, and 4-wave displacement
- **River banks** blend to muddy terrain via vertex color blue channel
- **Microbiome `riverside`** spawns more rocks and bushes along rivers

### Biomes & Microbiomes
- **Hearthlands** — the single playable biome. Ocean is the world-edge boundary.
- **Microbiomes** within Hearthlands: `meadow`, `forest`, `birch_forest`, `hills`, `riverside` — driven by noise + flow accumulation. Each adjusts tree/rock/bush/enemy spawn counts and tree species distribution.
- Biome materials use custom terrain shaders with triplanar mapping, clay paths, mud patches, and slope-based texture blending.

### Day/Night Cycle
- 20-minute real-time day cycle (`DAY_LENGTH_SECONDS = 1200`)
- Sun arc with gradient keyframes for energy, color, sky colors, fog, and ambient light
- Time range: 0.0 = midnight, 0.5 = noon

### Vegetation
- **Trees**: Procedural trunk meshes with root flare + buttress ridges (Oak, Birch, Pine, Willow, Palm). Billboard leaf canopies via MultiMesh.
- **Grass**: 8 varieties, dense clustering via noise-based density, ~300 instances per type per zone. No grass on dirt patches, paths, or river banks.
- **Saplings**: Smaller procedural trunks with billboard leaves.

## Combat System

Oathbound uses **context-based weapon switching** — the equipped weapon depends on interaction target:

| Action | Input | Weapon Slot |
|--------|-------|-------------|
| Attack enemies | Left-click on creature | **Melee** (sword) |
| Chop trees | Left-click on tree | **Woodaxe** |
| Mine rocks | Left-click on rock | **Pick** (pickaxe) |
| Ranged attack | Hold right-click (bow draw) then left-click | **Ranged** (bow) |
| Block | Right-click (with shield) | **Shield** |

- **Damage variance:** All weapon damage has +-30% random range per hit
- **Bow draw speed:** Base 1.2s. Rapid Draw (+15%) and Quickdraw (+33%) stack additively
- **Fall damage:** Landing with downward velocity > 12.0 units/s
- **Damage numbers:** WoW-style floating combat text with camera-relative spread (simultaneous hits fan out)
- **Multiplayer combat:** Player damage to creatures routed through `WorldStateSync.request_creature_damage(zone_x, zone_z, creature_idx, amount, source_peer)` to avoid node-path mismatches

## Equipment Slots

Players have 8 equipment slots organized into two categories:

### Tools
| Slot | Purpose | Ghost Icon |
|------|---------|------------|
| Woodaxe | Chopping trees | Stone axe |
| Pick | Mining rocks/ore | Stone pickaxe |

### Equipment
| Slot | Purpose | Ghost Icon |
|------|---------|------------|
| Melee | Sword combat vs creatures | Stone sword |
| Ranged | Bow combat | Crude bow |
| Shield | Blocking damage | Wood shield |
| Chest | Body armor | Leather vest |
| Legs | Leg armor | Leather pants |
| Boots | Boot armor | Leather boots |

**Gear does not stack** — each gear piece (weapons, armor) gets a unique instance ID (`item_id#N`) in inventory to support unique affixes on same-type items.

## Starting Gear

New characters spawn with "Terrible" quality gear (grey text) in all slots:

| Slot | Item | Flavor |
|------|------|--------|
| Woodaxe | Splintered Hatchet | "Half the handle is missing and the head is held on by sheer stubbornness." |
| Melee | Rusty Butter Knife | "It's a flat piece of scrap metal that couldn't cut warm butter." |
| Ranged | Sad Twig & String | "Arrows fired from this may actually apologize to their targets on impact." |
| Pick | Blunt Rock-Poker | "Rocks openly mock you when you swing this. Even pebbles feel safe." |
| Chest | Moth-Eaten Rag | "The moths that lived in it left for somewhere nicer." |
| Legs | Questionable Trousers | "They smell like regret and old cheese." |
| Boots | Soggy Foot Wraps | "They provide the same protection as a strongly-worded letter." |

## Items & Crafting

### Materials

| Material | Source |
|----------|--------|
| Wood | Trees |
| Stone | Rocks |
| Flint | Rocks (chance) |
| Leather | Creatures |
| Bone | Creatures |
| Meat | Creatures |
| Resin | Trees (chance) |
| Feather | Birds |
| Copper Ore | Cave veins |
| Raw Fish | Fishing |
| Thick Hide | Grizzly, Lion, Minotaur (rare) |
| Fang | Wolf, Lion, Hawk (rare) |
| Ancient Bone | Orc Brute, Cyclops, Minotaur (rare) |
| Ember Stone | Fire Imp (rare) |
| Frost Shard | Frost Wraith (rare) |
| Gold | Humanoid creatures (rare, no stars) |
| Amber | Trees (Ancient Grove axe affix, 20% chance) |
| Living Wood | Trees (Ancient Grove axe affix, 20% chance) |
| Fairy Dust | Trees (Ancient Grove axe affix, 20% chance) |
| Gemstone | Rocks (Deep Earth pickaxe affix, 20% chance) |

### Weapon Tiers

**Axes** (Woodcutting): Splintered Hatchet (6 dmg) -> Stone Axe (18) -> Flint Axe (15) -> Iron Axe (30) -> Steel Axe (45)

**Swords** (Melee): Rusty Butter Knife (5) -> Stone Sword (18) -> Bronze Sword (25) -> Iron Sword (40) -> Steel Sword (55)

**Bows** (Ranged): Sad Twig & String (3) -> Crude Bow (12) -> Hunting Bow (20) -> War Bow (30) -> Longbow (40)

**Pickaxes** (Mining): Blunt Rock-Poker (4) -> Stone Pickaxe (8) -> Bronze Pickaxe (14) -> Iron Pickaxe (20) -> Steel Pickaxe (28)

**Maces** (Heavy Melee): Stone Mace (22/35kb) -> Bronze Mace (35/50kb) -> Iron Mace (45/55kb) -> Steel Mace (60/65kb)

### Armor Tiers

**Chest**: Moth-Eaten Rag (1) -> Leather Vest (5) -> Chain Chest (10) -> Iron Chest (18) -> Steel Chest (28)

**Legs**: Questionable Trousers (0.5) -> Leather Pants (3) -> Chain Legs (7) -> Iron Legs (12) -> Steel Legs (20)

**Boots**: Soggy Foot Wraps (0.5) -> Leather Boots (2) -> Chain Boots (5) -> Iron Boots (8) -> Steel Boots (14)

**Shields**: Wood Shield (10) -> Reinforced Shield (15) -> Bronze Shield (22) -> Iron Kite Shield (30) -> Steel Tower Shield (40)

### Crafting Stations

| Station | Examples |
|---------|----------|
| **Hand** | Stone Axe, Hammer, Torch |
| **Workbench** | Most weapons, armor, arrows, raft |
| **Forge** | Metal weapons/armor (iron, steel tier) |
| **Stonecutter** | Stone building pieces |
| **Artisan Table** | Decorative items |
| **Galdr Table** | Magical items |
| **Black Forge** | Endgame crafting |

**Auto-trash**: The workbench has an auto-trash threshold — crafted items at or below a rarity are instantly destroyed (not dropped on ground).

**Non-equipment crafting** always consumes only 0-star materials.

## Star / Rarity System

Items can roll 0-5 stars, affecting stats and enabling affixes:

| Stars | Rarity | Drop Weight | Affixes |
|-------|--------|-------------|---------|
| 0 | Common | 82.0% | 0 |
| 1 | Uncommon | 10.9% | 0 |
| 2 | Rare | 4.0% | 1 |
| 3 | Epic | 2.0% | 2 |
| 4 | Legendary | 0.8% | 3 |
| 5 | Mythical | 0.3% | 5 |

**Stat scaling per star:** Damage +15%, Armor +25%, Knockback +10%, Range +5%.

**Composite ID format:** `"base_id:stars:affix1@roll1,affix2@roll2"` (e.g. `"stone_sword:3:windfury@73,lifesteal@45"`). The `@roll` is an int 0-100 encoding the affix's magnitude within its min/max range. `parse_star_id()` / `make_star_id()` handle encoding/decoding. Instance suffixes (`#N`) are stripped before parsing.

## Affix System

Equipment with 2+ stars rolls random affixes from a pool specific to their item type. Each affix has a roll range (min-max) determining its magnitude. Tier 2 affixes have half the roll weight.

### Axe Affixes (9)
Lumberjack (+40% wood), Deep Cut (-1 hit to fell), Bark Stripper (25% bonus resin), Double Yield (10% double wood), Timber Cleave (hit 3 trees), Frenzied Chop (25% windfury), Master Woodsman (+2 star rerolls), Rapid Chop (+12% speed), Ancient Grove (20% rare materials)

### Pickaxe Affixes (10)
Prospector (+40% stone), Vein Finder (30% bonus ore), Frenzied Mining (25% windfury), Stone Breaker (-1 hit), Efficient Miner (-20% stamina), Rich Vein (10% double stone), Master Miner (+2 star rerolls), Quick Strike (+12% speed), Ore Seeker (+30% copper), Deep Earth (20% rare materials)

### Sword Affixes (18)
Windfury (30% extra attacks), Lifesteal (8% heal), Firebrand (15% fire damage), Frostbite (20% slow), Venomous (12% poison), Stunning Blow (8% stun), Executioner (+30% to low HP), Berserker (+1% per 2% missing HP), Sharpened (+10% crit), Savage (+40% crit damage), Rapid Strikes (+12% speed), Cleaving (wider arc), Momentum (+4% per hit), Reaching (+20% range), Chain Lightning (10% arc), Bane (8% double damage), Siphon (+3 stamina/hit), Runic (12% AoE)

### Bow Affixes (12)
Precision (+20% headshot), Multishot (20% 2 arrows), Piercing (pierce first target), Sniper (+25% at range), Rapid Draw (+15% draw speed), Poison Tip (poison), Frost Arrow (slow), Explosive (10% AoE), Steady Aim (+12% crit while still), Quiver Mastery (15% bonus arrow), Heatseeking (homing), Quickdraw (+33% draw speed)

### Armor Affixes
**Chest (10):** Vitality (+15 HP), Fortified (+8% DR), Iron Skin (8% negate), Thorns (15% reflect), Second Wind (heal at 20% HP), Undying (revive on death), Bulwark (+3 armor), Regenerator (+1 HP/s), Guardian (better block), Battle Hardened (+5% DR per nearby enemy)

**Legs (10):** Endurance (+20 stamina), Resilience (+25% stam regen), Steadfast (knockback immune), Thick Skinned (first hit -30%), Last Stand (+25% DR at low HP), Fleet (-25% sprint cost), Rejuvenation (+30% HP regen), Quick Recovery (faster regen start), Lucky (+5% rare drops), Tenacity (can't be slowed below 60%)

**Boots (10):** Swiftness (+10% speed), Aquatic (+30% swim), Warmth (-40% swim stamina), Featherfall (-50% fall damage), Evasion (5% dodge), Adrenaline (speed on kill), Sure-Footed (no slope penalty), Light Step (-30% fall damage), Trailblazer (+15% water speed), Nimble (+8% dodge while sprinting)

**Shield (10):** Shield Wall (+15% block), Retaliation (+30% after block), Fortress (+5 armor), Deflection (15% deflect projectiles), Steadfast Guard (no block stamina), Aegis (10% absorb shield), Stalwart (-30% knockback), Rally Cry (+2 HP/s), Shield Bash (25% stun on block), Unbreakable (100% block at low HP)

## Creatures

| Creature | Pipeline | Scale | Notable Loot |
|----------|----------|-------|-------------|
| Boar | Meshy | 800x | Meat, Leather, Bone |
| Grizzly Bear | Meshy | 462x | Meat, Leather, Thick Hide, Fang |
| Lion | Meshy | 280x | Meat, Leather, Thick Hide, Fang |
| Wolf | — | — | Meat, Leather, Fang |
| Goblin | Tripo | 2x | Bone, Gold |
| Orc Brute | Tripo | 3.5x | Bone, Ancient Bone, Gold |
| Cyclops | Tripo | 5x | Bone, Ancient Bone, Gold |
| Minotaur | Tripo | 4.5x | Thick Hide, Ancient Bone, Gold |
| Fire Imp | — | — | Ember Stone, Gold |
| Frost Wraith | — | — | Frost Shard, Gold |

HP and damage scale with stars: `base * (1.0 + stars * 0.4)`.

### 3D Model Pipelines

**Meshy AI models** (Grizzly, Boar, Lion, Horse): Exported at tiny unit scale (need 280-800x in Godot). Materials work out of the box. Single animation per model. Face -Z forward.

**Tripo models** (Cyclops, Minotaur, Orc Brute, Goblin, Player): Normal unit scale (2-5x in Godot). **Materials are broken on import** — must use `material_override` with basecolor JPG. NlaTrack-based animations renamed from generic Blender names. Forward direction varies per model.

### Creature AI
- States: IDLE, WANDER, CHASE, ATTACK, with evade behavior on leash
- Combat timer keeps creatures engaged for 8s after dealing/receiving damage
- Retaliation: any hit provokes chase regardless of distance
- Status effects: slow, stun, poison (all using max duration on reapply)
- Distance-based sleep: creatures >100m from player skip full `_physics_process`

## Building System

### Building Pieces
| Piece | Cost | Notes |
|-------|------|-------|
| Wood Wall | 4 wood | 3m wide, textured `wood_planks.png` |
| Wood Floor | 3 wood | 3m x 3m square |
| Wood Stair | 6 wood | 6-step procedural mesh with per-step collision |
| Stone Wall | 6 stone | Textured `cobblestone.png` |
| Stone Floor | 4 stone | Textured `cobblestone.png` |
| Thatch Roof 45/26 | 4 wood, 2 leather | Angled/shallow roof pieces |
| Workbench | 6 wood | Required for mid-tier crafting |
| Chest | 4 wood, 2 copper_ore | Storage container |
| Bed | 8 wood, 4 leather | Respawn point |
| Campfire | 3 wood, 2 stone | Animated fire + light |
| Torch Post | 2 wood, 1 resin | Standing torch with point light |
| Raft | 12 wood, 4 leather | Water vehicle |

### Build Mode
- Mouse-based placement via camera raycast (max 12 units)
- Scroll wheel rotates; Ctrl+Scroll adjusts height
- Snap points connect walls, floors, and roofs automatically
- Vegetation cleared in building footprint
- **Step-up climbing**: Player can walk onto floors/stairs without jumping (0.35m step height)

### Abandoned Villages
- 12% chance per hearthlands zone; forced village near spawn at (20, 20)
- 6-12 huts per village using the same building components as player structures (salvageable)
- Each hut has a chance to contain a chest with starred gear (guaranteed minimum 1 chest per village)
- Hero centerpiece at village center (Meshy-generated GLB or procedural fallback)

## Multiplayer Architecture

### Overview
LAN co-op (Valheim-style) where one player hosts and others join over local network or Steam. Host-authoritative — clients manage their own input/camera/UI.

### Connection Flow
1. Host starts `ENetMultiplayerPeer` on port 7777 (or Steam lobby)
2. Client connects, receives world seed + name via RPC
3. Client generates deterministic terrain from seed
4. Host creates player nodes for both sides via `_rpc_create_player`
5. `MultiplayerSynchronizer` replicates position, rotation, animation, equipment at ~20Hz

### Sync Architecture

**Deterministic (no sync needed):** Terrain, zone population, villages, caves — same seed = same world. Changes to generation code are automatically multiplayer-safe.

**Runtime mutations (sync required):**
- Object destruction (trees, rocks) via `WorldStateSync._destroyed_objects`
- Building placement via `WorldStateSync.record_building_placed()`
- Chest contents via host-authoritative RPCs
- Creature damage via `request_creature_damage` RPC (zone coords + creature index)
- Loot drops via host spawn + `_spawn_loot_replicated` RPC
- Loot pickup via `request_pickup` → host grants to first requester

### Known Multiplayer Gotchas
1. **Never RPC to dynamically generated nodes** — route through scene-defined singletons using stable identifiers
2. **`MultiplayerSpawner` can silently fail** — player replication uses direct RPCs instead
3. **Attack animations must update broadcast variables** (`_gltf_playing_clip` / `_gltf_playing_speed`)
4. **Remote player bars need explicit `_update_floating_bars(delta)` calls**
5. **Dropped items must go through WorldStateSync** — locally creating `LootDrop` is invisible to peers
6. **Steam App ID 480** (Spacewar) limits "Join Game" from Steam friends list — use in-game overlay invites or LAN join

### Save System
- **Host** auto-saves full game state every 10 seconds
- **Clients** auto-save their own inventory/stats to a `lan_client` save file
- Health/stamina reset to max on session start
- Settings (volume, display mode, resolution) persist to `user://settings.json`

## Performance

### Floating Origin
Severe FPS degradation at large world coordinates on Apple M4 (Metal 4.0). Solution: floating origin re-centers the scene around the player when scene-pos exceeds 512 units. All systems (zones, saves, multiplayer sync, shaders, portals) use `origin_shift` for coordinate conversion.

### Zone Lifecycle (3-Stage Pipeline)
| Stage | Thread | Cost |
|-------|--------|------|
| Build | WorkerThreadPool | ~15ms (hidden) — noise + BVH construction |
| Mesh setup | Main thread, frame N | ~2ms — GPU upload, collision assignment |
| Populate | Main thread, frame N+1 | ~5-10ms — spawn trees, rocks, creatures, grass |

### Key Optimizations
- **MultiMeshInstance3D** for grass and leaf canopies (thousands of instances, single draw call)
- **Material caching** — shared leaf/grass/creature materials prevent draw call multiplication
- **Object pooling** (`zone_pool.gd`) — zone nodes recycled, not freed (prevents server-side RID leaks)
- **Terrain caching** — mesh arrays + collision shapes cached per zone (revisits skip all computation)
- **Distance culling** — structures hidden beyond 50 units; grass hidden beyond 1.5 zones; saplings beyond 2 zones
- **Creature distance sleep** — creatures >100m skip `_physics_process` (wake on approach or combat)
- **Group query caching** — `get_nodes_in_group()` results cached per-frame or per-timer, never in per-entity loops
- **Debug print gating** — `const _DEBUG_LOG := false` guards on all print calls; zero console output in normal play
- **Loot despawn** — dropped items auto-delete after 60 seconds; max 150 loot nodes enforced

### Collision Layers
| Layer | Purpose |
|-------|---------|
| 1 | Terrain |
| 2 | Player |
| 4 | Interactables |
| 8 | Buildings |
| 16 | Creatures |
| 32 | Items |

Do NOT add player to creature `collision_mask` — causes creatures to ride up player capsule and float.

## Mounts

Wild horses spawn with 0-5 star levels. Mount speed: `2.0x + 0.2x per star` (5-star = 3.0x). Horses have their own stamina pool (base 100 + 20/star). Jumping disabled while mounted. Force dismount on entering water.

## Inventory & UI

- **Grid inventory** with drag-and-drop reordering
- **Right-click hold to equip** (0.5s progress bar)
- **Shift+right-click to drop** items on the ground (synced via WorldStateSync)
- **Equipment bar** organized into Tools (Woodaxe, Pick) and Equipment (Melee, Ranged, Shield, Chest, Legs, Boots) categories with dark panel background
- **Tooltips** show item name, type, stats, quality, stars, and affixes with rolled values
- **Floating bars** (shader-driven): HP (red), Stamina (blue), Horse Stamina (amber), Swim Fatigue (blue, appears at 75% warning)

## Progression

Currently tier 1 only. Defeating the Stag King drops `antler_pick` and advances to tier 2. Boss powers: 5-min active buff, 20-min cooldown (Stag King: +30% movement speed).

## Dev Mode & Cheat Codes

**Dev Mode**: Toggle in pause menu — free crafting and building (skip material checks). Not persisted across sessions.

**Chat commands** (Enter to open, type command, Enter):
| Command | Effect |
|---------|--------|
| `rosebud` | Spawns Oathbreaker — 5-star god sword with all 18 sword affixes |
| `oathgun` | Spawns Oathgun — 5-star god bow with all 12 bow affixes |

## Known Gotchas

- **Godot renames NlaTrack dots to underscores**: `NlaTrack.001` in GLB becomes `NlaTrack_001` in AnimationPlayer
- **No idle animation for Cyclops/Brute/Minotaur**: `speed_scale = 0.0` freezes walk pose when idle
- **`BILLBOARD_FIXED_SIZE` does not exist** in Godot 4 — use `BILLBOARD_ENABLED` with `fixed_size = true`
- **Death animations must not have root motion stripped** — `_strip_root_motion()` skips any animation containing "death"
- **UI container children must use `free()`, not `queue_free()`** — deferred frees cause crashes in `Container::_child_minsize_changed` during rapid refresh
- **`call_deferred` for UI refresh from signal handlers** — prevents "Attempted to free a locked object" errors
- **`global_position` requires scene tree membership** — always `add_child()` first, then set `global_position`
- **GDScript type inference**: Dictionary values are `Variant` — use explicit types (`var x: float = ...`) instead of `:=` for arithmetic on dictionary access
- **`_DEBUG_LOG` pattern**: Set `const _DEBUG_LOG := true` at top of any script to re-enable verbose logging
- **`VillageGenerator` must be accessed via `preload()`** — bare class name resolution can fail for files created outside the editor
- **RNG sequence sensitivity**: Adding/removing any `rng.*()` call in generation loops shifts all subsequent values for that seed
