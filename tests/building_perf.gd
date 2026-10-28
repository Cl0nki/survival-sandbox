extends SceneTree

## Frame-time comparison: the local arena alone, then with the Phase 1
## showcase built, then with the Build Tool equipped and its preview showing.
## Needs a renderer: godot --path <project> --script res://tests/building_perf.gd


func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	var arena := (load("res://scenes/world/test_arena.tscn") as PackedScene).instantiate()
	arena.set("force_mode", NetConfig.MODE_LOCAL)
	root.add_child(arena)
	await _measure("arena only")
	var system := arena.get_node("BuildingSystem") as BuildingSystem
	BuildingScenarios.build_all(system.authority)
	await _measure("showcase built (%d pieces)" % system.state.component_count())
	var player := arena.get_node("Player") as PlayerController
	for i in player.inventory.capacity:
		if str(player.inventory.slots[i]["id"]) == "build_tool":
			player.select_hotbar(i)
	var tool := player.get_node("BuildTool") as BuildTool
	await process_frame
	tool.select_by_id("room")
	Input.warp_mouse(player.current_camera().unproject_position(player.global_position + Vector3(2.0, 0.0, -2.0)))
	await process_frame
	tool.begin_drag()
	Input.warp_mouse(player.current_camera().unproject_position(player.global_position + Vector3(4.0, 0.0, 0.0)))
	await _measure("tool equipped, preview shown")
	system.debug_view.set_enabled(true)
	await _measure("building debug view on")
	quit(0)


func _measure(label: String) -> void:
	for _i in 60:
		await process_frame
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for _i in 240:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	times.sort()
	var total := 0.0
	var slow := 0
	for ms in times:
		total += ms
		slow += 1 if ms > 30.0 else 0
	print("%-34s avg %6.2f ms  p95 %6.2f ms  worst %6.2f ms  frames>30ms %d/%d" % [label, total / times.size(), times[int(times.size() * 0.95)], times[-1], slow, times.size()])
