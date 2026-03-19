# Oathbound

A 3D survival-crafting RPG built in **Godot 4** with GDScript. Explore a procedurally generated open world, harvest resources, craft gear, fight creatures, and build a base.

## Tech Stack

- **Engine:** Godot 4 (GDScript)
- **Rendering:** Forward+ with custom shaders (water, foliage wind, grass billboards, leaf billboards)
- **World Gen:** Procedural zones with biomes, rivers, lakes, and caves
- **Assets:** 32x32 pixel art icons, GLB/GLTF 3D models

## Project Structure

```
Oathbound/
├── scripts/
│   ├── autoloads/          # Singletons (ItemDatabase, Inventory, SaveManager, GameEvents, etc.)
│   ├── player/             # Player controller, skills, food/comfort systems
│   ├── creatures/          # Creature AI, fish behavior
│   ├── items/              # LootDrop
│   ├── world/              # WorldGenerator, ZonePopulator, CaveGenerator, PortalSystem
│   ├── combat/             # CombatController, DamageSystem
│   ├── building/           # Player-built structures
│   ├── interactables/      # Workstations, chests, harvestable resources
│   └── data/               # Biome data, workstation data
├── textures/
│   └── items/              # 32x32 pixel art icons (all items)
│       └── archived/       # Old/unused icon assets
├── models/                 # 3D models (player, armor, creatures)
├── scenes/                 # Game scenes, UI
└── shaders/                # Terrain, water, foliage, grass
```

## Core Systems

### World Generation

- Circular map (~10,000 unit radius) divided into 64x64 unit zones
- Watershed-based rivers using D8 flow accumulation
- Lakes generated from noise
- **Biomes:** Hearthlands, Thornwood, Scorched Steppe, Ocean
- **Microbiomes (Hearthlands):** Meadow, Forest, Birch Forest, Hills, Riverside
- Zones populate with trees (Oak, Birch, Pine, Willow, Palm), rocks (30 procedural mesh variants), bushes, grass, enemies, horses, fish, and cave entrances

### Combat System

Oathbound uses **context-based weapon switching** — the equipped weapon used depends on what the player interacts with:

| Action | Input | Weapon Slot Used |
|--------|-------|-----------------|
| Attack enemies | Left-click on creature | **Sword** slot |
| Chop trees | Left-click on tree | **Weapon** (axe) slot |
| Mine rocks | Left-click on rock | **Pickaxe** slot |
| Ranged attack | Hold right-click (bow draw) → left-click to fire | **Bow** slot |
| Block | Right-click (with shield) | **Shield** slot |

**Damage variance:** All weapon damage has a ±30% random range per hit.

### Equipment Slots

Players have 8 equipment slots, each with a dedicated purpose:

| Slot | Purpose | Ghost Icon |
|------|---------|------------|
| Weapon | Axe for chopping trees | Stone axe |
| Sword | Melee combat vs creatures | Stone sword |
| Bow | Ranged combat | Crude bow |
| Pickaxe | Mining rocks/ore | Stone pickaxe |
| Shield | Blocking damage | Wood shield |
| Chest | Body armor | Leather vest |
| Legs | Leg armor | Leather pants |
| Feet | Boot armor | Leather boots |

### Starting Gear

New characters spawn with "Terrible" quality gear (grey text) in all equipment slots and nothing in the inventory:

| Slot | Item | Flavor |
|------|------|--------|
| Weapon | Splintered Hatchet | "Half the handle is missing and the head is held on by sheer stubbornness." |
| Sword | Rusty Butter Knife | "It's a flat piece of scrap metal that couldn't cut warm butter." |
| Bow | Sad Twig & String | "Arrows fired from this may actually apologize to their targets on impact." |
| Pickaxe | Blunt Rock-Poker | "Rocks openly mock you when you swing this. Even pebbles feel safe." |
| Chest | Moth-Eaten Rag | "The moths that lived in it left for somewhere nicer." |
| Legs | Questionable Trousers | "They smell like regret and old cheese." |
| Feet | Soggy Foot Wraps | "They provide the same protection as a strongly-worded letter." |

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
| **Thick Hide** | Grizzly, Lion, Minotaur (rare) |
| **Fang** | Wolf, Lion, Hawk (rare) |
| **Ancient Bone** | Orc Brute, Cyclops, Minotaur (rare) |
| **Ember Stone** | Fire Imp (rare) |
| **Frost Shard** | Frost Wraith (rare) |
| **Gold** | Goblin, Orc Brute, Cyclops (rare) |
| **Amber** | Trees (Ancient Grove axe affix, 20% chance) |
| **Living Wood** | Trees (Ancient Grove axe affix, 20% chance) |
| **Fairy Dust** | Trees (Ancient Grove axe affix, 20% chance) |
| **Gemstone** | Rocks (Deep Earth pickaxe affix, 20% chance) |

