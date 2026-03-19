# Oathbound — Technical Roadmap

## Art Direction
- **3D environments, pixel-art aesthetic**: Low-poly meshes with pixel-art textures (PixelLab MCP)
- **Texture Filtering**: All materials use `TEXTURE_FILTER_NEAREST` — no bilinear smoothing
- **Target Resolution**: Render at a fixed low resolution (e.g. 480p) and upscale with nearest-neighbor
- **Palette Discipline**: Shared color palette across biomes for visual cohesion

---

## Milestone 0 — Project Scaffold & Rendering Pipeline
**Goal**: Playable empty world with correct pixel-art rendering.

| Task | Details |
|------|---------|
| Project settings | Godot 4.x, Forward+ renderer, fixed viewport stretch mode (`canvas_items`, `keep` aspect) |
| Pixel-art camera rig | `SubViewport` at 480×270 rendered to full window via `TextureRect` with nearest filter |
| Environment | `WorldEnvironment` + `DirectionalLight3D` with baked-style hard shadows (1-tap PCF, small shadow atlas) |
| Test scene | Flat `MeshInstance3D` plane + CSG box with placeholder pixel texture to validate the pipeline |
| Input map | Define all actions: `move_forward/back/left/right`, `jump`, `sprint`, `interact`, `attack`, `build_mode`, `rotate_piece`, `inventory` |

**Deliverable**: A window showing a crisp pixel-textured 3D scene with no blurring.

---

## Milestone 1 — Player Controller (Third-Person)
**Goal**: A responsive character that can run, sprint, jump, and look around.

| Task | Details |
|------|---------|
| `CharacterBody3D` setup | Capsule collision, mesh placeholder, `SpringArm3D` + `Camera3D` |
| Movement | WASD input relative to camera facing, `move_and_slide()` with gravity |
| Stamina system | Sprint drains stamina; regenerates after a delay. Stamina gates jumping & attacks too |
| Camera orbit | Mouse-look rotates `SpringArm3D` pivot; camera collision via spring arm |
| Animation tree | `AnimationTree` with blend space: Idle → Walk → Run (hooked up later with real anims) |

**Deliverable**: Third-person character running around the test plane with stamina HUD.

---

## Milestone 2 — Modular Interaction System
**Goal**: A scalable framework for detecting and interacting with world objects.

| Task | Details |
|------|---------|
| `Interactable` base class | Abstract GDScript class with `get_interaction_name()`, `interact(player)`, `can_interact(player)` |
| `InteractionManager` | `RayCast3D` child of camera; detects nearest `Interactable`, shows UI prompt |
| `HarvestableResource` | Extends `Interactable` — trees, rocks. Has HP, yields items on hit, plays FX, respawns |
| `Chest` | Extends `Interactable` — opens inventory panel |
| `Workstation` | Extends `Interactable` — opens crafting UI (Forge, Workbench, etc.) |
| Interaction HUD | `Control` node showing "[E] Chop Tree" / "[E] Open Chest" contextually |

**Deliverable**: Walk up to objects, see prompt, press E to interact. Modular — new types require only a new script.

---

## Milestone 3 — Inventory & Item System
**Goal**: Items exist, can be picked up, stored, and used.

| Task | Details |
|------|---------|
| `ItemDatabase` (autoload) | Dictionary/Resource-based item registry: id, name, icon, stack_size, type (material/tool/weapon/food/buildable) |
| `Inventory` class | Array of `ItemStack` (item_id + count). Add/remove/find/transfer operations |
| `PlayerInventory` | Player's `Inventory` instance with hotbar (slots 0-7) and main grid |
| Inventory UI | Grid-based panel. Drag-and-drop between slots. Tooltip on hover |
| Item drops | `RigidBody3D` world items with pickup via `Area3D` overlap or interact |
| Equipment slots | Weapon, helmet, chest, legs — modify player stats/appearance |

**Deliverable**: Harvest a tree → logs appear in inventory. Equip a tool from hotbar.

---

## Milestone 4 — Building System
**Goal**: Snap-based construction.

