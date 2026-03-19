# Oathbound — Quick Reference for AI Agents

This file gets an AI agent up to speed on the Oathbound Godot 4 project.
All game code lives under `/Users/andreattar/Documents/Games/Oathbound/`.

---

## Project Structure (key files)

```
scripts/
  player/player_controller.gd    — Player movement, combat, animations, HUD, weapons, bow, building,
                                    inventory, crafting, pause menu, workbench, chest UI
  player/interaction_manager.gd   — E-key interaction logic
  creatures/creature_ai.gd        — All creature behavior, HP, animations, floating UI, death, status effects
  world/zone_populator.gd         — Creature/resource spawning, model paths, scales, yaw offsets, stats
  items/loot_drop.gd              — Ground loot pickups, nameplate UI, star system, pickup text
  ui/main_menu.gd                 — Main menu, character/world selection, delete confirmation
  ui/damage_number.gd             — Floating Label3D that rises and fades (DamageNumber class)
  autoloads/audio_manager.gd      — SFX and music playback (pooled AudioStreamPlayer/3D)
  autoloads/item_database.gd      — Item definitions, rarity colors, star IDs, crafting, star-quality crafting, affix registry
  autoloads/inventory.gd          — Inventory slots, equipment, star-aware consume/preview, star-capped helpers
  autoloads/game_events.gd        — Signal bus (item_picked_up, inventory_changed, etc.)
scenes/world/test_world.tscn      — Main world scene (lighting, shadows)
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

## Player Character (Tripo Barbarian)

- **Model**: `res://models/player/Lowpolyvikingwithaxe/barbarian+3d+model.glb`
- **Texture**: `barbarian+3d+model_barbarian3dmodel_basecolor.jpg` (applied via `_apply_tripo_player_texture`)
- **Scale**: 4.0
- **Rotation**: `-PI/2` offset via `_player_yaw_offset` (applied in `_rotate_model` and `_respawn`)
- External Mixamo animations are **SKIPPED** (`if not is_tripo_barbarian: _load_external_animations()`)
  because they target a different skeleton. Uses built-in NlaTracks only.
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
- `_try_attack()` applies `rapid_strikes`/`rapid_chop`/`quick_strike` (×0.88 cooldown), `sharpened_edge`/`precision_strike` (+15% dmg), `reaching` (×1.2 range), and `efficient_miner` (-20% stamina) before scheduling resolve
- `_resolve_attack()` runs after `hit_delay` (0.18s or 0.30s for 2h), checks enemies + harvestables
  - Includes crit roll, affix damage modifiers, and post-hit affix procs (see affix ordering)
- **Harvestable hit cap**: Max 2 per swing (or 3 with `timber_cleave` axe affix), sorted by distance (closest first)
- Tree drops boosted by axe affixes: `lumberjack` (+40%), `double_yield` (10% double), `bark_stripper` (25% resin)
- Rock drops boosted by pickaxe affixes: `prospector` (+40% stone), `ore_seeker` (+30% copper), `rich_vein` (10% double), `vein_finder` (30% bonus ore)
- `deep_cut` (axe) and `stone_breaker` (pickaxe) add +50% damage to trees/rocks respectively
- `sap_drinker` (axe) and `geologist` (pickaxe) heal +2 HP per resource hit
- Tree hit: plays `axe_chop` (non-positional); fists play `fist_hit_tree`
- Stone hit: plays `pickaxe_hit` (non-positional)
- All player combat audio uses `play_sfx()` (non-positional) for constant volume regardless of zoom
- **Player death guard**: `take_damage()` returns early if `current_health <= 0.0` (unless `undying` triggers)

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
- Blocking: `final_amount *= 0.3` (or `0.2` with `guardian` affix)
- Armor: `final_amount *= max(1.0 - armor_value * 0.02, 0.2)` (caps at 80% reduction)
- Full 0★ leather set (10 armor) → 20% damage reduction
- Additional layers from affixes: thick_skinned, fortified, last_stand, battle_hardened (see affix ordering)

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
- Affixes are rolled via `roll_affixes(crafted_stars, get_affix_slot(item_id))` and encoded into the output ID

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
Affixes extend the composite ID: `base_id:stars:affix1,affix2` (sorted alphabetically).
Example: `stone_sword:4:lifesteal,rapid_strikes`. Items with 0-2★ keep `base_id:stars`.

### Affix registry (`item_database.gd`)
- `AFFIXES` dictionary: ~88 entries keyed by StringName, each with `name`, `description`, `slot`, `tier`
- `slot` is the **specific** weapon class or armor slot: `"axe"`, `"pickaxe"`, `"sword"`, `"bow"`, `"chest"`, `"legs"`, `"feet"`
- `tier`: 1 (common) or 2 (rare, weighted 0.5x in rolling)
- `get_affix_slot(item_id)` — returns the affix pool key for an item (calls `get_weapon_class()` for weapons or reads `armor_slot` for armor)
- `roll_affixes(stars, affix_slot)` — weighted random selection without replacement from the matching pool
- `_get_affix_pool(affix_slot)` — filters affixes by exact slot match
- `get_affix_data(affix_id)` — returns affix dictionary