### Weapon Tier Progression

#### Axes (Woodcutting)

| Tier | Name | Damage | Recipe |
|------|------|--------|--------|
| 0 | Splintered Hatchet | 6 | Starting gear |
| 1 | Stone Axe | 18 | 5 wood, 4 stone |
| 2 | Flint Axe | 15 | 3 wood, 5 flint |
| 3 | Iron Axe | 30 | 8 wood, 6 copper_ore |
| 4 | Steel Axe | 45 | 10 wood, 8 copper_ore, 2 gold |

#### Swords (Melee Combat)

| Tier | Name | Damage | Recipe |
|------|------|--------|--------|
| 0 | Rusty Butter Knife | 5 | Starting gear |
| 1 | Stone Sword | 18 | 5 wood, 6 stone |
| 2 | Bronze Sword | 25 | 4 wood, 5 copper_ore |
| 3 | Iron Sword | 40 | 6 wood, 8 copper_ore |
| 4 | Steel Sword | 55 | 8 wood, 10 copper_ore, 3 gold |

#### Bows (Ranged)

| Tier | Name | Damage | Recipe |
|------|------|--------|--------|
| 0 | Sad Twig & String | 3 | Starting gear |
| 1 | Crude Bow | 12 | 4 wood, 2 leather |
| 2 | Hunting Bow | 20 | 6 wood, 4 leather, 2 feather |
| 3 | War Bow | 30 | 8 wood, 5 leather, 4 bone |
| 4 | Longbow | 40 | 10 wood, 6 leather, 3 thick_hide |

#### Pickaxes (Mining)

| Tier | Name | Damage | Recipe |
|------|------|--------|--------|
| 0 | Blunt Rock-Poker | 4 | Starting gear |
| 1 | Stone Pickaxe | 8 | 4 wood, 3 stone |
| 2 | Bronze Pickaxe | 14 | 5 wood, 4 copper_ore |
| 3 | Iron Pickaxe | 20 | 6 wood, 6 copper_ore |
| 4 | Steel Pickaxe | 28 | 8 wood, 8 copper_ore, 2 gold |

#### Maces (Heavy Melee)

| Tier | Name | Damage | Knockback |
|------|------|--------|-----------|
| 1 | Stone Mace | 22 | 35 |
| 2 | Bronze Mace | 35 | 50 |
| 3 | Iron Mace | 45 | 55 |
| 4 | Steel Mace | 60 | 65 |

### Armor Tier Progression

#### Chest Armor

| Tier | Name | Armor |
|------|------|-------|
| 0 | Moth-Eaten Rag | 1 |
| 1 | Leather Vest | 5 |
| 2 | Chain Chest | 10 |
| 3 | Iron Chest | 18 |
| 4 | Steel Chest | 28 |

#### Leg Armor

| Tier | Name | Armor |
|------|------|-------|
| 0 | Questionable Trousers | 0.5 |
| 1 | Leather Pants | 3 |
| 2 | Chain Legs | 7 |
| 3 | Iron Legs | 12 |
| 4 | Steel Legs | 20 |

#### Boots

| Tier | Name | Armor |
|------|------|-------|
| 0 | Soggy Foot Wraps | 0.5 |
| 1 | Leather Boots | 2 |
| 2 | Chain Boots | 5 |
| 3 | Iron Boots | 8 |
| 4 | Steel Boots | 14 |

