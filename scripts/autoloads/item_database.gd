extends Node
## Singleton item registry. All item definitions live here.

var _items: Dictionary = {}

# Star rarity drop weights (index = star count)
const STAR_WEIGHTS: Array[float] = [0.82, 0.109, 0.04, 0.02, 0.008, 0.003]

# WoW-style rarity colors
const RARITY_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0),        # 0★ Common — white
	Color(0.118, 1.0, 0.0),      # 1★ Uncommon — #1eff00
	Color(0.0, 0.44, 0.867),     # 2★ Rare — #0070dd
	Color(0.639, 0.208, 0.933),  # 3★ Epic — #a335ee
	Color(1.0, 0.502, 0.0),      # 4★ Legendary — #ff8000
	Color(0.9, 0.1, 0.1),        # 5★ Mythical — red
]

const RARITY_NAMES: Array[String] = [
	"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical",
]

# ── Affix system ─────────────────────────────────────────────────────────────
# slot: weapon class ("axe","pickaxe","sword","bow") or armor slot ("chest","legs","feet")
# tier: 1 = common weight, 2 = rare (half weight)
const AFFIXES: Dictionary = {
	# ── Axe affixes (woodcutting) ────────────────────────────────────────
	# min/max = the actual value range; description uses %s for the displayed value
	&"lumberjack":      {"name": "Lumberjack",      "slot": "axe", "tier": 1, "min": 0.30, "max": 0.50, "fmt": "+%.0f%% wood drops from trees", "pct": true, "description": "+40% wood drops from trees"},
	&"splitter":        {"name": "Splitter",         "slot": "axe", "tier": 1, "min": 0.22, "max": 0.38, "fmt": "Trees fall %.0f%% faster", "pct": true, "description": "Trees fall 30% faster"},
	&"deep_cut":        {"name": "Deep Cut",         "slot": "axe", "tier": 1, "description": "Trees take 1 fewer hit to fell"},
	&"bark_stripper":   {"name": "Bark Stripper",    "slot": "axe", "tier": 1, "min": 0.18, "max": 0.32, "fmt": "%.0f%% chance to get bonus resin from trees", "pct": true, "description": "25% chance to get bonus resin from trees"},
	&"double_yield":    {"name": "Double Yield",     "slot": "axe", "tier": 2, "min": 0.07, "max": 0.13, "fmt": "%.0f%% chance to double wood drops", "pct": true, "description": "10% chance to double wood drops"},
	&"timber_cleave":   {"name": "Timber Cleave",    "slot": "axe", "tier": 1, "description": "Can hit up to 3 trees per swing instead of 2"},
	&"sharpened_edge":  {"name": "Frenzied Chop",    "slot": "axe", "tier": 2, "min": 0.18, "max": 0.32, "fmt": "%.0f%% chance per swing to land 2 extra hits on the tree", "pct": true, "description": "25% chance per swing to land 2 extra hits on the tree"},
	&"heavy_chop":      {"name": "Master Woodsman",  "slot": "axe", "tier": 1, "description": "Trees drop higher star-quality wood"},
	&"rapid_chop":      {"name": "Rapid Chop",       "slot": "axe", "tier": 1, "min": 0.09, "max": 0.15, "fmt": "%.0f%% faster axe swing speed", "pct": true, "description": "12% faster axe swing speed"},
	&"sap_drinker":     {"name": "Ancient Grove",    "slot": "axe", "tier": 2, "description": "Trees have a chance to drop rare materials (amber, living wood, fairy dust)"},
	# ── Pickaxe affixes (mining) ─────────────────────────────────────────
	&"prospector":      {"name": "Prospector",       "slot": "pickaxe", "tier": 1, "min": 0.30, "max": 0.50, "fmt": "+%.0f%% stone drops from rocks", "pct": true, "description": "+40% stone drops from rocks"},
	&"vein_finder":     {"name": "Vein Finder",      "slot": "pickaxe", "tier": 2, "min": 0.22, "max": 0.38, "fmt": "%.0f%% chance for bonus ore from rocks", "pct": true, "description": "30% chance for bonus ore from rocks"},
	&"precision_strike":{"name": "Frenzied Mining",    "slot": "pickaxe", "tier": 2, "min": 0.18, "max": 0.32, "fmt": "%.0f%% chance per swing to land 2 extra hits on the rock", "pct": true, "description": "25% chance per swing to land 2 extra hits on the rock"},
	&"stone_breaker":   {"name": "Stone Breaker",    "slot": "pickaxe", "tier": 1, "description": "Rocks take 1 fewer hit to break"},
	&"efficient_miner": {"name": "Efficient Miner",  "slot": "pickaxe", "tier": 1, "min": 0.15, "max": 0.25, "fmt": "-%.0f%% stamina cost when mining", "pct": true, "description": "-20% stamina cost when mining"},
	&"rich_vein":       {"name": "Rich Vein",        "slot": "pickaxe", "tier": 2, "min": 0.07, "max": 0.13, "fmt": "%.0f%% chance to double stone drops", "pct": true, "description": "10% chance to double stone drops"},
	&"heavy_swing":     {"name": "Master Miner",     "slot": "pickaxe", "tier": 1, "description": "Rocks drop higher star-quality stone"},
	&"quick_strike":    {"name": "Quick Strike",     "slot": "pickaxe", "tier": 1, "min": 0.09, "max": 0.15, "fmt": "%.0f%% faster pickaxe swing speed", "pct": true, "description": "12% faster pickaxe swing speed"},
	&"ore_seeker":      {"name": "Ore Seeker",       "slot": "pickaxe", "tier": 1, "min": 0.22, "max": 0.38, "fmt": "+%.0f%% copper ore drops", "pct": true, "description": "+30% copper ore drops"},
	&"geologist":       {"name": "Deep Earth",       "slot": "pickaxe", "tier": 2, "description": "Rocks have a chance to drop rare materials (gemstones, ancient bone, ember stone)"},
	# ── Sword affixes (melee combat) ─────────────────────────────────────
	&"windfury":        {"name": "Windfury",         "slot": "sword", "tier": 2, "min": 0.22, "max": 0.38, "fmt": "%.0f%% chance on hit to trigger 2 extra attacks", "pct": true, "description": "30% chance on hit to trigger 2 extra attacks"},
	&"lifesteal":       {"name": "Lifesteal",        "slot": "sword", "tier": 1, "min": 0.06, "max": 0.10, "fmt": "Heal for %.0f%% of damage dealt", "pct": true, "description": "Heal for 8% of damage dealt"},
	&"firebrand":       {"name": "Firebrand",        "slot": "sword", "tier": 1, "min": 0.11, "max": 0.19, "fmt": "%.0f%% chance to deal bonus fire damage (50%% weapon dmg)", "pct": true, "description": "15% chance to deal bonus fire damage (50% weapon dmg)"},
	&"frostbite":       {"name": "Frostbite",        "slot": "sword", "tier": 1, "min": 0.15, "max": 0.25, "fmt": "%.0f%% chance to slow enemy by 40%% for 3s", "pct": true, "description": "20% chance to slow enemy by 40% for 3s"},
	&"venomous":        {"name": "Venomous",         "slot": "sword", "tier": 1, "min": 0.09, "max": 0.15, "fmt": "%.0f%% chance to poison (3%% max HP/s for 4s)", "pct": true, "description": "12% chance to poison (3% max HP/s for 4s)"},
	&"stunning_blow":   {"name": "Stunning Blow",    "slot": "sword", "tier": 2, "min": 0.06, "max": 0.10, "fmt": "%.0f%% chance to stun enemy for 1.5s", "pct": true, "description": "8% chance to stun enemy for 1.5s"},
	&"executioner":     {"name": "Executioner",      "slot": "sword", "tier": 1, "min": 0.22, "max": 0.38, "fmt": "+%.0f%% damage to enemies below 30%% HP", "pct": true, "description": "+30% damage to enemies below 30% HP"},
	&"berserker":       {"name": "Berserker",        "slot": "sword", "tier": 1, "min": 0.38, "max": 0.62, "fmt": "Up to +%.0f%% damage based on missing health", "pct": true, "description": "+1% damage per 2% missing health (up to +50%)"},
	&"sharpened":       {"name": "Sharpened",        "slot": "sword", "tier": 1, "min": 7.0, "max": 13.0, "fmt": "+%.0f%% critical hit chance", "pct": false, "description": "+10% critical hit chance"},
	&"savage":          {"name": "Savage",            "slot": "sword", "tier": 1, "min": 0.30, "max": 0.50, "fmt": "+%.0f%% critical hit damage", "pct": true, "description": "+40% critical hit damage"},
	&"rapid_strikes":   {"name": "Rapid Strikes",    "slot": "sword", "tier": 1, "min": 0.09, "max": 0.15, "fmt": "%.0f%% faster attack speed", "pct": true, "description": "12% faster attack speed"},
	&"cleaving":        {"name": "Cleaving",         "slot": "sword", "tier": 1, "description": "Melee attacks hit in a wider arc"},
	&"momentum":        {"name": "Momentum",         "slot": "sword", "tier": 1, "min": 0.03, "max": 0.05, "fmt": "Each hit within 3s adds +%.1f%% damage (max 5 stacks)", "pct": true, "description": "Each hit within 3s adds +4% damage (max 5 stacks)"},
	&"reaching":        {"name": "Reaching",         "slot": "sword", "tier": 1, "min": 0.15, "max": 0.25, "fmt": "+%.0f%% melee attack range", "pct": true, "description": "+20% melee attack range"},
	&"chain_lightning": {"name": "Chain Lightning",  "slot": "sword", "tier": 2, "min": 0.07, "max": 0.13, "fmt": "%.0f%% chance to arc lightning to a nearby enemy for 40%% damage", "pct": true, "description": "10% chance to arc lightning to a nearby enemy for 40% damage"},
	&"bane":            {"name": "Bane",              "slot": "sword", "tier": 2, "min": 0.06, "max": 0.10, "fmt": "%.0f%% chance to deal double damage", "pct": true, "description": "8% chance to deal double damage"},
	&"siphon":          {"name": "Siphon",            "slot": "sword", "tier": 1, "min": 2.0, "max": 4.0, "fmt": "Restore %.0f stamina per hit", "pct": false, "description": "Restore 3 stamina per hit"},
	&"runic":           {"name": "Runic",             "slot": "sword", "tier": 2, "min": 0.09, "max": 0.15, "fmt": "%.0f%% chance to trigger AoE for 25%% weapon damage", "pct": true, "description": "12% chance to trigger AoE for 25% weapon damage"},
	# ── Bow affixes (ranged combat) ──────────────────────────────────────
	&"precision":       {"name": "Precision",        "slot": "bow", "tier": 1, "min": 0.16, "max": 0.24, "fmt": "+%.0f%% headshot damage", "pct": true, "description": "+20% headshot damage"},
	# multishot: REMOVED
	&"bouncing_shot":   {"name": "Bouncing Shot",    "slot": "bow", "tier": 2, "min": 0.28, "max": 0.38, "fmt": "%.0f%% chance for arrows to bounce to a nearby enemy", "pct": true, "description": "33% chance for arrows to bounce to a nearby enemy"},
	&"sniper":          {"name": "Sniper",            "slot": "bow", "tier": 1, "min": 0.19, "max": 0.31, "fmt": "+%.0f%% damage at long range (>15 units)", "pct": true, "description": "+25% damage at long range (>15 units)"},
	&"rapid_draw":      {"name": "Rapid Draw",       "slot": "bow", "tier": 1, "min": 0.11, "max": 0.19, "fmt": "%.0f%% faster bow draw speed", "pct": true, "description": "15% faster bow draw speed"},
	&"poison_tip":      {"name": "Poison Tip",       "slot": "bow", "tier": 1, "min": 0.015, "max": 0.025, "fmt": "Arrows apply poison (%.1f%% max HP/s for 4s)", "pct": true, "description": "Arrows apply poison (2% max HP/s for 4s)"},
	&"frost_arrow":     {"name": "Frost Arrow",      "slot": "bow", "tier": 1, "min": 0.28, "max": 0.42, "fmt": "Arrows slow target by %.0f%% for 3s", "pct": true, "description": "Arrows slow target by 35% for 3s"},
	&"explosive":       {"name": "Explosive",        "slot": "bow", "tier": 2, "min": 0.07, "max": 0.13, "fmt": "%.0f%% chance for arrows to deal AoE damage on impact", "pct": true, "description": "10% chance for arrows to deal AoE damage on impact"},
	&"steady_aim":      {"name": "Steady Aim",       "slot": "bow", "tier": 1, "min": 9.0, "max": 15.0, "fmt": "+%.0f%% crit chance while standing still", "pct": false, "description": "+12% crit chance while standing still"},
	&"echoing_shot":    {"name": "Echoing Shot",     "slot": "bow", "tier": 1, "min": 0.38, "max": 0.46, "fmt": "%.0f%% chance to fire a bonus arrow", "pct": true, "description": "42% chance to fire a bonus arrow"},
	&"heatseeking":     {"name": "Heatseeking",      "slot": "bow", "tier": 2, "description": "Arrows home toward nearby enemies in their trajectory"},
	&"quickdraw":       {"name": "Quickdraw",         "slot": "bow", "tier": 1, "min": 0.25, "max": 0.41, "fmt": "%.0f%% faster bow draw speed", "pct": true, "description": "33% faster bow draw speed"},
	# echoing_shot (phantom arrow): REMOVED — replaced by new echoing_shot (was quiver_mastery)
	# ── Chest armor affixes ──────────────────────────────────────────────
	&"vitality":        {"name": "Vitality",         "slot": "chest", "tier": 1, "min": 10.0, "max": 20.0, "fmt": "+%.0f max health", "pct": false, "description": "+15 max health"},
	&"fortified":       {"name": "Fortified",        "slot": "chest", "tier": 1, "min": 0.06, "max": 0.10, "fmt": "+%.0f%% damage reduction", "pct": true, "description": "+8% damage reduction"},
	&"iron_skin":       {"name": "Iron Skin",        "slot": "chest", "tier": 2, "min": 0.06, "max": 0.10, "fmt": "%.0f%% chance to negate most damage", "pct": true, "description": "8% chance to negate most damage"},
	&"thorns":          {"name": "Thorns",           "slot": "chest", "tier": 1, "min": 0.11, "max": 0.19, "fmt": "Reflect %.0f%% of damage taken to attacker", "pct": true, "description": "Reflect 15% of damage taken to attacker"},
	&"second_wind":     {"name": "Second Wind",      "slot": "chest", "tier": 2, "min": 0.15, "max": 0.25, "fmt": "When hit below 20%% HP, heal %.0f%% HP (45s cooldown)", "pct": true, "description": "When hit below 20% HP, heal 20% HP (45s cooldown)"},
	&"undying":         {"name": "Undying",           "slot": "chest", "tier": 2, "min": 0.07, "max": 0.13, "fmt": "On death, revive with %.0f%% HP (300s cooldown)", "pct": true, "description": "On death, revive with 10% HP (300s cooldown)"},
	&"bulwark":         {"name": "Bulwark",          "slot": "chest", "tier": 1, "min": 2.0, "max": 4.0, "fmt": "+%.0f flat armor", "pct": false, "description": "+3 flat armor"},
	&"regenerator":     {"name": "Regenerator",      "slot": "chest", "tier": 2, "min": 0.7, "max": 1.3, "fmt": "+%.1f HP/s even during combat", "pct": false, "description": "+1.0 HP/s even during combat"},
	&"guardian":        {"name": "Guardian",         "slot": "chest", "tier": 1, "min": 0.75, "max": 0.85, "fmt": "Blocking grants %.0f%% damage reduction (base 70%%)", "pct": true, "description": "Block reduces damage to 20% instead of 30%"},
	&"battle_hardened": {"name": "Battle Hardened",  "slot": "chest", "tier": 1, "min": 0.04, "max": 0.06, "fmt": "+%.0f%% damage reduction per nearby enemy (max 3)", "pct": true, "description": "+5% damage reduction per nearby enemy (max 3)"},
	# ── Legs armor affixes ───────────────────────────────────────────────
	&"endurance":       {"name": "Endurance",        "slot": "legs", "tier": 1, "min": 15.0, "max": 25.0, "fmt": "+%.0f max stamina", "pct": false, "description": "+20 max stamina"},
	&"resilience":      {"name": "Resilience",       "slot": "legs", "tier": 1, "min": 0.19, "max": 0.31, "fmt": "+%.0f%% stamina regeneration rate", "pct": true, "description": "+25% stamina regeneration rate"},
	&"steadfast":       {"name": "Steadfast",        "slot": "legs", "tier": 1, "description": "Immune to knockback"},
	&"thick_skinned":   {"name": "Thick Skinned",    "slot": "legs", "tier": 2, "min": 0.22, "max": 0.38, "fmt": "First hit in combat deals %.0f%% less damage (10s cooldown)", "pct": true, "description": "First hit in combat deals 30% less damage (10s cooldown)"},
	&"last_stand":      {"name": "Last Stand",       "slot": "legs", "tier": 1, "min": 0.19, "max": 0.31, "fmt": "+%.0f%% damage reduction below 25%% HP", "pct": true, "description": "+25% damage reduction below 25% HP"},
	&"fleet":           {"name": "Fleet",            "slot": "legs", "tier": 1, "min": 0.19, "max": 0.31, "fmt": "Sprint stamina cost reduced by %.0f%%", "pct": true, "description": "Sprint stamina cost reduced by 25%"},
	&"rejuvenation":    {"name": "Rejuvenation",     "slot": "legs", "tier": 1, "min": 0.22, "max": 0.38, "fmt": "+%.0f%% health regeneration rate", "pct": true, "description": "+30% health regeneration rate"},
	&"quick_recovery":  {"name": "Quick Recovery",   "slot": "legs", "tier": 1, "min": 1.5, "max": 2.5, "fmt": "Health regen starts %.1fs sooner after damage", "pct": false, "description": "Health regen starts 2s sooner after damage"},
	&"lucky":           {"name": "Lucky",            "slot": "legs", "tier": 1, "min": 0.03, "max": 0.07, "fmt": "+%.0f%% rare drop chance from creatures", "pct": true, "description": "+5% rare drop chance from creatures"},
	&"tenacity":        {"name": "Tenacity",         "slot": "legs", "tier": 1, "min": 0.50, "max": 0.70, "fmt": "Cannot be slowed below %.0f%% base speed", "pct": true, "description": "Cannot be slowed below 60% base speed"},
	# ── Mace affixes (heavy melee / crowd control) ──────────────────────
	&"skull_crusher":    {"name": "Skull Crusher",    "slot": "mace", "tier": 1, "min": 0.19, "max": 0.31, "fmt": "+%.0f%% damage to stunned enemies", "pct": true, "description": "+25% damage to stunned enemies"},
	&"concussive":       {"name": "Concussive",       "slot": "mace", "tier": 1, "min": 0.15, "max": 0.25, "fmt": "%.0f%% chance to disorient enemies for 3s", "pct": true, "description": "20% chance to disorient enemies, reducing their damage by 20% for 3s"},
	&"bone_breaker":     {"name": "Bone Breaker",     "slot": "mace", "tier": 2, "min": 0.07, "max": 0.13, "fmt": "%.0f%% chance to shred enemy armor by 30%% for 5s", "pct": true, "description": "10% chance to shred enemy armor by 30% for 5s"},
	&"earthshaker":      {"name": "Earthshaker",      "slot": "mace", "tier": 2, "min": 0.09, "max": 0.15, "fmt": "%.0f%% chance for ground slam AoE on hit (30%% weapon dmg)", "pct": true, "description": "12% chance for ground slam AoE on hit (30% weapon dmg)"},
	&"echoing_blade":    {"name": "Echoing Blade",    "slot": "mace", "tier": 1, "min": 0.19, "max": 0.31, "fmt": "Ghost swing follows 0.5s later for %.0f%% damage", "pct": true, "description": "After a heavy attack, a ghost swing follows 0.5s later for 25% damage"},
	&"staggering":       {"name": "Staggering",       "slot": "mace", "tier": 1, "min": 0.13, "max": 0.23, "fmt": "%.0f%% chance to interrupt enemy attacks", "pct": true, "description": "18% chance to interrupt enemy attacks"},
	&"relentless_fury":  {"name": "Relentless Fury",  "slot": "mace", "tier": 1, "min": 0.04, "max": 0.06, "fmt": "Each consecutive hit adds +%.1f%% damage (max 5 stacks)", "pct": true, "description": "Each consecutive hit adds +5% damage (max 5 stacks, resets after 3s)"},
	&"iron_will":        {"name": "Iron Will",        "slot": "mace", "tier": 1, "min": 0.07, "max": 0.13, "fmt": "+%.0f%% damage reduction while attacking", "pct": true, "description": "+10% damage reduction while attacking"},
	&"crushing_momentum":{"name": "Crushing Momentum","slot": "mace", "tier": 1, "min": 0.15, "max": 0.25, "fmt": "On kill, +%.0f%% attack speed for 4s", "pct": true, "description": "On kill, +20% attack speed for 4s"},
	&"thunderclap":      {"name": "Thunderclap",      "slot": "mace", "tier": 2, "min": 0.06, "max": 0.10, "fmt": "%.0f%% chance to deal lightning AoE (25%% weapon dmg)", "pct": true, "description": "8% chance to deal lightning damage to all enemies within 3 units (25% weapon dmg)"},
	# ── Shield affixes (blocking / defense) ──────────────────────────────
	&"shield_wall":      {"name": "Shield Wall",      "slot": "shield", "tier": 1, "min": 0.11, "max": 0.19, "fmt": "+%.0f%% block chance", "pct": true, "description": "+15% block chance"},
	&"retaliation":      {"name": "Retaliation",      "slot": "shield", "tier": 1, "min": 0.22, "max": 0.38, "fmt": "After blocking, next attack deals +%.0f%% damage for 3s", "pct": true, "description": "After blocking, next attack deals +30% damage for 3s"},
	&"fortress":         {"name": "Fortress",         "slot": "shield", "tier": 2, "min": 3.0, "max": 7.0, "fmt": "+%.0f flat armor while shield is equipped", "pct": false, "description": "+5 flat armor while shield is equipped"},
	&"deflection":       {"name": "Deflection",       "slot": "shield", "tier": 1, "min": 0.11, "max": 0.19, "fmt": "%.0f%% chance to deflect projectiles", "pct": true, "description": "15% chance to deflect projectiles"},
	&"steadfast_guard":  {"name": "Steadfast Guard",  "slot": "shield", "tier": 1, "description": "Blocking no longer costs stamina"},
	&"aegis":            {"name": "Aegis",             "slot": "shield", "tier": 2, "min": 0.07, "max": 0.13, "fmt": "%.0f%% chance when hit to absorb 15%% max HP as shield for 5s", "pct": true, "description": "10% chance when hit to absorb 15% max HP as a damage shield for 5s"},
	&"stalwart":         {"name": "Stalwart",          "slot": "shield", "tier": 1, "min": 0.22, "max": 0.38, "fmt": "-%.0f%% knockback received", "pct": true, "description": "-30% knockback received"},
	&"rally_cry":        {"name": "Rally Cry",         "slot": "shield", "tier": 1, "min": 1.5, "max": 2.5, "fmt": "+%.1f HP/s while shield is equipped", "pct": false, "description": "+2 HP/s while shield is equipped"},
	&"shield_bash":      {"name": "Shield Bash",       "slot": "shield", "tier": 1, "min": 0.19, "max": 0.31, "fmt": "%.0f%% chance when blocking to stun attacker for 1s", "pct": true, "description": "25% chance when blocking to stun attacker for 1s"},
	&"unbreakable":      {"name": "Unbreakable",       "slot": "shield", "tier": 2, "description": "When below 25% HP, blocking absorbs 100% of damage"},
	# ── Boots armor affixes ──────────────────────────────────────────────
	&"swiftness":       {"name": "Swiftness",       "slot": "feet", "tier": 1, "min": 0.07, "max": 0.13, "fmt": "+%.0f%% movement speed", "pct": true, "description": "+10% movement speed"},
	&"aquatic":         {"name": "Aquatic",          "slot": "feet", "tier": 1, "min": 0.22, "max": 0.38, "fmt": "+%.0f%% swim speed", "pct": true, "description": "+30% swim speed"},
	&"warmth":          {"name": "Warmth",           "slot": "feet", "tier": 1, "min": 0.30, "max": 0.50, "fmt": "Reduce swim stamina cost by %.0f%%", "pct": true, "description": "Reduce swim stamina cost by 40%"},
	&"featherfall":     {"name": "Featherfall",      "slot": "feet", "tier": 1, "min": 0.38, "max": 0.62, "fmt": "Reduce fall damage by %.0f%%", "pct": true, "description": "Reduce fall damage by 50%"},
	&"evasion":         {"name": "Evasion",          "slot": "feet", "tier": 2, "min": 0.04, "max": 0.06, "fmt": "%.0f%% chance to auto-dodge an attack", "pct": true, "description": "5% chance to auto-dodge an attack"},
	&"adrenaline":      {"name": "Adrenaline",       "slot": "feet", "tier": 1, "min": 0.11, "max": 0.19, "fmt": "On kill, +%.0f%% movement speed for 4s", "pct": true, "description": "On kill, +15% movement speed for 4s"},
	&"sure_footed":     {"name": "Sure-Footed",      "slot": "feet", "tier": 1, "description": "No movement speed penalty on slopes"},
	&"light_step":      {"name": "Light Step",       "slot": "feet", "tier": 1, "min": 0.22, "max": 0.38, "fmt": "-%.0f%% fall damage and silent movement", "pct": true, "description": "-30% fall damage and silent movement"},
	&"trailblazer":     {"name": "Trailblazer",      "slot": "feet", "tier": 1, "min": 0.11, "max": 0.19, "fmt": "+%.0f%% movement speed in water", "pct": true, "description": "+15% movement speed in water"},
	&"nimble":          {"name": "Nimble",            "slot": "feet", "tier": 2, "min": 0.06, "max": 0.10, "fmt": "+%.0f%% dodge chance while sprinting", "pct": true, "description": "+8% dodge chance while sprinting"},
	&"double_jump":     {"name": "Double Jump",       "slot": "feet", "tier": 2, "description": "Perform one additional jump while mid-air"},
}

