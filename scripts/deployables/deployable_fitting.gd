extends StaticBody3D

const _READOUT := preload("res://scripts/deployables/deployable_readout.gd")

## Door or window bars. The deployable system owns the health.
## A door swings on its hinge when the player uses it.

var display_name := "Fitting"
var label_y := 2.4
var is_door := false
var swing_span := 0.85
var open := false
var swing_yaw := 0.0

var _label: Label3D
var _pivot: Node3D
var _health := 0
var _show_name := false
var _in_reach := false
var _show_hp := false


func _ready() -> void:
	if is_door:
		_build_hinge()
		add_to_group(&"deployable_door")
	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0.0, label_y, 0.0)
	_label.pixel_size = 0.005
	_label.font_size = 28
	_label.outline_size = 6
	_label.visible = false
	add_child(_label)


## `show_name` is hover, standing close, or F1. `show_hp` is F1 only.
func set_label_focus(show_name: bool, in_reach: bool = false, show_hp: bool = false) -> void:
	if show_name == _show_name and in_reach == _in_reach and show_hp == _show_hp:
		return
	_show_name = show_name
	_in_reach = in_reach
	_show_hp = show_hp
	_refresh_label()


func set_deployable_health(current: int, _maximum: int) -> void:
	_health = current
	_refresh_label()


## Free edge of the leaf in this body's local space. Tests use it to see the swing.
func leaf_tip() -> Vector3:
	if _pivot == null:
		return Vector3.ZERO
	return _pivot.position + _pivot.basis * Vector3(swing_span, 0.0, 0.0)


func toggle_from(from_world: Vector3) -> bool:
	if not is_door or _pivot == null:
		return false
	open = not open
	if open:
		var local_from := global_transform.affine_inverse() * from_world
		swing_yaw = (-1.0 if local_from.z >= 0.0 else 1.0) * PI * 0.5
	else:
		swing_yaw = 0.0
	_apply_yaw()
	_refresh_label()
	return true


func apply_swing(is_open: bool, yaw: float) -> void:
	if not is_door or _pivot == null:
		return
	open = is_open
	swing_yaw = yaw if is_open else 0.0
	_apply_yaw()
	_refresh_label()


func _apply_yaw() -> void:
	if _pivot == null:
		return
	_pivot.rotation = Vector3(0.0, swing_yaw, 0.0)


func _build_hinge() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Hinge"
	_pivot.position = Vector3(-swing_span * 0.5, 0.0, 0.0)
	var moving: Array[Node3D] = []
	for child in get_children():
		if child is MeshInstance3D or child is CollisionShape3D:
			moving.append(child)
	add_child(_pivot)
	for node in moving:
		var kept := node.position
		remove_child(node)
		_pivot.add_child(node)
		node.position = kept - _pivot.position


func _refresh_label() -> void:
	if _label == null:
		return
	_label.visible = _show_name
	if not _label.visible:
		return
	var extra := "Open" if is_door and open else ""
	_label.text = _READOUT.text(display_name, _health, _show_hp, _in_reach and is_door, extra)


func receive_damage(amount: int, _point: Vector3) -> bool:
	return DeployableSystem.forward_damage(self, amount)
