extends Node3D

## Scene glue for the arena. Geometry lives in the scene file.
## Local play keeps the baked player. Server and client modes spawn networked bodies.

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
	if mode == NetConfig.MODE_SERVER:
		var overlay := get_node_or_null("DebugOverlay")
		if overlay != null:
			overlay.set_meta(&"suppress_ready", true)


func _ready() -> void:
	LootLayout.build(self)
	_sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	_sun.shadow_enabled = true
	_sun.light_energy = 1.15
	_sun.directional_shadow_max_distance = 70.0
	var mode := _resolved_mode()
	if mode == NetConfig.MODE_LOCAL:
		_add_building()
		return
	_discard("Player")
	if mode == NetConfig.MODE_SERVER:
		_discard("DebugOverlay")
	var net := GameNet.new()
	net.name = "GameNet"
	add_child(net)


## Local play builds through BuildingSystem. Networked building is not wired yet.
func _add_building() -> void:
	if get_node_or_null("BuildingSystem") != null:
		return
	add_child(BuildingSystem.new())


func _discard(node_name: String) -> void:
	var node := get_node_or_null(node_name)
	if node == null:
		return
	node.set_physics_process(false)
	node.set_process(false)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	remove_child(node)
	node.free()