static func _get_affix_pool(affix_slot: String) -> Array[StringName]:
	var pool: Array[StringName] = []
	for affix_id: StringName in AFFIXES.keys():
		var a: Dictionary = AFFIXES[affix_id]
		var s: String = a.get("slot", "") as String
		if s == affix_slot:
			pool.append(affix_id)
	return pool

static func roll_affixes(stars: int, affix_slot: String) -> Array[StringName]:
	var count := 0
	if stars == 2: count = 1
	elif stars == 3: count = 2
	elif stars == 4: count = 3
	elif stars >= 5: count = 5
	if count == 0:
		return []
	var pool := _get_affix_pool(affix_slot)
	if pool.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var weighted: Array[Dictionary] = []
	for affix_id in pool:
		var tier: int = int(AFFIXES[affix_id].get("tier", 1))
		var w := 1.0 if tier == 1 else 0.5
		weighted.append({"id": affix_id, "weight": w})
	var chosen: Array[StringName] = []
	for _i in count:
		if weighted.is_empty():
			break
		var total_w := 0.0
		for entry in weighted:
			total_w += float(entry["weight"])
		var roll := rng.randf() * total_w
		var cum := 0.0
		for j in weighted.size():
			cum += float(weighted[j]["weight"])
			if roll < cum:
				chosen.append(weighted[j]["id"] as StringName)
				weighted.remove_at(j)
				break
	chosen.sort()
	return chosen

