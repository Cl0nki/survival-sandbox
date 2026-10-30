extends Node
class_name RepairTool

## Hotbar item. Left click on a damaged piece restores it to full health.
## The piece has to still be standing. A destroyed wall or room is already
## gone, so it is built again with the Build Tool instead of repaired.

var system: BuildingSystem
var player: PlayerController
var equipped := false


func setup(building_system: BuildingSystem, owner_player: PlayerController) -> void:
	name = "RepairTool"
	system = building_system
	player = owner_player


func _process(_delta: float) -> void:
	if player == null:
		return
	equipped = player.holds_repair_tool()


func _unhandled_input(event: InputEvent) -> void:
	if not equipped or not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	_repair_aimed()
	get_viewport().set_input_as_handled()


func _repair_aimed() -> void:
	var component_id := _ray_component()
	if component_id == 0:
		_notify("No piece to repair")
		return
	var component := system.state.get_component(component_id)
	if component == null:
		_notify("No piece to repair")
		return
	var result := system.authority.repair(component_id)
	var label := BuildTypes.kind_name(component.kind)
	if bool(result.get("ok", false)):
		_notify("Repaired %s" % label)
	else:
		_notify("%s: %s" % [label, str(result.get("reason", "unchanged"))])


func _ray_component() -> int:
	if player == null:
		return 0
	var camera := player.current_camera()
	var world := player.get_world_3d()
	if camera == null or world == null or world.direct_space_state == null:
		return 0
	var mouse := player.get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var hit := AimProjector.first_solid(
		world.direct_space_state,
		origin,
		origin + camera.project_ray_normal(mouse) * 80.0,
		PhysicsLayers.BUILDING,
		[],
		Callable(system.world, &"collider_is_hidden")
	)
	if hit.is_empty():
		return 0
	var collider: Object = hit.get("collider")
	if collider != null and collider.has_meta(&"component_id"):
		return int(collider.get_meta(&"component_id"))
	return 0


func _notify(text: String) -> void:
	if player != null:
		player.show_item_notice(text)
