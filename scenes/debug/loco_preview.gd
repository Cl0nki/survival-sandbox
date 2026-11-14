extends Node3D

## Manual loco preview: cycle stand BlendSpace directions on the player mannequin.
## Run scenes/debug/loco_preview.tscn (F6).
## Keys: 1-9 directions, 0/5/Space idle, C crouch toggle.

const DIRS := {
	KEY_0: Vector2(0, 0),
	KEY_1: Vector2(-0.707, -0.707),
	KEY_2: Vector2(0, -1),
	KEY_3: Vector2(0.707, -0.707),
	KEY_4: Vector2(-1, 0),
	KEY_5: Vector2(0, 0),
	KEY_6: Vector2(1, 0),
	KEY_7: Vector2(-0.707, 0.707),
	KEY_8: Vector2(0, 1),
	KEY_9: Vector2(0.707, 0.707),
}

@onready var _player: Node = $Player
@onready var _label: Label = $UI/Label
@onready var _camera: Camera3D = $Camera3D

var _blend := Vector2.ZERO
var _crouch := 0.0
var _tree: AnimationTree


func _ready() -> void:
	## Freeze gameplay so velocity-driven loco does not overwrite the preview.
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_tree = _player.get_node_or_null("AnimationTree") as AnimationTree
	if _tree:
		_tree.process_mode = Node.PROCESS_MODE_ALWAYS
		_tree.active = true
		_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var cam_rig := _player.get_node_or_null("CameraRig")
	if cam_rig:
		cam_rig.visible = false
	if _camera:
		_camera.current = true
	_apply()
	_update_label()


func _process(delta: float) -> void:
	if _tree and _tree.active:
		_tree.advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event.keycode
		if DIRS.has(key):
			_blend = DIRS[key]
			_apply()
		elif key == KEY_C:
			_crouch = 0.0 if _crouch > 0.5 else 1.0
			_apply()
		elif key == KEY_SPACE:
			_blend = Vector2.ZERO
			_crouch = 0.0
			_apply()
		_update_label()


func _apply() -> void:
	if _tree == null:
		return
	_tree.set("parameters/stand_loco/blend_position", _blend)
	_tree.set("parameters/crouch_loco/blend_position", _blend)
	_tree.set("parameters/stance/blend_amount", _crouch)
	_tree.set("parameters/upper/blend_amount", 0.0)


func _update_label() -> void:
	_label.text = "blend=%s  crouch=%.0f\n1-9 dirs · 0/5/Space idle · C crouch" % [_blend, _crouch]