static func get_affix_data(affix_id: StringName) -> Dictionary:
	return AFFIXES.get(affix_id, {})


static func get_affix_value(affix_id: StringName, roll: float, fallback: float = -1.0) -> float:
	var data: Dictionary = AFFIXES.get(affix_id, {})
	if not data.has("min"):
		return fallback
	return lerpf(float(data["min"]), float(data["max"]), clampf(roll, 0.0, 1.0))


static func format_affix_description(affix_id: StringName, roll: float) -> String:
	var data: Dictionary = AFFIXES.get(affix_id, {})
	if not data.has("fmt"):
		return str(data.get("description", ""))
	var val := get_affix_value(affix_id, roll)
	var display_val: float = val * 100.0 if data.get("pct", false) else val
	return str(data["fmt"]) % display_val


static func roll_affix_magnitudes(affixes: Array[StringName]) -> Dictionary:
	var rolls := {}
	for a in affixes:
		rolls[a] = randi_range(0, 100)
	return rolls


func get_affix_slot(item_id: StringName) -> String:
	var parsed := parse_star_id(item_id)
	var base_id: StringName = parsed["base_id"]
	var data: Dictionary = _items.get(base_id, {})
	var item_type: String = str(data.get("type", ""))
	if item_type == "weapon":
		return get_weapon_class(item_id)
	elif item_type == "armor":
		return str(data.get("armor_slot", "chest"))
	return ""