#### Shields

| Tier | Name | Armor |
|------|------|-------|
| 1 | Wood Shield | 10 |
| 2 | Reinforced Shield | 15 |
| 3 | Bronze Shield | 22 |
| 4 | Iron Kite Shield | 30 |
| 5 | Steel Tower Shield | 40 |

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

## Star / Rarity System

Items can roll 0-5 stars, affecting stats and enabling affixes:

| Stars | Rarity | Drop Weight | Affixes |
|-------|--------|-------------|---------|
| 0 | Common | 82.0% | 0 |
| 1 | Uncommon | 10.9% | 0 |
| 2 | Rare | 4.0% | 0 |
| 3 | Epic | 2.0% | 1 |
| 4 | Legendary | 0.8% | 2 |
| 5 | Mythical | 0.3% | 3 |

**Stat scaling per star:**
- Damage: +15% per star
- Armor: +25% per star
- Knockback: +10% per star
- Range: +5% per star

## Affix System

High-star equipment (3+) rolls random affixes from a pool specific to their item type. Tier 1 affixes are common; tier 2 affixes have half the roll weight.

### Axe Affixes (10)

| Affix | Tier | Effect |
|-------|------|--------|
| Lumberjack | 1 | +40% wood drops from trees |
| Splitter | 1 | Trees fall 30% faster |
| Deep Cut | 1 | Trees take 1 fewer hit to fell |
| Bark Stripper | 1 | 25% chance to get bonus resin from trees |
| Double Yield | 2 | 10% chance to double wood drops |
| Timber Cleave | 1 | Can hit up to 3 trees per swing |
| Frenzied Chop | 1 | 25% chance per tree swing to do 2 extra hits (windfury) |
| Master Woodsman | 1 | 2 extra star rerolls on wood drops (higher quality wood) |
| Rapid Chop | 1 | 12% faster axe swing speed |
| Ancient Grove | 2 | 20% chance to drop rare tree materials (amber, living wood, fairy dust) |

### Pickaxe Affixes (10)

| Affix | Tier | Effect |
|-------|------|--------|
| Prospector | 1 | +40% stone drops from rocks |
| Vein Finder | 2 | 30% chance for bonus ore from rocks |
| Frenzied Mining | 1 | 25% chance per rock swing to do 2 extra hits (windfury) |
| Stone Breaker | 1 | Rocks take 1 fewer hit to break |
| Efficient Miner | 1 | -20% stamina cost when mining |
| Rich Vein | 2 | 10% chance to double stone drops |
| Master Miner | 1 | 2 extra star rerolls on stone drops (higher quality stone) |
| Quick Strike | 1 | 12% faster pickaxe swing speed |
| Ore Seeker | 1 | +30% copper ore drops |
| Deep Earth | 2 | 20% chance to drop rare rock materials (gemstone, ancient bone, ember stone) |

### Sword Affixes (18)

| Affix | Tier | Effect |
|-------|------|--------|
| Windfury | 2 | 30% chance on hit to trigger 2 extra attacks |
| Lifesteal | 1 | Heal for 8% of damage dealt |
| Firebrand | 1 | 15% chance to deal bonus fire damage (50% weapon dmg) |
| Frostbite | 1 | 20% chance to slow enemy by 40% for 3s |
| Venomous | 1 | 12% chance to poison (3% max HP/s for 4s) |
| Stunning Blow | 2 | 8% chance to stun enemy for 1.5s |
| Executioner | 1 | +30% damage to enemies below 30% HP |
| Berserker | 1 | +1% damage per 2% missing health (up to +50%) |
| Sharpened | 1 | +10% critical hit chance |
| Savage | 1 | +40% critical hit damage |
| Rapid Strikes | 1 | 12% faster attack speed |
| Cleaving | 1 | Melee attacks hit in a wider arc |
| Momentum | 1 | Each hit within 3s adds +4% damage (max 5 stacks) |
| Reaching | 1 | +20% melee attack range |
| Chain Lightning | 2 | 10% chance to arc lightning to a nearby enemy (40% dmg) |
| Bane | 2 | 8% chance to deal double damage |
| Siphon | 1 | Restore 3 stamina per hit |
| Runic | 2 | 12% chance to trigger AoE for 25% weapon damage |

