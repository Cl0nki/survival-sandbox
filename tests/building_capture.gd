extends SceneTree

## Renders the building test scene from fixed cameras and saves PNGs, for
## visual checks that a headless run cannot do (winding, Z-fighting, preview).
## Needs a renderer, so run it without --headless:
## godot --path <project> --resolution 1600x900 --script res://tests/building_capture.gd

const SHOTS := [
	["overview", Vector3(-1.0, 24.0, 6.0), Vector3(-1.0, 0.0, -10.0)],
	["shared_walls_corners", Vector3(-8.5, 4.5, -9.0), Vector3(-8.5, 0.8, -13.5)],
	["rectangle_doors_windows", Vector3(3.5, 5.0, -8.5), Vector3(3.5, 1.0, -13.5)],
	["levels_and_stairs", Vector3(-6.0, 11.0, -1.0), Vector3(-7.0, 2.5, -8.0)],
	["house_rotated", Vector3(9.0, 9.0, -2.0), Vector3(4.5, 1.0, -8.0)],
	["grazing_floor", Vector3(-15.5, 0.35, -12.6), Vector3(-12.0, 0.0, -14.0)],
	["grazing_upper_floor", Vector3(-12.5, 3.35, -5.5), Vector3(-13.0, 3.0, -8.0)],
]

var _out := ""


func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	_out = ProjectSettings.globalize_path("user://building_shots")
	DirAccess.make_dir_recursive_absolute(_out)
	var scene := (load("res://scenes/world/building_test.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _i in 10:
		await process_frame
	var failures: PackedStringArray = scene.get("failures")
	print("scenario failures: ", failures.size())
	for failure in failures:
		print("  ", failure)
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var camera := Camera3D.new()
	camera.fov = 55.0
	scene.add_child(camera)
	camera.current = true
	for shot: Array in SHOTS:
		await _capture(camera, str(shot[0]), shot[1], shot[2])
	var system: BuildingSystem = scene.get("system")
	var tool := BuildTool.new()
	scene.add_child(tool)
	tool.setup(system)
	tool.set_equipped(true)
	tool.select_by_id("room")
	tool.update_aim(Vector3(-8.5, 0.0, -10.5))
	tool.begin_drag()
	tool.update_aim(Vector3(-7.5, 0.0, -9.5))
	print("preview_valid: ", tool.preview.status_text().replace("\n", " | "))
	await _capture(camera, "preview_valid_reuse", Vector3(-8.0, 6.5, -6.0), Vector3(-9.0, 0.5, -12.0))
	tool.cancel_drag()
	tool.update_aim(Vector3(-10.5, 0.0, -14.5))
	tool.begin_drag()
	tool.update_aim(Vector3(-9.5, 0.0, -13.5))
	print("preview_invalid: ", tool.preview.status_text().replace("\n", " | "))
	await _capture(camera, "preview_invalid", Vector3(-9.5, 6.5, -8.5), Vector3(-10.0, 0.5, -13.5))
	tool.cancel_drag()
	tool.select_by_id("doorway")
	tool.update_aim(Vector3(-1.5, 0.0, -14.02))
	print("preview_replace: ", tool.preview.status_text().replace("\n", " | "))
	await _capture(camera, "preview_replace", Vector3(-1.5, 4.0, -18.5), Vector3(-1.5, 1.0, -14.0))
	system.debug_view.set_enabled(true)
	await _capture(camera, "debug_view", Vector3(-10.5, 6.0, -10.5), Vector3(-8.5, 0.5, -13.5))
	system.debug_view.set_enabled(false)
	tool.set_equipped(false)
	await _capture_player_tool(scene)
	await _measure_frames()
	print("BUILDING_CAPTURE_DONE ", _out)
	quit(0)


## The real flow: hotbar Build Tool, blueprint menu, player camera, mouse aim.
func _capture_player_tool(scene: Node) -> void:
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = true
	var player := scene.find_children("Player", "PlayerController", true, false)[0] as PlayerController
	player.current_camera().make_current()
	for i in player.inventory.capacity:
		if str(player.inventory.slots[i]["id"]) == "build_tool":
			player.select_hotbar(i)
	var tool := player.get_node("BuildTool") as BuildTool
	for _i in 4:
		await process_frame
	tool.select_by_id("room")
	var camera := player.current_camera()
	Input.warp_mouse(camera.unproject_position(player.global_position + Vector3(2.5, 0.0, -1.5)))
	for _i in 4:
		await process_frame
	tool.begin_drag()
	Input.warp_mouse(camera.unproject_position(player.global_position + Vector3(5.5, 0.0, 0.5)))
	for _i in 10:
		await process_frame
	print("player_tool: equipped=%s menu=%s status=%s" % [tool.equipped, tool.menu.visible, tool.preview.status_text().replace("\n", " | ")])
	await _save("player_build_tool")


## Steady-state frame cost with the showcase built and the tool equipped.
func _measure_frames() -> void:
	for _i in 30:
		await process_frame
	var worst := 0.0
	var total := 0.0
	var frames := 180
	var last := Time.get_ticks_usec()
	for _i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		total += ms
		worst = maxf(worst, ms)
	print("frames: avg %.2f ms  worst %.2f ms  fps %d  process %.2f ms  draw_calls %d" % [
		total / frames, worst, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
	])


func _capture(camera: Camera3D, label: String, from: Vector3, at: Vector3) -> void:
	camera.global_position = from
	camera.look_at(at, Vector3.UP)
	await _save(label)


func _save(label: String) -> void:
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [_out, label]
	image.save_png(path)
	print("saved ", path)
