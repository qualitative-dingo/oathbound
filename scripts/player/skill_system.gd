class_name SkillSystem
extends Node
## Use-based skill leveling. Skills improve as you use them
## (swing a sword → Swords skill goes up) and decay on death.
##
## Key mechanics:
##   - Skills range from 0 to 100.
##   - XP needed increases with level (soft cap — diminishing returns at high levels).
##   - Death penalty: lose 5% of total levels across all skills (~1/8 of total XP).
##   - After retrieving tombstone: 10-minute "No Skill Drain" immunity.
##   - Higher skill = more damage, less stamina cost, faster actions, etc.

signal skill_level_changed(skill_id: StringName, new_level: float)
signal skill_xp_gained(skill_id: StringName, amount: float)
signal skills_lost_on_death(total_lost: float)

const MAX_SKILL_LEVEL := 100.0
const DEATH_PENALTY_FRACTION := 0.05  # Lose 5% of total levels
const SKILL_DRAIN_IMMUNITY_DURATION := 600.0  # 10 minutes

## All supported skills with their current level and accumulated XP.
## Each skill: { "level": float, "xp": float, "xp_to_next": float }
var skills: Dictionary = {}
var no_skill_drain_timer: float = 0.0

## Skill definitions: base XP per use, and what the skill affects.
const SKILL_DEFS: Dictionary = {
	&"swords":       { "xp_per_use": 1.0, "desc": "Sword damage and attack speed" },
	&"knives":       { "xp_per_use": 1.0, "desc": "Knife damage and backstab bonus" },
	&"clubs":        { "xp_per_use": 1.0, "desc": "Club and mace damage" },
	&"polearms":     { "xp_per_use": 1.0, "desc": "Polearm damage and reach" },
	&"axes":         { "xp_per_use": 1.0, "desc": "Axe damage and chopping efficiency" },
	&"bows":         { "xp_per_use": 1.0, "desc": "Bow damage and draw speed" },
	&"unarmed":      { "xp_per_use": 1.0, "desc": "Fist damage" },
	&"blocking":     { "xp_per_use": 0.5, "desc": "Block power and parry window" },
	&"pickaxes":     { "xp_per_use": 1.0, "desc": "Mining damage and speed" },
	&"woodcutting":  { "xp_per_use": 1.0, "desc": "Tree chopping damage" },
	&"run":          { "xp_per_use": 0.1, "desc": "Sprint stamina efficiency" },
	&"jump":         { "xp_per_use": 0.5, "desc": "Jump height and stamina cost" },
	&"sneak":        { "xp_per_use": 0.5, "desc": "Sneak speed and detection range" },
	&"swim":         { "xp_per_use": 0.5, "desc": "Swim speed and stamina cost" },
	&"fishing":      { "xp_per_use": 1.0, "desc": "Fishing reel speed" },
	&"ride":         { "xp_per_use": 0.5, "desc": "Mount control and speed" },
}


func _ready() -> void:
	for skill_id in SKILL_DEFS:
		skills[skill_id] = { "level": 0.0, "xp": 0.0 }


func _process(delta: float) -> void:
	if no_skill_drain_timer > 0.0:
		no_skill_drain_timer -= delta


func get_skill_level(skill_id: StringName) -> float:
	if not skills.has(skill_id):
		return 0.0
	return skills[skill_id]["level"]


## The damage/efficiency multiplier for a skill.
## At level 0 = 1.0x, at level 100 = 2.0x (linear interpolation).
func get_skill_factor(skill_id: StringName) -> float:
	return 1.0 + get_skill_level(skill_id) / MAX_SKILL_LEVEL


## Add XP from performing an action (e.g. swinging a sword, chopping a tree).
func add_xp(skill_id: StringName, multiplier: float = 1.0) -> void:
	if not SKILL_DEFS.has(skill_id):
		return
	var skill: Dictionary = skills[skill_id]
	var base_xp: float = SKILL_DEFS[skill_id]["xp_per_use"]

	# Soft cap: XP gain decreases as you approach max level
	var level_factor: float = 1.0 - (float(skill["level"]) / MAX_SKILL_LEVEL) * 0.5
	var xp_gained: float = base_xp * multiplier * level_factor

	skill["xp"] += xp_gained
	skill_xp_gained.emit(skill_id, xp_gained)

	# Check for level up
	var xp_needed := _xp_for_next_level(skill["level"])
	while skill["xp"] >= xp_needed and skill["level"] < MAX_SKILL_LEVEL:
		skill["xp"] -= xp_needed
		skill["level"] = minf(skill["level"] + 1.0, MAX_SKILL_LEVEL)
		xp_needed = _xp_for_next_level(skill["level"])
		skill_level_changed.emit(skill_id, skill["level"])


## Called on player death. Reduces all skills by 5% of total levels.
func apply_death_penalty() -> void:
	if no_skill_drain_timer > 0.0:
		return  # Protected by "No Skill Drain" buff

	var total_levels := 0.0
	for skill_id in skills:
		total_levels += skills[skill_id]["level"]

	var total_to_lose := total_levels * DEATH_PENALTY_FRACTION

	# Distribute loss proportionally across all skills
	if total_levels <= 0.0:
		return

	for skill_id in skills:
		var skill: Dictionary = skills[skill_id]
		var fraction: float = skill["level"] / total_levels
		var loss := total_to_lose * fraction
		skill["level"] = maxf(skill["level"] - loss, 0.0)
		skill["xp"] = 0.0
		skill_level_changed.emit(skill_id, skill["level"])

	skills_lost_on_death.emit(total_to_lose)


## Called when the player retrieves their tombstone. Grants immunity.
func grant_no_skill_drain() -> void:
	no_skill_drain_timer = SKILL_DRAIN_IMMUNITY_DURATION


func _xp_for_next_level(current_level: float) -> float:
	# Escalating XP curve — higher levels need more XP
	return 10.0 + current_level * 5.0


## --- Save / Load ---

func serialize() -> Dictionary:
	var data := {}
	for skill_id in skills:
		data[skill_id] = skills[skill_id].duplicate()
	return data

func deserialize(data: Dictionary) -> void:
	for skill_id in data:
		if skills.has(skill_id):
			skills[skill_id] = data[skill_id]
