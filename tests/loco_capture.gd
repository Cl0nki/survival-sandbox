extends SceneTree

## Renders stand loco blend directions to PNGs for visual review.
## Needs a renderer — do NOT use --headless:
##
## godot --path <project> --resolution 1280x720 --script res://tests/loco_capture.gd
##
## Shots land in user://loco_shots/

const LIBRARY_PATH := "res://assets/characters/Shared/Quaternius/ual_locomotion.res"
const PRO_PATH := "res://assets/characters/Shared/Quaternius/AnimationLibrary_Godot_Pro.glb"
const PLAYER_PATH := "res://scenes/player/player.tscn"

const SHOTS := [
	["idle", Vector2(0, 0)],
	["walk_fwd", Vector2(0, 1)],
	["walk_bwd", Vector2(0, -1)],
	["walk_l", Vector2(-1, 0)],
	["walk_r", Vector2(1, 0)],
	["walk_fwd_l", Vector2(-0.707, 0.707)],
	["walk_fwd_r", Vector2(0.707, 0.707)],
	["walk_bwd_l", Vector2(-0.707, -0.707)],
	["walk_bwd_r", Vector2(0.707, -0.707)],
	["crouch_idle", Vector2(0, 0), 1.0],
	["crouch_fwd", Vector2(0, 1), 1.0],
]


func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	await _run()
	quit(0)


func _run() -> void:
	var out := ProjectSettings.globalize_path("user://loco_shots")
	DirAccess.make_dir_recursive_absolute(out)

	var world := Node3D.new()
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 35, 0)
	world.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)

	var player_packed: PackedScene = load(PLAYER_PATH) as PackedScene
	var player: Node = player_packed.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var cam_rig := player.get_node_or_null("CameraRig")
	if cam_rig:
		cam_rig.visible = false

	var tree := player.get_node_or_null("AnimationTree") as AnimationTree
	var model := player.get_node_or_null("VisualRoot/LeanPivot/CharacterModel")
	if tree == null or model == null:
		push_error("player AnimationTree/CharacterModel missing")
		return

	## Ensure shared library is loaded the same way as gameplay.
	var lib: AnimationLibrary = load(LIBRARY_PATH) as AnimationLibrary
	var ap := _find_animation_player(model)
	if ap and lib:
		for lib_name in ap.get_animation_library_list():
			ap.remove_animation_library(lib_name)
		ap.add_animation_library(&"", lib)
	tree.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.anim_player = tree.get_path_to(ap)
	tree.active = true
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	var camera := Camera3D.new()
	camera.fov = 40.0
	world.add_child(camera)
	camera.current = true
	camera.global_position = Vector3(2.2, 1.6, 3.2)
	camera.look_at(Vector3(0, 0.9, 0))

	for _i in 20:
		await process_frame

	for shot in SHOTS:
		var name: String = shot[0]
		var blend: Vector2 = shot[1]
		var crouch := float(shot[2]) if shot.size() > 2 else 0.0
		tree.set("parameters/stand_loco/blend_position", blend)
		tree.set("parameters/crouch_loco/blend_position", blend)
		tree.set("parameters/stance/blend_amount", crouch)
		tree.set("parameters/upper/blend_amount", 0.0)
		## Advance the tree so the pose settles.
		for _j in 30:
			tree.advance(1.0 / 30.0)
			await process_frame
		await _capture(name, out)
		print("SHOT ", name, " blend=", blend, " crouch=", crouch)

	print("LOCO_CAPTURE_DONE ", out)


func _capture(name: String, out_dir: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img == null:
		push_warning("no viewport image for %s" % name)
		return
	img.save_png("%s/%s.png" % [out_dir, name])


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