func _ready() -> void:
	_register_defaults()


func register_item(id: StringName, data: Dictionary) -> void:
	_items[id] = data


func get_item(id: StringName) -> Dictionary:
	if _items.has(id):
		return _items[id]
	var parsed := parse_star_id(id)
	var base: Dictionary = _items.get(parsed["base_id"], {})
	var stars: int = parsed["stars"]
	var affixes: Array = parsed.get("affixes", [])
	if base.is_empty():
		return base
	if stars == 0 and affixes.is_empty():
		return base
	var scaled := base.duplicate()
	var dmg_mult := 1.0 + stars * 0.15
	var armor_mult := 1.0 + stars * 0.25
	if scaled.has("damage"):
		scaled["damage"] = float(scaled["damage"]) * dmg_mult
	if scaled.has("armor"):
		scaled["armor"] = float(scaled["armor"]) * armor_mult
	if scaled.has("knockback"):
		scaled["knockback"] = float(scaled["knockback"]) * (1.0 + stars * 0.10)
	if scaled.has("range"):
		scaled["range"] = float(scaled["range"]) * (1.0 + stars * 0.05)
	if not affixes.is_empty():
		scaled["affixes"] = affixes
	return scaled


func has_item(id: StringName) -> bool:
	if _items.has(id):
		return true
	var parsed := parse_star_id(id)
	return _items.has(parsed["base_id"])


func get_icon(id: StringName) -> Texture2D:
	var data: Dictionary = get_item(id)
	var path: String = data.get("icon", "") as String
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


# --- Star rarity helpers ---

static func make_star_id(base_id: StringName, stars: int, affixes: Array[StringName] = [], affix_rolls: Dictionary = {}) -> StringName:
	if stars <= 0 and affixes.is_empty():
		return base_id
	var result := str(base_id) + ":" + str(maxi(stars, 0))
	if not affixes.is_empty():
		var sorted_affixes := affixes.duplicate()
		sorted_affixes.sort()
		var parts: PackedStringArray = []
		for a in sorted_affixes:
			var roll_val: int = int(affix_rolls.get(a, 50))
			parts.append(str(a) + "@" + str(clampi(roll_val, 0, 100)))
		result += ":" + ",".join(parts)
	return StringName(result)


static func parse_star_id(composite_id: StringName) -> Dictionary:
	var s := str(composite_id)
	var colon := s.find(":")
	if colon < 0:
		return {"base_id": composite_id, "stars": 0, "affixes": [] as Array[StringName], "affix_rolls": {}}
	var base_id := StringName(s.substr(0, colon))
	var rest := s.substr(colon + 1)
	var colon2 := rest.find(":")
	if colon2 < 0:
		if rest.is_valid_int():
			return {"base_id": base_id, "stars": int(rest), "affixes": [] as Array[StringName], "affix_rolls": {}}
		return {"base_id": composite_id, "stars": 0, "affixes": [] as Array[StringName], "affix_rolls": {}}
	var stars_str := rest.substr(0, colon2)
	var affix_str := rest.substr(colon2 + 1)
	var affixes: Array[StringName] = []
	var affix_rolls := {}
	for a in affix_str.split(","):
		if a.is_empty():
			continue
		var at_pos := a.find("@")
		if at_pos >= 0:
			var affix_name := StringName(a.substr(0, at_pos))
			var roll_int := int(a.substr(at_pos + 1))
			affixes.append(affix_name)
			affix_rolls[affix_name] = clampf(float(roll_int) / 100.0, 0.0, 1.0)
		else:
			var affix_name := StringName(a)
			affixes.append(affix_name)
			affix_rolls[affix_name] = randf()
	if stars_str.is_valid_int():
		return {"base_id": base_id, "stars": int(stars_str), "affixes": affixes, "affix_rolls": affix_rolls}
	return {"base_id": composite_id, "stars": 0, "affixes": [] as Array[StringName], "affix_rolls": {}}


