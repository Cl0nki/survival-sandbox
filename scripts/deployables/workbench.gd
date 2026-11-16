extends StaticBody3D
class_name Workbench

const _READOUT := preload("res://scripts/deployables/deployable_readout.gd")

## Solid bench. It has no crafting use yet. body_size is the full box, set
## before the node enters the tree. X is the long axis.

var display_name := "Workbench"
var body_size := Vector3(1.81, 2.0, 0.81)
var art_id := "workbench"

var _label: Label3D
var _hp := 0
var _show_name := false
var _show_hp := false


func _ready() -> void:
	add_to_group(&"deployable")
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0
	_build_visual()


func _build_visual() -> void:
	var length := body_size.x
	var height := body_size.y
	var depth := body_size.z
	if not DeployableArt.attach(self, art_id, body_size):
		var cabinet := MeshInstance3D.new()
		var body := BoxMesh.new()
		body.size = Vector3(length * 0.9, height - 0.08, depth * 0.8)
		cabinet.mesh = body
		cabinet.position = Vector3(0.0, body.size.y * 0.5, 0.0)
		var cabinet_mat := StandardMaterial3D.new()
		cabinet_mat.albedo_color = Color(0.38, 0.26, 0.16)
		cabinet_mat.roughness = 0.9
		cabinet.set_surface_override_material(0, cabinet_mat)
		add_child(cabinet)
		var top := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(length, 0.08, depth)
		top.mesh = slab
		top.position = Vector3(0.0, height - 0.04, 0.0)
		var top_mat := StandardMaterial3D.new()
		top_mat.albedo_color = Color(0.52, 0.36, 0.2)
		top_mat.roughness = 0.82
		top.set_surface_override_material(0, top_mat)
		add_child(top)
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = body_size
	shape.shape = hull
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(shape)
	var label := Label3D.new()
	label.name = "NameLabel"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, height + 0.28, 0.0)
	label.pixel_size = 0.005
	label.font_size = 32
	label.outline_size = 6
	label.visible = false
	add_child(label)
	_label = label


## `show_name` is hover, standing close, or F1. `show_hp` is F1 only.
func set_label_focus(show_name: bool, _in_reach: bool = false, show_hp: bool = false) -> void:
	if show_name == _show_name and show_hp == _show_hp:
		return
	_show_name = show_name
	_show_hp = show_hp
	_apply_label()


func set_deployable_health(current: int, _maximum: int) -> void:
	_hp = current
	_apply_label()


func _apply_label() -> void:
	if _label == null:
		return
	_label.visible = _show_name
	if not _label.visible:
		return
	_label.text = _READOUT.text(display_name, _hp, _show_hp, false)


func receive_damage(amount: int, _point: Vector3) -> bool:
	return DeployableSystem.forward_damage(self, amount)