| Task | Details |
|------|---------|
| `BuildingPiece` resource | Defines mesh, snap points (named + typed: floor_edge, wall_bottom, roof_top), material cost |
| Ghost preview | Semi-transparent preview mesh follows cursor raycast against terrain/other pieces |
| Snap logic | When ghost is near an existing piece's snap point of compatible type, lock to that transform |
| Placement | On click, instance the real `StaticBody3D` piece at the ghost's transform; deduct materials |
| Stability (optional) | Each piece has a stability value (0.0–1.0). Ground-touching = 1.0. Pieces inherit from parent minus decay. Below threshold → collapse |
| Piece types | Foundation, Wall, Floor, Roof (45°/26°), Stairs, Door frame, Door (openable) |

**Deliverable**: Place foundations, snap walls on top, add a roof. Structure stands or collapses based on support.

---

## Milestone 5 — Procedural World Generation
**Goal**: Infinite biome-based terrain.

| Task | Details |
|------|---------|
| Chunk system | World divided into chunks (e.g. 64×64). Load/unload based on player distance |
| Terrain mesh | `SurfaceTool` or `ArrayMesh` heightmap per chunk, generated from noise |
| `FastNoiseLite` stack | Layer 1: continent shape (low freq). Layer 2: mountains (high freq). Layer 3: detail |
| Biome map | Separate noise for temperature + moisture → Voronoi-ish biome assignment (Meadow, Forest, Swamp, Mountain, Plains) |
| Biome decoration | Per-biome scatter tables: tree density, rock density, grass density, mob spawn weights |
| LOD | Distant chunks use simplified meshes or `MultiMeshInstance3D` for trees |
| Serialization | Save/load chunk modifications (placed buildings, harvested trees) |

**Deliverable**: Walk through varied biomes with trees, rocks, and terrain variation. World persists across sessions.

---

## Milestone 6 — Combat & Creatures
**Goal**: Enemies roam biomes; player can fight them.

| Task | Details |
|------|---------|
| `Creature` base class | `CharacterBody3D` + `NavigationAgent3D`. HP, damage, drop table, detection radius |
| AI state machine | Idle → Patrol → Chase → Attack → Flee. Uses `NavigationServer3D` for pathfinding |
| Player combat | Weapon hitbox (`Area3D`) active during attack animation frames. Damage = weapon_base + skill |
| Damage system | `Damageable` component. Handles HP, damage types (slash/blunt/pierce), resistance, death |
| Creature types | Per-biome: Boar (Meadow), Skeleton (Forest), Blob (Swamp), Drake (Mountain) |
| Boss encounters | Summoned at altars. Unique attack patterns. Drop progression-gating materials |

**Deliverable**: Creatures wander biomes, aggro on player, combat with hit feedback.

---

## Milestone 7 — Crafting, Cooking & Progression
**Goal**: Workstation-based crafting gates progression through biomes.

| Task | Details |
|------|---------|
| Recipe system | Recipes tied to workstation type + level. Unlocked by discovering materials |
| Workstation leveling | Place addon items near workstation to level it up (e.g. chopping block near workbench) |
| Food & cooking | Campfire/cauldron recipes. Food buffs: +HP, +stamina, +regen (timed) |
| Skill system | Skills improve with use: Running, Woodcutting, Swords, etc. Soft caps + death penalty |
| Tech tree | Boss drops unlock new biome tier materials → new workstation tier → new gear |

**Deliverable**: Full crafting loop from raw materials to endgame gear.

---

## Milestone 8 — World Events, Weather & Polish
**Goal**: Living world that pushes back.

| Task | Details |
|------|---------|
| Day/night cycle | `DirectionalLight3D` rotation + sky color lerp. Enemies more aggressive at night |
| Weather | Rain, fog, snow (particle systems). Affects stamina regen, wet debuff |
| Raid events | "The forest is moving..." — waves of enemies attack player's base |
| Sound design | Ambient biome sounds, footsteps on material, combat SFX, music layers |
| Save system | Full serialization: player, inventory, world chunks, buildings, creature state |
| Main menu | New Game, Continue, Settings (resolution, controls, audio) |

**Deliverable**: A polished vertical slice ready for playtesting.

---

## Milestone 9 — Multiplayer (Stretch Goal)
**Goal**: Co-op survival with friends.