### Bow Affixes (10)

| Affix | Tier | Effect |
|-------|------|--------|
| Precision | 1 | +20% headshot damage |
| Multishot | 2 | 20% chance to fire 2 arrows |
| Piercing | 2 | Arrows pierce through the first target |
| Sniper | 1 | +25% damage at long range (>15 units) |
| Rapid Draw | 1 | 15% faster bow draw speed |
| Poison Tip | 1 | Arrows apply poison (2% max HP/s for 4s) |
| Frost Arrow | 1 | Arrows slow target by 35% for 3s |
| Explosive | 2 | 10% chance for arrows to deal AoE on impact |
| Steady Aim | 1 | +12% crit chance while standing still |
| Quiver Mastery | 1 | 15% chance to fire a bonus arrow on each shot |

### Mace Affixes (10)

| Affix | Tier | Effect |
|-------|------|--------|
| Skull Crusher | 1 | +25% damage to stunned enemies |
| Concussive | 1 | 20% chance to disorient enemies (-20% damage for 3s) |
| Bone Breaker | 2 | 10% chance to shred enemy armor by 30% for 5s |
| Earthshaker | 2 | 12% chance for ground slam AoE (30% weapon dmg) |
| Brutal Force | 1 | +25% knockback distance |
| Staggering | 1 | 18% chance to interrupt enemy attacks |
| Relentless Fury | 1 | Each consecutive hit adds +5% damage (max 5 stacks) |
| Iron Will | 1 | +10% damage reduction while attacking |
| Crushing Momentum | 1 | On kill, +20% attack speed for 4s |
| Thunderclap | 2 | 8% chance to deal lightning AoE to enemies within 3 units |

### Chest Armor Affixes (10)

| Affix | Tier | Effect |
|-------|------|--------|
| Vitality | 1 | +15 max health |
| Fortified | 1 | +8% damage reduction |
| Iron Skin | 2 | 8% chance to completely negate damage |
| Thorns | 1 | Reflect 15% of damage taken to attacker |
| Second Wind | 2 | When hit below 20% HP, heal 20% HP (45s cooldown) |
| Undying | 2 | On death, revive with 10% HP (300s cooldown) |
| Bulwark | 1 | +3 flat armor |
| Regenerator | 2 | +1.0 HP/s even during combat |
| Guardian | 1 | Block reduces damage to 20% instead of 30% |
| Battle Hardened | 1 | +5% damage reduction per nearby enemy (max 3) |

### Leg Armor Affixes (10)

| Affix | Tier | Effect |
|-------|------|--------|
| Endurance | 1 | +20 max stamina |
| Resilience | 1 | +25% stamina regeneration rate |
| Steadfast | 1 | Immune to knockback |
| Thick Skinned | 2 | First hit in combat deals 30% less damage (10s cooldown) |
| Last Stand | 1 | +25% damage reduction below 25% HP |
| Fleet | 1 | Sprint stamina cost reduced by 25% |
| Rejuvenation | 1 | +30% health regeneration rate |
| Quick Recovery | 1 | Health regen starts 2s sooner after damage |
| Lucky | 1 | +5% rare drop chance from creatures |
| Tenacity | 1 | Cannot be slowed below 60% base speed |

### Boot Affixes (10)

| Affix | Tier | Effect |
|-------|------|--------|
| Swiftness | 1 | +10% movement speed |
| Aquatic | 1 | +30% swim speed |
| Warmth | 1 | Reduce swim stamina cost by 40% |
| Featherfall | 1 | Reduce fall damage by 50% |
| Evasion | 2 | 5% chance to auto-dodge an attack |
| Adrenaline | 1 | On kill, +15% movement speed for 4s |
| Sure-Footed | 1 | No movement speed penalty on slopes |
| Light Step | 1 | -30% fall damage and silent movement |
| Trailblazer | 1 | +15% movement speed in water |
| Nimble | 2 | +8% dodge chance while sprinting |

### Shield Affixes (10)

