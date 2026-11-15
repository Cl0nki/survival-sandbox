extends SceneTree

## Renders the scavenge pad and every salvage prop to PNGs for visual review.
## Needs a renderer, so do NOT use --headless:
##
## godot --path <project> --resolution 1280x720 --script res://tests/salvage_capture.gd
##
## Shots land in user://salvage_shots/

const PAD := ShowcasePad.SCAVENGE


func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	await _run()
	quit(0)


func _run() -> void:
	var out := ProjectSettings.globalize_path("user://salvage_shots")
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 35, 0)
	light.shadow_enabled = true
	world.add_child(light)
	var sky := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.65, 0.75)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.72, 0.75)
	environment.ambient_light_energy = 0.6
	sky.environment = environment
	world.add_child(sky)
	var arena := Node3D.new()
	arena.name = "Arena"
	world.add_child(arena)
	LootLayout.build(arena)
	ScavengeField.build(arena)

	var camera := Camera3D.new()
	camera.fov = 50.0
	world.add_child(camera)
	camera.current = true
	for _i in 8:
		await process_frame

	await _shot(camera, out, "pad_overview", PAD + Vector3(3.0, 11.0, 7.5), PAD + Vector3(-0.5, 0.0, -1.0))
	for deposit_id in ResourceCatalog.scavenge_ids():
		var node := arena.get_node("Scavenge/%s" % deposit_id) as Node3D
		var at := node.global_position
		await _shot(camera, out, "node_%s" % deposit_id, at + Vector3(2.6, 2.1, 3.0), at + Vector3(0.0, 0.5, 0.0))
	print("SALVAGE_CAPTURE_DONE ", out)


func _shot(camera: Camera3D, out: String, shot_name: String, from: Vector3, target: Vector3) -> void:
	camera.global_position = from
	camera.look_at(target)
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("%s/%s.png" % [out, shot_name])
	print("SHOT ", shot_name)
