extends Node3D

## Scene glue for the arena. Geometry lives in the scene file.
## Local play keeps the baked player. Server and client modes spawn networked bodies.

const _ShootingRange := preload("res://scripts/world/shooting_range.gd")
const _ResourceField := preload("res://scripts/world/resource_field.gd")
const _WoodsField := preload("res://scripts/world/woods_field.gd")
const _GroundDepositField := preload("res://scripts/world/ground_deposit_field.gd")
const _ScavengeField := preload("res://scripts/world/scavenge_field.gd")
const _CraftingField := preload("res://scripts/world/crafting_field.gd")
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
	_ShowcasePad.add(self, _ShowcasePad.BUILDING, Color(0.34, 0.40, 0.34))
	_ShowcasePad.add(self, _ShowcasePad.DEPLOYABLES, Color(0.30, 0.36, 0.30))
	_ShowcasePad.label(self, "BUILDING", _ShowcasePad.BUILDING + Vector3(0.0, 2.6, -3.6), 52, Color(0.78, 0.82, 0.74))
	_ShowcasePad.label(self, "DEPLOYABLES", _ShowcasePad.DEPLOYABLES + Vector3(0.0, 2.4, -3.6), 36, Color(0.70, 0.76, 0.68))
	_sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	_sun.shadow_enabled = true
	_sun.light_energy = 1.15
	_sun.directional_shadow_max_distance = 70.0
	var mode := _resolved_mode()
	_add_building()
	_add_deployables()
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


## Chests and workbenches. The sample pair sits on the deployables tile.
func _add_deployables() -> void:
	if get_node_or_null("DeployableSystem") != null:
		return
	add_child(DeployableSystem.new())


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
