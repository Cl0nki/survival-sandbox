extends SceneTree

## Renders upper-body states (unarmed idle, pistol held, shoot, mining, chopping)
## to PNGs for visual review. Needs a renderer, so do NOT use --headless:
##
## godot --path <project> --resolution 1280x720 --script res://tests/upper_capture.gd
##
## Shots land in user://upper_shots/

const LIBRARY_PATH := "res://assets/characters/Shared/Quaternius/ual_locomotion.res"
const PLAYER_PATH := "res://scenes/player/player.tscn"

## [name, walk blend, upper amount, aim pitch blend, oneshot ("" | "shoot" | "Mining" | "TreeChopping"), oneshot seconds]
const SHOTS := [
	["unarmed_idle", Vector2(0, 0), 0.0, 0.0, "", 0.0],
	["unarmed_walk", Vector2(0, 1), 0.0, 0.0, "", 0.0],
	["carry_idle", Vector2(0, 0), 0.0, 0.0, "", 0.0],
	["carry_walk", Vector2(0, 1), 0.0, 0.0, "", 0.0],
	["aimed_idle", Vector2(0, 0), 1.0, 0.0, "", 0.0],
	["aimed_walk", Vector2(0, 1), 1.0, 0.0, "", 0.0],
	["shoot_early", Vector2(0, 0), 1.0, 0.0, "shoot", 0.12],
	["shoot_late", Vector2(0, 0), 1.0, 0.0, "shoot", 0.35],
	["mining_a", Vector2(0, 0), 0.0, 0.0, "Mining", 0.25],
	["mining_b", Vector2(0, 0), 0.0, 0.0, "Mining", 0.55],
	["chop_a", Vector2(0, 0), 0.0, 0.0, "TreeChopping", 0.25],
	["chop_b", Vector2(0, 0), 0.0, 0.0, "TreeChopping", 0.6],
	["mining_walk", Vector2(0, 1), 0.0, 0.0, "Mining", 0.4],
]


func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	await _run()
	quit(0)


func _run() -> void:
	var out := ProjectSettings.globalize_path("user://upper_shots")
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

	var player: Node = (load(PLAYER_PATH) as PackedScene).instantiate()
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
	var lib: AnimationLibrary = load(LIBRARY_PATH) as AnimationLibrary
	var ap := _find_animation_player(model)
	for lib_name in ap.get_animation_library_list():
		ap.remove_animation_library(lib_name)
	ap.add_animation_library(&"", lib)
	tree.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.anim_player = tree.get_path_to(ap)
	tree.active = true
	# Same filters the controller applies at runtime.
	player.call("_configure_upper_body_filters")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	var camera := Camera3D.new()
	camera.fov = 40.0
	world.add_child(camera)
	camera.current = true
	camera.global_position = Vector3(2.2, 1.4, 3.2)
	camera.look_at(Vector3(0, 1.0, 0))
	for _i in 10:
		await process_frame

	var graph := tree.tree_root as AnimationNodeBlendTree
	for shot in SHOTS:
		var name: String = shot[0]
		var oneshot: String = shot[4]
		tree.set("parameters/stand_loco/blend_position", shot[1])
		tree.set("parameters/upper/blend_amount", shot[2])
		tree.set("parameters/aim/blend_position", shot[3])
		# Cancel any one-shot still running from the last shot.
		tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		tree.set("parameters/harvest/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		for _j in 20:
			tree.advance(1.0 / 30.0)
		if oneshot == "shoot":
			tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		elif oneshot != "":
			(graph.get_node(&"harvest_clip") as AnimationNodeAnimation).animation = StringName(oneshot)
			tree.set("parameters/harvest/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		var steps := int(float(shot[5]) * 30.0)
		for _j in maxi(steps, 4):
			tree.advance(1.0 / 30.0)
			await process_frame
		await _capture(name, out)
		print("SHOT ", name)
	print("UPPER_CAPTURE_DONE ", out)


func _capture(name: String, out_dir: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
