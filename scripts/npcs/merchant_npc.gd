class_name MerchantNPC
extends Interactable

const SHOP_ITEMS: Array[Dictionary] = [
	{"item_id": &"fishing_rod", "price": 120},
	{"item_id": &"large_chest_recipe", "price": 200},
	{"item_id": &"merchant_bag", "price": 50},
	{"item_id": &"wood_arrow", "price": 5, "amount": 10},
	{"item_id": &"leather", "price": 8},
	{"item_id": &"copper_ore", "price": 12},
]

var _nameplate: Label3D
var _idle_timer: float = 0.0
var _idle_bob_phase: float = 0.0
var _body: MeshInstance3D
var _head: MeshInstance3D
var _hat: MeshInstance3D

func _ready() -> void:
	super._ready()
	display_name = &"Halvard"
	add_to_group(&"npcs")
	add_to_group(&"merchants")
	_build_visuals()
	_build_nameplate()


func get_interaction_verb() -> String:
	return "Trade"


func _do_interact(player: CharacterBody3D) -> void:
	if player.has_method("open_shop"):
		player.open_shop(self)


func _build_visuals() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.45, 0.28, 0.15)
	body_mat.roughness = 0.85

	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.82, 0.68, 0.55)
	skin_mat.roughness = 0.7

	var hat_mat := StandardMaterial3D.new()
	hat_mat.albedo_color = Color(0.3, 0.18, 0.08)
	hat_mat.roughness = 0.9

	_body = MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.35
	body_mesh.height = 1.2
	_body.mesh = body_mesh
	_body.material_override = body_mat
	_body.position = Vector3(0, 0.7, 0)
	add_child(_body)

	_head = MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	_head.mesh = head_mesh
	_head.material_override = skin_mat
	_head.position = Vector3(0, 1.5, 0)
	add_child(_head)

	_hat = MeshInstance3D.new()
	var hat_mesh := CylinderMesh.new()
	hat_mesh.top_radius = 0.15
	hat_mesh.bottom_radius = 0.3
	hat_mesh.height = 0.2
	_hat.mesh = hat_mesh
	_hat.material_override = hat_mat
	_hat.position = Vector3(0, 1.72, 0)
	add_child(_hat)

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.6
	col.shape = shape
	col.position = Vector3(0, 0.8, 0)
	add_child(col)


func _build_nameplate() -> void:
	_nameplate = Label3D.new()
	_nameplate.text = "Halvard\nTrader"
	_nameplate.font_size = 48
	_nameplate.pixel_size = 0.008
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.no_depth_test = true
	_nameplate.modulate = Color(1.0, 0.85, 0.4)
	_nameplate.outline_modulate = Color(0, 0, 0, 0.8)
	_nameplate.outline_size = 8
	_nameplate.position = Vector3(0, 2.1, 0)
	_nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nameplate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_nameplate)


func _process(delta: float) -> void:
	_idle_bob_phase += delta * 1.5
	var bob := sin(_idle_bob_phase) * 0.02
	if _body:
		_body.position.y = 0.7 + bob
	if _head:
		_head.position.y = 1.5 + bob
	if _hat:
		_hat.position.y = 1.72 + bob
	if _nameplate:
		_nameplate.position.y = 2.1 + bob


static func create_camp(pos: Vector3, height_func: Callable) -> Node3D:
	var camp := Node3D.new()
	camp.name = "MerchantCamp"
	camp.add_to_group(&"structures")

	var npc := MerchantNPC.new()
	npc.name = "Halvard"
	npc.position = Vector3(0, 0, 0)
	camp.add_child(npc)

	var tent := _build_tent()
	tent.position = Vector3(-2.5, 0, -1.5)
	camp.add_child(tent)

	var campfire := _build_campfire()
	campfire.position = Vector3(1.5, 0, 1.0)
	camp.add_child(campfire)

	var crate1 := _build_crate(Vector3(0.6, 0.4, 0.5))
	crate1.position = Vector3(-1.0, 0, 2.0)
	camp.add_child(crate1)

	var crate2 := _build_crate(Vector3(0.5, 0.35, 0.4))
	crate2.position = Vector3(-0.3, 0, 2.3)
	crate2.rotation.y = 0.4
	camp.add_child(crate2)

	var barrel := _build_barrel()
	barrel.position = Vector3(2.5, 0, -0.5)
	camp.add_child(barrel)

	camp.global_position = pos
	var ground_y: float = height_func.call(pos.x, pos.z)
	camp.global_position.y = ground_y

	for child in camp.get_children():
		if child is Node3D and child != npc:
			var c3d := child as Node3D
			var cx: float = pos.x + c3d.position.x
			var cz: float = pos.z + c3d.position.z
			var cy: float = height_func.call(cx, cz)
			c3d.position.y = cy - ground_y

	return camp


static func _build_tent() -> MeshInstance3D:
	var tent := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(3.0, 2.0, 3.0)
	tent.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.45, 0.25)
	mat.roughness = 0.95
	tent.material_override = mat
	tent.position.y = 1.0
	return tent


static func _build_campfire() -> Node3D:
	var root := Node3D.new()
	root.name = "Campfire"
	root.add_to_group(&"campfires")

	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.3, 0.2, 0.1)
	log_mat.roughness = 0.9

	for i in 3:
		var log := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.height = 0.8
		lm.top_radius = 0.06
		lm.bottom_radius = 0.08
		log.mesh = lm
		log.material_override = log_mat
		log.rotation.z = deg_to_rad(80.0)
		log.rotation.y = deg_to_rad(i * 120.0)
		log.position = Vector3(cos(deg_to_rad(i * 120.0)) * 0.15, 0.1, sin(deg_to_rad(i * 120.0)) * 0.15)
		root.add_child(log)

	var fire_light := OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.6, 0.2)
	fire_light.light_energy = 2.0
	fire_light.omni_range = 8.0
	fire_light.position = Vector3(0, 0.5, 0)
	root.add_child(fire_light)

	return root


static func _build_crate(sz: Vector3) -> MeshInstance3D:
	var crate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	crate.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.35, 0.18)
	mat.roughness = 0.9
	crate.material_override = mat
	crate.position.y = sz.y * 0.5
	return crate


static func _build_barrel() -> MeshInstance3D:
	var barrel := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.height = 0.9
	mesh.top_radius = 0.28
	mesh.bottom_radius = 0.32
	barrel.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.25, 0.12)
	mat.roughness = 0.85
	barrel.material_override = mat
	barrel.position.y = 0.45
	return barrel
