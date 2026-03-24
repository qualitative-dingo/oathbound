# Oathbound — Quick Reference for AI Agents

This file gets an AI agent up to speed on the Oathbound Godot 4 project.
All game code lives under `/Users/andreattar/Documents/Games/Oathbound/`.

**Multiplayer**: LAN co-op for up to 4 players (ENet, host-authoritative). See [LAN Multiplayer](#lan-multiplayer) section.
**Single biome**: Currently only Hearthlands (with microbiome variety). More biomes planned for later.

---

## AI Agent MCP Access

You have direct tool access to these MCP servers — **do NOT ask the user** for information you can retrieve yourself.

### Godot Editor MCP (`user-godot-*` tools)
Full read/write access to the running Godot editor and game:
- **Editor control**: `godot-editor` — `get_state`, `get_selection`, `select`, `run`, `stop`, `screenshot_game`, `screenshot_editor`, `get_log_messages`, `get_debug_output`, `get_errors`, `get_stack_trace`, `get_performance`
- **Scene tree**: `godot-node` — `get_properties`, `find`, `create`, `update`, `delete`, `reparent`, `attach_script`, `detach_script`, `connect_signal`
- **Scenes**: `godot-scene` — `open`, `save`, `create`
- **3D spatial**: `godot-scene3d` — `get_spatial_info`, `get_bounds`
- **Animations**: `godot-animation` — list players, get info/details/keyframes, play/stop/seek, create/edit
- **Resources**: `godot-resource` — `get_info` (SpriteFrames, TileSet, Material, etc.)
- **Project**: `godot-project` — `get_info`, `get_settings`, `addon_status`
- **TileMaps**: `godot-tilemap` — list layers, get/set cells, convert coords
- **GridMaps**: `godot-gridmap` — list, get/set cells
- **Input injection**: `godot-input` — `get_map`, `sequence`, `type_text` (for testing)
- **Docs**: `godot-godot_docs` — `fetch_class`, `fetch_page` (Godot engine documentation)

**Key point**: When the game is running, use `get_log_messages` or `get_debug_output` to read console output, `screenshot_game` to see the running game, and `get_errors`/`get_stack_trace` for crash info. Never ask the user to paste Godot output.

### PixelLab MCP (`user-pixellab-*` tools)
AI pixel art generation for game assets:
- Characters with directional views + animations (humanoid and quadruped)
- Isometric tiles, top-down Wang tilesets, sidescroller tilesets
- Pro tiles (hex, iso, square, octagon with style matching)
- Map objects with style-matching inpainting
- All ops are async — create returns a job ID, poll with `get_*` to retrieve results

### Meshy AI MCP (`user-meshy-*` tools)
3D model generation and processing:
- Text-to-3D and image-to-3D model generation
- Rigging, animation, remeshing, text-to-texture
- Async tasks with streaming status updates

### Gemini Image MCP (`user-gemini-image-*` tools)
AI image generation and editing:
- `generate_image` — text-to-image
- `edit_image` — modify existing images with prompts
- `compose_images` — combine multiple images
- `style_transfer` — apply style from one image to another

---

## Project Structure (key files)

```
scripts/
  player/player_controller.gd    — Player movement, combat, animations, HUD, weapons, bow,
                                  inventory, crafting, minimap, map, chest UI (main 10k+ line file)
  player/player_hud.gd            — HUD construction (pause menu, hotbar, minimap, map), split from controller
  player/player_combat.gd          — Player combat logic (attacks, damage, affix processing, affix_val() helper)
  player/player_inventory_ui.gd    — Inventory UI, crafting grid, tooltips
  player/player_workbench_ui.gd    — Workbench UI (category tabs, star tiers, craft preview, building tab)
  player/player_building.gd        — Building system (placement, snapping, ghost preview, cost checks)
  player/interaction_manager.gd   — E-key interaction logic
  player/player_interaction.gd    — Chest UI (open/close, slots, deposit/withdraw, tooltips)
  player/skill_system.gd          — Skill XP and leveling
  creatures/creature_ai.gd        — All creature behavior, HP, animations, floating UI, death, status effects
  world/world_generator.gd        — Terrain generation, zone loading/unloading, biome determination, height noise
  world/zone_populator.gd         — Creature/resource spawning, model paths, scales, yaw offsets, stats
  world/art_unifier.gd            — Fog/ambient transitions per biome (loads BiomeData .tres files)
  items/loot_drop.gd              — Ground loot pickups, nameplate UI, star system, pickup text
  ui/main_menu.gd                 — Main menu, character/world selection, delete confirmation
  ui/damage_number.gd             — Floating Label3D that rises and fades (DamageNumber class)
  data/biome_data.gd              — BiomeData Resource class (identity, environment, terrain, creatures, boss)
  progression/progression_manager.gd — Boss progression tiers, boss powers, station unlocks
  autoloads/audio_manager.gd      — SFX and music playback (pooled AudioStreamPlayer/3D)
  autoloads/item_database.gd      — Item definitions, rarity colors, star IDs, crafting, star-quality crafting,
                                    affix registry + roll ranges. dev_mode bypass for free crafting.
  autoloads/save_manager.gd       — Save/load, item ID migration (adds @roll to old affix IDs)
  autoloads/inventory.gd          — Inventory slots, equipment, star-aware consume/preview, star-capped helpers.
                                    Also holds `dev_mode` flag (bool) for free build/craft.
  autoloads/game_events.gd        — Signal bus (item_picked_up, inventory_changed, biome_entered, etc.)
scenes/world/test_world.tscn      — Main world scene (lighting, shadows)
resources/biomes/*.tres           — BiomeData resources (hearthlands.tres, etc.)
models/
  player/Lowpolyvikingwithaxe/    — Tripo barbarian player model
  creatures/<Name>/               — Per-creature GLB + basecolor JPG
  weapons/<type>/                 — Weapon GLBs + textures
shaders/
  bar_hud.gdshader                 — Player floating health/stamina bar shader (SDF rounded rect, gradient, glow, pulse)
  creature_shadow.gdshader         — Creature shadow
  creature_sprite.gdshader         — Creature sprite rendering
  terrain.gdshader                 — Terrain rendering
  water.gdshader                   — Water surface
  wind_foliage.gdshader            — Wind effect on foliage
textures/items/                    — Item/building icons (32×32 pixel art, generated via PixelLab)
audio/sfx/                         — All sound effects (.wav)
audio/music/                       — Background music
```

---

## Two Model Pipelines

### Meshy AI models (Grizzly Bear, Boar, Lion, Horse)
- Export at TINY unit scale → need 280–800x scale in Godot
- Materials usually work out of the box (StandardMaterial3D with albedo)
- Animation names: `"Armature|Unreal Take|baselayer"` (single animation per model)
- Face Godot's default -Z forward → no yaw offset needed

### Tripo models (Cyclops, Minotaur, Orc Brute, Goblin, Player Barbarian)
- Export at NORMAL unit scale → need 2–5x scale in Godot
- **Materials are BROKEN on import** → must use `material_override` with basecolor JPG
  - `_fix_model_materials()` in `zone_populator.gd` handles this
  - If a new Tripo creature is invisible: add its basecolor JPG path to `_creature_texture_paths`
- Animation names in GLB: `"NlaTrack"`, `"NlaTrack.001"`, etc. (generic Blender NLA names)
- **Godot renames dots to underscores**: `NlaTrack.001` → `NlaTrack_001` in AnimationPlayer
- Forward direction varies per model — use `_creature_yaw_offsets` / `_player_yaw_offset`
- Animation order varies per model — must be mapped explicitly per `creature_kind`
- Godot 4 may add a "RESET" animation — NlaTrack detection filters by `"NlaTrack" in name`
- **No Blockbench models** are used in this project

---

## World Generation & Biomes

### Current state: single biome
The world currently has **one playable biome — Hearthlands**. Ocean is kept as the world-edge
boundary (zones beyond 90% of `world_radius` or low altitude). All other biome code (Thornwood,
Scorched Steppe) has been stripped out; it will be re-added later as new biomes are introduced.

### Zone system (`world_generator.gd`)
- World is divided into `ZONE_SIZE`-unit square chunks, loaded/unloaded around the player
- `_determine_biome(zone)` returns `&"hearthlands"` or `&"ocean"` based on distance/altitude
- `_determine_microbiome(zone)` adds variety within Hearthlands: `meadow`, `forest`,
  `birch_forest`, `hills`, `riverside`, or `none` (driven by noise functions)
- Each zone gets a terrain mesh with biome-specific material from `_biome_materials`
- `_generate_zone(coord)` builds mesh → applies material → calls `ZonePopulator.populate_zone()`
- Height is global (`get_height_at(x, z)`) using layered `FastNoiseLite`; not per-biome
- Zone biome is cached in `_zone_biome_cache` (Dictionary keyed by `Vector2i`)

### Biome signals
- `biome_at_player_changed(biome_id)` — emitted by `WorldGenerator` when host zone changes
- `GameEvents.biome_entered(biome_name)` — global signal bus mirror
- `art_unifier.gd` listens to `biome_at_player_changed` and tweens fog/ambient from `BiomeData .tres`

### Microbiome effects on spawning (`zone_populator.gd`)
- `_get_microbiome_counts(biome, micro)` overrides tree/rock/bush/enemy counts per microbiome
- `_pick_tree_name()` uses microbiome to weight Oak vs Birch distribution
- Grass is always Hearthlands-style green (no biome variants currently)

### BiomeData resource (`data/biome_data.gd`)
Resource class with exports for identity, environment (fog, ambient), terrain hints,
vegetation/creature tables, boss info, and progression tier. `.tres` files live in
`res://resources/biomes/`. Currently only `hearthlands.tres` is used at runtime (by `art_unifier`
for fog/ambient tweens). The resource format is forward-compatible for adding new biomes later.

---

## Progression System (`progression_manager.gd`)

### Current state: tier 1 only
- `TIER_DATA` contains a single entry: tier 1 / Hearthlands / The Stag King boss
- Defeating the Stag King drops `antler_pick` and advances to tier 2 (unlocking everything)
- Additional tiers (with new biomes and bosses) will be added later

### Boss powers
- `activate_boss_power(boss_id)` — 5 min active buff, 20 min cooldown
- Stag King power: "Movement speed +30% for 5 min"
- Only one power active at a time; tracked via `active_boss_power` and timer

### Station gating
- `is_station_unlocked(station_type)` checks if the tier granting that station has been reached
- Stations not in `TIER_DATA` (e.g. workbench) are always available (returns `true`)

---

## Dev Mode

A **dev mode toggle** exists on the pause screen for testing.

### How it works
- `Inventory.dev_mode` (bool, default `false`) — global flag on the Inventory autoload
- Pause menu has a "Dev Mode (free build & craft)" checkbox that toggles it
- When enabled:
  - `ItemDatabase.can_craft()` always returns `true` (skip material checks)
  - `ItemDatabase.craft_item()` and `craft_item_at()` skip material consumption
  - Building placement in `player_building.gd` skips cost checks and material deduction
  - Workbench placeable crafting skips material removal
  - All UI `can_afford` checks return `true`; cost text shows green instead of red
- State is **not** persisted across sessions (resets to off on game restart)

---

## Player Character (Tripo Barbarian)

- **Model**: `res://models/player/Lowpolyvikingwithaxe/barbarian+3d+model.glb`
- **Texture**: `barbarian+3d+model_barbarian3dmodel_basecolor.jpg` (applied via `_apply_tripo_player_texture`)
- **Scale**: 4.0
- **Rotation**: `-PI/2` offset via `_player_yaw_offset` (applied in `_rotate_model` and `_respawn`)
- External Mixamo animations are **SKIPPED** (`if not is_tripo_barbarian: _load_external_animations()`)
  because they target a different skeleton. Uses built-in NlaTracks only.
- **Jump velocity**: 9.9 (increased 20% from 8.25)
- **Gravity multiplier**: 2.34
- Armor baked into mesh — `_update_armor_visuals()` returns early when `_is_lowpoly_viking` is true

### Player NlaTrack mapping (`_rename_nla_tracks()` in `player_controller.gd`)

| Track | Renamed To | Used For |
|-------|-----------|----------|
| NlaTrack | sit | Mounted/sitting |
| NlaTrack.001 | chop | Axe attack (via "axe_swing" alias) |
| NlaTrack.002 | afraid | Hit react (via "hit_react" alias) |
| NlaTrack.003 | stand | Idle |
| NlaTrack.004 | walk | Walking |
| NlaTrack.005 | stand_alt | Idle variant |
| NlaTrack.006 | run | Running |
| NlaTrack.007 | kick | Unarmed attack, sword slash, alt attack |
| NlaTrack.008 | swim | Swimming |

### Player animation aliases (`_gltf_play()` aliases dict)

```
axe_swing   → ["chop", "axe_swing"]        speed: 4.0x
sword_slash → ["kick", "sword_slash"]        speed: 1.0x
punch       → ["kick", "punch"]             speed: 2.5x
punch_alt   → ["kick", "punch_alt"]          speed: 2.0x
kick        → (direct)                       speed: 2.0x
hit_react   → ["afraid", "hit_react"]        speed: 2.0x
idle        → ["stand", "idle"]
```

### Player attack flow
- `_start_attack_animation()` sets `_gltf_attack_anim` and `_gltf_attack_timer` per weapon class
- A whoosh sound (`arrow_swoosh`) plays on every melee swing via `AudioManager.play_sfx()` (non-positional)
- `_try_attack()` applies `rapid_strikes`/`rapid_chop`/`quick_strike` (rolled faster cooldown), `sharpened_edge`/`precision_strike` (rolled +dmg%), `reaching` (rolled +range%), and `efficient_miner` (rolled -stamina%) before scheduling resolve
- `_resolve_attack()` runs after `hit_delay` (0.18s or 0.30s for 2h), checks enemies + harvestables
  - Includes crit roll, affix damage modifiers, and post-hit affix procs (see affix ordering)
- **Harvestable hit cap**: Max 2 per swing (or 3 with `timber_cleave` axe affix), sorted by distance (closest first)
- Tree drops boosted by axe affixes: `lumberjack` (rolled 30-50%), `double_yield` (rolled 8-12% double), `bark_stripper` (rolled 20-30% resin)
- Rock drops boosted by pickaxe affixes: `prospector` (rolled 30-50% stone), `ore_seeker` (rolled 25-35% copper), `rich_vein` (rolled 8-12% double), `vein_finder` (rolled 25-35% bonus ore)
- `deep_cut` (axe) and `stone_breaker` (pickaxe) add +50% damage to trees/rocks respectively
- `sap_drinker` (axe) and `geologist` (pickaxe) heal +2 HP per resource hit
- Tree hit: plays `axe_chop` (non-positional); fists play `fist_hit_tree`
- Stone hit: plays `pickaxe_hit` (non-positional)
- All player combat audio uses `play_sfx()` (non-positional) for constant volume regardless of zoom
- **Player death guard**: `take_damage()` returns early if `current_health <= 0.0` (unless `undying` triggers)

### Double jump (`_handle_jump()` in `player_controller.gd`)
- Requires the `double_jump` boots affix (tier 2, rare)
- Tracked by `_double_jump_used: bool`, reset to `false` when `is_on_floor()`
- If airborne + has affix + not used yet: performs a second jump at **85%** of normal `jump_velocity`
- Only one extra jump per airborne period — cannot chain multiple double jumps

### Pickup radius
- Auto-pickup: 2.07 units
- E-key loot range: 3.45 units
- Interact distance: 4.0 units

---

## 3D Creatures

### Model inventory

| Creature | Pipeline | Path | Scale | Yaw Offset |
|----------|----------|------|-------|------------|
| Grizzly Bear | Meshy | `Grizzly Bear/` | 462 | — |
| Boar | Meshy | `Boar/` | 800 | — |
| Lion | Meshy | `Lion/` | 280 | — |
| Horse | Meshy | `Horse/` | 350 | — (mount) |
| Cyclops | Tripo | `Cyclops/` | 5.0 | -PI/2 |
| Minotaur | Tripo | `Minotaur/` | 4.5 | -PI/2 |
| Orc Brute | Tripo | `Orc Brute/` | 3.5 | -PI/2 |
| Goblin | Tripo | `Small Goblin/` | 2.0 | -PI/2 |

### Creature NlaTrack animation mappings (`_build_anim_map()` in `creature_ai.gd`)

Each creature has `creature_kind` (e.g. `&"goblin"`) which selects the correct mapping.

**Goblin** (5 tracks):
```
["walk", "run", "death", "attack", "idle"]
  NlaTrack=walk, 001=run, 002=death, 003=attack, 004=idle
```

**Cyclops / Orc Brute / Minotaur** (unified — 6 tracks):
```
["walk", "attack", "run", "attack", "attack", "death"]
  NlaTrack=walk, 001=punch1, 002=run, 003=punch2, 004=punch3, 005=death
```
All three humanoid Tripo creatures share the SAME mapping and yaw offset (-PI/2).
**No dedicated idle animation** — idle falls back to walk (NlaTrack). See animation speed
scaling below for how this is handled.

**Default** (Meshy AI models — keyword matching):
```
Keyword matching: idle/walk/run/attack/fly mapped by name substring
```

**Animation fallbacks** (applied after mapping):
- If "walk" not mapped → use "run"
- If "idle" not mapped → use "walk" → else use "run"

### Creature animation speed scaling (`_tick_3d_animation()`)

Creatures wander at 40% of their `move_speed`. Without speed scaling, the walk animation
cycles too fast relative to ground speed, making walk look like running.

- **Walk (wander)**: `speed_scale = flat_speed / move_speed` (clamped 0.25–1.0).
  Matches leg cycle to actual ground speed.
- **Run (chase)**: `speed_scale = 1.0` (full speed).
- **Idle (no dedicated idle track)**: When `idle` maps to the same track as `walk`
  (Cyclops/Brute/Minotaur), `speed_scale = 0.0` freezes the animation so the creature
  stands still. Creatures with a dedicated idle track (Goblin) play idle normally.
- **Attack**: `speed_scale = anim.length / attack_cooldown` so the full animation fits
  the attack window.

### Creature animation debugging

`_build_anim_map()` prints `[CREATURE] <name> anim_map=...` to the Godot log on spawn.
Godot logs are at `~/Library/Application Support/Godot/app_userdata/Oathbound/logs/godot.log`.

**IMPORTANT**: Godot 4 renames NlaTrack dots to underscores on import.
Raw GLB has `NlaTrack.001` → Godot AnimationPlayer has `NlaTrack_001`.
The `_build_anim_map()` filter checks `"NlaTrack" in name` which matches both formats.

### Creature attack system
- When a creature enters ATTACK state, `_attack_timer = attack_cooldown` (the full duration)
- Attack animation `speed_scale` is auto-set to `anim.length / attack_cooldown` so the full
  animation plays exactly within the attack window
- Damage is dealt at the **midpoint** (50%) of the attack animation via `_attack_hit_done` flag
- After the timer expires, creature transitions back to CHASE with `_attack_timer = 0`
- `_model_current_anim` is cleared on each new attack so the animation properly restarts

### Creature death
- Death animation plays from `_anim_map["death"]` if it exists
- Death animations are **excluded from root motion stripping** and set to `LOOP_NONE`
- `DESIRED_DEATH_TIME = 1.75` seconds (30% faster than original 2.5s)
- After the death animation finishes, `_explode_and_free()` creates a particle burst
  ("piñata explosion") and the creature is freed — no shrink-to-despawn
- If no death animation: falls over via rotation tween (legacy behavior)
- Flying creatures fall from sky first, then play ground death

### Creature HP bar
- Embedded directly inside the nameplate SubViewport (under the name text)
- Two `ColorRect` nodes: background (dark) and fill (green→yellow→red by %)
- Updated via `_update_hp_bar()` which resizes the fill rect and triggers `UPDATE_ONCE`
- Clamped: `current_health` cannot go below 0 (`maxf(current_health - amount, 0.0)`)

### Arrow hitbox
- `_compute_arrow_hitbox()` calculates visual AABB from model meshes at ready time
- Sets `arrow_hit_radius`, `arrow_hit_height`, `arrow_hit_y_offset` per creature
- Used by bow/arrow hit detection for accurate hit regions matching visual models

### Creature stats (set in `_creature_stats()` in `zone_populator.gd`)
- `creature_type` = `stats.sound` (used for sound selection: "boar", "bear", etc.)
- `creature_kind` = the spawn key (`&"grizzly"`, `&"goblin"`, etc.) — used for animation mapping

### UI height overrides
Some creatures need manual nameplate height overrides because `_estimate_model_top()` underestimates:
```gdscript
const _UI_HEIGHT_OVERRIDES := { &"grizzly": 2.0 }
```

### Drop tables (`_creature_loot_for()` in `zone_populator.gd`)
Each creature has a **normal** and a **rare** (super) drop table, returned as
`{ "normal": [...], "rare": [...] }`. Both are set on `creature_ai.gd` as
`loot_table` / `rare_loot_table` and forwarded to `LootDrop.spawn_loot()`.

**Normal table**: standard materials rolled every kill (leather, bone, meat, etc.).
Boosted by creature star level (+5% chance, +50% qty per star, rarity rerolls).

**Rare table**: low-chance high-value drops rolled independently after normal drops.
Star level gives +2% per star to each rare entry's base chance. Entries can set
`"no_stars": true` to always drop at 0★ (used for gold).

Humanoids (goblin, orc_brute, ghoul, fire_imp, frost_wraith, cyclops, minotaur)
drop **gold** from their rare table. Gold uses `"no_stars": true` and `stack_size: 999`.

Rare materials: `thick_hide` (bears, mama_bear, lion, moose, minotaur, mountain_goat),
`fang` (wolf, lion, tiger, hyena, grizzly, mama_bear, hawk), `ancient_bone` (orc_brute,
ghoul, cyclops, minotaur), `ember_stone` (fire_imp), `frost_shard` (frost_wraith).

Both `zone_populator.gd` and `cave_generator.gd` call `_creature_loot_for()` and set
`loot_table` + `rare_loot_table` on the creature. `_spawn_single_drop()` in `loot_drop.gd`
is the shared helper that creates individual `LootDrop` nodes for both normal and rare drops.

**Abandoned Villages** — `village_generator.gd` (static class, same pattern as `cave_generator.gd`).
Called from `zone_populator.gd` with 12% chance per hearthlands zone (`VILLAGE_CHANCE = 0.12`).
A forced village always spawns at `(20, 20)` in the `(0,0)` zone (near player spawn).

- **Huts**: 6–12 per village (`MIN_HUTS`/`MAX_HUTS`), spread in a ring at radius 17–34m from center
- **Variations**: 45 hut variations parameterized by footprint (`gx×gz` grid cells, each 3.6m),
  roof type (thatch_45, thatch_26, collapsed, none), material (wood/stone/mixed), floor, door
- **Renovatable buildings**: Village huts use the **same building components as player-built
  structures**. Each wall, floor, and roof section is its own `StaticBody3D` with proper `build_id`
  metadata (`wood_wall`, `stone_wall`, `wood_floor`, `stone_floor`, `thatch_roof_45`, etc.) in the
  `structures` group. Players can **salvage (remove) individual pieces** with a hammer and get
  half the materials back, then rebuild/renovate with their own building pieces.
- **80% minimum completeness**: Buildings randomly omit up to 20% of their components for an
  abandoned look, but are always at least 80% intact.
- **Hut anchor**: Each hut has a lightweight `Node3D` anchor with `footprint_radius` metadata
  (for tree/grass exclusion). The anchor is in the `structures` group but has no `build_id`,
  so the salvage system skips it. Individual building pieces are children of the anchor.
- **Wall openings**: Every hut always has at least one front wall removed (facing village center)
  as a doorway.
- **Collapsed roofs**: Roof debris scatters *outside* the hut footprint (leaning against exterior
  walls or lying on the ground nearby). Never placed flat on the hut floor. Each collapsed piece
  is its own salvageable `StaticBody3D` with `build_id = thatch_roof_26`.
- **Chests**: Each hut has a 1-in-3 chance (`CHEST_CHANCE = 0.333`) to contain a chest with basic
  materials + starred gear (1-5★). **Guaranteed minimum 1 chest per village** — if RNG produces
  zero chests, a fallback chest is placed in a random hut.
- **Hero centerpiece**: Meshy-generated GLB (stone statue, well, or broken cart) at village center.
  GLBs in `res://models/village/`. Falls back to procedural stone pillar if GLBs missing.

---

## Floating Nameplates (Creatures & Loot)

Both creatures and loot drops use **Label3D + Sprite3D** (no SubViewport) for nameplates:

1. Two `Label3D` nodes meet at a center origin point:
   - Name label (white, `HORIZONTAL_ALIGNMENT_RIGHT` when starred)
   - Stars label (rarity-colored, `HORIZONTAL_ALIGNMENT_LEFT`)
   - `font_size = 32`, `pixel_size = 0.00096`
   - `billboard = BaseMaterial3D.BILLBOARD_ENABLED` + `fixed_size = true`
   - `outline_size = 6`, black outline
2. A `Sprite3D` background panel behind the text:
   - Uses a shared 4×4 white `ImageTexture` tinted via `modulate`
   - Dark semi-transparent: `Color(0.05, 0.05, 0.08, 0.85)`
   - Sized via `pixel_size = bg_w / 4.0` and `scale.y = bg_h / bg_w`
   - **Creatures**: HP bar (two more `Sprite3D` nodes — bg + fill) sits below the panel
3. Text width estimated via `_estimate_text_width()` in `creature_ai.gd`:
   - Per-character width: `★ = 0.72`, space = 0.3, wide chars (mwMW) = 0.7, narrow (iltILT) = 0.3, default = 0.52
   - Background width: `text_w * 1.15 + pad_x * 2.0` (tightened from 1.55 to avoid excess right padding)
   - **Important**: Godot 4 does NOT have `BILLBOARD_FIXED_SIZE` — use `BILLBOARD_ENABLED`
     with `fixed_size = true`

### Visibility distances
- Creature names: 70 units show / 84 units hide (controlled via `_LABEL_SHOW_DIST` / `_LABEL_HIDE_DIST`)
- Loot names: 45 units (except stone: 9 units) — in `loot_drop.gd _process()`

---

## Player Floating Health & Stamina Bars

Shader-driven 3D bars floating above the player, built in `_setup_floating_bars()` in
`player_controller.gd`.

### Architecture
- A `Node3D` anchor (`_bar_anchor`) at `position.y = 4.2` above the player root
- Two `MeshInstance3D` quads (`_hp_bar`, `_stam_bar`) with `ShaderMaterial` using `res://shaders/bar_hud.gdshader`
- Anchor is manually billboarded toward the camera each frame (horizontal only)
- **No SubViewport** — the shader handles all visuals (rounded shape, gradient, glow, fill)

### Shader (`bar_hud.gdshader`)
- **Rounded-rect SDF** with capsule-like ends (`corner_r = half_h * 0.85`)
- **Fill ratio** uniform (0.0–1.0) controls left-to-right fill
- **Color gradient** from `color_a` (dark) to `color_b` (bright) along the fill
- **Glassy center highlight** for volumetric look
- **Glow rim** at the fill edge + outer bloom
- **Damage pulse** uniform flashes white, decayed by GDScript at `delta * 3.0`
- `render_mode unshaded, depth_test_disabled, shadows_disabled`

### Bar dimensions
- Health bar: 1.352 × 0.1014 (aspect ~13.3)
- Stamina bar: 1.352 × 0.0754 (gap = 0.031 below HP bar)

### Colors
- **Health**: dark crimson `(0.5, 0.05, 0.05)` → bright scarlet `(0.95, 0.15, 0.15)`
- **Stamina**: deep blue `(0.05, 0.2, 0.5)` → electric cyan `(0.15, 0.7, 0.9)`
- **Background**: dark `(0.06, 0.06, 0.08)` with subtle border ring

### Update flow
- `_update_floating_bars(delta)` called from `_physics_process()` — sets `fill_ratio` and
  `pulse` shader uniforms each frame. No quad scaling or position offset tricks.
- `_hp_pulse` set to `1.0` in `take_damage()`, decays to `0.0` via `move_toward`
- The anchor position is in player-local space (not model-local), so it doesn't rotate
  with the player model — it stays centered above the collision shape origin

### Variables
- `_bar_anchor: Node3D`, `_hp_bar: MeshInstance3D`, `_stam_bar: MeshInstance3D`
- `_hp_pulse: float`, `_bar_shader: Shader`

---

## Target HUD

Upper-center screen panel showing targeted creature's name, stars, HP, and HP bar.

- Built in `_build_target_hud()` in `player_controller.gd`
- Same dark panel style as floating nameplates
- HP bar: 330x20px, color changes green→yellow→red by percentage
- Appears when: camera raycast hits creature, player deals damage, or creature hits player
- Disappears after 5 seconds of no interaction
- Switches targets on new hover/hit
- Position: centered horizontally, y=50

---

## Audio System

### Sound groups (preloaded in `audio_manager.gd`)
- `axe_chop` (3 variants) — plays on wood hit
- `arrow_swoosh` (3 variants) — plays on every melee swing + bow shots
- `pickaxe_hit` (3 variants) — plays on stone hit
- `fist_hit_tree` — plays when punching trees unarmed
- `tree_fall`, `rock_fall`, `stone_rubble`, `wood_pickup`, `wood_thud`
- `player_hurt`, `player_death`, `boar_hurt`, `lion_hurt`, `lion_death`, `lion_roar`
- `bow_creak`, `arrow_fire`, `grass_step`, `horse_gallop`, etc.

### Two playback modes
- `AudioManager.play_sfx(group, volume_db, pitch_variance)` — **non-positional**, constant volume
  Used for: player combat sounds (whoosh, chop, pickaxe), pickup sounds
- `AudioManager.play_sfx_at(group, world_pos, volume_db, pitch_variance)` — **3D positional**
  Used for: ambient sounds, tree falls, distant events

---

## Star Rating System

- Creatures: 0–5 stars (82% 0★, 10.9% 1★, 4% 2★, 2% 3★, 0.8% 4★, 0.3% 5★)
- Per star: +40% HP/damage, +50% loot quantity, +5% normal drop chance, +2% rare drop chance, bonus rarity rerolls
- Stars shown with rarity color: white/green/blue/purple/orange/red
- Star level passed to `LootDrop.spawn_loot()` for scaling

### Pickup text (loot_drop.gd)
- 0-star items: single white DamageNumber label (`+2 Wood`)
- Starred items: two Label3D nodes meeting at a center origin point
  - Parent DamageNumber (right-aligned, white): `+2 Wood `
  - Child Label3D (left-aligned, rarity color): `★★`
  - Child inherits parent's position, scale, and fade automatically

---

## Equipment & Inventory

### Equipment slots
4 slots: `weapon`, `chest`, `legs`, `feet` (defined in `Inventory.EQUIPMENT_SLOTS`)

### Star-scaled equipment stats (`get_item()` in item_database.gd)
Starred equipment gets per-star multipliers applied at lookup time:
- Damage: +15% per ★
- Armor: +25% per ★
- Knockback: +10% per ★
- Range: +5% per ★

Base armor values: Leather Vest 5, Leather Pants 3, Leather Boots 2 (total 10 at 0★).

### Damage reduction formula (`take_damage()` in player_controller.gd)
- Blocking: base 70% DR (or rolled 75-85% with `guardian` affix)
- Armor: `final_amount *= max(1.0 - armor_value * 0.02, 0.2)` (caps at 80% reduction)
- Full 0★ leather set (10 armor) → 20% damage reduction
- Defensive affixes stack **additively** with an 85% hard cap:
  iron_will, thick_skinned, fortified, last_stand, battle_hardened, blocking — all rolled values
  summed into one DR percentage, then `clampf(total, 0.0, 0.85)`
- Iron Skin and Deflection are high-DR procs (rolled 80-90%) with proc chance rolls, NOT immunity

### Critical hits (`_resolve_attack()` / `_fire_bow()`)
- Base crit chance: `5.0 + dex * 0.5`%
- Base crit damage: `150.0 + str * 2.0`%
- Crit is rolled once per attack (melee) or once per shot (bow)
- `DamageNumber.spawn()` receives `is_crit` flag for visual feedback (yellow/enlarged text)

### Starting gear
`give_starting_gear()` in `inventory.gd` gives:
- Worn Axe (weapon), Leather Vest (chest), Leather Pants (legs), Leather Boots (feet)
- All auto-equipped

### Inventory grouping
- Materials/food/trophies are grouped by base_id (star variants collapsed into one stack display)
- Equipment items are shown individually (each star variant is a separate slot)
- `get_grouped_item_list()` handles the grouping logic

### Inventory size & scrolling
- Total inventory slots: 64 (8 columns × 8 rows)
- The inventory grid is wrapped in a `ScrollContainer` with `custom_minimum_size.y = 252`
- First 4 rows visible without scrolling; scroll down for the remaining 4 rows

### Inventory slot visuals
- Equipment with stars: slot border colored by rarity (`get_rarity_color(stars)`, 2px width)
- Equipped items: white "E" badge (top-left), no green border (removed to avoid confusion with rarity)

### Item types in `item_database.gd`
- `"material"` — stackable resources (wood, stone, leather, bone, meat, flint, resin, copper_ore,
  feather, raw_fish, gold, thick_hide, fang, ancient_bone, ember_stone, frost_shard)
- `"trophy"` — stackable trophies (trophy_boar, trophy_skeleton)
- `"weapon"` — equippable to weapon slot via `armor_slot: "weapon"` (starting_axe,
  stone_axe, stone_pickaxe, stone_sword, crude_bow, flint_axe,
  bronze_sword, bronze_mace, iron_sword)
- `"tool"` — usable from hotbar, NOT equippable via right-click, cannot gain stars
  (hammer, torch). Selected via hotbar number keys.
- `"armor"` — equippable to chest/legs/feet (leather_vest, leather_pants, leather_boots, wood_shield)
- `"ammo"` — consumed by bow (wood_arrow)
- `"placeable"` — enters build/placement mode (raft)

### Crafting text notification
When an item is crafted, a floating DamageNumber text spawns above the player (offset to camera right
so it isn't hidden by the crafting window). For starred items, name is white + stars in rarity color.
Function: `_spawn_craft_text(crafted_id)` in `player_controller.gd`.
If the workbench auto-discard filter is active and the crafted item is at/below the threshold,
`_spawn_discard_text(crafted_id)` is used instead (red "Discarded:" prefix).

### Star-aware operations (inventory.gd)
- `get_amount_any_star(base_id)` — total count across all star variants
- `has_item_any_star(base_id, amount)` — checks total
- `remove_item_any_star(base_id, amount)` — consumes lowest-star variants first (0★, 1★, 2★...)
- `preview_consume_any_star(base_id, amount)` — returns `{star_level: qty}` dict of what WOULD be consumed (without modifying inventory)

### Star-capped operations (inventory.gd) — used by quality tier crafting
- `get_amount_capped_star(base_id, max_star, min_star=0)` — total count of items with stars in `[min_star..max_star]`
- `has_item_capped_star(base_id, amount, max_star, min_star=0)` — boolean availability check within star range
- `preview_consume_capped_star(base_id, amount, max_star, min_star=0, prefer_low=false)` — previews consumption within the star range. When `prefer_low=true`, consumes **lowest star first** (0★→1★→...); otherwise **highest first** (max→min).
- `remove_item_capped_star(base_id, amount, max_star, min_star=0, prefer_low=false)` — actual consumption with the same direction control

---

## Crafting System

### Two crafting stations
1. **Hand crafting** (`crafting_station: "hand"`) — available in inventory panel (right side)
   - Stone Axe, Hammer, Torch
   - Always uses any available materials (no quality tier selector)
2. **Workbench** (`crafting_station: "workbench"`) — press E on placed workbench
   - Shows ALL recipes (both hand + workbench station items)
   - **Category tabs**: Tools (default), Equipment, Supplies, Building
   - Tools: hammer, torch (type `"tool"`, unstarrable)
   - Equipment: weapons/armor that can gain stars (stone axe, stone pickaxe, stone sword, crude bow, leather vest/pants/boots, wood shield)
   - Supplies: ammo (wood arrows)
   - Building: all BUILD_RECIPES items (walls, floors, roofs, furniture, etc.) — clicking "Build" enters placement mode

### Star-quality crafting (equipment only)
When crafting weapons or armor, the output star quality depends on input material quality:

1. `compute_recipe_star_avg(recipe, max_star, min_star, prefer_low)` calculates the weighted average star of materials that would be consumed (returns float, e.g. 2.75)
2. `get_crafting_probabilities(avg_quality)` generates a weighted probability distribution across star tiers 0–5:
   - **Distance rule**: `rawWeight = max(0, 2.0 - abs(avg - tier))` — tiers more than 2 steps away have 0% chance
   - **Downward gravity**: tiers above avg get ×0.75 weight (harder to "level up")
   - **Tier hardening**: tiers with distance > 1.5 get ×0.5 weight (sharp reduction for extreme jumps)
   - Weights are normalized to sum to 1.0
3. `roll_crafting_star(avg_quality)` rolls a random float against the cumulative probability distribution

Example for avg 2.75: favors 2★ and 3★, small chance for 1★ and 4★, **0% for 0★ and 5★** (distance > 2.0).

Non-equipment items (arrows, etc.) always produce 0-star output.

### Craft preview system
The workbench has a **Preview toggle** ("👁 Preview" / "👁 Off") in the title bar next to the auto-discard button. Preview is **on by default** and only visible on the Equipment tab.

When Preview is ON:
- Equipment recipe buttons show "Preview" instead of "Craft"
- Clicking opens a **preview popup** (to the right of the workbench) showing:
  - Materials consumed — star-level breakdown per ingredient, color-coded by rarity
  - Average quality — float average of all consumed materials
  - Star chances — percentage per tier, color-coded
  - "Confirm Craft" and "Cancel" buttons
- The popup auto-closes when switching tabs, tiers, or closing the workbench

When Preview is OFF:
- Equipment recipe buttons show "Craft" and immediately craft (no popup)

State: `_workbench_preview_on` (bool, default true), `_workbench_preview_btn` (Button), `_workbench_preview_panel` (PanelContainer).

### Quality tier crafting (workbench only)

The workbench Equipment tab has a **Low / Medium / High** selector that controls which
star levels of materials are consumed when crafting weapons and armor:

- **Low** (`min=0, max=1, prefer_low=true`): Uses 0–1★ materials, consuming **lowest quality first** (0★ before 1★). Ideal for basic crafts.
- **Medium** (`min=1, max=3, prefer_low=false`): Uses 1–3★ materials only (ignores 0★), consuming **highest quality first** (3★→2★→1★). Good mid-tier option.
- **High** (`min=3, max=5, prefer_low=false`): Uses 3–5★ materials only (ignores 0–2★), consuming **highest quality first** (5★→4★→3★). Best chance at high-star gear.

Each tier has a **star floor** (minimum) and **ceiling** (maximum), plus a consumption direction.
This lets players precisely control which materials get used.

**Tools** (hammer, torch) always craft as "low" regardless of the selector — they
cannot gain stars. The selector is panel-wide but star config is resolved per item:
`eff_max/eff_min/eff_low` are set to the tier config only when `is_starrable` (weapon/armor).

The selector row also has a clickable **"ⓘ Material Quality"** info button that toggles an
explanatory tooltip panel describing each tier.

State: `_workbench_quality_tier` (String: "low"/"medium"/"high"), `_get_workbench_star_config()`
returns `{"min": int, "max": int, "prefer_low": bool}`. Tier buttons are color-coded: white (Low), blue (Medium), red (High).

Cost labels in the recipe list use `Inventory.get_amount_capped_star(id, max, min)` so the player sees
accurate material counts for the selected tier. Craft button disables via `can_craft(item_id, max, min)`.

### Key crafting functions (item_database.gd)
- `can_craft(item_id, max_star=5, min_star=0)` — checks if player has enough materials within star range
- `craft_item(item_id)` — hand crafting (uses any materials, includes star quality + affix rolling for 3+ star equipment)
- `craft_item_at(item_id, station, max_star=5, min_star=0, prefer_low=false)` — workbench crafting with quality tier support
- `compute_recipe_star_avg(recipe, max_star=5, min_star=0, prefer_low=false)` — weighted average star of materials via `preview_consume_capped_star`
- `get_crafting_probabilities(avg_material_quality)` — returns `Array[float]` of 6 probabilities (0–5★) using the distance-based weight system: `max(0, 2.0 - distance)` with downward gravity (×0.75 for tiers above avg) and tier hardening (×0.5 when distance > 1.5)
- `roll_crafting_star(avg_material_quality)` — rolls output star using `get_crafting_probabilities()`
- `get_hand_recipes()` — returns recipes with `crafting_station == "hand"`
- `get_workbench_recipes()` — returns recipes with station `"hand"` or `"workbench"`
- Affixes are rolled via `roll_affixes(crafted_stars, get_affix_slot(item_id))`, then magnitudes via
  `roll_affix_magnitudes(affixes)`, both encoded into the output ID via `make_star_id()`

---

## Equipment Affix System

### Overview
Items with 3+ stars gain random **affixes** when crafted or dropped. Affix count scales with rarity:
- 3★: 1 affix
- 4★: 2 affixes
- 5★: 3 affixes

Affixes are **weapon-specific** or **armor-slot-specific**. An axe gets axe (woodcutting) affixes,
a sword gets sword (combat) affixes, boots get movement affixes, etc.

Affixes are permanent, encoded in the item ID, and make each item unique. Two items with the
same base and stars but different affixes are distinct inventory entries.

### Item ID format
Affixes extend the composite ID with roll values: `base_id:stars:affix1@roll1,affix2@roll2`
(sorted alphabetically). The `@roll` is an integer 0–100 representing where the affix's
numeric value falls within its min/max range (0 = minimum, 100 = maximum).
Example: `stone_sword:4:lifesteal@73,rapid_strikes@42`. Items with 0-2★ keep `base_id:stars`.
Old saves without `@` in affix IDs get a fresh `randf()` roll on parse (backward compatible).

### Affix registry (`item_database.gd`)
- `AFFIXES` dictionary: ~88 entries keyed by StringName, each with `name`, `description`, `slot`, `tier`
- **Roll ranges**: Most numeric affixes also have `"min"`, `"max"`, `"fmt"`, `"pct"` fields:
  - `min`/`max`: the actual value range (e.g. `0.06` to `0.10` for Lifesteal's 6-10% heal)
  - `fmt`: printf format string for display (e.g. `"Heal for %.0f%% of damage dealt"`)
  - `pct`: if `true`, the display value is `val * 100` (converts 0.08 → "8%")
  - Affixes without `min`/`max` are binary (no variable magnitude, e.g. Cleaving, Steadfast)
- `slot` is the **specific** weapon class or armor slot: `"axe"`, `"pickaxe"`, `"sword"`, `"bow"`, `"mace"`, `"shield"`, `"chest"`, `"legs"`, `"feet"`
- `tier`: 1 (common) or 2 (rare, weighted 0.5x in rolling)
- `get_affix_slot(item_id)` — returns the affix pool key for an item (calls `get_weapon_class()` for weapons or reads `armor_slot` for armor)
- `roll_affixes(stars, affix_slot)` — weighted random selection without replacement from the matching pool
- `roll_affix_magnitudes(affixes)` — generates a `{affix_id: int(0-100)}` roll dictionary for each affix
- `_get_affix_pool(affix_slot)` — filters affixes by exact slot match
- `get_affix_data(affix_id)` — returns affix dictionary
- `get_affix_value(affix_id, roll, fallback)` — interpolates between min/max using `roll` (0.0–1.0 float). Returns `fallback` if affix has no min/max.
- `format_affix_description(affix_id, roll)` — returns a human-readable description with the rolled value (e.g. "+18% headshot damage"). Falls back to static `description` for non-numeric affixes.
- `make_star_id(base_id, stars, affixes, affix_rolls)` — creates composite ID with `@roll` encoding
- `parse_star_id(composite_id)` — returns `{"base_id", "stars", "affixes", "affix_rolls"}`. `affix_rolls` is `{affix_id: float(0.0-1.0)}`. Old IDs without `@` get `randf()` rolls.

### Axe affixes (10) — woodcutting themed
All numeric values below are rolled ranges (each item rolls independently within the range):
`lumberjack` (30-50% wood drops), `splitter` (trees fall 25-35% faster), `deep_cut` (+40-60% tree dmg),
`bark_stripper` (20-30% bonus resin), `double_yield` (8-12% double wood), `timber_cleave` (hit 3 trees per swing),
`sharpened_edge` (12-18% axe damage), `heavy_chop` (25-35% knockback), `rapid_chop` (10-14% faster swing),
`sap_drinker` (2-3 HP per tree chop)

### Pickaxe affixes (10) — mining themed
All numeric values are rolled ranges:
`prospector` (30-50% stone drops), `vein_finder` (25-35% bonus ore), `precision_strike` (12-18% pickaxe dmg),
`stone_breaker` (+40-60% rock dmg), `efficient_miner` (15-25% less stamina),
`rich_vein` (8-12% double stone), `heavy_swing` (25-35% knockback), `quick_strike` (10-14% faster swing),
`ore_seeker` (25-35% copper ore drops), `geologist` (2-3 HP per mining hit)

### Sword affixes (18) — melee combat themed
All numeric values are rolled ranges:
`windfury` (25-35% extra 2 attacks), `lifesteal` (6-10% heal), `firebrand` (12-18% fire bonus),
`frostbite` (15-25% slow), `venomous` (10-14% poison), `stunning_blow` (6-10% stun),
`executioner` (+25-35% to low HP), `berserker` (+dmg from missing HP, rolled scaling),
`sharpened` (+7-13% crit), `savage` (+30-50% crit dmg), `rapid_strikes` (10-14% faster),
`cleaving` (wider arc, binary), `momentum` (+3-5%/stack), `reaching` (+15-25% range),
`chain_lightning` (8-12% arc), `bane` (6-10% double dmg), `siphon` (+2-4 stam/hit),
`runic` (10-14% AoE)

### Bow affixes (10) — ranged combat themed
All numeric values are rolled ranges:
`precision` (+15-25% headshot dmg), `bouncing_shot` (28-38% chance arrow bounces to nearby enemy),
`sniper` (+20-30% dmg at long range), `rapid_draw` (12-18% faster draw), `poison_tip` (25-35% apply poison),
`frost_arrow` (30-40% slow target), `explosive` (8-12% AoE on impact), `steady_aim` (+9-15% crit while still),
`echoing_shot` (12-25% chance to fire a bonus arrow, triggers recursively on itself)

### Chest armor affixes (10) — defense themed
All numeric values are rolled ranges:
`vitality` (+12-18 max HP), `fortified` (+6-10% DR), `iron_skin` (6-10% proc → 80-90% DR),
`thorns` (12-18% reflect), `second_wind` (heal at low HP, rolled threshold + heal %), `undying` (revive once, 300s CD),
`bulwark` (+2-4 flat armor), `regenerator` (+0.8-1.2 HP/s), `guardian` (block grants 75-85% DR),
`battle_hardened` (+4-6%/enemy DR max 3)

### Legs armor affixes (10) — stamina/resilience themed
All numeric values are rolled ranges:
`endurance` (+16-24 max stamina), `resilience` (+20-30% stam regen), `steadfast` (KB immune, binary),
`thick_skinned` (first hit 25-35% DR, 10s CD), `last_stand` (+20-30% DR below 25% HP),
`fleet` (20-30% less sprint stam cost), `rejuvenation` (+25-35% HP regen), `quick_recovery` (1.5-2.5s less regen delay),
`lucky` (+4-6% rare drop chance), `tenacity` (min 50-70% move speed)

### Boots armor affixes (11) — movement themed
All numeric values are rolled ranges:
`swiftness` (+8-12% move speed), `aquatic` (+25-35% swim speed), `warmth` (33-47% less swim stam cost),
`featherfall` (40-60% less fall dmg), `evasion` (4-6% dodge), `adrenaline` (on kill +12-18% speed 4s),
`sure_footed` (no slope penalty, binary), `light_step` (25-35% less fall dmg + silent), `trailblazer` (+12-18% water speed),
`nimble` (+6-10% dodge while sprinting), `double_jump` (one extra mid-air jump, binary, tier 2)

### Combat integration (`player_controller.gd` + `player_combat.gd`)
- `_get_active_affixes()` / `get_active_affixes()` — cached dictionary of all equipped affixes (weapon + armor), keyed by affix StringName with the **roll float (0.0–1.0)** as the value (not `true`). Invalidated on inventory change via `_invalidate_affix_cache()` called from `_on_inventory_changed()`
- `_has_affix(id)` / `has_affix(id)` — O(1) lookup, safe to call from hot paths
- `_affix_val(id)` / `affix_val(id)` — looks up the cached roll for the affix and calls `ItemDatabase.get_affix_value(id, roll)` to get the interpolated min/max value. All combat code uses this instead of hardcoded numbers.
- `_get_weapon_affixes()` — affixes on currently equipped weapon only
- `_apply_affix_stat_bonuses()` — called on equip change, adjusts `max_health`/`max_stamina` while preserving current ratio. Uses `affix_val()` for vitality/endurance.
- `_tick_affix_timers(delta)` — runs each physics frame, counts down momentum, second_wind, thick_skinned, undying, and adrenaline timers
- Sword procs fire in `_resolve_attack()` (melee); bow procs fire in `_fire_bow()` / `_tick_arrows()`; axe/pickaxe procs fire in `_hit_harvestable()` / `_destroy_rock()` / `_fell_tree()`
- Armor procs fire in `take_damage()` (chest), `_handle_movement()` (boots), `_handle_stamina()` (legs)
- Sword crit system: base `5% + dex*0.5`, `sharpened` adds rolled crit chance (7-13%), `savage` adds rolled crit dmg (30-50%)
- Bow crit: `steady_aim` adds rolled crit chance (9-15%) while standing still
- Windfury uses `_windfury_guard` bool to prevent infinite recursion when extra attacks trigger

### `take_damage()` affix ordering
1. Iron Skin — high DR proc (rolled 80-90%, NOT full negate)
2. Evasion / Nimble — dodge roll (early return, combined chance, rolled values)
3. Deflection — shield high DR proc (rolled 80-90%)
4. Thick Skinned — first-hit reduction (rolled 25-35%, 10s cooldown)
5. Block (Guardian modifies reduction, rolled 75-85%)
6. Armor (Bulwark/Stalwart add flat armor, rolled values)
7. Additive DR stack: Iron Will + Thick Skinned + Fortified + Last Stand + Battle Hardened + Blocking,
   all rolled values, stacked additively with 85% hard cap
8. Apply damage
9. Quick Recovery (reduces regen delay, rolled value)
10. Thorns (reflect rolled 12-18% to source)
11. Second Wind (heal at low HP, rolled values, 45s CD)
12. Undying (revive at 10% HP on death, 300s CD)

### `_resolve_attack()` affix ordering (swords)
1. Additive offense stack: berserker + momentum + relentless_fury + retaliation + headshot + sniper
   (all rolled values, stacked additively into one `offense_add` bonus multiplier)
2. Crit roll: base chance + `sharpened` rolled bonus; crit damage: base + `savage` rolled bonus.
   Crit and headshot applied as final separate multipliers (not additive with the stack).
3. Per-enemy modifiers: executioner (rolled +25-35% to low HP), bane (rolled 6-10% double dmg)
4. Post-hit procs: lifesteal, siphon, firebrand, chain_lightning, runic, frostbite, venomous,
   stunning_blow, concussive, bone_breaker, earthshaker, staggering, thunderclap, echoing_blade
   — all using rolled values via `affix_val()`
5. Momentum stack update
6. Windfury check (rolled 25-35% chance, 2 recursive calls with guard)

### `_hit_harvestable()` affix effects (axes/pickaxes)
- `deep_cut`: +50% damage to trees
- `stone_breaker`: +50% damage to rocks
- `sap_drinker`: +2 HP per tree hit
- `geologist`: +2 HP per rock hit

### `_fell_tree()` affix effects
- `lumberjack`: +40% wood drops
- `double_yield`: 10% chance to double all wood
- `bark_stripper`: 25% chance for bonus resin
- `splitter`: tree fall animation 30% faster

### `_destroy_rock()` affix effects
- `prospector`: +40% stone drops (only for stone, not copper)
- `ore_seeker`: +30% copper ore drops
- `rich_vein`: 10% chance to double all stone
- `vein_finder`: 30% chance for bonus copper ore

### Creature status effects (`creature_ai.gd`)
- `apply_slow(factor, duration)` — multiplies move speed, uses max duration / min factor if reapplied
- `apply_stun(duration)` — freezes AI completely: skips all AI, zeroes velocity, early-returns from `_physics_process`
- `apply_poison(dps, duration, source)` — ticks damage per second, can kill the creature
- `_tick_status_effects(delta)` runs at top of `_physics_process`, before AI state machine
- `_get_effective_speed()` returns `move_speed * _slow_factor` when slowed; used in wander and chase

### Creature on-kill hooks (`_explode_and_free()` in `creature_ai.gd`)
- Looks up player via `get_tree().get_nodes_in_group(&"player")`
- Checks player `_has_affix()` for `adrenaline` (sets timer)
- This cross-script access works because GDScript doesn't enforce method visibility

### Passive stat modifiers
- `vitality`: +15 max HP (applied via `_apply_affix_stat_bonuses()` on equip change)
- `endurance`: +20 max stamina (same)
- `swiftness`, `fleet`, `aquatic`, `warmth`, `trailblazer`: modify speeds/costs in `_handle_movement()` / `_handle_stamina()`
- `rejuvenation`, `resilience`, `regenerator`, `quick_recovery`: modify regen in `_handle_health_regen()` / `_handle_stamina()`
- `lucky`: +5% rare drop boost in `loot_drop.gd`

### Tooltip display
Items with affixes show a separator + affix list below stats:
- Affix name in gold (`#ffd700`)
- Description in gray (`#aaaaaa`) — uses `format_affix_description(affix_id, roll)` to show the
  actual rolled value (e.g. "+18% headshot damage" instead of a generic "+20% headshot damage").
  Affixes without min/max show their static `description` string.

### Legendary+ arrow glow (`_spawn_arrow()` in `player_controller.gd`)
Arrows fired from bows with 4+ stars (Legendary or better) get a purple magic-missile aura:
- **Color**: hardcoded purple `Color(0.55, 0.1, 0.9)` via `_arrow_aura_color()` (ignores
  quality_color — user preference for consistent purple regardless of item tier)
- **Glow layers**: 3 billboard `MeshInstance3D` quads (AuraCore 0.5×0.5, AuraMid 1.0×1.0,
  AuraOuter 1.75×1.75) using `BLEND_MODE_ADD` + emission for additive glow visible in any lighting
- **Light**: `OmniLight3D` with `light_energy = 5.0`, `omni_range = 4.0`
- **Particle trail**: `GPUParticles3D` (30 particles, 0.5s lifetime) with matching purple material
- **Arrow mesh tinting**: body, tip, and fletching materials get boosted emission in `aura_col`
- **Cleanup**: `_stick_arrow()` removes all aura children (light, quads, particles) and reverts
  mesh materials to defaults when the arrow stops moving (hits a surface or loses speed)
- Helper: `_make_aura_mat(col, alpha, energy)` creates `StandardMaterial3D` with unshaded +
  additive blend + billboard + no depth test + emission. Reusable for similar effects.
- Environment glow settings in `test_world.tscn` were boosted (`glow_intensity = 0.6`,
  `glow_bloom = 0.15`) to make emission-based effects more visible.

### Bow affix specifics
- Crit is rolled once per shot in `_fire_bow()` (not per arrow)
- `steady_aim` adds +12% crit chance when player is standing still
- `rapid_draw` increases bow tension buildup by 15%
- Echoing Shot rolls recursively in a `while` loop — each bonus arrow re-rolls the same chance,
  so a 25% roll can theoretically chain multiple arrows (alternating left/right offset by `cam_right * 0.3`)
- Bouncing Shot redirects the arrow toward the nearest alive enemy within 12 units on hit (re-triggers itself)
- Precision increases headshot multiplier from 1.3 to 1.5 in `_tick_arrows()`
- `sniper` adds +25% dmg when distance to target > 15 units
- `frost_arrow` (35% slow), `poison_tip` (30% poison), `explosive` (10% AoE) trigger from arrow hits

### Loot drop affix integration (`_spawn_single_drop()` in `loot_drop.gd`)
- Checks if item is equipment (`type` in `["weapon", "armor"]`) and `stars >= 2`
- Calls `ItemDatabase.roll_affixes(stars, ...)` then `roll_affix_magnitudes(affixes)` to generate rolls
- Encodes both affixes and rolls into composite ID via `make_star_id(id, stars, affixes, affix_rolls)`
- Player affix `lucky` is checked at the top of `spawn_loot()` by looking up the player node from the SceneTree

### Save/load
Affixes and their roll values are encoded in the StringName item ID, already persisted by inventory
serialization. `save_manager.gd` has `_migrate_missing_affixes()` and `_migrate_item_id()` which
retroactively roll affixes for 3+ star equipment loaded from old saves. Migration now uses
`get_affix_slot()` to roll the correct weapon-specific or armor-slot-specific affixes, and
`roll_affix_magnitudes()` to generate roll values for newly added affixes.

Old item IDs without `@roll` in affixes (e.g. `"sword:3:windfury,lifesteal"`) are automatically
upgraded on parse — `parse_star_id()` assigns a fresh `randf()` roll to each affix missing its `@`
value. This means old saved items get randomized rolls on first load.

---

## Trees & Harvesting

### Tree sizes
Big trees (not saplings) have had their trunk height increased by 50% via `_create_tree()` in
`zone_populator.gd`. This makes forests feel more imposing and gives more visual variety.

### Tree domino effect
When a tree is chopped and falls, it can knock over nearby trees it collides with.
`_fell_tree(node, override_angle, can_domino)` controls this:
- The **initial** chopped tree: `can_domino = true` — it CAN trigger secondary falls
- Trees knocked over by the initial fall: `can_domino = false` — they do NOT cascade further
- This prevents runaway chain reactions where entire forests collapse from one chop
- `_check_tree_domino()` calls `_fell_tree(n3d, push_angle, false)` for secondary trees

### Footstep audio
- `_tick_footstep_sfx()` dynamically scales `_footstep_player.pitch_scale` based on
  `flat_speed / walk_speed` (clamped 0.4–2.2), multiplied by `0.65` for a slower, heavier feel
- Footsteps stop while swimming (`_is_swimming` check)
- Uses the `grass_step` sound group

### Swim fatigue / drowning (`_tick_swim_fatigue()` in `player_controller.gd`)
- When swimming (not on a raft), `_swim_fatigue` increments by `delta` each physics frame
- `SWIM_FATIGUE_MAX = 15.0` seconds — reaching this kills the player ("Drowned!" floating text)
- At 75% fatigue the bar starts pulsing (warning). At 100% the player dies via `_on_death()`
- On returning to land or boarding a raft, fatigue recovers at `SWIM_FATIGUE_RECOVER_RATE = 5.0`/s
  (takes ~3 seconds to fully recover from max fatigue)
- If the player enters water while mounted on a horse, `force_dismount()` is called immediately
  — the horse is dismounted and the player begins drowning on the fatigue timer
- A **swim fatigue bar** (blue, shader-driven) appears below the stamina bar while fatigue > 0.
  It drains left-to-right as fatigue increases (shows remaining breath). Uses the same
  `bar_hud.gdshader` as HP/stamina bars, with pulse on the danger threshold.
- Variables: `_swim_fatigue` (float), `_swim_fatigue_bar` (MeshInstance3D), `_swim_fatigue_pulse` (float)
- Reset to 0 in `_respawn()`

---

## Root Motion Stripping

Meshy AI walking animations bake position keyframes into the skeleton root.
At large scales (280–800x), even tiny root motion becomes a multi-unit lurch per step.
`creature_ai.gd` strips all `TYPE_POSITION_3D` tracks via `_strip_root_motion()` at load time.
Horse also strips root motion in `_create_horse()`.

---

## Collision Layers

| Layer | Purpose |
|-------|---------|
| 1 | Terrain |
| 2 | Player |
| 4 | Interactables |
| 8 | Buildings |
| 16 | Creatures |
| 32 | Items |

Creatures: `collision_layer=16`, `collision_mask=1` (terrain only).
Do NOT add player to creature collision_mask — causes creatures to ride up player capsule and float.

---

## Building System

### Building piece sizes
- **Wood wall**: `Vector3(3.0, 1.0, 0.15)` — 3m wide, 1m tall, thin panel. Uses `wood_wall.glb` model.
- **Wood floor**: `Vector3(3.0, 0.1, 3.0)` — 3m×3m square tile, no GLB model (uses procedural `BoxMesh`).
  The GLB was removed because `wood_floor.glb` had non-square internal proportions causing distortion.
- Wall width and floor width are matched (3.0m) so pieces tile together cleanly.

### Mouse-based placement (`_update_build_ghost()` in `player_controller.gd`)
- Ghost position is determined by a **camera raycast** through the screen center into the world
  (physics layer 1 = terrain). The ghost follows wherever the crosshair points.
- **Max distance**: `BUILD_MAX_DISTANCE = 12.0` units from the player. If the raycast hit is
  farther, it falls back to a fixed 3.5m forward offset.
- **Horizontal**: move the mouse/camera to aim the ghost position on the terrain
- **Height adjustment**: `Ctrl + Scroll Wheel` raises/lowers the ghost by `BUILD_HEIGHT_STEP = 0.3`
  units per tick. Stored in `_build_height_offset`, reset to 0 on entering build mode.
- **Rotation**: plain `Scroll Wheel` (no Ctrl) rotates the ghost (existing behavior)
- The raycast excludes the player's own RID to prevent self-collision

### Snap system (`_get_snap_points_for()`, `_find_best_snap()`)
- Walls have snap points at edges (wall_base, wall_top, wall_side) and center
- Floors have edge and corner snap points
- `SNAP_COMPAT` dictionary defines which point types can connect to which
- **Wall overlap**: Wall side snap points are inset by 0.04 units from the actual edge
  (`-hw + overlap` and `hw - overlap`) so adjacent walls overlap slightly, preventing light
  bleed through cracks between wall panels
- **Floor elevation**: Floor pieces (`wood_floor`, `stone_floor`) get a -0.05 Y offset when
  placed on terrain so the top surface sits nearly flush with the ground. This prevents the
  floor from creating a step that requires jumping. Applied in `_update_build_ghost()`.

### Vegetation clearing on build
When any building piece is placed, `_clear_vegetation_at(pos, sz)` is called:
- Removes all `interactables` group nodes (trees, rocks, bushes) within the building footprint radius
- Removes grass MultiMesh instances within the footprint via `_clear_grass_multimesh_at()`:
  iterates all `Grass_*` MultiMeshInstance3D nodes in loaded zones, rebuilds each multimesh
  excluding instances that fall within the building radius
- `_is_near_structure()` in `zone_populator.gd` prevents new grass from spawning within 2m
  of any placed structure when zones are regenerated

### Step-up climbing (`_step_up_move_and_slide()`)
Replaces raw `move_and_slide()` for the player. When the player is on the ground and moving
but gets blocked (moved less than 50% of intended distance), it:
1. Temporarily lifts the player up by `STEP_HEIGHT` (0.35m)
2. Moves forward at the elevated position
3. Raycasts back down to snap onto the surface
This allows walking onto wood floors, stone floors, and any small ledges without jumping.

### Workbench building piece
- Size: `Vector3(1.4, 0.9, 0.8)`, uses special `_build_workbench_visual()` for rendering
- Interaction: Press E to open workbench UI
- Placed via build menu or workbench Building tab

---

## Zone Boundary Jitter

Terrain is 64x64 zone chunks with trimesh collision. At chunk seams, `move_and_slide` can push
creatures upward. `creature_ai.gd` caps single-frame Y-rise to 0.4 units and uses gradual
correction via `move_toward` instead of instant snapping.

---

## Horse Mounting

- Horse model faces opposite to Godot's -Z forward → `rotation.y += PI` when syncing to player
- Rider is a duplicate of the player sprite at `_estimate_mount_height()`
- Horse collision disabled while mounted (`layer=0, mask=0`)
- **Dismount terrain snap**: Both `dismount()` and `force_dismount()` snap the horse's Y position
  to terrain height via `WorldGenerator.get_height_at()`. This prevents horses floating mid-air
  when the player dismounts while jumping or at elevation.

---

## Weapon Models

Each weapon lives in `res://models/weapons/<type>/` (GLB + textures).
Types: `1h_axe`, `2h_axe`, `2h_labrys`, `bow`, `shield`, `sword`.
Code ref: `_get_weapon_model_for_class()` in `player_controller.gd`.

---

## Spawn Distribution (`zone_populator.gd _pick_creature_kind`)

- 37% grizzly, 41% boar, 3.5% lion
- 3.5% cyclops, 3.5% minotaur, 5% orc brute, 6.5% goblin
- Enemy count per zone: `enemy_n * 0.3` (min 1)
- Horses: 15% chance per Hearthlands zone
- Creature visibility range: 60 units (`VISIBILITY_RANGE_FADE_DISABLED`)

---

## Camera

- 3rd-person via `SpringArm3D` (`$CameraPivot/SpringArm3D`)
- `zoom_speed`: 0.5 per scroll tick
- `min_zoom`: 2.0, `max_zoom`: 12.0
- **Spawn default**: 85% zoomed out (`spring_length = min_zoom + 0.85 * (max_zoom - min_zoom)` = 10.5)
  Set in `_ready()` so the player starts with a wide overview on login

---

## Flight Mode (Debug)

`flight_mode: bool = true` in `player_controller.gd` — a debug noclip camera for world exploration.

### How it works
- `_handle_flight(delta)` moves the player by directly modifying `global_position` (no physics)
- `velocity` is explicitly set to `Vector3.ZERO` every frame
- `move_and_slide()` is **never called** in flight mode (the entire normal movement `else` block is skipped)
- Speed: `FLIGHT_SPEED = 34.65` (150% of a 5-star horse sprint speed), doubled with sprint key
- Jump key = ascend, crouch key = descend
- Ground clamp: character cannot go below terrain height + 0.5

### Known side effects when flight mode is ON
- **No animations**: The animation system in `_tick_3d_model()` checks `velocity` (always zero)
  and `is_on_floor()` (always false since `move_and_slide()` isn't called). Result: the character
  is permanently stuck in "idle" animation with no visible walk/run/attack animations.
- **No model rotation**: `_rotate_model()` checks `velocity` for facing direction — always zero
  in flight mode, so the model never turns.
- **Character appears as a static shadow**: The combination of no animation + no rotation makes
  the character look like a dark, motionless silhouette — especially from the camera's top-down angle.
- **No fall damage, no stamina drain, no collision**: All physics-dependent systems are bypassed.
- If you see "no animations" or "permanent shadow" on the player, **check `flight_mode` first**.

---

## Shadow Settings (`test_world.tscn`)

- `shadow_opacity`: 0.3
- `shadow_blur`: 2.0
- `directional_shadow_max_distance`: 50.0

---

## Adding a New Tripo Creature (checklist)

1. Place GLB + basecolor JPG in `res://models/creatures/<Name>/`
2. Add to `_creature_model_paths` in `zone_populator.gd`
3. Add to `_creature_model_scales` (scale ~2–5 for Tripo)
4. Add basecolor JPG path to `_creature_texture_paths`
5. Add yaw offset to `_creature_yaw_offsets` (test -PI/2, 0, PI/2, PI — varies per model)
6. Add stats in `_creature_stats()` (hp, dmg, spd, cd, sound, name)
7. Add loot in `_creature_loot_for()` — returns `{ "normal": [...], "rare": [...] }`
8. Add NlaTrack animation mapping in `_build_anim_map()` in `creature_ai.gd`
   - Extract GLB animation names with Python: `json.loads(glb_json_chunk)["animations"]`
   - Each model's NlaTrack order is unique — must be tested visually
9. Add to `_pick_creature_kind()` spawn table
10. If nameplate sits inside model, add entry to `_UI_HEIGHT_OVERRIDES`

---

## UI Systems

### Pause menu (`player_hud.gd build_pause_menu()`)
- ESC opens pause menu (transparent overlay so game is still visible)
- Game tree is paused (`get_tree().paused = true`), Master audio bus muted
- Contains: Music slider, SFX slider, **Dev Mode checkbox**, Resume, "Exit to Character Screen", "Exit Game"
- Dev Mode checkbox toggles `Inventory.dev_mode` — enables free build/craft (see Dev Mode section)
- "Exit to Character Screen" calls `SaveManager.stop_game()` then `change_scene_to_file` to main menu
- "Exit Game" calls `SaveManager.stop_game()` then `get_tree().quit()`
- Dedicated `input_catcher` Control with `PROCESS_MODE_ALWAYS` and `grab_focus()` to capture ESC while paused
- Note: GPU-based visual effects (wind on leaves, etc.) cannot be paused by the game engine

### Tooltip
- `RichTextLabel` with BBCode enabled, supports `[color=...]` tags
- Default text color: **white** (`Color.WHITE`)
- Starred items: name + stars rendered in rarity color, rarity label (e.g. "Epic") shown below
- 0-star items: white bold name, no rarity label
- Armor displayed with one decimal (e.g. "Armor: 6.3")
- Items with affixes: separator line + each affix name in gold (`#ffd700`) + description in gray (`#aaaaaa`)
- `_show_tooltip_for_item(item_id)` — single item tooltip (stats, description, affixes)
- `_show_grouped_tooltip(base_id, variants, display_id)` — grouped material tooltip with star breakdown
- **Viewport clamping**: `_clamp_tooltip_pos()` ensures the tooltip stays within the screen.
  If it would overflow the right edge, it flips to the left of the cursor. If it would overflow
  the bottom, it shifts up. Prevents chest-UI tooltips from being cut off on the right side.
- **Scroll for long tooltips**: `_cap_tooltip_height()` caps the tooltip at `viewport_height - 32px`.
  If the content exceeds this (e.g., Oathgun with 9+ affixes), `fit_content` is disabled,
  `scroll_active` is enabled, and the label gets a fixed max height — making overflow scrollable
  with the mouse wheel. Short tooltips remain auto-sized with no scrollbar.

### Delete confirmation (main_menu.gd)
- Character/world deletion shows "Delete" button instead of "X"
- Pressing Delete opens a confirmation dialog with overlay ("Yes, Delete" / "Cancel")

### Workbench panel
- Panel size: `504×480` (scaled up 20% from original 420×400 for legibility)
- Opened by pressing E on a placed workbench
- Category tabs: Tools (default) / Equipment / Supplies / Building
- `_workbench_category` tracks active tab, `_on_workbench_tab()` switches categories
- **Tools tab**: shows tool-type items (hammer, torch) — always unstarrable
- **Equipment tab**: shows weapons/armor that can gain stars
  - **Quality tier selector**: Low / Medium / High buttons below category tabs, visible only on Equipment tab
  - Controls which star levels of materials are consumed for weapon/armor crafting
  - `_workbench_quality_tier` tracks selection, `_on_workbench_tier()` switches and refreshes
  - Info button ("i Material Quality") toggles `_workbench_tier_info_panel` with explanation text
- **Building tab**: shows all `BUILD_RECIPES` items (same items as hammer build menu)
  - Each recipe shows a 32×32 pixel art icon loaded via `_get_build_icon(recipe_id)` from
    `res://textures/items/{id}.png` (generated by PixelLab). Falls back to `ColorRect` if no icon exists.
  - Icons: campfire, torch_post, wall_torch, workbench, wood_wall, wood_floor, wood_stair,
    stone_wall, stone_floor, thatch_roof_45, thatch_roof_26, slate_roof_45, chest, bed, raft
  - Hammer build menu also shows these icons (36×36px)
  - Clicking "Build" closes workbench and enters placement mode via `_on_workbench_build()`
- Cost labels use `RichTextLabel` with BBCode for green/red material count coloring
- Equipment cost labels use `get_amount_capped_star()` (tier-aware); tools/supplies use `get_amount_any_star()`
- **Auto-discard rarity filter**: "🗑" button in workbench title bar (top-right)
  - Cycles through: Off → ≤Common → ≤Uncommon → ≤Rare → ≤Epic → ≤Legendary → Off
  - `_workbench_auto_discard_star` (-1 = off, 0-4 = discard at/below that star level)
  - When active, crafted items at or below the threshold are auto-removed from inventory
    and dropped on the ground as loot (despawns after 60s), with a red "Discarded:" text notification
- **Craft preview toggle**: "👁 Preview" button in title bar, next to auto-discard
  - Only visible on Equipment tab (same as auto-discard and tier selector)
  - When on, equipment craft buttons show "Preview" → opens detail popup before crafting
  - When off, buttons show "Craft" → crafts immediately

### Equipment bar
- Pinned below the inventory scroll area (inside the VBox, outside the ScrollContainer)
- 4 slots in order: **Weapon**, **Chest**, **Legs**, **Boots**
- Each slot shows a **ghost icon** (12% opacity silhouette of default gear) when empty
- When equipped, shows the item icon at full opacity; starred items get a rarity-colored border
- **Slot label**: small text at bottom of each slot ("Weapon", "Chest", "Legs", "Boots")
- **Right-click** an equipped slot to unequip the item
- **Drag-and-drop** from inventory: dropping a weapon/armor on the matching slot equips it
- Hover shows item tooltip (or "Empty X slot" hint if empty)
- Auto-populated on new game via `give_starting_gear()` (Worn Axe, Leather Vest, Pants, Boots)
- Refreshed via `_refresh_equip_bar()`, called from `_on_inventory_changed()`
- Member vars: `_equip_bar`, `_equip_bar_slots`, `_equip_bar_icons`, `_equip_bar_ghost`
- Ghost icon paths: `stone_axe.png`, `leather_vest.png`, `leather_pants.png`, `leather_boots.png`

### Inventory item discard
- **Shift+right-click** any inventory slot to drop the entire stack on the ground
  - Grouped materials (e.g. 5 wood = 3 common + 2 rare) are split into separate drops per star level
  - Dropped items despawn after 60 seconds
- **Drag-and-drop outside inventory**: hold left-click to drag an item, release outside the inventory panel to drop it on the ground
  - Uses the same split-by-star-level logic for grouped materials
  - `_drop_dragged_item()` reuses `_discard_inventory_slot()` for consistent behavior
- `_drop_item_on_ground(item_id, amount, despawn_time)` helper spawns a `LootDrop` in front of the player with a timed despawn

### Chest UI (`player_interaction.gd`)
- Chest slots are 56×56 `PanelContainer` nodes built dynamically in `refresh_chest_ui()`
- `CHEST_SLOTS` defines total capacity; contents stored as node metadata (`"chest_contents"`)
- **Tooltips**: hovering a filled chest slot shows the same item tooltip used for inventory
  (connects `mouse_entered` → `pc._show_tooltip_for_item(item_id)`, `mouse_exited` → `pc._hide_tooltip()`)
- **Right-click** a chest slot to move the **full stack** to player inventory
- **Shift+Left-click** a chest slot to take **half** the stack (rounded up)
- **Shift+Right-click** also takes the full stack
- Plain left-click (no shift) does nothing (prevents accidental moves)
- Tooltip is hidden on `refresh_chest_ui()` and `close_chest()` to prevent stale tooltips on freed nodes
- **Deposit**: shift+click inventory slots while chest is open to deposit items
  (`deposit_inv_slot_to_chest` / `deposit_item_to_chest` in `player_interaction.gd`)
- All `refresh_chest_ui()` and `pc._refresh_inventory_ui()` calls within signal handlers use
  `call_deferred()` to avoid "Attempted to free a locked object" errors (freeing UI nodes
  that are still emitting `gui_input`)

---

## Creature AI Behavior (`creature_ai.gd`)

### Combat engagement timer (`_combat_timer`)
- `_combat_timer` tracks seconds since the creature last dealt or received damage
- Reset to `8.0` on: `take_damage()`, `_do_attack()`, `_check_aggro()` (first aggro)
- Decremented every `_physics_process` frame
- While `_combat_timer > 0`, creatures will NOT leash back to spawn even if outside `leash_range`
- This keeps monsters engaged for longer during active combat

### Retaliation outside aggro range
- If a creature takes damage from a `source` and has no current `_target`, it sets
  `_target = source` and transitions to CHASE regardless of distance
- This means ranged attacks (bow) always provoke retaliation, even from beyond normal aggro range

### Evade behavior (`_evading` flag)
When a creature decides to leash (outside leash_range AND `_combat_timer <= 0`):
- `_evading = true`, `_wander_timer = 99.0` (no idle pauses)
- `_wander_direction` set toward `_spawn_position`
- During evade: moves at `1.5x` effective speed, always toward spawn, no idle breaks
- On reaching spawn (< 3m): `_evading = false`, transitions to IDLE, heals to full HP
- `take_damage()` clears `_evading` and resets `_combat_timer`, so hitting an evading creature
  forces it to re-engage
- `is_aggressive` includes `_evading` so running animations play during retreat

### Leash range
- `leash_range = 45.0` (distance from spawn before leash check triggers)

---

## LAN Multiplayer

### Overview
Oathbound supports **LAN co-op multiplayer** for up to 4 players using Godot's `ENetMultiplayerPeer`.
The host runs a **host-authoritative** server — clients connect by IP address on port 7777.
Single-player ("Play Offline") still works without any networking.

### Key files
```
scripts/autoloads/network_manager.gd    — Host/join, player spawn/despawn, chest sharing, player data sync
scripts/network/world_state_sync.gd     — World mutations, creature sync, loot replication, damage requests
scripts/network/creature_sync_manager.gd — Legacy creature sync (now delegated to WorldStateSync)
scripts/network/chat_manager.gd         — Simple text chat (client→host→broadcast)
```

### Main menu flow (`main_menu.gd`)
- **"Play Offline"** — **removed** from UI (function `_on_play_offline` still exists for future re-addition)
- **"Host LAN Game"** — calls `NetworkManager.host_game()`, starts ENet server, spawns host player
- **"Join LAN Game"** — player enters host IP, calls `NetworkManager.join_game(ip)`, receives world
  seed/name via RPC, generates the same deterministic world, then spawns via `_rpc_create_player`

### Connection lifecycle
1. Host calls `host_game()` → creates ENet server on port 7777
2. Client calls `join_game(address)` → connects to host
3. Host auto-sends world seed + name to client via `_send_world_info` RPC
4. Client generates the same deterministic terrain from the seed
5. Client calls `notify_server_ready()` → host spawns client player via `spawn_player()`
6. Each player node is named by `peer_id` with `set_multiplayer_authority(peer_id)`
7. On disconnect: host saves client's player data via `_save_player_data()`, despawns node

### World state sync (`world_state_sync.gd`)
Terrain and zone population are deterministic per world seed. Only **mutations** need sync:
- **Destroyed objects** (trees, rocks): keyed by `"zone_x_zone_z_index"`, broadcast to all clients
- **Placed buildings**: position, rotation, chest contents — broadcast on placement
- When a client joins mid-game, `request_world_state()` sends all accumulated mutations
- `apply_destroyed_to_zone()` is called from `WorldGenerator` when zones load to remove
  already-destroyed objects

### Creature sync (host → clients)
- **Positions**: broadcast at 10 Hz (`_CREATURE_POS_INTERVAL = 0.1s`) via **unreliable** RPCs
  (loss tolerable on LAN). Sends packed `Float32Array` of positions, rotations, velocities per zone.
- **State changes** (HP, AI state): broadcast at 5 Hz (`_CREATURE_STATE_INTERVAL = 0.2s`) via
  **reliable** RPCs. Only sends creatures whose state actually changed (delta compression).
- Clients interpolate creature positions via `_sync_target_position` on `CreatureAI`
- `_sync_initialized` flag ensures first position is snapped, not lerped

### Loot replication
- Host spawns `LootDrop` nodes and replicates to all clients via `_spawn_loot_replicated` RPC
- Each loot drop gets a unique `loot_id` tracked in `_loot_registry` (host only)
- **Pickup arbitration**: client calls `request_pickup(loot_id, peer_id)` → host grants to first
  requester via `_grant_pickup` RPC, then removes for everyone via `_remove_loot` RPC
- Host pickups use `process_host_pickup()` directly
- Player item drops use `spawn_player_drop_synced()` with `drop_owner_peer` for pickup grace

### Creature damage (client → host)
- Clients send `request_creature_damage(zone_x, zone_z, creature_idx, amount, source_peer)` RPC
- Host validates and clamps damage (max 9999) before applying `creature.take_damage()`
- TODO comment in code: "move full damage calc to host for cheat-proof authority"

### Chest sharing (host-authoritative)
- `request_open_chest(chest_path)` — client requests contents, host sends current state
- `request_deposit_to_chest` / `request_withdraw_from_chest` — host validates, updates, broadcasts
- Chest contents stored as node metadata (`"chest_contents"`)

### Building sync
- Client places building locally, sends `request_building_placed(entry)` to host
- Host records, spawns for itself, broadcasts to all other clients (excluding sender)
- Building entry: `{build_id, px, py, pz, ry, chest_contents}`

### Chat (`chat_manager.gd`)
- `send_message(text)` — client sends to host, host broadcasts to all peers
- Max 20 messages, 5-second fade time
- Uses character name from `SaveManager.current_character`

### Save/load in multiplayer
- Only the **host** runs autosaves and full save logic
- Clients save only their own inventory locally via `_save_client_inventory()`
- On client disconnect, host saves their cached player data via `save_disconnected_player()`
- Clients report player data to host periodically via `report_player_data` RPC
- When a client rejoins, `_load_latest_character_save()` restores their last state

### Networking gotchas
- `WorldStateSync` is a **scene-file node** (not dynamically added) so RPC node paths match
  between host and clients. `CreatureSyncManager` was moved here for the same reason.
- The default single-player `Player` node is `queue_free()`'d on multiplayer launch — players
  are created by `NetworkManager` via RPC-based spawning instead.
- Creature AI only runs on the host. Clients receive position/state updates and render accordingly.
- `drop_owner_peer` on `LootDrop` prevents other players from picking up items during the grace period.
- `multiplayer.has_multiplayer_peer()` checks are scattered throughout `save_manager.gd`,
  `player_controller.gd`, `loot_drop.gd`, etc. to branch between single-player and multiplayer paths.

### Multiplayer guidance for AI agents — what needs sync and what doesn't

Understanding the sync boundary is critical when modifying game code. The architecture splits
the game into **deterministic generation** (no sync needed) and **runtime mutations** (sync required).

#### Deterministic generation layer (NO sync needed)
These systems run identically on host and client using the same world seed + RNG:
- **Terrain**: `world_generator.gd` height maps, biome determination, zone meshes
- **Zone population**: `zone_populator.gd` trees, rocks, bushes, grass, creatures, horses
- **Villages**: `village_generator.gd` hut placement, wall construction, chest spawning, hero assets
- **Caves**: `cave_generator.gd` cave layout and contents

**Why it works**: `rng.seed = world_seed_hash + coord.x * 73856093 + coord.y * 19349663` produces
identical sequences on both host and client. As long as the code is the same, the output is the same.

**AI agent rule**: Changes to generation code (adding hut variations, changing spawn rates, modifying
wall construction, adjusting chest loot tables, etc.) are automatically multiplayer-safe. Both host
and client will generate identical results from the same seed.

**CAUTION — RNG sequence sensitivity**: The RNG is consumed sequentially. Adding or removing ANY
`rng.randf()` / `rng.randi_range()` call in the generation loop shifts all subsequent random values
for that seed. This can cause villages, creatures, and objects to change positions/properties across
the entire world. This is acceptable (it's a new world generation) but be aware that "small" changes
to generation code can have cascading visual effects.

#### Runtime mutation layer (sync REQUIRED)
These events happen during gameplay and MUST be replicated between host and clients:
- **Object destruction** (trees chopped, rocks mined): `WorldStateSync._destroyed_objects`
- **Building placement**: `WorldStateSync._placed_buildings` / `record_building_placed()`
- **Chest contents** (items taken/deposited): host-authoritative via `request_withdraw_from_chest` /
  `request_deposit_to_chest` RPCs
- **Creature damage/death**: client sends `request_creature_damage` RPC → host applies
- **Loot drops**: host spawns → replicates via `_spawn_loot_replicated` RPC
- **Loot pickup**: client sends `request_pickup` → host grants via `_grant_pickup` RPC
- **Player data** (position, health, equipment): synced via `report_player_data` RPC

**AI agent rule**: When modifying interaction code (chest UI, loot pickup, building placement,
combat), always check for the multiplayer branch pattern:
```gdscript
if not NetworkManager.is_multiplayer() or NetworkManager.is_server():
    # Direct local logic (singleplayer or host)
else:
    # Send RPC to host for validation
    NetworkManager.request_something.rpc_id(1, ...)
```
If you add a new mutation (e.g. a new interactable type), you MUST add corresponding RPC handling
so clients can request the action and the host can validate + broadcast the result.

#### Quick decision guide for AI agents
| Change type | Sync needed? | Example |
|------------|-------------|---------|
| Generation constants (spawn rates, sizes) | No | Changing `CHEST_CHANCE`, `MIN_HUTS` |
| Generation logic (new hut types, wall rules) | No | Adding wall openings, collapsed roof placement |
| Visual-only changes (materials, colors, sizes) | No | Changing `_bmat_wood` color |
| Player input/controls (keybinds, camera) | No | Adding Ctrl+scroll for build height |
| Client-side UI (HUD, tooltips, menus) | No | Chest slot tooltip, inventory display |
| Player combat (damage calc, affixes) | Partial | Melee is local; creature damage uses RPC |
| Chest contents modification | Yes | Must go through host RPC in multiplayer |
| Building placement | Yes | Uses `record_building_placed` + broadcast |
| Object destruction | Yes | Uses `WorldStateSync._destroyed_objects` |
| New interactable types | Yes | Need new RPC request/response handlers |

---

## Loot Drop Mechanics (`loot_drop.gd`)

### Pickup grace period
- `pickup_grace = 6.0` seconds: when the player drops an item, it cannot be picked up for 6 seconds
- Prevents accidental immediate re-pickup of intentionally discarded items

---

## Non-Equipment Crafting Material Rules

### Hand crafting (`craft_item()` in `item_database.gd`)
- Non-equipment items (tools, building pieces, consumables) ALWAYS consume only 0-star materials
- `eff_max = 0` for non-equipment, `eff_max = 5` for equipment
- Uses `remove_item_capped_star()` with `prefer_low=true` for non-equipment

### Crafting info icon (hand-crafting menu)
- An "i" button in the hand-crafting menu title bar toggles an info panel
- Panel explains the star system and that only unstarred materials are used for non-equipment crafting
- Built as a `PanelContainer` with a `RichTextLabel` containing BBCode-formatted explanation

---

## Asset Pipeline

### Item icons (`textures/items/`)
- All icons are 32×32 PNG with transparent background
- Content is sized to 29×29 (approximately 10% padding from 32×32 border) centered on the canvas
- Icons are generated from various sources (PixelLab pixel art, Gemini AI images)
- For non-pixel-art sources: `rembg` (AI background removal) is used, followed by alpha cleanup,
  crop-to-content, square-pad, resize to 29×29, then center on 32×32 transparent canvas
- Stubborn dark backgrounds (e.g. bone icon): additional pass zeroes out pixels where R, G, B < 60

### PixelLab MCP integration
- Used for generating pixel art icons (e.g. fang icon)
- `generate_top_down_tileset` or similar endpoints create assets; `get_map_object` retrieves job status/URLs
- Download images with `curl` using the URL from `get_map_object` (the tool itself does NOT support `download_path`)
- Candidate images stored in `textures/items/candidates/` for user selection

---

## Performance Optimizations

### `get_nodes_in_group()` caching
Frequent calls to `get_tree().get_nodes_in_group()` caused significant FPS degradation after
10+ minutes of gameplay as the node tree grew. The following caching strategies were applied:

- **`player_controller.gd`** (`_tick_arrows()`): The "enemies", "carried_fish", and
  "interactables" group arrays are queried **once per frame** at the top of the function and
  reused by all per-arrow loops. Previously each arrow re-queried every group.

- **`creature_ai.gd`**: Player reference (`_cached_player`) is cached for 0.5 seconds via
  `_player_cache_timer`. Aggro checks (`_check_aggro()`) are throttled to 4 Hz via
  `_aggro_check_cd`. World generator reference (`_cached_world_gen`) is cached once.

- **`loot_drop.gd`**: Uses **static class-level caches** (`_s_cached_players`,
  `_s_cached_world_gen`, `_s_cache_frame`) refreshed once per frame via
  `_refresh_static_caches()`. All `LootDrop` instances share the same cached arrays.

### General rules for new code
- Never call `get_nodes_in_group()` inside per-entity `_process` or `_physics_process` loops
- Cache group results at the start of the frame or use a timer-based refresh
- Use `static var` for caches shared across many instances of the same class

---

## Known Quirks / Gotchas

- **Godot renames NlaTrack dots to underscores**: `NlaTrack.001` in the GLB becomes
  `NlaTrack_001` in the AnimationPlayer. Python/model viewers show dots; Godot uses underscores.
- **Blockbench is NOT used** in this project. All creature models are from Tripo or Meshy AI.
- **Walk animation can look like running** if `speed_scale` isn't matched to ground speed.
  Creatures wander at 0.4× move_speed, so walk animation must be slowed proportionally.
- **No idle animation for Cyclops/Brute/Minotaur**: idle falls back to walk track (NlaTrack).
  `_tick_3d_animation()` sets `speed_scale = 0.0` to freeze the pose when idle.
- `_gltf_play()` uses an `aliases` dict to resolve animation names. If a Tripo barbarian
  animation doesn't play, check if the logical name has an alias mapping to a renamed NlaTrack.
- Unarmed attacks (punch/punch_alt) alias to "kick" on the barbarian since no punch track exists.
- `_create_floating_ui()` in `creature_ai.gd` is synchronous (no SubViewport, no await).
  It creates Label3D + Sprite3D nodes directly. The HP bar Sprite3D nodes are set up inline.
- `creature_type` (sound key) ≠ `creature_kind` (spawn key). Don't confuse them.
- Creature `attack_cooldown` drives both animation speed AND attack state duration.
  `speed_scale = anim.length / attack_cooldown`, creature stays in ATTACK for full `attack_cooldown`.
- **BILLBOARD_FIXED_SIZE does NOT exist** in Godot 4's `BaseMaterial3D`. Use `BILLBOARD_ENABLED`
  with `fixed_size = true` for constant screen-size billboards.
- Death animations must NOT have root motion stripped (they'd float mid-air). `_strip_root_motion()`
  skips any animation name containing "death".
- All UI container children (`_workbench_grid`, `_crafting_grid`, `_build_grid`, `_chest_grid`)
  are freed with `remove_child()` + `free()`, NOT `queue_free()`, because deferred frees
  cause crashes in `Container::_child_minsize_changed` when rapidly refreshing (e.g. spam-crafting).
- Star composite IDs use format `"base_id:stars"` (e.g. `"wood:3"` for 3★ wood).
  Equipment with affixes: `"base_id:stars:affix1@roll1,affix2@roll2"` (e.g. `"stone_sword:3:windfury@73"`).
  The `@roll` is an int 0–100 encoding the affix's magnitude within its min/max range.
  `parse_star_id()` splits on the **first** colon; returns
  `{"base_id": ..., "stars": ..., "affixes": [...], "affix_rolls": {id: float}}`.
  `make_star_id(base_id, stars, affixes, affix_rolls)` creates them. 0★ items have no suffix.
  Affixes in the ID are always sorted alphabetically for deduplication. Old IDs without `@`
  get fresh `randf()` rolls on parse for backward compatibility.
- Affix cache (`_cached_affixes`) is a Dictionary `{affix_id: roll_float}` (NOT `true`) rebuilt on
  inventory change. Use `affix_val(id)` / `_affix_val(id)` to get the interpolated value from the roll.
  Don't forget to call `_invalidate_affix_cache()` if you change equipment outside normal flow.
- **Affixes are weapon-class/armor-slot specific**: `get_affix_slot()` determines the pool.
  Axe→woodcutting, pickaxe→mining, sword→combat, bow→ranged, chest→defense, legs→stamina, feet→movement.
  There are NO universal affixes anymore; each slot has 10-11 affixes (boots has 11 with `double_jump`).
- `_apply_affix_stat_bonuses()` modifies the @export `max_health`/`max_stamina` directly. If the
  base values change, the function must be updated (currently hardcodes base 100/100).
- Windfury (sword-only) recursive `_resolve_attack()` calls are guarded by `_windfury_guard`. If you add new
  on-hit procs, they will fire during windfury extra attacks too (by design).
- Clubs have been removed from the game entirely (item definition, model, icon, animation aliases).
- Spears have been removed from the game entirely (stone_spear, flint_spear). No "spear" weapon class exists.
- Creature `apply_slow/stun/poison` use `maxf` for duration so multiple procs extend rather than
  override. Slow uses `minf` for factor (stronger slow wins).
- `remove_item_any_star()` consumes lowest-star variants first (used by hand crafting).
  `remove_item_capped_star()` consumes within a `[min_star..max_star]` range; direction is
  controlled by `prefer_low` (Low tier → lowest first, Medium/High → highest first).
- **`call_deferred` for `add_child` in `_ready()`**: If a node's `_ready()` tries to add a child
  to its parent (`get_parent().add_child(...)`) while the parent is still setting up children,
  Godot errors with "Parent node is busy setting up children". Fix: use
  `get_parent().call_deferred("add_child", child_node, true)`. This was the cause of sporadic
  game crashes in `world_generator.gd` when adding `CreatureSyncManager`.
- **`global_position` requires scene tree membership**: Setting `node.global_position` before
  `add_child()` triggers "Condition !is_inside_tree() is true". Always add the node to the scene
  tree FIRST, then set `global_position`. Fixed in `_spawn_arrow()` and `_spawn_tree_stump()`.
- **Raft dismount rotation bug**: During raft riding, `rotation.y` on the CharacterBody3D is synced
  to the raft heading. `_dismount_raft()` must reset `rotation = Vector3.ZERO` on both code paths
  (normal dismount + early-exit), otherwise the player model faces sideways after leaving the raft.
  The model's local rotation (via `_rotate_model()`) combines with the parent body rotation.
- **`_DEBUG_LOG` pattern**: Most player scripts (`player_controller.gd`, `player_animation.gd`)
  wrap `print()` calls with `if _DEBUG_LOG:` guards (default `false`). Set `_DEBUG_LOG = true`
  at the top of the file to re-enable verbose logging for debugging. Creature scripts still use
  unconditional `print()` on spawn.
- Debug print `[CREATURE] <name> (kind=...) anim_map=... full_list=...` logs on every spawn.
- Debug print `[PLAYER ANIM] '<name>' not found...` logs when player animation is missing (guarded by `_DEBUG_LOG`).
- Loot stone visibility is intentionally shorter (9 units) vs other loot (45 units).
- Gold has `stack_size: 999` and `"no_stars": true` in rare drop tables — it never rolls star rarity.
- Tools (hammer, torch) have `type: "tool"` — selectable from hotbar
  but NOT equippable via right-click. Hotbar selection checks tool type FIRST (before `armor_slot`),
  so tools bypass `Inventory.equip_armor()`. Tools cannot gain stars or affixes when crafted/dropped.
- Stone axe and stone pickaxe are `type: "weapon"` — equippable, starrable, and gain weapon-specific
  affixes (axe→woodcutting themed, pickaxe→mining themed). They appear in the Equipment tab.
- `_creature_loot_for()` returns a Dictionary `{ "normal": [...], "rare": [...] }`, NOT an Array.
  Both `zone_populator.gd` and `cave_generator.gd` must destructure it when setting creature vars.
- **Player bar anchor is in player-local space**, NOT model-local space. The `_bar_anchor` is a
  child of the CharacterBody3D, not `_model`. The model rotates via `_model.rotation.y` but the
  anchor stays fixed. X/Z offsets on the anchor rotate with the player body (which doesn't rotate),
  so they're stable — but the visual head position shifts with model rotation, making bars appear
  slightly off-center from the head at certain camera angles. This is normal and expected.
- **Nameplate bg_w formula**: `text_w * 1.15 + pad_x * 2.0` (both `creature_ai.gd` and `loot_drop.gd`).
  Using a higher multiplier (e.g. 1.55) creates excess right padding, especially for starred items.
  Star character width estimate is `0.72 * unit` (not 0.95) to match actual rendered width.
- **Always use `DamageNumber.spawn()`** for floating damage numbers. Do NOT manually instantiate
  `DamageNumber.new()` with custom font_size/pixel_size — it produces tiny text. The `spawn()`
  method handles consistent sizing, animation, and distance scaling. Accepts `hit_type` parameter
  (`"ability"` for affix procs like Firebrand, Chain Lightning, Thunderclap).
- **`skill_system.gd` type inference**: Dictionary values accessed via `skill["level"]` are
  `Variant` type. Using `:=` with arithmetic on them causes parse errors. Fix by explicitly
  casting: `var level_factor: float = 1.0 - (float(skill["level"]) / MAX)`.
- **Horse nameplate**: Uses a single `Label3D` (name + stars combined), no banner/background.
  `fixed_size` is disabled so the text scales with player distance. `font_size = 48`,
  `pixel_size = 0.005`.
- **`dev_mode` is not persisted**: `Inventory.dev_mode` resets to `false` on every game restart.
  The pause menu checkbox reads the current value on open.
- **Chest UI `call_deferred` pattern**: `refresh_chest_ui()` and `_refresh_inventory_ui()` MUST
  be called via `call_deferred()` when invoked from `gui_input` signal handlers (e.g.
  `on_chest_slot_click`, `deposit_inv_slot_to_chest`, `deposit_item_to_chest`). Direct calls
  trigger "Attempted to free a locked object" because `refresh_chest_ui` frees the slot node
  that is still emitting the signal. Also hide tooltip before freeing chest slot children.

---

## Performance & Zone System Architecture

### Zone lifecycle (3-stage pipeline)
Zone generation uses a **threaded 3-stage pipeline** to keep the main thread under budget:

| Stage | Thread | Cost | What happens |
|-------|--------|------|--------------|
| Build | WorkerThreadPool | ~15ms (hidden) | `_build_zone_mesh()` noise computation + `ConcavePolygonShape3D` BVH construction |
| Mesh setup | Main thread, frame N | ~2ms | GPU upload via `add_surface_from_arrays()`, collision shape assignment, node setup |
| Populate | Main thread, frame N+1 | ~5-10ms | `ZonePopulator.populate_zone()` spawns trees, rocks, creatures, grass |

Mesh setup and population **never share the same frame** (enforced by `return` after processing
a populate item). This ensures no single frame exceeds ~15ms of zone work.

- `WorldGenerator._physics_process()` runs every physics frame: queues zones within `load_radius_zones` (2),
  submits builds to the thread pool, finalizes completed zones, and unloads distant zones.
- At any time, ~25 zones are loaded (5×5 grid). Up to `MAX_ZONES_PER_FRAME = 2` zones can be
  submitted to background threads per frame (the actual computation is off-thread so this is cheap).
- `_unload_distant_zones()` recycles zone roots via `ZonePool.recycle_zone()` (not `queue_free()`).
- Zone roots are stored in `_loaded_zones: Dictionary[Vector2i, StaticBody3D]` and erased on unload.
  `_explored_zones` and `_explored_sub_chunks` are lightweight `Dictionary[key, true]` maps for the minimap;
  they grow unbounded but are just booleans and not a performance concern.

**Key data structures:**
- `_gen_in_flight: Dictionary` — zone coords currently being built on worker threads
- `_finalize_backlog: Array` — zones with mesh/shape ready, waiting for main-thread GPU upload
- `_populate_backlog: Array` — zones with terrain visible, waiting for object spawning next frame
- `_terrain_mesh_cache: Dictionary` — `Vector2i → Array` (mesh vertex/normal/index/color/UV arrays)
- `_terrain_shape_cache: Dictionary` — `Vector2i → ConcavePolygonShape3D` (pre-built BVH)
- `_gen_mutex: Mutex` — protects `_gen_ready_queue` (worker→main thread communication)

**Spawn area exception:** `_generate_spawn_area()` runs all 3 stages synchronously (including
populate) for the 9 zones around spawn, because the player must land on fully populated terrain.

### Material caching (critical for draw calls)
- **Tree leaf materials** are cached per tree-type (texture + base color) in `_cached_leaf_mats`.
  DO NOT create unique ShaderMaterials per tree — each unique material prevents GPU batching and
  creates a separate draw call. Wind parameters are fixed at cached values.
- **Grass materials** are cached per texture+color in `_cached_grass_mats`. DO NOT mutate cached
  materials with per-zone wind variation (e.g. `mat.set_shader_parameter("wind_strength", ...)`)
  after retrieving from cache — that modifies the shared material for all zones.
- **Creature sprite materials** are cached per texture RID in `_cached_creature_mats`.
- General rule: if a helper function like `_make_*_mat()` creates a `ShaderMaterial.new()`,
  it MUST cache and reuse. Unique materials per-node is the #1 draw call multiplier.

### Zone LOD culling
- `_update_zone_lod()` in `world_generator.gd` hides grass (`Grass_*` nodes) for zones >1.5 away
  and saplings for zones >2.0 away. This halves active draw calls since distant grass is invisible anyway.
- The terrain mesh and trees remain visible at all loaded distances.

### Creature distance sleep
- `creature_ai.gd` has a distance-based sleep system: creatures >100m from the nearest player
  skip their full `_physics_process()` (pathfinding, aggro, proximity labels). They re-check
  distance every 1 second and wake up when the player approaches or if they're in combat.
- Sleep is disabled during CHASE and ATTACK states so mid-combat creatures never freeze.

### FPS degradation bug — diagnosis and fixes (mostly resolved)

The game originally started at 60fps but degraded to 9-25fps after 5-10 minutes of exploration.
Through systematic profiling with a debug panel (F3), the root causes were identified and fixed
in layers. FPS now holds 50-60 during extended exploration.

#### Root causes identified (in order of discovery)

1. **Resource leaks from `queue_free()`**: Godot's `queue_free()` on zone `StaticBody3D` roots
   does not fully release server-side resources (`Mesh`, `Material`, `Shape3D` held by
   RenderingServer/PhysicsServer). These leaked RIDs accumulated as zones loaded/unloaded.
   **Fix**: Object pooling via `zone_pool.gd` — nodes are recycled, not freed.

2. **High draw calls from saplings**: Each sapling leaf was a separate `MeshInstance3D` with a
   unique material, preventing GPU batching. With hundreds of saplings, draw calls hit 2000+.
   **Fix**: Converted to `MultiMeshInstance3D` with shared cached materials.

3. **Terrain regeneration on revisit**: Every time a zone was loaded (including revisits),
   `_build_zone_mesh()` ran ~22,000 noise evaluations and `create_trimesh_shape()` rebuilt the
   BVH tree. This cost 15-20ms per zone on the main thread.
   **Fix**: Terrain mesh array + `ConcavePolygonShape3D` caching in `_terrain_mesh_cache` and
   `_terrain_shape_cache`. Revisited zones skip all computation.

4. **Main-thread zone generation blocking**: Even with caching, first-time zone visits ran
   `_build_zone_mesh()` (~5ms noise) + `create_trimesh_shape()` (~10ms BVH) + `populate_zone()`
   (~5-10ms spawning) all on the main thread in a single frame = 20-25ms spike.
   **Fix**: 3-stage threaded pipeline (see "Zone lifecycle" above). Noise and BVH run on
   `WorkerThreadPool`. Mesh upload and object spawning are split across separate frames.

#### Attempted fixes that did NOT help (context for future agents)
- `visibility_range_end` on zone objects — no measurable impact
- Deep resource cleanup (nullifying mesh/material/shape refs before `queue_free()`) — Godot
  still holds internal server references
- Creature distance-based sleep — helped `phys` time but not `proc`

#### Object pooling (`zone_pool.gd`)
Instead of `queue_free()` on zone children, nodes are categorized (tree, rock, sapling, grass
MMI, zone root) and stashed in typed static pools. When a new zone generates, `_create_tree()`,
`_create_rock()`, `_scatter_grass()`, and `_scatter_saplings()` check the pool first. Reused
nodes keep their server-side RIDs alive — zero new allocations. Creatures, villages, and loot
drops are still `queue_free()`'d. Pooled nodes have `process_mode = PROCESS_MODE_DISABLED` to
remove them from physics/render processing while stored.

#### Terrain caching
- `_terrain_mesh_cache: Dictionary[Vector2i, Array]` stores the vertex/normal/UV/color/index
  arrays from `_build_zone_mesh()`. On revisit, the cached arrays are passed directly to
  `add_surface_from_arrays()` — no noise computation needed.
- `_terrain_shape_cache: Dictionary[Vector2i, ConcavePolygonShape3D]` stores the collision
  shape with its pre-built BVH. On revisit, the shape is assigned directly to the
  `CollisionShape3D` — no `create_trimesh_shape()` call.
- Both caches grow unbounded (one entry per unique zone ever visited). At ~1000 zones explored,
  memory usage is ~670MB VRAM which is acceptable on modern GPUs.

#### Debug panel (`scripts/debug/debug_panel.gd`)
Accessible via F3 or the pause menu "Debug Panel" button. Provides:
- **Spawning toggles**: Trees, Rocks, Saplings, Grass, Creatures, Villages, Stones, Fish, Horses,
  Terrain Collision, Minimap Refresh — each can be toggled off to isolate FPS impact.
- **Actions**: Flush Object Pool, Nuke All Zones (regenerate), Disable/Enable ALL Spawning.
- **Live metrics**: FPS (color-coded), node count, object count, draw calls, proc/phys times,
  pool stats.
- Toggle states are stored as `static var debug_skip_*` flags on `ZonePopulator` so they
  persist across zone loads. The panel also hides/disables existing instances in the scene.

#### Performance diagnostics
A 5-second printout in `world_generator.gd` (`_diag_timer`) logs:
```
[PERF DIAG] FPS=60 nodes=3000 objects=12000 draws=400 vram=625MB buf=89MB tex=-300MB
  proc=15ms phys=3ms zones=26 enemies=17 interact=500 loot=50 explored=200 sub=1400
  tcache=150 bg=0 mesh_q=0 pop_q=1 pool[z=0 t=10 r=0 s=0 g=0 re=2000 ru=1990]
```
Key fields: `tcache` = terrain cache size, `bg` = zones building on threads, `mesh_q` = zones
awaiting mesh finalization, `pop_q` = zones awaiting object population, `re` = total recycled,
`ru` = total reused from pool.

#### Remaining known issues
- `OBJECT_COUNT` still grows over time (~20k after extended exploration) due to terrain cache
  holding mesh arrays and shapes for all visited zones. This doesn't cause FPS drops but
  increases memory usage.
- `tex` (texture VRAM counter) goes increasingly negative — a Godot Metal driver accounting
  bug on Apple Silicon. Does not affect actual rendering.
- FPS can still dip to ~43-50 during rapid exploration of completely new territory (never-cached
  zones). This is the cost of `populate_zone()` object spawning on the main thread. Revisiting
  cached zones is instant.

### GDScript type inference pitfalls
- `var dx := od.global_position.x - my_pos.x` fails with "Cannot infer the type" if `od` was
  cast via `as LootDrop` (nullable cast). Use explicit `var dx: float = ...` instead of `:=`.
- `Dictionary` values from `get_nodes_in_group()` are `Variant`; arithmetic on them needs casting.
- **Freed instance in typed variable**: `var node: Node = dict["node_ref"]` errors with
  "Trying to assign invalid previously freed instance" if the stored node was freed between
  frames. Use untyped `var node = dict["node_ref"]` then guard with `is_instance_valid(node)`.
  This bit the `_populate_backlog` in `world_generator.gd` — fast flight causes zones to be
  recycled before their deferred populate step runs.

### Grass system
- 4 grass varieties per hearthlands zone (reduced from 9 for performance), each a `MultiMeshInstance3D`
  with 40-60 cross-quad instances. Named `Grass_0` through `Grass_3` under the zone root.
- Grass is only spawned in `hearthlands` biome. The grass shader (`grass_billboard.gdshader`)
  handles wind animation. Grass textures are procedurally generated at startup (20 varieties in
  `_grass_textures[]`), only 4 are used per zone.

### Village generator
- `VillageGenerator` (class_name) must be accessed via `const _VillageGenerator := preload(...)` in
  `zone_populator.gd`, NOT by bare class name. Godot's editor sometimes fails to resolve newly
  added `class_name` declarations for files created outside the editor.
- Huts use individual `StaticBody3D` pieces (walls, floors, roofs) with `collision_layer = 8,
  collision_mask = 1`, each with `build_id` metadata matching player building items. The hut anchor
  is a plain `Node3D` in the `&"structures"` group for grass suppression. Individual pieces are also
  in `&"structures"` and have their own `build_id` so the salvage system can reclaim them.
- Hero assets (GLBs) are loaded via `load()` which caches the PackedScene; subsequent instantiations
  reuse the cached scene. The procedural fallback (`_place_hero_fallback`) activates if GLBs are missing.
- Village chests follow the same pattern as cave chests: `StaticBody3D` in `&"chests"` +
  `&"interactables"` groups, with `chest_contents` meta (32-slot Array of Dictionaries).
- **RNG sensitivity**: Village generation consumes RNG calls sequentially (hut variation index,
  overlap check, face angle, wall removal, chest roll, etc.). Adding/removing ANY `rng.*()` call
  shifts the entire sequence for that seed. This can cause a village that previously had 4 chests
  to have 0 chests (or vice versa). The guaranteed-minimum-1-chest fallback guards against this.
- **Dead code warning**: `player_combat.gd` contains duplicate bow functions (`fire_bow`,
  `spawn_arrow`, `tick_arrows`) that are NEVER called at runtime. The actual active bow logic
  lives in `player_controller.gd` (`_fire_bow`, `_spawn_arrow`, `_tick_arrows`). Do NOT modify
  the `player_combat.gd` versions thinking they'll have any effect — always check which file
  contains the live code path before making changes.