| Task | Details |
|------|---------|
| Networking layer | Godot `MultiplayerAPI` with `ENetMultiplayerPeer` or Steam networking |
| Authority model | Server-authoritative movement + combat. Client-predicted input |
| Sync | `MultiplayerSynchronizer` for transforms, HP, inventory state |
| Shared world | Host's world + chunk loading per player |

---

## Important: This is a TRUE 3D Game, Not Isometric

Oathbound is a **full 3D third-person game** with a free-orbiting camera (360-degree rotation, zoom, full pitch control). The pixel-art look comes from:

1. **Low-resolution textures** (32×32 or 64×64 px) applied to 3D meshes with `TEXTURE_FILTER_NEAREST`
2. **Low-poly geometry** — simple shapes, few vertices, no smooth subdivision
3. **Tilt-shift depth of field** — blurs foreground/background, creates a miniature diorama feel
4. **Limited color palettes** — pixel-art discipline in the textures themselves

Assets are NOT 2D sprites or isometric tiles. They are **tileable textures wrapped around 3D models** via UV mapping.

---

## Pixel Art Asset Pipeline (PixelLab MCP)

### Tileable 3D Surface Textures
Generated via `create_tiles_pro` with `tile_type: "square_topdown"` and `tile_view: "top-down"`. This produces flat, square pixel-art patterns that tile seamlessly when UV-mapped onto any 3D surface.

| Asset Category | PixelLab Tool | Settings | Usage |
|---------------|--------------|----------|-------|
| Terrain textures | `create_tiles_pro` | `square_topdown`, `top-down`, 32px | Grass, dirt, stone, sand, snow — applied to terrain mesh UVs |
| Building materials | `create_tiles_pro` | `square_topdown`, `top-down`, 32px | Wood planks, cobblestone, thatch, brick — applied to building piece meshes |
| Terrain transitions | `create_topdown_tileset` | Wang tiles, 32px | Biome edge blending (grass→dirt, sand→stone) for terrain splatmaps |
| UI icons | `create_tiles_pro` | `square_topdown`, 16-32px | Inventory item icons, HUD elements |

### 2D Reference Art (for modelling guidance)
| Asset Category | PixelLab Tool | Usage |
|---------------|--------------|-------|
| Character concept | `create_character` (humanoid, 48px) | Reference sheet for building the low-poly player model |
| Creature concepts | `create_character` (humanoid/quadruped) | Reference art for creature models |
| Object concepts | `create_map_object` | Visual reference for modelling trees, rocks, chests, workstations |

### 3D Model Workflow
1. **Model** low-poly mesh in Blender (or use Godot CSG/primitives for prototyping)
2. **UV unwrap** the mesh — keep UVs simple and blocky
3. **Generate texture** via PixelLab (`create_tiles_pro` at `top-down` view)
4. **Apply texture** to a `StandardMaterial3D` with `texture_filter = NEAREST`
5. **Import** into Godot — the `.import` file must disable mipmaps and set nearest filtering

### Rendering Pipeline for the "Oathbound Look"
- `WorldEnvironment` with **depth-of-field blur** (far + near) for tilt-shift miniature effect
- **SSAO** for ambient shadowing in corners and under objects
- **Glow/bloom** at low intensity for atmospheric warmth
- **Fog** with sun scatter for distance haze
- Hard directional shadows (1-tap PCF, `light_angular_distance = 0`) — no soft penumbra
- Optional: Render to a `SubViewport` at lower resolution (e.g. 960×540) and upscale with nearest-neighbor for extra crunch

---

## Architecture Principles
1. **Composition over inheritance** — Use child nodes as components (e.g., `Damageable`, `Inventory`) rather than deep class hierarchies
2. **Signal-driven communication** — Decouple systems via Godot signals; avoid direct references where possible
3. **Resource-based data** — Items, recipes, building pieces, biome configs are all `Resource` subclasses for editor-friendly authoring
4. **Autoloads for globals** — `GameManager`, `ItemDatabase`, `EventBus` as singletons
5. **Scene composition** — Each entity is a self-contained `.tscn`; instantiate and configure at runtime
