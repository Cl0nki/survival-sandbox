extends StaticBody3D
class_name LootContainer

const _READOUT := preload("res://scripts/deployables/deployable_readout.gd")

## Storage crate. Contents live on the server copy. Clients clear theirs at boot
## and only receive a snapshot while the server says they have it open.
## The box matches the mesh, so the body stops on it and a standing shot
## passes over the lid.

@export var container_id := ""
@export var slot_count := 8
@export var prompt := "Crate"
@export var box_color := Color(0.42, 0.3, 0.18, 1)

var inventory: Inventory
var _label: Label3D
## Placed pieces hide the name until hover, proximity, or F1. Yard crates stay labeled.
var _placed := false
var _hp := 0
var _show_name := false
var _in_reach := false
var _show_hp := false
## When set before the node enters the tree, the box uses this size instead of
## the small yard crate. Y is the height. The mesh sits on the node origin.
var body_size := Vector3.ZERO
var display_name := ""
## Empty slot captions. Stations use Input, Fuel, and Out.
var slot_labels := PackedStringArray()
## Deployable kind used to look up res://assets/deployables/<id>.glb.
var art_id := ""
## World prop id (WorldPropCatalog) for storage crates that are not deployables.
## The box keeps the size it was built with. The mesh is fitted to the prop box.
var prop_art_id := ""
var _born_msec := 0


func _ready() -> void:
	_born_msec = Time.get_ticks_msec()
	add_to_group(&"loot_container")
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0
	if display_name.is_empty():
		display_name = prompt
	_placed = get_parent() is DeployableSystem
	if inventory == null:
		inventory = Inventory.new(slot_count)
	_build_visual()


## Presentation only. A station that starts or finishes a job is heard where it stands.
## event is craft_start or craft_done. The server and headless clients make no sound.
func hear_job(event: StringName) -> void:
	Sfx.play_at(event, global_position)


## Client side: the server sent a new queue. A queue that grew from empty is a job starting
## and one that shrank is a job done. Stations already running when this client
## arrived stay quiet, so joining a busy yard is not a burst of noise.
func hear_queue_change(before: int, after: int) -> void:
	if Time.get_ticks_msec() - _born_msec < 1500:
		return
	if after < before:
		hear_job(&"craft_done")
	elif before == 0 and after > 0:
		hear_job(&"craft_start")


func clear_contents() -> void:
	if inventory == null:
		inventory = Inventory.new(slot_count)
	else:
		inventory.resize(slot_count)


func _build_visual() -> void:
	var size := body_size if body_size.x > 0.0 else Vector3(1.15, 0.72, 0.8)
	var used_art := false
	if not art_id.is_empty():
		used_art = DeployableArt.attach(self, art_id, size)
	if not used_art and not prop_art_id.is_empty():
		used_art = WorldPropArt.attach(self, prop_art_id) != null
	if not used_art:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.position = Vector3(0.0, size.y * 0.5, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = box_color
		mesh.set_surface_override_material(0, material)
		add_child(mesh)
	var collision_size := size
	var collision_pos := Vector3(0.0, size.y * 0.5, 0.0)
	var label_y := size.y
	if art_id == "machine_shop":
		var fitted := _collision_inside_mesh()
		if not fitted.is_empty():
			collision_size = fitted["size"]
			collision_pos = fitted["position"]
			label_y = float(fitted["top"])
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = collision_size
	shape.shape = hull
	shape.position = collision_pos
	add_child(shape)
	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, label_y + 0.33, 0.0)
	_label.pixel_size = 0.005
	_label.font_size = 32
	_label.outline_size = 6
	_label.text = "%s  [F]" % prompt
	_label.visible = not _placed
	add_child(_label)


## The machine shop pad is wider than the lathe. The hitbox stays inside the mesh.
func _collision_inside_mesh() -> Dictionary:
	var art := get_node_or_null("WorldArt") as Node3D
	if art == null:
		return {}
	var bounds := DeployableArt._visual_aabb(art, Transform3D.IDENTITY)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		return {}
	var side := 0.04
	var shrunk := Vector3(
		maxf(bounds.size.x - side * 2.0, 0.2),
		maxf(bounds.size.y - side, 0.2),
		maxf(bounds.size.z - side * 2.0, 0.2)
	)
	var center := bounds.get_center()
	return {
		"size": shrunk,
		"position": Vector3(center.x, bounds.position.y + shrunk.y * 0.5, center.z),
		"top": bounds.position.y + bounds.size.y,
	}


## `show_name` is hover, standing close, or F1. `show_hp` is F1 only.
func set_label_focus(show_name: bool, in_reach: bool = false, show_hp: bool = false) -> void:
	if not _placed:
		return
	if show_name == _show_name and in_reach == _in_reach and show_hp == _show_hp:
		return
	_show_name = show_name
	_in_reach = in_reach
	_show_hp = show_hp
	_apply_label()


func set_deployable_health(current: int, _maximum: int) -> void:
	_placed = true
	_hp = current
	_apply_label()


func _label_extra() -> String:
	return ""


func _apply_label() -> void:
	if _label == null or not _placed:
		return
	_label.visible = _show_name
	if not _label.visible:
		return
	_label.text = _READOUT.text(prompt, _hp, _show_hp, _in_reach, _label_extra())


func receive_damage(amount: int, _point: Vector3) -> bool:
	return DeployableSystem.forward_damage(self, amount)