### Axe affixes (10) — woodcutting themed
`lumberjack` (+40% wood drops), `splitter` (trees fall 30% faster), `deep_cut` (trees take 1 fewer hit / +50% dmg),
`bark_stripper` (25% bonus resin), `double_yield` (10% double wood), `timber_cleave` (hit 3 trees per swing),
`sharpened_edge` (+15% axe damage), `heavy_chop` (+30% knockback), `rapid_chop` (12% faster swing),
`sap_drinker` (+2 HP per tree chop)

### Pickaxe affixes (10) — mining themed
`prospector` (+40% stone drops), `vein_finder` (30% bonus ore), `precision_strike` (+15% pickaxe damage),
`stone_breaker` (rocks take 1 fewer hit / +50% dmg), `efficient_miner` (-20% stamina cost),
`rich_vein` (10% double stone), `heavy_swing` (+30% knockback), `quick_strike` (12% faster swing),
`ore_seeker` (+30% copper ore drops), `geologist` (+2 HP per mining hit)

### Sword affixes (18) — melee combat themed
`windfury` (30% extra 2 attacks), `lifesteal` (8% heal), `firebrand` (15% fire bonus),
`frostbite` (20% slow), `venomous` (12% poison), `stunning_blow` (8% stun),
`executioner` (+30% to low HP), `berserker` (+dmg from missing HP),
`sharpened` (+10% crit), `savage` (+40% crit dmg), `rapid_strikes` (12% faster),
`cleaving` (wider arc), `momentum` (+4%/stack), `reaching` (+20% range),
`chain_lightning` (10% arc), `bane` (8% double dmg), `siphon` (+3 stam/hit),
`runic` (12% AoE)

### Bow affixes (10) — ranged combat themed
`precision` (+20% headshot dmg), `multishot` (20% double arrow), `piercing` (arrow pierce),
`sniper` (+25% dmg at long range), `rapid_draw` (15% faster draw), `poison_tip` (30% apply poison),
`frost_arrow` (35% slow target), `explosive` (10% AoE on impact), `steady_aim` (+12% crit while still),
`quiver_mastery` (15% no arrow consumption)

### Chest armor affixes (10) — defense themed
`vitality` (+15 max HP), `fortified` (+8% DR), `iron_skin` (8% negate dmg),
`thorns` (15% reflect), `second_wind` (heal at 20% HP), `undying` (revive once, 300s CD),
`bulwark` (+3 flat armor), `regenerator` (+1 HP/s always), `guardian` (block→20%),
`battle_hardened` (+5%/enemy DR max 3)

### Legs armor affixes (10) — stamina/resilience themed
`endurance` (+20 max stamina), `resilience` (+25% stam regen), `steadfast` (KB immune),
`thick_skinned` (first hit -30%, 10s CD), `last_stand` (+25% DR below 25% HP),
`fleet` (-25% sprint stam cost), `rejuvenation` (+30% HP regen), `quick_recovery` (-2s regen delay),
`lucky` (+5% rare drop chance), `tenacity` (min 60% move speed)

### Boots armor affixes (10) — movement themed
`swiftness` (+10% move speed), `aquatic` (+30% swim speed), `warmth` (-40% swim stam cost),
`featherfall` (-50% fall dmg), `evasion` (5% dodge), `adrenaline` (on kill +15% speed 4s),
`sure_footed` (no slope penalty), `light_step` (-30% fall dmg + silent), `trailblazer` (+15% water speed),
`nimble` (+8% dodge while sprinting)

### Combat integration (`player_controller.gd`)
- `_get_active_affixes()` — cached dictionary of all equipped affixes (weapon + armor), invalidated on inventory change via `_invalidate_affix_cache()` called from `_on_inventory_changed()`
- `_has_affix(id)` — O(1) lookup, safe to call from hot paths
- `_get_weapon_affixes()` — affixes on currently equipped weapon only
- `_apply_affix_stat_bonuses()` — called on equip change, adjusts `max_health`/`max_stamina` while preserving current ratio
- `_tick_affix_timers(delta)` — runs each physics frame, counts down momentum, second_wind, thick_skinned, undying, and adrenaline timers
- Sword procs fire in `_resolve_attack()` (melee); bow procs fire in `_fire_bow()` / `_tick_arrows()`; axe/pickaxe procs fire in `_hit_harvestable()` / `_destroy_rock()` / `_fell_tree()`
- Armor procs fire in `take_damage()` (chest), `_handle_movement()` (boots), `_handle_stamina()` (legs)
- Sword crit system: base `5% + dex*0.5`, `sharpened` adds +10%, `savage` adds +40% to crit damage
- Bow crit: `steady_aim` adds +12% crit while standing still
- Windfury uses `_windfury_guard` bool to prevent infinite recursion when extra attacks trigger

