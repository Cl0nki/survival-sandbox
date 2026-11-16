extends Node3D
class_name CreatureView

## Client-side stand-in for a server creature. It holds no game rules: the
## server sends poses and a state number, and this node smooths the poses and
## plays a matching animation. The art is primitives for now; swap
## _build_hog() for a model later and keep the rest.

const LABEL_HEIGHT := 1.35

var creature_id := 0
var kind := 0
var hp := 0
var max_hp := 0
var state := Creature.S_IDLE

var _buffer := MotionBuffer.new()
var _rig: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _skin: StandardMaterial3D
var _label: Label3D
var _phase := 0.0
var _head_pitch := 0.0
var _roll := 0.0
var _lean := 0.0
var _tint := 0.0
var _sink := 0.0
var _dig := 0.0

const SKIN := Color(0.42, 0.3, 0.22, 1)
const SKIN_ANGRY := Color(0.62, 0.16, 0.1, 1)
const SKIN_STUNNED := Color(0.55, 0.5, 0.2, 1)
const SKIN_DEAD := Color(0.18, 0.15, 0.14, 1)


func setup(id: int, kind_id: int, hit_points: int, max_hit_points: int, start_state: int, pos: Vector3, yaw: float) -> void:
	creature_id = id
	kind = kind_id
	hp = hit_points
	max_hp = max_hit_points
	state = start_state
	name = "Creature_%d" % id
	_build_hog()
	position = pos
	rotation.y = yaw
	# Back-dated so the first snapshots (stamped a little before now) still queue.
	_buffer.push(_now() - 1.0, pos, yaw, 0.0)
	_refresh_label()
	if state == Creature.S_DEAD:
		_sink = 1.0


func push_pose(stamp: float, pos: Vector3, yaw: float, next_state: int) -> void:
	if not NetConfig.finite_vector(pos) or not is_finite(yaw):
		return
	_buffer.push(stamp, pos, yaw, 0.0)
	set_state(next_state)


func set_state(next: int) -> void:
	state = next
	_refresh_label()


func set_health(current: int) -> void:
	hp = clampi(current, 0, max_hp)
	if hp == 0:
		state = Creature.S_DEAD
	_refresh_label()


func is_dead() -> bool:
	return state == Creature.S_DEAD


func _process(delta: float) -> void:
	var pose := _buffer.sample(_now() - NetConfig.INTERP_DELAY_SEC)
	if not pose.is_empty():
		position = pose["position"]
		rotation.y = float(pose["yaw"])
	_animate(delta)


func _animate(delta: float) -> void:
	var swing := 0.0
	var rate := 0.0
	var pitch := 0.0
	var roll := 0.0
	var lean := 0.0
	var tint := 0.0
	var sink := 0.0
	var dig := 0.0
	var color := SKIN
	match state:
		Creature.S_IDLE:
			rate = 1.6
		Hog.S_WALK:
			swing = 0.5
			rate = 6.0
		Hog.S_WINDUP:
			pitch = 0.45
			dig = 1.0
			tint = 1.0
			color = SKIN_ANGRY
		Hog.S_CHARGE:
			swing = 0.95
			rate = 17.0
			pitch = 0.35
			lean = 0.12
			tint = 1.0
			color = SKIN_ANGRY
		Hog.S_RECOVER:
			rate = 9.0
			pitch = 0.1
		Hog.S_STUNNED:
			roll = 0.28
			pitch = 0.3
			rate = 3.0
			tint = 0.7
			color = SKIN_STUNNED
		Creature.S_DEAD:
			sink = 1.0
			color = SKIN_DEAD
			tint = 0.0
	var follow := clampf(delta * 10.0, 0.0, 1.0)
	_head_pitch = lerpf(_head_pitch, pitch, follow)
	_roll = lerpf(_roll, roll, follow)
	_lean = lerpf(_lean, lean, follow)
	_tint = lerpf(_tint, tint, follow)
	_sink = lerpf(_sink, sink, clampf(delta * 6.0, 0.0, 1.0))
	_dig = lerpf(_dig, dig, follow)
	_phase += delta * rate
	if _head != null:
		_head.rotation.x = _head_pitch + sin(_phase * 0.5) * 0.04
	for index in _legs.size():
		var leg := _legs[index]
		var side := 1.0 if (index == 0 or index == 3) else -1.0
		var angle := sin(_phase) * swing * side
		if _dig > 0.01 and index < 2:
			angle = -absf(sin(_phase * 2.0)) * 0.8 * _dig
		leg.rotation.x = angle
	if _rig != null:
		_rig.rotation.z = _roll + _sink * (PI * 0.5)
		_rig.rotation.x = -_lean
		_rig.position.y = 0.3 * _sink + sin(_phase) * 0.012
		_rig.scale = Vector3.ONE * (1.0 + sin(_phase) * 0.012 * (1.0 - _sink))
	if _skin != null:
		_skin.albedo_color = _skin.albedo_color.lerp(color, clampf(delta * 8.0, 0.0, 1.0))
		_skin.emission_enabled = _tint > 0.02
		_skin.emission = Color(0.7, 0.08, 0.04, 1) * _tint * 0.35


func _refresh_label() -> void:
	if _label == null:
		return
	var show := hp > 0 and hp < max_hp and state != Creature.S_DEAD
	_label.visible = show
	if show:
		_label.text = "Hog %d/%d" % [hp, max_hp]


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _build_hog() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = SKIN
	_skin.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.14, 0.11, 1)
	dark.roughness = 0.95
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.9, 0.86, 0.74, 1)
	bone.roughness = 0.6
	_box(_rig, Vector3(0, 0.52, 0), Vector3(0.7, 0.55, 1.1), _skin, "Body")
	_box(_rig, Vector3(0, 0.84, 0.05), Vector3(0.24, 0.12, 0.8), dark, "Bristles")
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 0.56, -0.58)
	_rig.add_child(_head)
	_box(_head, Vector3(0, 0, -0.14), Vector3(0.46, 0.4, 0.42), _skin, "Skull")
	_box(_head, Vector3(0, -0.07, -0.43), Vector3(0.3, 0.2, 0.24), dark, "Snout")
	_box(_head, Vector3(0.19, -0.1, -0.4), Vector3(0.05, 0.05, 0.2), bone, "TuskR")
	_box(_head, Vector3(-0.19, -0.1, -0.4), Vector3(0.05, 0.05, 0.2), bone, "TuskL")
	_box(_head, Vector3(0.15, 0.24, -0.05), Vector3(0.12, 0.12, 0.05), dark, "EarR")
	_box(_head, Vector3(-0.15, 0.24, -0.05), Vector3(0.12, 0.12, 0.05), dark, "EarL")
	var spots: Array[Vector3] = [
		Vector3(0.22, 0.28, -0.38),
		Vector3(-0.22, 0.28, -0.38),
		Vector3(0.22, 0.28, 0.38),
		Vector3(-0.22, 0.28, 0.38),
	]
	for index in spots.size():
		var hip := Node3D.new()
		hip.name = "Leg%d" % index
		hip.position = spots[index]
		_rig.add_child(hip)
		_box(hip, Vector3(0, -0.14, 0), Vector3(0.13, 0.3, 0.13), dark, "Shank")
		_legs.append(hip)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.005
	_label.font_size = 36
	_label.outline_size = 8
	_label.position = Vector3(0, LABEL_HEIGHT, 0)
	_label.visible = false
	add_child(_label)


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material, label: String) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
