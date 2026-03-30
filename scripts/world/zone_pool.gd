class_name ZonePool
extends RefCounted
## Object pool that recycles zone roots, trees, rocks, and blueberry bushes.
##
## Instead of queue_free() on zone children, nodes are stripped from the tree,
## hidden, and stashed here. Next zone that needs the same kind of object grabs
## one from the pool and reconfigures it — zero new server-side RID allocations.
##
## Pool sizes are kept small (1-2 zones worth) to avoid "zombie" overhead
## from orphan nodes whose server-side RIDs are still alive.

# ─── Pool storage ──────────────────────────────────────────────────────────────

static var _zone_roots: Array[StaticBody3D] = []
static var _trees: Array[StaticBody3D] = []
static var _rocks: Array[StaticBody3D] = []
static var _blueberry_bushes: Array[StaticBody3D] = []

const MAX_TREES := 100
const MAX_ROCKS := 10
const MAX_BLUEBERRY := 30
const MAX_ZONE_ROOTS := 5

static var _stats_recycled := 0
static var _stats_reused := 0


# ─── Zone Root Pool ────────────────────────────────────────────────────────────

static func get_zone_root() -> StaticBody3D:
	if not _zone_roots.is_empty():
		var root := _zone_roots.pop_back() as StaticBody3D
		if is_instance_valid(root):
			# Safety: ensure node is orphaned before reuse
			if root.get_parent():
				root.get_parent().remove_child(root)
			# Safety: clean up any stale children (should only have TerrainMesh/TerrainCol)
			for child in root.get_children():
				var cname: String = child.name if is_instance_valid(child) else ""
				if cname != "TerrainMesh" and cname != "TerrainCol":
					root.remove_child(child)
					child.queue_free()
			root.visible = true
			root.collision_layer = 1
			root.collision_mask = 0
			root.process_mode = Node.PROCESS_MODE_INHERIT
			_stats_reused += 1
			return root
	return null


static func recycle_zone_root(root: StaticBody3D) -> void:
	if not is_instance_valid(root):
		return
	if root.get_parent():
		root.get_parent().remove_child(root)
	root.visible = false
	root.collision_layer = 0
	root.process_mode = Node.PROCESS_MODE_DISABLED
	if _zone_roots.size() < MAX_ZONE_ROOTS:
		_zone_roots.append(root)
		_stats_recycled += 1
	else:
		root.queue_free()


# ─── Tree Pool ─────────────────────────────────────────────────────────────────

static func get_tree_node() -> StaticBody3D:
	while not _trees.is_empty():
		var t := _trees.pop_back() as StaticBody3D
		if is_instance_valid(t):
			# Strip old branch MeshInstance3D children from trunk
			# (pre-merge trees had separate Branch_/SubBranch_ nodes)
			var trunk := t.get_node_or_null("MeshInstance3D")
			if trunk:
				for child in trunk.get_children():
					if child is MeshInstance3D:
						trunk.remove_child(child)
						child.queue_free()
			t.visible = true
			t.collision_layer = 4
			t.process_mode = Node.PROCESS_MODE_INHERIT
			_stats_reused += 1
			return t
	return null


static func recycle_tree(node: StaticBody3D) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent():
		node.get_parent().remove_child(node)
	node.visible = false
	node.collision_layer = 0
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if _trees.size() < MAX_TREES:
		_trees.append(node)
		_stats_recycled += 1
	else:
		node.queue_free()


# ─── Rock Pool ─────────────────────────────────────────────────────────────────

static func get_rock_node() -> StaticBody3D:
	while not _rocks.is_empty():
		var r := _rocks.pop_back() as StaticBody3D
		if is_instance_valid(r):
			r.visible = true
			r.collision_layer = 4
			r.process_mode = Node.PROCESS_MODE_INHERIT
			_stats_reused += 1
			return r
	return null


static func recycle_rock(node: StaticBody3D) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent():
		node.get_parent().remove_child(node)
	node.visible = false
	node.collision_layer = 0
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if _rocks.size() < MAX_ROCKS:
		_rocks.append(node)
		_stats_recycled += 1
	else:
		node.queue_free()


# ─── Blueberry Bush Pool ──────────────────────────────────────────────────────

static func get_blueberry_node() -> StaticBody3D:
	while not _blueberry_bushes.is_empty():
		var s := _blueberry_bushes.pop_back() as StaticBody3D
		if is_instance_valid(s):
			s.visible = true
			s.collision_layer = 4
			s.process_mode = Node.PROCESS_MODE_INHERIT
			_stats_reused += 1
			return s
	return null


static func recycle_blueberry(node: StaticBody3D) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent():
		node.get_parent().remove_child(node)
	node.visible = false
	node.collision_layer = 0
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if _blueberry_bushes.size() < MAX_BLUEBERRY:
		_blueberry_bushes.append(node)
		_stats_recycled += 1
	else:
		node.queue_free()


# ─── Zone Recycling (walks children, categorizes, and pools everything) ────────

static func recycle_zone(zone_root: StaticBody3D) -> void:
	if not is_instance_valid(zone_root):
		return

	var children := zone_root.get_children()
	for child in children:
		if not is_instance_valid(child):
			continue

		var cname: String = child.name

		if child is StaticBody3D and child.is_in_group(&"interactables"):
			var sb := child as StaticBody3D
			if cname.begins_with("BlueberryBush"):
				recycle_blueberry(sb)
			elif sb.has_meta("tree_name"):
				recycle_tree(sb)
			elif sb.has_meta("drop_id") and sb.get_meta("drop_id") == &"stone":
				recycle_rock(sb)
			elif sb.get_meta("harvest_type", &"") == &"bush":
				zone_root.remove_child(child)
				child.queue_free()
			else:
				zone_root.remove_child(child)
				child.queue_free()
		elif child is CharacterBody3D:
			zone_root.remove_child(child)
			child.queue_free()
		elif cname == "TerrainMesh" or cname == "TerrainCol":
			pass
		elif child is StaticBody3D and child.is_in_group(&"horses"):
			zone_root.remove_child(child)
			child.queue_free()
		else:
			zone_root.remove_child(child)
			child.queue_free()

	recycle_zone_root(zone_root)


# ─── Flush (free everything in all pools) ──────────────────────────────────────

static func flush_all() -> void:
	for n in _zone_roots:
		if is_instance_valid(n):
			n.queue_free()
	_zone_roots.clear()
	for n in _trees:
		if is_instance_valid(n):
			n.queue_free()
	_trees.clear()
	for n in _rocks:
		if is_instance_valid(n):
			n.queue_free()
	_rocks.clear()
	for n in _blueberry_bushes:
		if is_instance_valid(n):
			n.queue_free()
	_blueberry_bushes.clear()
	_stats_recycled = 0
	_stats_reused = 0


# ─── Diagnostics ───────────────────────────────────────────────────────────────

static func get_pool_stats() -> String:
	return "pool[z=%d t=%d r=%d bb=%d re=%d ru=%d]" % [
		_zone_roots.size(), _trees.size(), _rocks.size(),
		_blueberry_bushes.size(),
		_stats_recycled, _stats_reused]