static func roll_star_level(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	var cumulative := 0.0
	for i in STAR_WEIGHTS.size():
		cumulative += STAR_WEIGHTS[i]
		if roll < cumulative:
			return i
	return 0


static func get_rarity_color(stars: int) -> Color:
	if stars >= 0 and stars < RARITY_COLORS.size():
		return RARITY_COLORS[stars]
	return RARITY_COLORS[0]


static func get_rarity_name(stars: int) -> String:
	if stars >= 0 and stars < RARITY_NAMES.size():
		return RARITY_NAMES[stars]
	return "Common"


func compute_recipe_star_avg(recipe: Array, max_star: int = 5, min_star: int = 0, prefer_low: bool = false) -> float:
	var total_weight := 0.0
	var total_qty := 0
	for ingredient in recipe:
		if not ingredient is Dictionary:
			continue
		var req_id: StringName = StringName(str(ingredient.get("item_id", "")))
		var req_amount: int = int(ingredient.get("amount", 0))
		var consumed: Dictionary = Inventory.preview_consume_capped_star(req_id, req_amount, max_star, min_star, prefer_low)
		for star_level: int in consumed.keys():
			var qty: int = int(consumed[star_level])
			total_weight += star_level * qty
			total_qty += qty
	if total_qty == 0:
		return 0.0
	return total_weight / float(total_qty)


static func get_crafting_probabilities(avg_material_quality: float) -> Array[float]:
	var weights: Array[float] = []
	var total := 0.0
	for i in 6:
		var distance := absf(avg_material_quality - float(i))
		var raw_weight := maxf(0.0, 2.0 - distance)
		if float(i) > avg_material_quality:
			raw_weight *= 0.75
		if distance > 1.5:
			raw_weight *= 0.5
		weights.append(raw_weight)
		total += raw_weight
	var probs: Array[float] = []
	for w in weights:
		probs.append(w / total if total > 0.0 else 0.0)
	return probs


static func roll_crafting_star(avg_material_quality: float) -> int:
	var probs := get_crafting_probabilities(avg_material_quality)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var roll := rng.randf()
	var cumulative := 0.0
	for i in probs.size():
		cumulative += probs[i]
		if roll < cumulative:
			return i
	return clampi(roundi(avg_material_quality), 0, 5)


func get_weapon_class(item_id: StringName) -> String:
	var parsed := parse_star_id(item_id)
	var data: Dictionary = _items.get(parsed["base_id"], {})
	if data.has("weapon_class"):
		return str(data["weapon_class"])
	var n := str(data.get("name", "")).to_lower()
	if "bow" in n: return "bow"
	if "pickaxe" in n: return "pickaxe"
	if "axe" in n: return "axe"
	if "sword" in n: return "sword"
	if "mace" in n: return "sword"
	return "fists"


func get_display_name(composite_id: StringName) -> String:
	var parsed := parse_star_id(composite_id)
	var base_id: StringName = parsed["base_id"]
	var data: Dictionary = _items.get(base_id, {})
	return data.get("name", str(base_id)) as String


func get_hand_recipes() -> Array:
	var result: Array = []
	for id: StringName in _items.keys():
		var data: Dictionary = _items[id]
		if data.get("crafting_station", "") == "hand" and data.has("recipe"):
			result.append({"id": id, "data": data})
	return result


func get_workbench_recipes() -> Array:
	var result: Array = []
	for id: StringName in _items.keys():
		var data: Dictionary = _items[id]
		var station: String = data.get("crafting_station", "") as String
		if (station == "workbench" or station == "hand") and data.has("recipe"):
			result.append({"id": id, "data": data})
	return result


func craft_item_at(item_id: StringName, _station: String, max_star: int = 5, min_star: int = 0, prefer_low: bool = false) -> StringName:
	var data := get_item(item_id)
	var recipe_var = data.get("recipe", [])
	var recipe: Array = recipe_var if recipe_var is Array else []
	if recipe.is_empty():
		return &""
	if not Inventory.has_free_craft():
		for ingredient in recipe:
			if not ingredient is Dictionary:
				continue
			var req_id: StringName = StringName(str(ingredient.get("item_id", "")))
			var req_amount: int = int(ingredient.get("amount", 0))
			if not Inventory.has_item_capped_star(req_id, req_amount, max_star, min_star):
				return &""

	var item_type: String = str(data.get("type", "material"))
	var is_equipment := item_type in ["weapon", "armor"]
	var crafted_stars := 0
	if is_equipment:
		crafted_stars = roll_crafting_star(compute_recipe_star_avg(recipe, max_star, min_star, prefer_low))

	if not Inventory.has_free_craft():
		for ingredient in recipe:
			if not ingredient is Dictionary:
				continue
			var req_id: StringName = StringName(str(ingredient.get("item_id", "")))
			var req_amount: int = int(ingredient.get("amount", 0))
			Inventory.remove_item_capped_star(req_id, req_amount, max_star, min_star, prefer_low)

	var crafted_affixes: Array[StringName] = []
	var crafted_rolls: Dictionary = {}
	if is_equipment and crafted_stars >= 2:
		crafted_affixes = roll_affixes(crafted_stars, get_affix_slot(item_id))
		crafted_rolls = roll_affix_magnitudes(crafted_affixes)

	var amount: int = int(data.get("craft_amount", 1))
	var output_id := make_star_id(item_id, crafted_stars, crafted_affixes, crafted_rolls) if is_equipment and (crafted_stars > 0 or not crafted_affixes.is_empty()) else item_id
	Inventory.add_item(output_id, amount)
	return output_id


func can_craft(item_id: StringName, max_star: int = 5, min_star: int = 0) -> bool:
	var data := get_item(item_id)
	var recipe_var = data.get("recipe", [])
	var recipe: Array = recipe_var if recipe_var is Array else []
	if recipe.is_empty():
		return false
	if Inventory.has_free_craft():
		return true
	for ingredient in recipe:
		if not ingredient is Dictionary:
			continue
		var req_id: StringName = StringName(str(ingredient.get("item_id", "")))
		var req_amount: int = int(ingredient.get("amount", 0))
		if not Inventory.has_item_capped_star(req_id, req_amount, max_star, min_star):
			return false
	return true


func craft_item(item_id: StringName) -> StringName:
	var data := get_item(item_id)
	var item_type: String = str(data.get("type", "material"))
	var is_equipment := item_type in ["weapon", "armor"]
	var eff_max: int = 5 if is_equipment else 0
	var eff_min: int = 0
	if not can_craft(item_id, eff_max, eff_min):
		return &""
	var recipe: Array = data.get("recipe", []) as Array
	var crafted_stars := 0
	if is_equipment:
		crafted_stars = roll_crafting_star(compute_recipe_star_avg(recipe))
	if not Inventory.has_free_craft():
		for ingredient: Dictionary in recipe:
			var req_id: StringName = StringName(ingredient.get("item_id", ""))
			var req_amount: int = int(ingredient.get("amount", 0))
			Inventory.remove_item_capped_star(req_id, req_amount, eff_max, eff_min, not is_equipment)
	var crafted_affixes: Array[StringName] = []
	var crafted_rolls: Dictionary = {}
	if is_equipment and crafted_stars >= 2:
		crafted_affixes = roll_affixes(crafted_stars, get_affix_slot(item_id))
		crafted_rolls = roll_affix_magnitudes(crafted_affixes)
	var output_id := make_star_id(item_id, crafted_stars, crafted_affixes, crafted_rolls) if is_equipment and (crafted_stars > 0 or not crafted_affixes.is_empty()) else item_id
	Inventory.add_item(output_id, 1)
	return output_id


func _spawn_oath_item(base_id: StringName, affix_slot: String) -> void:
	var all_affixes: Array[StringName] = _get_affix_pool(affix_slot)
	var god_rolls := {}
	for a in all_affixes:
		god_rolls[a] = 100
	var god_id := make_star_id(base_id, 5, all_affixes, god_rolls)
	Inventory.add_item(god_id, 1)

func spawn_god_sword() -> void:
	_spawn_oath_item(&"god_sword", "sword")

func spawn_god_bow() -> void:
	_spawn_oath_item(&"god_bow", "bow")

func spawn_god_axe() -> void:
	_spawn_oath_item(&"god_axe", "axe")

func spawn_god_pickaxe() -> void:
	_spawn_oath_item(&"god_pickaxe", "pickaxe")

func spawn_god_mace() -> void:
	_spawn_oath_item(&"god_mace", "mace")

func spawn_god_shield() -> void:
	_spawn_oath_item(&"god_shield", "shield")

func spawn_god_chest() -> void:
	_spawn_oath_item(&"god_chest", "chest")

func spawn_god_legs() -> void:
	_spawn_oath_item(&"god_legs", "legs")

func spawn_god_boots() -> void:
	_spawn_oath_item(&"god_boots", "feet")

func spawn_all_oath_gear() -> void:
	spawn_god_sword()
	spawn_god_bow()
	spawn_god_axe()
	spawn_god_pickaxe()
	spawn_god_mace()
	spawn_god_shield()
	spawn_god_chest()
	spawn_god_legs()
	spawn_god_boots()


func _register_defaults() -> void:
	# --- Materials ---
	register_item(&"wood", {
		"name": "Wood", "description": "A sturdy log.",
		"stack_size": 50, "type": "material",
		"icon": "res://textures/items/wood.png",
	})
	register_item(&"stone", {
		"name": "Stone", "description": "A chunk of rock.",
		"stack_size": 50, "type": "material",
		"icon": "res://textures/items/stone.png",
	})
	register_item(&"flint", {
		"name": "Flint", "description": "Sharp stone fragment.",
		"stack_size": 30, "type": "material",
		"icon": "res://textures/items/flint.png",
	})
	register_item(&"leather", {
		"name": "Leather Scraps", "description": "Scraggly hide.",
		"stack_size": 30, "type": "material",
		"icon": "res://textures/items/leather.png",
	})
	register_item(&"bone", {
		"name": "Bone Fragments", "description": "Bleached bones.",
		"stack_size": 30, "type": "material",
		"icon": "res://textures/items/bone.png",
	})
	register_item(&"meat", {
		"name": "Raw Meat", "description": "Uncooked meat.",
		"stack_size": 20, "type": "material",
		"icon": "res://textures/items/meat.png",
	})
	register_item(&"trophy_boar", {
		"name": "Boar Trophy", "description": "A boar's head.",
		"stack_size": 5, "type": "trophy",
		"icon": "res://textures/items/trophy_boar.png",
	})
	register_item(&"trophy_skeleton", {
		"name": "Skeleton Trophy", "description": "A skull.",
		"stack_size": 5, "type": "trophy",
		"icon": "res://textures/items/trophy_skeleton.png",
	})

	register_item(&"resin", {
		"name": "Resin", "description": "Sticky tree sap.",
		"stack_size": 50, "type": "material",
		"icon": "res://textures/items/resin.png",
	})
	register_item(&"copper_ore", {
		"name": "Copper Ore", "description": "Raw copper. Can be smelted into copper bars.",
		"stack_size": 30, "type": "material",
		"icon": "res://textures/items/copper_ore.png",
	})
	register_item(&"feather", {
		"name": "Feather", "description": "A light feather.",
		"stack_size": 50, "type": "material",
		"icon": "res://textures/items/feather.png",
	})
	register_item(&"raw_fish", {
		"name": "Raw Fish", "description": "A fresh catch. Could be cooked.",
		"stack_size": 20, "type": "material",
		"icon": "res://textures/items/raw_fish.png",
	})
	register_item(&"gold", {
		"name": "Gold", "description": "Shiny coins plundered from the fallen.",
		"stack_size": 999, "type": "material",
		"icon": "res://textures/items/gold.png",
	})
	register_item(&"thick_hide", {
		"name": "Thick Hide", "description": "A dense, tough pelt from a powerful beast.",
		"stack_size": 20, "type": "material",
		"icon": "res://textures/items/thick_hide.png",
	})
	register_item(&"fang", {
		"name": "Fang", "description": "A razor-sharp tooth ripped from a predator's jaw.",
		"stack_size": 20, "type": "material",
		"icon": "res://textures/items/fang.png",
	})
	register_item(&"amber", {
		"name": "Amber", "description": "A golden drop of fossilized tree sap. It glows faintly in moonlight.",
		"stack_size": 20, "type": "material",
		"icon": "res://textures/items/amber.png",
	})
	register_item(&"living_wood", {
		"name": "Living Wood", "description": "A branch that still pulses with life despite being severed.",
		"stack_size": 20, "type": "material",
		"icon": "res://textures/items/living_wood.png",
	})
	register_item(&"fairy_dust", {
		"name": "Fairy Dust", "description": "Shimmering particles left behind by woodland spirits.",
		"stack_size": 20, "type": "material",
		"icon": "res://textures/items/fairy_dust.png",
	})
	register_item(&"gemstone", {
		"name": "Gemstone", "description": "A rough but radiant stone that catches every beam of light.",
		"stack_size": 20, "type": "material",
		"icon": "res://textures/items/gemstone.png",
	})
	register_item(&"ancient_bone", {
		"name": "Ancient Bone", "description": "A weathered relic humming with faint energy.",
		"stack_size": 20, "type": "material",
		"icon": "res://textures/items/ancient_bone.png",
	})
	register_item(&"ember_stone", {
		"name": "Ember Stone", "description": "A smoldering fragment that never cools.",
		"stack_size": 20, "type": "material",
		"icon": "res://textures/items/ember_stone.png",
	})
	register_item(&"frost_shard", {
		"name": "Frost Shard", "description": "An icy crystal that chills the air around it.",
		"stack_size": 20, "type": "material",
		"icon": "res://textures/items/frost_shard.png",
	})

	# --- Tools / Weapons ---
	register_item(&"fists", {
		"name": "Fists", "type": "weapon", "hands": "1h",
		"damage": 5.0, "attack_speed": 1.0, "range": 2.5,
		"stamina_cost": 4.0, "knockback": 10.0,
	})
	register_item(&"starting_axe", {
		"name": "Splintered Hatchet", "type": "weapon", "hands": "1h", "armor_slot": "weapon",
		"weapon_class": "axe",
		"damage": 6.0, "attack_speed": 1.3, "range": 2.5,
		"stamina_cost": 5.0, "knockback": 8.0,
		"description": "Half the handle is missing and the head is held on by sheer stubbornness. Trees laugh when they see you coming.",
		"icon": "res://textures/items/stone_axe.png",
		"quality_color": Color(0.5, 0.5, 0.5), "quality_name": "Terrible",
	})
	register_item(&"starting_sword", {
		"name": "Rusty Butter Knife", "type": "weapon", "hands": "1h", "armor_slot": "sword",
		"weapon_class": "sword",
		"damage": 5.0, "attack_speed": 1.0, "range": 2.5,
		"stamina_cost": 5.0, "knockback": 8.0,
		"description": "Calling this a sword is generous. It's a flat piece of scrap metal that couldn't cut warm butter. Please craft literally anything else.",
		"icon": "res://textures/items/stone_sword.png",
		"quality_color": Color(0.5, 0.5, 0.5), "quality_name": "Terrible",
	})
	register_item(&"starting_bow", {
		"name": "Sad Twig & String", "type": "weapon", "hands": "2h", "armor_slot": "bow",
		"weapon_class": "bow",
		"damage": 3.0, "attack_speed": 2.2, "range": 18.0,
		"stamina_cost": 6.0, "knockback": 4.0,
		"description": "A 'bow' assembled from a bent stick and what appears to be old shoelace. Arrows fired from this may actually apologize to their targets on impact.",
		"icon": "res://textures/items/crude_bow.png",
		"quality_color": Color(0.5, 0.5, 0.5), "quality_name": "Terrible",
	})
	register_item(&"starting_pickaxe", {
		"name": "Blunt Rock-Poker", "type": "weapon", "hands": "1h", "armor_slot": "pickaxe",
		"weapon_class": "pickaxe",
		"damage": 4.0, "attack_speed": 1.3, "range": 2.5,
		"stamina_cost": 6.0, "knockback": 6.0,
		"description": "More of a pointy stick than a mining tool. Rocks openly mock you when you swing this. Even pebbles feel safe.",
		"icon": "res://textures/items/stone_pickaxe.png",
		"quality_color": Color(0.5, 0.5, 0.5), "quality_name": "Terrible",
	})
	register_item(&"starting_chest", {
		"name": "Moth-Eaten Rag", "type": "armor", "armor_slot": "chest",
		"armor": 1.0,
		"description": "Technically a 'vest' in the same way a trash bag is technically a raincoat. The moths that lived in it left for somewhere nicer.",
		"model": "res://models/armor/hooded+leather+cloak+3d+model.glb",
		"icon": "res://textures/items/leather_vest.png",
		"fit_scale": Vector3(1.05, 1.0, 1.05),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
		"quality_color": Color(0.5, 0.5, 0.5), "quality_name": "Terrible",
	})
	register_item(&"starting_legs", {
		"name": "Questionable Trousers", "type": "armor", "armor_slot": "legs",
		"armor": 0.5,
		"description": "You found these hanging from a branch. They smell like regret and old cheese. At least they have both legs... mostly.",
		"model": "res://models/armor/leather+pants+3d+model.glb",
		"icon": "res://textures/items/leather_pants.png",
		"fit_scale": Vector3(1.0, 1.0, 1.0),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
		"quality_color": Color(0.5, 0.5, 0.5), "quality_name": "Terrible",
	})
	register_item(&"starting_feet", {
		"name": "Soggy Foot Wraps", "type": "armor", "armor_slot": "feet",
		"armor": 0.5,
		"description": "Two strips of damp cloth wrapped around your feet. They provide the same protection as a strongly-worded letter. Rocks can feel you flinching through these.",
		"model": "res://models/armor/stylized+boots+3d+model.glb",
		"icon": "res://textures/items/leather_boots.png",
		"fit_scale": Vector3(1.0, 1.0, 1.0),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
		"quality_color": Color(0.5, 0.5, 0.5), "quality_name": "Terrible",
	})
	register_item(&"stone_axe", {
		"name": "Stone Axe", "type": "weapon", "hands": "2h", "armor_slot": "weapon",
		"damage": 18.0, "attack_speed": 1.3, "range": 3.2,
		"stamina_cost": 10.0, "knockback": 25.0,
		"description": "A hefty two-handed axe. Slow but devastating.",
		"icon": "res://textures/items/stone_axe.png",
		"recipe": [{"item_id": "wood", "amount": 5}, {"item_id": "stone", "amount": 4}],
		"crafting_station": "hand",
	})
	register_item(&"hammer", {
		"name": "Hammer", "type": "tool", "hands": "1h",
		"damage": 3.0, "attack_speed": 1.2, "range": 2.5,
		"stamina_cost": 3.0, "knockback": 5.0,
		"description": "Building tool. Right-click to open build menu.",
		"icon": "res://textures/items/hammer.png",
		"recipe": [{"item_id": "wood", "amount": 3}, {"item_id": "stone", "amount": 2}],
		"crafting_station": "hand",
	})
	register_item(&"torch", {
		"name": "Torch", "type": "tool", "hands": "1h",
		"damage": 5.0, "attack_speed": 0.8, "range": 2.0,
		"stamina_cost": 3.0, "knockback": 5.0,
		"description": "A burning torch. Provides light when equipped. Crafts 2.",
		"icon": "res://textures/items/torch.png",
		"recipe": [{"item_id": "wood", "amount": 1}, {"item_id": "resin", "amount": 1}],
		"crafting_station": "hand", "craft_amount": 2,
	})
	# --- Workbench recipes ---
	register_item(&"wood_arrow", {
		"name": "Wood Arrow", "type": "ammo",
		"description": "Simple wooden arrows. Crafted in bundles of 10.",
		"stack_size": 100,
		"icon": "res://textures/items/wood_arrow.png",
		"recipe": [{"item_id": "wood", "amount": 8}],
		"crafting_station": "workbench", "craft_amount": 10,
	})
	register_item(&"crude_bow", {
		"name": "Crude Bow", "type": "weapon", "hands": "2h", "armor_slot": "bow",
		"damage": 12.0, "attack_speed": 1.8, "range": 30.0,
		"stamina_cost": 8.0, "knockback": 10.0,
		"description": "A simple bow. Requires arrows.",
		"icon": "res://textures/items/crude_bow.png",
		"recipe": [{"item_id": "wood", "amount": 10}, {"item_id": "leather", "amount": 8}],
		"crafting_station": "workbench",
	})
	register_item(&"starting_shield", {
		"name": "Driftwood Plank", "type": "armor", "hands": "1h", "armor_slot": "shield",
		"armor": 1.0, "knockback": 5.0,
		"description": "A waterlogged plank you picked up off the beach. Calling it a 'shield' is an insult to shields everywhere. A stiff breeze could punch through this.",
		"icon": "res://textures/items/wood_shield.png",
		"quality_color": Color(0.5, 0.5, 0.5), "quality_name": "Terrible",
	})
	register_item(&"wood_shield", {
		"name": "Wood Shield", "type": "armor", "hands": "1h", "armor_slot": "shield",
		"armor": 10.0, "knockback": 20.0,
		"description": "A round wooden shield.",
		"icon": "res://textures/items/wood_shield.png",
		"recipe": [{"item_id": "wood", "amount": 10}],
		"crafting_station": "workbench",
	})
	register_item(&"stone_pickaxe", {
		"name": "Stone Pickaxe", "type": "weapon", "hands": "1h", "armor_slot": "pickaxe",
		"damage": 8.0, "attack_speed": 1.2, "range": 2.8,
		"stamina_cost": 8.0, "knockback": 10.0,
		"description": "A crude pickaxe for mining stone and ore.",
		"icon": "res://textures/items/stone_pickaxe.png",
		"recipe": [{"item_id": "wood", "amount": 5}, {"item_id": "stone", "amount": 6}],
		"crafting_station": "workbench",
	})
	register_item(&"stone_sword", {
		"name": "Stone Sword", "type": "weapon", "hands": "1h", "armor_slot": "sword",
		"damage": 18.0, "attack_speed": 1.0, "range": 3.0,
		"stamina_cost": 7.0, "knockback": 20.0,
		"description": "A rough blade of sharpened stone. Balanced and reliable.",
		"icon": "res://textures/items/stone_sword.png",
		"recipe": [{"item_id": "wood", "amount": 4}, {"item_id": "stone", "amount": 8}, {"item_id": "leather", "amount": 2}],
		"crafting_station": "workbench",
	})

	# --- Advanced weapons (no recipe yet) ---
	register_item(&"flint_axe", {
		"name": "Flint Axe", "type": "weapon", "hands": "1h", "armor_slot": "weapon",
		"weapon_class": "axe",
		"damage": 15.0, "attack_speed": 1.1, "range": 2.8,
		"stamina_cost": 8.0, "knockback": 20.0,
		"description": "A sharp flint blade bound to a wooden handle.",
		"icon": "res://textures/items/flint_axe.png",
		"recipe": [{"item_id": "wood", "amount": 6}, {"item_id": "flint", "amount": 4}],
		"crafting_station": "workbench",
	})
	register_item(&"bronze_sword", {
		"name": "Bronze Sword", "type": "weapon", "hands": "1h", "armor_slot": "sword",
		"weapon_class": "sword",
		"damage": 25.0, "attack_speed": 0.9, "range": 3.0,
		"stamina_cost": 10.0, "knockback": 25.0,
		"description": "A bronze blade with a simple crossguard.",
		"icon": "res://textures/items/bronze_sword.png",
		"recipe": [{"item_id": "wood", "amount": 5}, {"item_id": "copper_ore", "amount": 10}, {"item_id": "leather", "amount": 3}],
		"crafting_station": "workbench",
	})
	register_item(&"bronze_mace", {
		"name": "Bronze Mace", "type": "weapon", "hands": "1h", "armor_slot": "sword",
		"weapon_class": "mace",
		"damage": 35.0, "attack_speed": 1.5, "range": 2.5,
		"stamina_cost": 14.0, "knockback": 50.0,
		"description": "A flanged bronze mace. Crushes bones with ease.",
		"icon": "res://textures/items/bronze_mace.png",
		"recipe": [{"item_id": "wood", "amount": 6}, {"item_id": "copper_ore", "amount": 12}],
		"crafting_station": "workbench",
	})
	register_item(&"iron_sword", {
		"name": "Iron Sword", "type": "weapon", "hands": "1h", "armor_slot": "sword",
		"weapon_class": "sword",
		"damage": 40.0, "attack_speed": 0.85, "range": 3.0,
		"stamina_cost": 12.0, "knockback": 30.0,
		"description": "A dark iron longsword. Reliable in battle.",
		"icon": "res://textures/items/iron_sword.png",
	})

	# --- Starter Armor ---
	register_item(&"leather_vest", {
		"name": "Leather Vest", "type": "armor", "armor_slot": "chest",
		"armor": 5.0,
		"description": "A worn leather vest with carved patterns. Barely protective.",
		"model": "res://models/armor/hooded+leather+cloak+3d+model.glb",
		"icon": "res://textures/items/leather_vest_t2.png",
		"fit_scale": Vector3(1.05, 1.0, 1.05),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
		"recipe": [{"item_id": "leather", "amount": 6}, {"item_id": "wood", "amount": 2}],
		"crafting_station": "workbench",
	})
	register_item(&"leather_pants", {
		"name": "Leather Pants", "type": "armor", "armor_slot": "legs",
		"armor": 3.0,
		"description": "Stitched leather trousers. Better than nothing.",
		"model": "res://models/armor/leather+pants+3d+model.glb",
		"icon": "res://textures/items/leather_pants_t2.png",
		"fit_scale": Vector3(1.0, 1.0, 1.0),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
		"recipe": [{"item_id": "leather", "amount": 5}, {"item_id": "wood", "amount": 1}],
		"crafting_station": "workbench",
	})
	register_item(&"leather_boots", {
		"name": "Leather Boots", "type": "armor", "armor_slot": "feet",
		"armor": 2.0,
		"description": "Sturdy boots with metal plating and turquoise studs.",
		"model": "res://models/armor/stylized+boots+3d+model.glb",
		"icon": "res://textures/items/leather_boots_t2.png",
		"fit_scale": Vector3(1.0, 1.0, 1.0),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
		"recipe": [{"item_id": "leather", "amount": 4}],
		"crafting_station": "workbench",
	})

	# --- Advanced Axes ---
	register_item(&"iron_axe", {
		"name": "Iron Axe", "type": "weapon", "hands": "2h", "armor_slot": "weapon",
		"weapon_class": "axe",
		"damage": 30.0, "attack_speed": 1.2, "range": 3.2,
		"stamina_cost": 12.0, "knockback": 30.0,
		"description": "A heavy iron axe. Fells trees and enemies alike.",
		"icon": "res://textures/items/iron_axe.png",
		"recipe": [{"item_id": "wood", "amount": 8}, {"item_id": "iron_ore", "amount": 6}],
		"crafting_station": "workbench",
	})
	register_item(&"steel_axe", {
		"name": "Steel Axe", "type": "weapon", "hands": "2h", "armor_slot": "weapon",
		"weapon_class": "axe",
		"damage": 45.0, "attack_speed": 1.1, "range": 3.5,
		"stamina_cost": 14.0, "knockback": 35.0,
		"description": "A masterwork steel axe with a mirror-polished edge.",
		"icon": "res://textures/items/steel_axe.png",
	})

	# --- Advanced Swords ---
	register_item(&"steel_sword", {
		"name": "Steel Sword", "type": "weapon", "hands": "1h", "armor_slot": "sword",
		"weapon_class": "sword",
		"damage": 55.0, "attack_speed": 0.8, "range": 3.2,
		"stamina_cost": 14.0, "knockback": 35.0,
		"description": "A gleaming steel blade. The pinnacle of swordcraft.",
		"icon": "res://textures/items/steel_sword.png",
	})

	# --- Developer Oath Gear (all affixes for that slot, spawned via chat commands) ---
	register_item(&"god_sword", {
		"name": "Oathbreaker", "type": "weapon", "hands": "1h", "armor_slot": "sword",
		"weapon_class": "sword",
		"damage": 55.0, "attack_speed": 0.7, "range": 3.5,
		"stamina_cost": 5.0, "knockback": 40.0,
		"description": "A blade forged in developer tears. Every sword affix known to mortals hums within its edge.",
		"icon": "res://textures/items/steel_sword.png",
		"quality_color": Color(1.0, 0.84, 0.0), "quality_name": "Godly",
	})
	register_item(&"god_bow", {
		"name": "Oathgun", "type": "weapon", "hands": "2h", "armor_slot": "bow",
		"weapon_class": "bow",
		"damage": 40.0, "attack_speed": 0.9, "range": 75.0,
		"stamina_cost": 4.0, "knockback": 30.0,
		"description": "A bow that bends light itself. Every bow affix known to mortals sings along its string.",
		"icon": "res://textures/items/longbow.png",
		"quality_color": Color(1.0, 0.84, 0.0), "quality_name": "Godly",
	})
	register_item(&"god_axe", {
		"name": "Oathcleaver", "type": "weapon", "hands": "2h", "armor_slot": "weapon",
		"weapon_class": "axe",
		"damage": 45.0, "attack_speed": 1.0, "range": 3.5,
		"stamina_cost": 5.0, "knockback": 45.0,
		"description": "An axe that fells forests in a single thought. Every axe affix pulses through its head.",
		"icon": "res://textures/items/steel_axe.png",
		"quality_color": Color(1.0, 0.84, 0.0), "quality_name": "Godly",
	})
	register_item(&"god_pickaxe", {
		"name": "Oathpick", "type": "weapon", "hands": "1h", "armor_slot": "pickaxe",
		"weapon_class": "pickaxe",
		"damage": 28.0, "attack_speed": 0.8, "range": 3.0,
		"stamina_cost": 4.0, "knockback": 35.0,
		"description": "A pickaxe that drinks mountains dry. Every mining affix known to mortals rings in its strike.",
		"icon": "res://textures/items/steel_pickaxe.png",
		"quality_color": Color(1.0, 0.84, 0.0), "quality_name": "Godly",
	})
	register_item(&"god_mace", {
		"name": "Oathcrusher", "type": "weapon", "hands": "1h", "armor_slot": "sword",
		"weapon_class": "mace",
		"damage": 60.0, "attack_speed": 1.2, "range": 2.8,
		"stamina_cost": 6.0, "knockback": 50.0,
		"description": "A mace that shatters the laws of physics. Every mace affix thunders within its head.",
		"icon": "res://textures/items/steel_mace.png",
		"quality_color": Color(1.0, 0.84, 0.0), "quality_name": "Godly",
	})
	register_item(&"god_shield", {
		"name": "Oathguard", "type": "armor", "hands": "1h", "armor_slot": "shield",
		"armor": 40.0, "knockback": 40.0,
		"description": "A shield that blocks the concept of damage itself. Every shield affix wards its face.",
		"icon": "res://textures/items/steel_shield.png",
		"quality_color": Color(1.0, 0.84, 0.0), "quality_name": "Godly",
	})
	register_item(&"god_chest", {
		"name": "Oathplate", "type": "armor", "armor_slot": "chest",
		"armor": 28.0,
		"description": "Armor woven from pure willpower. Every chest affix reinforces its plates.",
		"icon": "res://textures/items/steel_chest.png",
		"quality_color": Color(1.0, 0.84, 0.0), "quality_name": "Godly",
	})
	register_item(&"god_legs", {
		"name": "Oathcuisses", "type": "armor", "armor_slot": "legs",
		"armor": 20.0,
		"description": "Cuisses that make the wearer tireless. Every legs affix flows through their links.",
		"icon": "res://textures/items/steel_legs.png",
		"quality_color": Color(1.0, 0.84, 0.0), "quality_name": "Godly",
	})
	register_item(&"god_boots", {
		"name": "Oathstriders", "type": "armor", "armor_slot": "feet",
		"armor": 14.0,
		"description": "Boots that outrun time itself. Every boots affix propels each step.",
		"icon": "res://textures/items/steel_boots.png",
		"quality_color": Color(1.0, 0.84, 0.0), "quality_name": "Godly",
	})

	# --- Advanced Bows ---
	register_item(&"hunting_bow", {
		"name": "Hunting Bow", "type": "weapon", "hands": "2h", "armor_slot": "bow",
		"weapon_class": "bow",
		"damage": 20.0, "attack_speed": 1.5, "range": 35.0,
		"stamina_cost": 10.0, "knockback": 15.0,
		"description": "A well-crafted bow carved from aged wood.",
		"icon": "res://textures/items/hunting_bow.png",
		"recipe": [{"item_id": "wood", "amount": 15}, {"item_id": "leather", "amount": 10}, {"item_id": "feather", "amount": 5}],
		"crafting_station": "workbench",
	})
	register_item(&"war_bow", {
		"name": "War Bow", "type": "weapon", "hands": "2h", "armor_slot": "bow",
		"weapon_class": "bow",
		"damage": 30.0, "attack_speed": 1.3, "range": 40.0,
		"stamina_cost": 12.0, "knockback": 20.0,
		"description": "A recurve bow reinforced with metal tips. Hits hard.",
		"icon": "res://textures/items/war_bow.png",
	})
	register_item(&"longbow", {
		"name": "Longbow", "type": "weapon", "hands": "2h", "armor_slot": "bow",
		"weapon_class": "bow",
		"damage": 40.0, "attack_speed": 1.1, "range": 50.0,
		"stamina_cost": 14.0, "knockback": 25.0,
		"description": "An elegant longbow of incredible range and power.",
		"icon": "res://textures/items/longbow.png",
	})

	# --- Advanced Pickaxes ---
	register_item(&"bronze_pickaxe", {
		"name": "Bronze Pickaxe", "type": "weapon", "hands": "1h", "armor_slot": "pickaxe",
		"weapon_class": "pickaxe",
		"damage": 14.0, "attack_speed": 1.1, "range": 2.8,
		"stamina_cost": 9.0, "knockback": 12.0,
		"description": "A bronze-tipped pickaxe. Mines faster than stone.",
		"icon": "res://textures/items/bronze_pickaxe.png",
		"recipe": [{"item_id": "wood", "amount": 6}, {"item_id": "copper_ore", "amount": 8}],
		"crafting_station": "workbench",
	})
	register_item(&"iron_pickaxe", {
		"name": "Iron Pickaxe", "type": "weapon", "hands": "1h", "armor_slot": "pickaxe",
		"weapon_class": "pickaxe",
		"damage": 20.0, "attack_speed": 1.0, "range": 3.0,
		"stamina_cost": 10.0, "knockback": 15.0,
		"description": "A sturdy iron pickaxe for serious mining.",
		"icon": "res://textures/items/iron_pickaxe.png",
	})
	register_item(&"steel_pickaxe", {
		"name": "Steel Pickaxe", "type": "weapon", "hands": "1h", "armor_slot": "pickaxe",
		"weapon_class": "pickaxe",
		"damage": 28.0, "attack_speed": 0.9, "range": 3.0,
		"stamina_cost": 12.0, "knockback": 18.0,
		"description": "A masterwork steel pickaxe. Shatters stone effortlessly.",
		"icon": "res://textures/items/steel_pickaxe.png",
	})

	# --- Advanced Maces ---
	register_item(&"stone_mace", {
		"name": "Stone Mace", "type": "weapon", "hands": "1h", "armor_slot": "sword",
		"weapon_class": "mace",
		"damage": 22.0, "attack_speed": 1.3, "range": 2.5,
		"stamina_cost": 10.0, "knockback": 35.0,
		"description": "A heavy stone ball on a stick. Simple but brutal.",
		"icon": "res://textures/items/stone_mace.png",
		"recipe": [{"item_id": "wood", "amount": 5}, {"item_id": "stone", "amount": 10}],
		"crafting_station": "workbench",
	})
	register_item(&"iron_mace", {
		"name": "Iron Mace", "type": "weapon", "hands": "1h", "armor_slot": "sword",
		"weapon_class": "mace",
		"damage": 45.0, "attack_speed": 1.4, "range": 2.5,
		"stamina_cost": 15.0, "knockback": 55.0,
		"description": "A flanged iron mace that dents armor with ease.",
		"icon": "res://textures/items/iron_mace.png",
	})
	register_item(&"steel_mace", {
		"name": "Steel Mace", "type": "weapon", "hands": "1h", "armor_slot": "sword",
		"weapon_class": "mace",
		"damage": 60.0, "attack_speed": 1.3, "range": 2.8,
		"stamina_cost": 16.0, "knockback": 65.0,
		"description": "A spiked steel war mace. Devastating in combat.",
		"icon": "res://textures/items/steel_mace.png",
	})

	# --- Advanced Chest Armor ---
	register_item(&"chain_chest", {
		"name": "Chainmail Shirt", "type": "armor", "armor_slot": "chest",
		"armor": 10.0,
		"description": "Interlocking metal rings provide solid protection.",
		"model": "res://models/armor/hooded+leather+cloak+3d+model.glb",
		"icon": "res://textures/items/chain_chest.png",
		"fit_scale": Vector3(1.05, 1.0, 1.05),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
	})
	register_item(&"iron_chest", {
		"name": "Iron Breastplate", "type": "armor", "armor_slot": "chest",
		"armor": 18.0,
		"description": "Heavy iron plates riveted together. Tough as nails.",
		"model": "res://models/armor/hooded+leather+cloak+3d+model.glb",
		"icon": "res://textures/items/iron_chest.png",
		"fit_scale": Vector3(1.05, 1.0, 1.05),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
	})
	register_item(&"steel_chest", {
		"name": "Steel Plate Armor", "type": "armor", "armor_slot": "chest",
		"armor": 28.0,
		"description": "Ornate steel plate armor. The finest protection available.",
		"model": "res://models/armor/hooded+leather+cloak+3d+model.glb",
		"icon": "res://textures/items/steel_chest.png",
		"fit_scale": Vector3(1.05, 1.0, 1.05),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
	})

	# --- Advanced Leg Armor ---
	register_item(&"chain_legs", {
		"name": "Chainmail Leggings", "type": "armor", "armor_slot": "legs",
		"armor": 7.0,
		"description": "Chain links woven into sturdy leg protection.",
		"model": "res://models/armor/leather+pants+3d+model.glb",
		"icon": "res://textures/items/chain_legs.png",
		"fit_scale": Vector3(1.0, 1.0, 1.0),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
	})
	register_item(&"iron_legs", {
		"name": "Iron Cuisses", "type": "armor", "armor_slot": "legs",
		"armor": 12.0,
		"description": "Solid iron leg plates. Heavy but reliable.",
		"model": "res://models/armor/leather+pants+3d+model.glb",
		"icon": "res://textures/items/iron_legs.png",
		"fit_scale": Vector3(1.0, 1.0, 1.0),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
	})
	register_item(&"steel_legs", {
		"name": "Steel Cuisses", "type": "armor", "armor_slot": "legs",
		"armor": 20.0,
		"description": "Polished steel leg armor with ornate engravings.",
		"model": "res://models/armor/leather+pants+3d+model.glb",
		"icon": "res://textures/items/steel_legs.png",
		"fit_scale": Vector3(1.0, 1.0, 1.0),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
	})

	# --- Advanced Boots ---
	register_item(&"chain_boots", {
		"name": "Chainmail Boots", "type": "armor", "armor_slot": "feet",
		"armor": 5.0,
		"description": "Chain-link boots offering decent foot protection.",
		"model": "res://models/armor/stylized+boots+3d+model.glb",
		"icon": "res://textures/items/chain_boots.png",
		"fit_scale": Vector3(1.0, 1.0, 1.0),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
	})
	register_item(&"iron_boots", {
		"name": "Iron Sabatons", "type": "armor", "armor_slot": "feet",
		"armor": 8.0,
		"description": "Heavy iron boots. Your feet are basically weapons now.",
		"model": "res://models/armor/stylized+boots+3d+model.glb",
		"icon": "res://textures/items/iron_boots.png",
		"fit_scale": Vector3(1.0, 1.0, 1.0),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
	})
	register_item(&"steel_boots", {
		"name": "Steel Sabatons", "type": "armor", "armor_slot": "feet",
		"armor": 14.0,
		"description": "Masterwork steel boots with intricate detail.",
		"model": "res://models/armor/stylized+boots+3d+model.glb",
		"icon": "res://textures/items/steel_boots.png",
		"fit_scale": Vector3(1.0, 1.0, 1.0),
		"fit_offset": Vector3(0.0, 0.0, 0.0),
		"fit_rotation": Vector3(0.0, -90.0, 0.0),
	})

	# --- Shields ---
	register_item(&"reinforced_shield", {
		"name": "Reinforced Shield", "type": "armor", "hands": "1h", "armor_slot": "shield",
		"armor": 15.0, "knockback": 25.0,
		"description": "A wooden shield reinforced with metal studs.",
		"icon": "res://textures/items/reinforced_shield.png",
		"recipe": [{"item_id": "wood", "amount": 15}, {"item_id": "copper_ore", "amount": 5}],
		"crafting_station": "workbench",
	})
	register_item(&"bronze_shield", {
		"name": "Bronze Shield", "type": "armor", "hands": "1h", "armor_slot": "shield",
		"armor": 22.0, "knockback": 30.0,
		"description": "A solid bronze round shield with an embossed boss.",
		"icon": "res://textures/items/bronze_shield.png",
	})
	register_item(&"iron_shield", {
		"name": "Iron Kite Shield", "type": "armor", "hands": "1h", "armor_slot": "shield",
		"armor": 30.0, "knockback": 35.0,
		"description": "A dark iron kite shield bearing a cross design.",
		"icon": "res://textures/items/iron_shield.png",
	})
	register_item(&"steel_shield", {
		"name": "Steel Tower Shield", "type": "armor", "hands": "1h", "armor_slot": "shield",
		"armor": 40.0, "knockback": 40.0,
		"description": "An ornate steel tower shield. Nearly impenetrable.",
		"icon": "res://textures/items/steel_shield.png",
	})

	# --- Placeables ---
	register_item(&"raft", {
		"name": "Raft", "type": "placeable", "stack_size": 1,
		"description": "A crude wooden raft. Place on water to sail.",
		"icon": "res://textures/items/raft.png",
		"recipe": [{"item_id": "wood", "amount": 20}],
		"crafting_station": "workbench",
	})
