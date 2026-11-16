extends SceneTree

## Renders the hog placeholder in each state for visual review. Needs a
## renderer, so do NOT use --headless:
##
## godot --path <project> --resolution 1280x720 --script res://tests/creature_capture.gd
##
## The shot lands in user://creature_shots/

const STATES := [
	Creature.S_IDLE,
	Hog.S_WALK,
	Hog.S_WINDUP,
	Hog.S_CHARGE,
	Hog.S_STUNNED,
	Creature.S_DEAD,
]


func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	await _run()
	quit(0)


func _run() -> void:
	var out := ProjectSettings.globalize_path("user://creature_shots")
	DirAccess.make_dir_recursive_absolute(out)
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 12.0)
	floor_mesh.mesh = plane
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.32, 0.4, 0.26, 1)
	floor_mesh.material_override = ground
	stage.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	stage.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85, 1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75, 1)
	stage.add_child(env)
	for index in STATES.size():
		var view := CreatureView.new()
		stage.add_child(view)
		var x := (float(index) - float(STATES.size() - 1) * 0.5) * 2.4
		view.setup(index + 1, Creature.KIND_HOG, 50, 80, int(STATES[index]), Vector3(x, 0.0, 0.0), deg_to_rad(-35.0))
	var camera := Camera3D.new()
	camera.fov = 45.0
	stage.add_child(camera)
	camera.position = Vector3(0.0, 3.2, 8.5)
	camera.look_at(Vector3(0.0, 0.4, 0.0))
	await create_timer(1.2).timeout
	for _i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out.path_join("hog_states.png"))
	print("CREATURE_CAPTURE_DONE ", out)
