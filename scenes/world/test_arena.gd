extends Node3D

## Scene glue for the arena. Geometry lives in the scene file.
## Local play keeps the baked player. Server and client modes spawn networked bodies.

const _ShootingRange := preload("res://scripts/world/shooting_range.gd")
const _ResourceField := preload("res://scripts/world/resource_field.gd")
const _WoodsField := preload("res://scripts/world/woods_field.gd")
const _GroundDepositField := preload("res://scripts/world/ground_deposit_field.gd")
const _ScavengeField := preload("res://scripts/world/scavenge_field.gd")
const _CraftingField := preload("res://scripts/world/crafting_field.gd")
const _TextureCompare := preload("res://scripts/world/texture_compare.gd")
const _ShowcasePad := preload("res://scripts/world/showcase_pad.gd")

var force_mode := -1

@onready var _sun: DirectionalLight3D = $Sun


func _resolved_mode() -> int:
	if force_mode >= 0:
		return force_mode
	var session := get_node_or_null("/root/NetSession")
	if session != null:
		return int(session.get("mode"))
	return NetConfig.MODE_LOCAL


func _enter_tree() -> void:
	var mode := _resolved_mode()
	if mode == NetConfig.MODE_LOCAL:
		return
	var baked := get_node_or_null("Player")
	if baked != null:
		baked.set_meta(&"suppress_ready", true)


func _ready() -> void:
	LootLayout.build(self)
	_ShootingRange.build(self)
	_ResourceField.build(self)
	_WoodsField.build(self)
	_GroundDepositField.build(self)
	_ScavengeField.build(self)
	_CraftingField.build(self)
	_ShowcasePad.add_rect(self, _ShowcasePad.BUILDING, _ShowcasePad.BUILDING_SIZE, Color(0.30, 0.42, 0.22), "ground_meadow")
	_ShowcasePad.add(self, _ShowcasePad.DEPLOYABLES, Color(0.42, 0.36, 0.24), "ground_dirt")
	_ShowcasePad.add(self, _ShowcasePad.SMELTING, Color(0.48, 0.46, 0.44), "ground_rock")
	_ShowcasePad.add(self, _ShowcasePad.FOOD, Color(0.42, 0.36, 0.24), "ground_dirt")
	_ShowcasePad.label(self, "BUILDING", _ShowcasePad.BUILDING + Vector3(0.0, 2.6, 8.6), 52, Color(0.78, 0.82, 0.74))
	_ShowcasePad.label(self, "DEPLOYABLES", _ShowcasePad.DEPLOYABLES + Vector3(0.0, 2.4, -3.6), 36, Color(0.70, 0.76, 0.68))
	_ShowcasePad.label(self, "SMELTING", _ShowcasePad.SMELTING + Vector3(0.0, 2.6, -4.2), 52, Color(0.90, 0.62, 0.40))
	_ShowcasePad.label(self, "FOOD", _ShowcasePad.FOOD + Vector3(0.0, 2.6, -4.2), 52, Color(0.92, 0.62, 0.36))
	_TextureCompare.build(self)
	_sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	_sun.shadow_enabled = true
	_sun.light_energy = 1.15
	_sun.directional_shadow_max_distance = 90.0
	# Split shadow maps change texel size with distance, so the walls shimmer while walking north or south.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	var mode := _resolved_mode()
	_add_building()
	_add_deployables()
	_seed_stations()
	if mode == NetConfig.MODE_LOCAL:
		return
	_discard("Player")
	var net := GameNet.new()
	net.name = "GameNet"
	add_child(net)


## Local play and the server both own a BuildingSystem. Clients keep a replica.
func _add_building() -> void:
	if get_node_or_null("BuildingSystem") != null:
		return
	add_child(BuildingSystem.new())


## Chests, workbenches, and the stations already standing on their tiles.
func _add_deployables() -> void:
	if get_node_or_null("DeployableSystem") != null:
		return
	add_child(DeployableSystem.new())


## Smelters, crafting stations, and cooking stations are already placed.
func _seed_stations() -> void:
	var deployables := get_node_or_null("DeployableSystem") as DeployableSystem
	if deployables == null:
		return
	var spots: Array = [
		["smelter_steel", Vector2i(2, -18)],
		["foundry", Vector2i(6, -18)],
		["smelter_iron", Vector2i(2, -13)],
		["furnace_scrap", Vector2i(6, -13)],
		["sawbench", Vector2i(-19, 2)],
		["kiln", Vector2i(-15, 2)],
		["sawmill", Vector2i(-19, 5)],
		["kiln_shed", Vector2i(-15, 5)],
		["workbench", Vector2i(2, 12)],
		["workbench_iron", Vector2i(4, 12)],
		["workbench_steel", Vector2i(6, 12)],
		["workbench_composite", Vector2i(8, 12)],
		["machine_shop", Vector2i(3, 15)],
		["chem_bench", Vector2i(11, 12)],
		["ammo_bench", Vector2i(16, 12)],
		["refinery", Vector2i(11, 14)],
		["armory", Vector2i(16, 14)],
		["campfire", Vector2i(11, 3)],
		["fire_pit", Vector2i(11, 5)],
		["cooking_pot", Vector2i(16, 3)],
		["stove", Vector2i(16, 5)],
		["kitchen", Vector2i(14, 7)],
	]
	for spot in spots:
		var placed: Dictionary = deployables.try_place(str(spot[0]), spot[1], 0, 0)
		if not bool(placed.get("ok", false)):
			push_error("demo %s refused: %s" % [str(spot[0]), str(placed.get("reason", ""))])


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"debug_toggle"):
		return
	var labels := get_tree().get_nodes_in_group(&"resource_info")
	var show := true
	if not labels.is_empty() and labels[0] is Node3D:
		show = not (labels[0] as Node3D).visible
	for node in labels:
		if node is Node3D:
			(node as Node3D).visible = show
	get_viewport().set_input_as_handled()


func _discard(node_name: String) -> void:
	var node := get_node_or_null(node_name)
	if node == null:
		return
	node.set_physics_process(false)
	node.set_process(false)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	remove_child(node)
	node.free()