| Affix | Tier | Effect |
|-------|------|--------|
| Shield Wall | 1 | +15% block chance |
| Retaliation | 1 | After blocking, next attack deals +30% damage for 3s |
| Fortress | 2 | +5 flat armor while shield is equipped |
| Deflection | 1 | 15% chance to deflect projectiles |
| Steadfast Guard | 1 | Blocking no longer costs stamina |
| Aegis | 2 | 10% chance when hit to absorb 15% max HP as shield for 5s |
| Stalwart | 1 | -30% knockback received |
| Rally Cry | 1 | +2 HP/s while shield is equipped |
| Shield Bash | 1 | 25% chance when blocking to stun attacker for 1s |
| Unbreakable | 2 | When below 25% HP, blocking absorbs 100% of damage |

## Creatures

| Creature | Stars | Notable Loot |
|----------|-------|-------------|
| Boar | 0-5 | Meat, Leather, Bone |
| Grizzly | 0-5 | Meat, Leather, Thick Hide, Fang |
| Lion | 0-5 | Meat, Leather, Thick Hide, Fang |
| Wolf | 0-5 | Meat, Leather, Fang |
| Goblin | 0-5 | Bone, Gold |
| Orc Brute | 0-5 | Bone, Ancient Bone, Gold |
| Cyclops | 0-5 | Bone, Ancient Bone, Gold |
| Minotaur | 0-5 | Thick Hide, Ancient Bone, Gold |
| Fire Imp | 0-5 | Ember Stone, Gold |
| Frost Wraith | 0-5 | Frost Shard, Gold |

Creature HP and damage scale with stars: `base * (1.0 + stars * 0.4)`.

## Building System

Players can craft and place structures in the world. Enter build mode from the crafting menu, then left-click to place. Structures snap to adjacent pieces via snap points.

### Building Pieces

| Piece | Mesh Type | Size | Cost | Notes |
|-------|-----------|------|------|-------|
| Wood Wall | Box (procedural) | 3.6 × 5.0 × 0.20 | 4 wood | Textured with `wood_planks.png`. 20% thickness overlap at corners to prevent gaps. |
| Wood Floor | Box (procedural) | 3.6 × 0.1 × 3.6 | 3 wood | Textured with `wood_planks.png`. Snaps flush with walls. |
| Wood Stair | Stair (procedural) | 3.6 × 5.0 × 3.6 | 6 wood | 6-step `SurfaceTool` mesh with per-step `BoxShape3D` collisions for walkability. |
| Stone Wall | Box (procedural) | 3.6 × 5.0 × 0.20 | 6 stone | Textured with `cobblestone.png`. |
| Stone Floor | Box (procedural) | 3.6 × 0.1 × 3.6 | 4 stone | Textured with `cobblestone.png`. |
| Thatch Roof 45° | Roof mesh | 3.6 × 1.8 × 3.6 | 4 wood, 2 leather | Angled roof piece. |
| Thatch Roof 26° | Roof mesh | 3.6 × 0.9 × 3.6 | 4 wood, 2 leather | Shallow angle roof piece. |
| Workbench | Custom procedural | 4.2 × 2.7 × 2.4 | 6 wood | Wood-textured tabletop and legs. Required for mid-tier crafting. |
| Chest | Custom procedural | 2.4 × 1.8 × 1.5 | 4 wood, 2 copper_ore | Wood body with metal bands and latch. Storage container. |
| Bed | Custom procedural | 1.2 × 0.6 × 2.2 | 8 wood, 4 leather | Wood frame, mattress, blanket, pillow, head/footboards. |
| Campfire | Custom visual | 0.8 × 0.4 × 0.8 | 3 wood, 2 stone | Animated fire particles + light. Distance-culled for FPS. |
| Torch Post | Cylinder | 0.15 × 1.8 × 0.15 | 2 wood, 1 resin | Standing torch with point light. |
| Wall Torch | Custom visual | — | 1 wood, 1 resin | Mounts to walls. |
| Raft | Special | — | 12 wood, 4 leather | Water vehicle. Spawned separately. |

### Building Materials

All building materials are `StandardMaterial3D` with tiled textures:

| Material | Texture | Tint | UV Scale |
|----------|---------|------|----------|
| Wood | `wood_planks.png` | (0.45, 0.32, 0.15) | 2×2 |
| Stone | `cobblestone.png` | (0.55, 0.55, 0.58) | 2×2 |
| Thatch | `thatch.png` | (0.60, 0.50, 0.30) | 2×2 |
| Slate | `slate_roof.png` | (0.50, 0.50, 0.55) | 2×2 |

Building materials have `FLAG_DONT_RECEIVE_SHADOWS` enabled and light emission (35% energy) to prevent structures from appearing too dark in shadow.

### Shadow Handling

All placed structures have shadows disabled to avoid overly dark interiors:
- `cast_shadow = SHADOW_CASTING_SETTING_OFF` on every `MeshInstance3D` child
- `FLAG_DONT_RECEIVE_SHADOWS` set on all materials (duplicated from shared materials to avoid global side effects)
- Light emission added to building materials for ambient brightness

### Snap System

Structures snap to adjacent pieces. Each building type exposes snap points (edges, corners) that align with other pieces. Walls overlap by 0.10 units at edges to eliminate corner gaps and light leaks.

### Structure Distance Culling

All man-made structures (except campfires, which have their own culling) are hidden beyond 50 units from the player. A `Timer` on each structure checks distance every 0.5s and toggles visibility.

## Performance Optimizations

- **MultiMeshInstance3D** for grass and tree canopies (thousands of instances, single draw call)
- **SubViewport removal** — nameplates use Label3D + MeshInstance3D instead of per-entity SubViewports
- **Distance culling** — structures beyond 50 units hide meshes, lights, and sprites
- **Campfire culling** — fire particles and audio deactivate beyond player range
- **Throttled group queries** — `get_nodes_in_group` calls run on timers, not every frame
- **Cached node references** — frequently accessed nodes stored as variables
- **Heightmap lookups** — replace physics raycasts for terrain snapping
- **Loot despawn timers** — dropped items auto-despawn after 60-180 seconds
- **Zone cache pruning** — biome/water caches cleared when zones unload
- **Shader simplification** — reduced FBM octaves in water shader
- **Post-processing disabled** — SSAO and Glow off for performance

## Inventory & UI

- **Grid inventory** with drag-and-drop reordering
- **Right-click hold to equip** (0.5s progress bar) — moves item from inventory to equipment slot
- **Shift + right-click to drop** items on the ground
- **3-second pickup grace period** on dropped items to prevent accidental re-pickup
- **Tooltips** show item name, type (specific: "Axe", "Chest Armor", etc.), stats, quality, star level, and affixes
- **Crafting window** with building/equipment tabs and tier quality display (Low = white, Medium = blue, High = red)
- **Building mode crosshair** — white `+` reticle with dark outline, visible only during build mode
- **Nameplates** — creature/item names on `Label3D` with rectangular dark panel background, health bar underneath, dynamically sized. Stars colored by rarity.

## Mounts

Players can mount wild horses found in the world. While mounted:
- Movement speed is multiplied by `MOUNT_SPEED_MULT`
- Jumping is disabled to prevent flight exploits
- Vertical velocity is clamped to `[-10.0, 1.0]` for faster descent and limited upward movement
- `floor_snap_length` is reduced to `1.5` and `floor_max_angle` to `55°` to avoid terrain snapping issues
- Terrain raycast for mounted players limited to 3.0 units above current position

## Fall Damage

Players take fall damage when landing with a downward velocity exceeding 12.0 units/s. Damage scales with impact speed. Boot affixes modify this:
- **Featherfall** — reduces fall damage by 50%
- **Light Step** — reduces fall damage by 30%

A slope speed penalty (up to 40% reduction on steep slopes) is applied during normal movement. The **Sure-Footed** boot affix bypasses this penalty entirely.

## Animation System

- Attack animations override walk/run animations when the player is moving and attacking simultaneously
- Attack animation speed is synchronized to the player's actual attack speed via `speed_scale`
- Context-based weapon switching selects the correct animation based on equipped weapon and target type
