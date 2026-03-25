# Oathbound

A 3D survival-crafting RPG built in **Godot 4** with GDScript. Explore a procedurally generated open world, harvest resources, craft gear, fight creatures, and build a base -- solo or with friends via **LAN co-op multiplayer**.

## Art Direction

Oathbound targets a **low-poly, Valheim-inspired** visual style:

- **Textures:** Low-resolution (64–256px), nearest-neighbor filtering for a chunky pixelated look
- **Geometry:** Procedural meshes with deliberate low vertex counts — rocks, trees, terrain all favor readable silhouettes over smoothness
- **Colors:** Muted, earthy palettes with natural variation (per-instance tinting) rather than uniform flat colors
- **Environment:** Dense grass ground cover, slope-aware moss on rocks, subtle wind animation on foliage
- **Lighting:** Simple directional light with minimal post-processing — no SSAO, no bloom. Depth comes from material work (normal maps, AO baked into shaders) rather than screen-space effects

## Tech Stack

- **Engine:** Godot 4 (GDScript)
- **Rendering:** Forward+ with custom shaders (water, foliage wind, grass billboards, leaf billboards, rock moss)
- **World Gen:** Procedural zones with biomes, rivers, lakes, and caves
- **Networking:** ENetMultiplayerPeer (LAN), RPCs, MultiplayerSynchronizer, host-authoritative model
- **Assets:** 32x32 pixel art icons, GLB/GLTF 3D models

## Project Structure

