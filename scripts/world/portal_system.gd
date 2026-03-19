class_name PortalSystem
extends Node
## Manages portal pairs for fast travel.
##
## Metals and ores CANNOT go through portals.
## This single restriction creates the entire sailing/carting logistics loop.
## Without it, the exploration incentive collapses.
##
## Portal rules:
##   - Portals are linked by a case-sensitive tag string.
##   - Only two portals can share a tag (pairs). A third with the same tag is unlinked.
##   - Crafting cost: 20 Fine Wood, 10 Greydwarf Eyes, 2 Surtling Cores.
##   - Teleport is instant but has a short channel time.
##   - ALL items in inventory are checked against the teleport blacklist.
##     If ANY restricted item is present, the portal refuses to activate.

signal portal_registered(tag: String, portal: Node3D)
signal portal_unregistered(tag: String)
signal teleport_blocked(reason: String)
signal teleport_started(from_portal: Node3D, to_portal: Node3D)
signal teleport_completed()

const CHANNEL_TIME := 2.0  # Seconds to stand in portal before teleport

## Items that CANNOT be teleported. This is the core design pillar.
## Ores, ingots, and special heavy items.
const TELEPORT_RESTRICTED_ITEMS: Array[StringName] = [
	# Ores
	&"copper_ore", &"tin_ore", &"iron_scrap", &"silver_ore",
	&"black_metal_scrap", &"flametal_ore",
	# Processed metals
	&"copper", &"tin", &"bronze", &"iron", &"silver",
	&"black_metal", &"flametal",
	# Special items
	&"dragon_egg",
]

## Active portal registry: tag -> Array of portal Node3D references (max 2 per tag).
var _portals: Dictionary = {}


func register_portal(tag: String, portal: Node3D) -> void:
	if not _portals.has(tag):
		_portals[tag] = []
	if _portals[tag].size() >= 2:
		push_warning("Portal tag '%s' already has 2 portals. New one is unlinked." % tag)
		return
	_portals[tag].append(portal)
	portal_registered.emit(tag, portal)


func unregister_portal(tag: String, portal: Node3D) -> void:
	if _portals.has(tag):
		_portals[tag].erase(portal)
		if _portals[tag].is_empty():
			_portals.erase(tag)
	portal_unregistered.emit(tag)


func get_linked_portal(tag: String, from_portal: Node3D) -> Node3D:
	if not _portals.has(tag):
		return null
	for portal in _portals[tag]:
		if portal != from_portal:
			return portal
	return null


func can_teleport(player_inventory: Array[Dictionary]) -> bool:
	## Check if the player is carrying any teleport-restricted items.
	for slot in player_inventory:
		if slot.is_empty():
			continue
		var item_id: StringName = slot.get("item_id", &"")
		if item_id in TELEPORT_RESTRICTED_ITEMS:
			return false
		# Also check the item's data resource for the teleport_restricted flag
		var item_data := ItemDatabase.get_item(item_id)
		if item_data.get("teleport_restricted", false):
			return false
	return true


func attempt_teleport(tag: String, from_portal: Node3D, player: CharacterBody3D, inventory: Array[Dictionary]) -> void:
	var target := get_linked_portal(tag, from_portal)
	if not target:
		teleport_blocked.emit("Portal has no linked destination.")
		return

	if not can_teleport(inventory):
		teleport_blocked.emit("You cannot teleport with metals or ores.")
		return

	teleport_started.emit(from_portal, target)

	# Channel for CHANNEL_TIME seconds, then move the player
	await get_tree().create_timer(CHANNEL_TIME).timeout

	player.global_position = target.global_position + Vector3(0, 1, 2)
	teleport_completed.emit()
