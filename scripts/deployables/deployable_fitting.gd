extends StaticBody3D

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


func _ready() -> void:
	if is_door:
		_build_hinge()
		add_to_group(&"deployable_door")
	_label = Label3D.new()
	_label.name = "Health"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0.0, label_y, 0.0)
	_label.pixel_size = 0.005
	_label.font_size = 28
	_label.outline_size = 6
	_label.text = display_name
	add_child(_label)


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
	if is_door:
		var state := "Open  [F]" if open else "[F]"
		_label.text = "%s\n%d HP\n%s" % [display_name, _health, state]
	else:
		_label.text = "%s\n%d HP" % [display_name, _health]


func receive_damage(amount: int, _point: Vector3) -> bool:
	return DeployableSystem.forward_damage(self, amount)