```
Oathbound/
├── scripts/
│   ├── autoloads/          # Singletons (ItemDatabase, Inventory, SaveManager, NetworkManager, etc.)
│   ├── player/             # Player controller, movement, combat, building, HUD sub-modules
│   ├── creatures/          # Creature AI (host-authoritative), fish behavior
│   ├── items/              # LootDrop (host-authoritative pickup)
│   ├── network/            # WorldStateSync, CreatureSyncManager, ChatManager
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

## Multiplayer Architecture

Oathbound supports LAN co-op (Valheim-style) where one player hosts and others join over the local network.

### Authority Model

- **Host** manages world state, creature AI, loot authority, and game logic
- **Clients** manage their own input, camera, and UI
- **Trusted client model:** clients have authority over their own player (movement, actions) since LAN means playing with friends

### Connection Flow

1. Host starts `ENetMultiplayerPeer` on port 9050 via `NetworkManager` autoload
2. Client connects to host IP, receives world seed + name via RPC
3. Client loads the same world scene (deterministic terrain from seed)
4. Host creates player nodes for both sides via `_create_player_node()`
5. Host sends `_rpc_create_player` to client so each peer has both players in-tree
6. `MultiplayerSpawner` is **not used** — player replication is handled entirely via direct RPCs to avoid runtime `_spawnable_scene_count: 0` issues

### Player Sync

- Each player node is named by peer ID (e.g. `Players/1`, `Players/2057384612`)
- `MultiplayerSynchronizer` replicates position, rotation, animation, equipment, and display name
- Primary animation/position sync uses `_broadcast_state` RPC at ~20Hz with immediate sends on animation changes (catches transient attack animations)
- `_broadcast_state` also sends `current_health`, `max_health`, `current_stamina`, `max_stamina` so remote players display accurate floating HP/stamina bars
- Remote players interpolate toward synced positions in `_physics_process`
- Remote players load the same 3D model (GLTF), play synced animations via manual `AnimationPlayer.advance()`, and show floating nameplates + HP/stamina bars
- Remote player `_physics_process` calls `_update_floating_bars(delta)` so bars face the camera and update fill ratios
- Model facing (yaw) is synced separately via `_remote_model_target_yaw` and interpolated with `lerp_angle`
- Attack animations use `is_playing()` detection to restart finished non-looping clips on the receiver
- **Critical:** `_fit_attack_anim_to_timer()` must set `_gltf_playing_clip` and `_gltf_playing_speed` (not just `_gltf_current_anim`) — these are the variables the broadcast reads. Missing this causes attack animations to be invisible to other players

### Creature Sync

- Creatures are generated deterministically from the world seed (same creatures on all peers)
- Creatures have stable names (`Creature_0`, `Creature_1`, etc.) for consistent node paths across peers
- Creature sync is handled by `WorldStateSync` (a scene-defined node with guaranteed RPC path consistency, replacing the earlier dynamic `CreatureSyncManager`):
  - **Position/rotation/velocity** via unreliable RPC at ~10Hz (batched per loaded zone)
  - **State changes** (idle, chase, attack, dead) and health via reliable RPC on change
- Clients interpolate creature positions toward `_sync_target_position` and strip root motion from animations to prevent model displacement
- Player-to-creature damage: client routes damage through `WorldStateSync.request_creature_damage` RPC (zone coords + creature index), avoiding node-path mismatches on dynamically generated creature nodes. Host looks up the creature by zone + index and applies `take_damage` locally
- Creature-to-player damage: host sends `deal_damage_to_player` RPC to the target client
- Creatures hit mid-attack no longer get interrupted — `take_damage` only transitions to `CHASE` state if the creature is not already in `ATTACK` state
- During attacks, creature models face their target (not velocity direction) to prevent rotation glitches

### World State Sync

- Terrain and zone populations are **deterministic** — same seed = same world
- Only **mutations** are synced via `WorldStateSync`:
  - Destroyed harvestables (trees, rocks) — indexed by zone + position in group
  - Placed buildings — position, rotation, contents
  - Loot drops — host assigns `loot_id`, replicates via RPC, authoritative pickup
  - Player-dropped items — routed through `WorldStateSync.spawn_player_drop_synced` (host) or `request_drop_item` RPC (client) so all peers see dropped items
- Late-joining clients request the full mutation set to catch up
- Loot pickup is host-authoritative: host calls `_grant_pickup` locally and broadcasts `_remove_loot` to clients (avoiding `call_local` RPC pitfalls)
- **Pickup grace:** Dropped items track `drop_owner_peer` — only the dropper is blocked from picking up the item for 5 seconds; other players can grab it immediately
- **Monster loot scatter:** ±0.85 units from death position (in `LootDrop._spawn_single_drop`)
- **Tree wood scatter:** Along the full fallen trunk length (20%-90% of `trunk_h` in the fall direction, ±1.5 lateral). Trees are tall (30-55 units), so percentage-based scatter covers the whole fallen log. Client-felled trees go through `_spawn_loot_from_harvestable` on the host with a random fall direction
- **HarvestableResource scatter:** `_compute_scatter_radius()` calculates 20% of the mesh AABB height for scatter radius (used by `HarvestableResource` scene instances like `tree_oak.tscn`)

### Save System & Inventory

- Each player has a separate `PlayerInventory` instance (not a global singleton)
- The `Inventory` autoload exposes the **local** player's inventory for UI
- Chest contents are synced via RPCs in `NetworkManager` (open, deposit, withdraw)
- **Host** auto-saves full game state (world, player, inventory) every 10 seconds
- **Clients** auto-save their own inventory and player stats to a `lan_client` save file (periodic + on disconnect)
- On session start, clients with no LAN save fall back to their character's most recent save from any world to preserve inventory across sessions
- Health and stamina are always reset to max on session start (prevents spawning at low HP from stale saves)

### Multiplayer Debugging Setup

- **Dual-instance testing:** Godot editor setting "Game Embed Mode" must be set to **Floating Window** (Editor > Editor Settings > Interface > Editor > Game Embed Mode). This allows two game windows to exist side-by-side
- **Automatic window layout:** `GameEvents._ready()` uses a UDP port probe to detect whether another instance is already running. First instance (host) positions left half of screen; second instance (client) positions right half. Window titles set to "Oathbound — Host" and "Oathbound — Client"
- **Music slider:** Defaults to 0% volume at startup for quieter bug-testing sessions (the slider still works — music plays if you raise it)

### Known Multiplayer Gotchas

These are hard-won lessons from the LAN co-op implementation:

1. **Never RPC directly to dynamically generated nodes** — creature nodes are created at runtime and may have different tree paths on host vs client. Route all cross-peer creature interactions through a scene-defined singleton like `WorldStateSync` using stable identifiers (zone coords + creature index)
2. **`MultiplayerSpawner` can silently fail** — `_spawnable_scene_count: 0` at runtime even when scenes are registered in the inspector. Player replication uses direct RPCs instead
3. **`_fit_attack_anim_to_timer` must update broadcast variables** — playing an animation locally via `AnimationPlayer.play()` doesn't automatically update `_gltf_playing_clip` / `_gltf_playing_speed`, which are what `_broadcast_state` sends. If you forget to set them, attack swings are invisible to other players
4. **Remote player floating bars need explicit updates** — the remote player branch of `_physics_process` must call `_update_floating_bars(delta)` so HP/stamina bars face the camera and update their fill
5. **`call_local` RPC pitfalls** — prefer separate local calls + `rpc()` to all remotes over `call_local` RPCs when the host needs different behavior from clients
6. **Creature `take_damage` should not unconditionally change state** — interrupting an attack to enter CHASE causes visible animation glitches. Only transition if not already attacking
7. **Dropped items must go through WorldStateSync** — locally creating a `LootDrop` node makes it invisible to other peers. All item drops (inventory shift+right-click, tree loot, monster loot) must use `_spawn_and_replicate_loot`
8. **Pickup grace is per-player** — `LootDrop.drop_owner_peer` tracks who dropped the item. The 5s pickup delay only applies to the dropper; other players can grab immediately
9. **Health/stamina resets on session start** — both host and client reset to max HP/stamina on spawn to avoid stale low-HP saves causing instant death
10. **Client inventory persistence** — clients save to a `lan_client` save file. On first join, they fall back to their most recent character save from any world to carry over gear

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

**Damage variance:** All weapon damage has a ±30% random range per hit. Multi-arrow shots (Multishot, Quiver Mastery) each roll damage and crit independently.

**Bow draw speed:** Base draw time is 1.2 seconds (`BOW_MAX_DRAW_TIME`). Rapid Draw (+15%) and Quickdraw (+33%) stack additively on the draw speed multiplier.

**Fall damage:** Players take damage when landing with downward velocity > 12.0 units/s. Red floating damage numbers are shown above the player.

**Damage numbers:** WoW-style floating combat text with camera-relative spread. Simultaneous hits (e.g. 3 arrows) fan out left/right using the camera's basis vector so numbers don't overlap. Each number gets increasing lateral offset and directional velocity.

**Multiplayer combat:** Player damage to creatures is routed through `WorldStateSync.request_creature_damage(zone_x, zone_z, creature_idx, amount, source_peer)` — this avoids node-path mismatches caused by dynamically generated creature nodes having different tree paths across peers. Creature damage to players is sent from the host to the target client via `deal_damage_to_player` RPC.

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
| 2 | Rare | 4.0% | 1 |
| 3 | Epic | 2.0% | 2 |
| 4 | Legendary | 0.8% | 3 |
| 5 | Mythical | 0.3% | 5 |

**Stat scaling per star:**
- Damage: +15% per star
- Armor: +25% per star
- Knockback: +10% per star
- Range: +5% per star

## Affix System

Equipment with 2+ stars rolls random affixes from a pool specific to their item type. Tier 1 affixes are common; tier 2 affixes have half the roll weight.

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

### Bow Affixes (12)

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
| Heatseeking | 2 | Arrows home toward nearby enemies in their trajectory (12-unit seek radius, ~66° cone) |
| Quickdraw | 1 | 33% faster bow draw speed |

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
- **Loot despawn timers** — dropped items auto-despawn after 180 seconds
- **Loot node cap** — `MAX_LOOT_NODES = 150`. When new loot spawns and the cap is exceeded, the oldest loot nodes are auto-despawned. Prevents unbounded node accumulation from heavy combat
- **Loot nameplate throttling** — nameplate visibility checks run every 0.5s instead of every frame, using `distance_squared_to` to avoid sqrt. Previously O(N×P) per frame where N=loot count, P=player count
- **Loot registry cleanup** — `WorldStateSync._loot_registry` entries are pruned when loot despawns naturally (180s) via `_cleanup_registry()`, and stale references are swept on zone unload via `_prune_loot_registry()`
- **Creature sync state pruning** — `WorldStateSync._csync_last_states` entries are erased when zones unload (connected to `WorldGenerator.zone_unloaded` signal). Previously this dictionary grew unbounded as new zones were visited
- **Debug print gating** — all ~118 `print()` calls across 10 script files are gated behind `const _DEBUG_LOG := false`. Zero console output in normal play. Set to `true` per-file when debugging
- **Zone cache pruning** — biome/water/microbiome caches cleared when zones unload
- **Shader simplification** — reduced FBM octaves in water shader
- **Post-processing disabled** — SSAO and Glow off for performance
- **Floating origin** — see "FPS Investigation" section below

## FPS Investigation & Floating Origin

### Problem

Severe FPS degradation at large world coordinates. Near spawn (0, 0, 0): stable 60 FPS. At distant locations (5120, 0, 5120): 25 FPS. The FPS drop scaled with distance from world origin.

### Investigation Process

1. **Initial hypothesis — CPU backlog**: Terrain generation queues (`mesh_q`, `pop_q`) were unbounded. Fixed with backlog management (clearing stale entries, capping submissions). **Result: No improvement.** FPS still dropped at far locations even with idle world generator.

2. **Initial hypothesis — Object count**: Aggressive LOD culling for trees, rocks, creatures. **Result: No improvement**, and caused slow tree pop-in. Reverted.

3. **Portal test**: Added debug portal pair (spawn at (25, 20) ↔ far at (5120, 5120)) to isolate position-dependent performance. **Result: Instant FPS drop on teleport to far location**, confirming the issue was position-dependent, not content-dependent.

4. **Nuking zones**: Spamming "nuke all zones" at far location temporarily raised FPS from 20→40, but it dropped back immediately when zones reloaded. **Result: Confirmed terrain rendering was involved.**

5. **Sky test**: Looking straight up at the sky restored 60 FPS regardless of location. Windowed mode at 60% screen size also gave 60 FPS everywhere. **Result: Confirmed GPU fill-rate / fragment workload as the bottleneck layer.**

6. **Minimap optimization**: Reduced minimap from ~33,696 pixel operations/frame to ~1,299 via low-res render + upscale. Minimap time dropped from 10ms to <1ms when disabled. **Result: Helped CPU time but did not fix the core FPS issue.**

7. **Shader complexity test**: Replaced the full terrain shader (12 texture samples + 11 noise evaluations per pixel) with a solid green shader (`ALBEDO = vec3(0.3, 0.55, 0.2)`, zero textures, zero noise). **Result: Still 25 FPS at far location.** This eliminated shader complexity as the cause.

8. **Terrain visibility test**: Added debug toggle to hide all terrain meshes entirely (`visible = false`). **Result: 60 FPS at far location with terrain hidden, 25 FPS with terrain visible (even solid green shader).** This proved the GPU vertex transform pipeline was the bottleneck — not fragment shading, not textures, not object count.

### Root Cause

**Large floating-point world coordinates cause GPU vertex transform performance degradation.** When terrain zone roots are positioned at (5120, 0, 5120), the GPU processes vertex transforms with large numbers. On Apple M4 (Metal 4.0, Forward+ renderer), this causes ~2.5x performance loss compared to coordinates near origin. The effect is:
- Not shader-related (solid color shader still slow)
- Not CPU-related (`proc` time inflated from CPU-GPU sync stalls, not script work)
- Purely distance-from-origin dependent
- Reproducible: looking at sky (reducing fill) or shrinking window restores 60 FPS

### Solution: Floating Origin (confirmed fix — 60 FPS at all distances)

Implemented a **floating origin** system that periodically re-centers the entire scene around the player. All Node3D children of the root scene are shifted so the player stays near (0, 0, 0) in scene space. Before the fix, the far portal location (5120, 5120) ran at 25 FPS. After: stable 60 FPS everywhere.

**Key variables** (`world_generator.gd`):
- `origin_shift: Vector3` — cumulative world-space offset applied to the scene
- `ORIGIN_SHIFT_THRESHOLD = 512.0` — shift triggers when player scene-pos exceeds this (originally 2048, lowered after finding FPS degradation at ~500-1000 units)

**Helper functions**:
- `get_world_position(node)` — returns `node.global_position + origin_shift` (true world position)
- `world_to_scene_pos(world_pos)` — returns `world_pos - origin_shift` (for node placement)
- `get_height_at_scene(sx, sz)` — terrain height lookup from scene-space coordinates
- `get_world_position_vec(scene_pos)` — converts a scene-space Vector3 to world coordinates

**Systems updated**:
- Zone placement: zones placed at `world_to_scene_pos(coord * ZONE_SIZE)`
- Zone management: load/unload/LOD all use world positions via `get_world_position(player)`
- Save/load: player and building positions saved as world coordinates, converted on load
- Multiplayer sync: positions broadcast as world coordinates, converted to scene-space on receive
- Minimap/map: terrain lookups use world-space player position
- Portals/respawn: world coordinates converted to scene-space for `global_position` assignment
- Creatures: terrain snap uses `get_height_at_scene()` for scene-space coordinates
- Buildings: serialized with world positions, deserialized with scene-space conversion
- Terrain shader: `origin_shift` uniform synced to all biome materials on every shift
- Zone populator: `_ZonePopulator.origin_shift` kept in sync for structure proximity checks

### Follow-up: Threshold Tuning

The original `ORIGIN_SHIFT_THRESHOLD` of 2048 was too high. Testing showed FPS degrading from 60 to 32-46 at distances of ~500-1000 units from origin — well below the 2048 threshold, so the floating origin never triggered during normal exploration. Lowered to 512 so the origin shifts every ~8 zones of travel, keeping scene coordinates consistently small.

### Follow-up: Terrain Shader Zone Seams

After implementing floating origin, the terrain shader was temporarily set to use `v_local_pos = VERTEX` (model-space coordinates 0-64) to avoid large GPU coordinates. This caused **visible square artifacts at zone boundaries** — every zone got identical noise/dirt/brightness patterns because they all used the same 0-64 coordinate range.

**Fix:** The shader now computes true world position in the vertex shader:
```glsl
uniform vec3 origin_shift;
varying vec3 v_world_pos;
void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
}
```
`MODEL_MATRIX * VERTEX` gives scene-space position (small thanks to floating origin), and adding `origin_shift` recovers the true world position for continuous texturing. Vertex transforms stay GPU-friendly (small scene coords), while fragment shader gets stable world coords for noise/texture continuity across zone boundaries. The `origin_shift` uniform is updated on all biome `ShaderMaterial`s whenever the origin shifts.

### Follow-up: Floating Objects on Hills

Trees, rocks, creatures, and horses were floating above the terrain on hills. **Root cause:** These objects used `height_func.call(wx, wz)` (the exact noise value at an arbitrary point) for their Y position, but the terrain mesh samples height on a 2-unit grid and **linearly interpolates** between vertices. On curved terrain (hills, valleys), the exact noise height and the mesh's interpolated height diverge.

**Fix:** Switched all object placement to `_snap_height_to_mesh(wx, wz, height_func)`, which bilinearly interpolates between the same 4 grid vertices the terrain mesh uses. Grass and saplings already used this function (and sat correctly). Now all objects match the rendered terrain surface:
- Trees: `_snap_height_to_mesh() - 1.5` (trunk burial offset)
- Rocks: `_snap_height_to_mesh()`
- Ground stones: `_snap_height_to_mesh() + 0.1`
- Creatures: `_snap_height_to_mesh() + 0.1` (flying creatures add `fly_height`)
- Horses: `_snap_height_to_mesh()`

### Follow-up: Coordinate Mismatch in Structure Proximity

After floating origin, `_is_near_structure()` in `zone_populator.gd` compared structure `global_position` (scene-space) against tree/rock world coordinates (`coord * ZONE_SIZE + local_offset`). After an origin shift, these are in different reference frames, breaking the proximity check (objects could spawn inside buildings).

**Fix:** Added `ZonePopulator.origin_shift` static variable, kept in sync by `WorldGenerator._sync_origin_shift_to_shaders()`. The proximity function now converts structure positions to world-space: `(sp.x + origin_shift.x) - wx`.

### Debug Panel Toggles

The debug panel (F3) includes toggles for isolating performance issues:

| Toggle | What it does |
|--------|-------------|
| Trees, Rocks, Saplings, Grass, Creatures, etc. | Hide/show specific object types |
| Minimap | Disable minimap rendering entirely |
| World Map | Disable full map rendering |
| Fancy Terrain Shader | Switch between full shader (12 tex + 11 noise) and solid green |
| Terrain Visible | Hide/show all terrain meshes (definitive GPU test) |
| Disable ALL / Enable ALL | Bulk toggle for rapid isolation testing |

## Inventory & UI

- **Grid inventory** with drag-and-drop reordering
- **Right-click hold to equip** (0.5s progress bar) — moves item from inventory to equipment slot
- **Shift + right-click to drop** items on the ground (replicated via WorldStateSync so all peers see it)
- **5-second pickup grace period** on dropped items — only blocks the dropper from re-picking up; other players can grab immediately
- **Tooltips** show item name, type (specific: "Axe", "Chest Armor", etc.), stats, quality, star level, and affixes
- **Crafting window** with building/equipment tabs and tier quality display (Low = white, Medium = blue, High = red)
- **Building mode crosshair** — white `+` reticle with dark outline, visible only during build mode
- **Nameplates** — creature/item names on `Label3D` with rectangular dark panel background, health bar underneath, dynamically sized. Stars colored by rarity.

## Mounts

Players can mount wild horses found in the world. Horses spawn with 0-5 star levels (same star roll as creatures). Starred horses display a colored nameplate above them.

### Horse Star Bonuses
- **Speed:** Base mount speed is `MOUNT_SPEED_MULT_BASE = 2.0x`. Each star adds +20% (`MOUNT_SPEED_PER_STAR = 0.2`), so a 5★ horse is 3.0x speed
- **Stamina:** Horses have their own stamina pool (base 100 + 20 per star). Galloping drains horse stamina, not player stamina. Horse stamina regens when not sprinting (18.0/s after 1.2s delay)
- **Mount stamina bar:** A separate amber bar appears below the player's stamina bar while mounted

### Mounted Movement
- Jumping is disabled to prevent flight exploits
- Vertical velocity is clamped to `[-10.0, 1.0]` for faster descent and limited upward movement
- `floor_snap_length` is reduced to `1.5` and `floor_max_angle` to `55°` to avoid terrain snapping issues
- Terrain raycast for mounted players limited to 3.0 units above current position
- Horse stamina is saved back to the horse node metadata on dismount

## Fall Damage

Players take fall damage when landing with a downward velocity exceeding 12.0 units/s. Damage scales with impact speed. Boot affixes modify this:
- **Featherfall** — reduces fall damage by 50%
- **Light Step** — reduces fall damage by 30%

A slope speed penalty (up to 40% reduction on steep slopes) is applied during normal movement. The **Sure-Footed** boot affix bypasses this penalty entirely.

## Developer Cheat Codes

Press Enter to open the chat box, type the command (case-insensitive), and press Enter:

| Command | Effect |
|---------|--------|
| `rosebud` | Spawns **Oathbreaker** (god sword) — 5★ Godly sword with all 18 sword affixes, 25 damage |
| `oathgun` | Spawns **Oathgun** (god bow) — 5★ Godly bow with all 12 bow affixes, 35 damage, 60 range |

Both god weapons are registered in `ItemDatabase` as `god_sword` and `god_bow`. Their `spawn_god_*()` functions call `_get_affix_pool()` to dynamically collect all affixes for their slot, so new affixes are automatically included.

## Monster Loot System

Loot drops from creatures scale with their star level:

### Piece Counts (per kill)

| Stars | Pieces |
|-------|--------|
| 0★ | 2-4 |
| 1★ | 3-5 |
| 2★ | 4-6 |
| 3★ | 6-9 |
| 4★ | 9-12 |
| 5★ | 12-15 |

Each "piece" is 1-2 quantity of a random item from the creature's loot table (weighted by chance). Pieces scatter radially (0.5-3.5 unit radius, golden-angle pattern) to avoid clumping.

### Quality Multiplier

Each piece independently rolls star quality. Higher creature stars boost the chance of better quality:

| Creature Stars | Quality Multiplier |
|----------------|-------------------|
| 0★ | 1.0x (base chance) |
| 1★ | 1.2x |
| 2★ | 1.5x |
| 3★ | 1.8x |
| 4★ | 2.5x |
| 5★ | 3.3x |

Rare/super drops are rolled independently with a `+2% per creature star` chance boost.

## Animation System

- Attack animations override walk/run animations when the player is moving and attacking simultaneously
- Attack animation speed is synchronized to the player's actual attack speed via `speed_scale`
- Context-based weapon switching selects the correct animation based on equipped weapon and target type
- 3D models use `AnimationPlayer` in **manual** callback mode — `advance(delta)` is called explicitly in `_physics_process` for both local and remote players
- NlaTrack-based models have their tracks renamed to logical names (`chop`, `kick`, `walk`, `run`, `stand`, etc.) via `_rename_nla_tracks()`
- Root motion position tracks are stripped from all animations (`_strip_root_motion`) to prevent model displacement from the collision body
- Custom attack animations (`axe_swing`, `sword_slash`, `club_smash`) are procedurally rebuilt with explicit bone keyframes when the base animation exists in the model
- **Multiplayer sync:** the local player broadcasts `_gltf_playing_clip` and `_gltf_playing_speed` via RPC; remote players play the clip with matching speed and detect finished non-looping animations to handle repeated attacks. Every code path that starts an animation (walk, run, attack, chop, mine) must set both `_gltf_playing_clip` and `_gltf_playing_speed` — these are the authoritative broadcast variables, not `_gltf_current_anim`
