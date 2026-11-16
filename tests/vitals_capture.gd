extends SceneTree

## Renders the owner's HUD in three states (healthy, hurt, dead) for visual
## review. Needs a renderer, so do NOT use --headless:
##
## godot --path <project> --resolution 1280x720 --script res://tests/vitals_capture.gd
##
## Shots land in user://vitals_shots/

func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	await _run()
	quit(0)


func _run() -> void:
	var out := ProjectSettings.globalize_path("user://vitals_shots")
	DirAccess.make_dir_recursive_absolute(out)
	var arena := (load("res://scenes/world/test_arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	for _i in 30:
		await physics_frame
	var player := arena.get_node("Player") as PlayerController
	var hud := VitalsHud.new()
	player.add_child(hud)
	hud.bind_player(player)
	await _shot(out, "1_healthy")
	player.apply_authoritative_health(35)
	await _shot(out, "2_hurt", 0.05)
	player.apply_authoritative_health(0)
	player.respawn_eta = 3.4
	await _shot(out, "3_dead", 0.1)
	print("VITALS_CAPTURE_DONE ", out)


func _shot(out: String, name: String, delay := 0.4) -> void:
	await create_timer(delay).timeout
	for _i in 4:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(out.path_join(name + ".png"))