### `take_damage()` affix ordering
1. Iron Skin — full negate (early return)
2. Evasion / Nimble — dodge roll (early return, combined chance)
3. Thick Skinned — first-hit reduction (10s cooldown)
4. Block (Guardian modifies multiplier 0.3→0.2)
5. Armor (Bulwark adds +3 flat)
6. Fortified (×0.92)
7. Last Stand (×0.75 below 25% HP)
8. Battle Hardened (×0.95 per nearby enemy, max 3)
9. Apply damage
10. Quick Recovery (reduces regen delay by 2s)
11. Thorns (reflect 15% to source)
12. Second Wind (heal 20% HP below 20%, 45s CD)
13. Undying (revive at 10% HP on death, 300s CD)

### `_resolve_attack()` affix ordering (swords)
1. Pre-damage modifiers: berserker, momentum stacks, sharpened_edge/precision_strike (+15% dmg for axes/pickaxes)
2. Crit roll (sharpened/savage)
3. Per-enemy modifiers: executioner, bane
4. Post-hit procs: lifesteal, siphon, firebrand, chain_lightning, runic, frostbite, venomous, stunning_blow
5. Momentum stack update
6. Windfury check (2 recursive calls with guard)

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
- Description in gray (`#aaaaaa`)

### Bow affix specifics
- Crit is rolled once per shot in `_fire_bow()` (not per arrow)
- `steady_aim` adds +12% crit chance when player is standing still
- `rapid_draw` increases bow tension buildup by 15%
- Multishot spawns a second arrow offset by `cam_right * 0.3`
- Piercing tracks `arrow.set_meta("pierce_count", ...)` — skips marking `hit=true` on first enemy
- Precision increases headshot multiplier from 1.3 to 1.5 in `_tick_arrows()`
- `sniper` adds +25% dmg when distance to target > 15 units
- `frost_arrow` (35% slow), `poison_tip` (30% poison), `explosive` (10% AoE) trigger from arrow hits

### Loot drop affix integration (`_spawn_single_drop()` in `loot_drop.gd`)
- Checks if item is equipment (`type` in `["weapon", "armor"]`) and `stars >= 3`
- Calls `ItemDatabase.roll_affixes(stars, ItemDatabase.get_affix_slot(id))` and encodes into composite ID via `make_star_id()`
- Player affix `lucky` is checked at the top of `spawn_loot()` by looking up the player node from the SceneTree

### Save/load
Affixes are encoded in the StringName item ID, already persisted by inventory serialization.
`save_manager.gd` has `_migrate_missing_affixes()` and `_migrate_item_id()` which retroactively
roll affixes for 3+ star equipment loaded from old saves. Migration now uses `get_affix_slot()` to
roll the correct weapon-specific or armor-slot-specific affixes.

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
- Horses: 15% chance per hearthlands/thornwood zone
- Creature visibility range: 60 units (`VISIBILITY_RANGE_FADE_DISABLED`)

---

## Camera

- 3rd-person via `SpringArm3D` (`$CameraPivot/SpringArm3D`)
- `zoom_speed`: 0.5 per scroll tick
- `min_zoom`: 2.0, `max_zoom`: 12.0
- **Spawn default**: 85% zoomed out (`spring_length = min_zoom + 0.85 * (max_zoom - min_zoom)` = 10.5)
  Set in `_ready()` so the player starts with a wide overview on login

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

### Pause menu
- ESC opens pause menu (transparent overlay so game is still visible)
- Game tree is paused (`get_tree().paused = true`), Master audio bus muted
- Contains: Music slider, SFX slider, Resume, "Exit to Character Screen", "Exit Game"
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
  Equipment with affixes: `"base_id:stars:affix1,affix2"` (e.g. `"stone_sword:3:windfury"`).
  `parse_star_id()` splits on the **first** colon (changed from `rfind` to `find`); returns
  `{"base_id": ..., "stars": ..., "affixes": [...]}`. `make_star_id()` creates them. 0★ items
  have no suffix. Affixes in the ID are always sorted alphabetically for deduplication.
- Affix cache (`_cached_affixes`) is a Dictionary `{affix_id: true}` rebuilt on inventory change.
  Don't forget to call `_invalidate_affix_cache()` if you change equipment outside normal flow.
- **Affixes are weapon-class/armor-slot specific**: `get_affix_slot()` determines the pool.
  Axe→woodcutting, pickaxe→mining, sword→combat, bow→ranged, chest→defense, legs→stamina, feet→movement.
  There are NO universal affixes anymore; each slot has exactly 10 affixes.
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
- **Raft dismount rotation bug**: During raft riding, `rotation.y` on the CharacterBody3D is synced
  to the raft heading. `_dismount_raft()` must reset `rotation = Vector3.ZERO` on both code paths
  (normal dismount + early-exit), otherwise the player model faces sideways after leaving the raft.
  The model's local rotation (via `_rotate_model()`) combines with the parent body rotation.
- Debug print `[CREATURE] <name> (kind=...) anim_map=... full_list=...` logs on every spawn.
- Debug print `[PLAYER ANIM] '<name>' not found...` logs when player animation is missing.
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
