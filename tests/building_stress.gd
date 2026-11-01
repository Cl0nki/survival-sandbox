extends SceneTree

## Spawns ten two-storey 6x6 rooms, measures place / idle / collapse, then
## knocks the supports out. Headless:
##   godot --headless --path <project> --script res://tests/building_stress.gd

const BUILDINGS := 10
const SIZE := Vector2i(6, 6)
const STOREYS := 2
const COLS := 5
const STRIDE := 7


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		print("BUILDING_STRESS timed out")
		quit(2), CONNECT_ONE_SHOT)
	await _run()
	print("BUILDING_STRESS_OK")
	quit(0)


func _run() -> void:
	var stage := Node3D.new()
	stage.name = "Stage"
	root.add_child(stage)
	var ground := StaticBody3D.new()
	ground.collision_layer = PhysicsLayers.WORLD
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	stage.add_child(ground)
	var config := BuildingConfig.new()
	config.collapse_delay_sec = 0.2
	var system := BuildingSystem.new()
	system.config = config
	stage.add_child(system)
	await physics_frame

	print("-- stress: %d buildings, %dx%d, %d storeys" % [BUILDINGS, SIZE.x, SIZE.y, STOREYS])
	var slowest_place := 0.0
	var place_started := Time.get_ticks_usec()
	for index in BUILDINGS:
		var one_started := Time.get_ticks_usec()
		var anchor := _anchor(index)
		for level in STOREYS:
			var result := system.authority.request_place(RoomPlacer.make_request(
				"room", anchor, 0, level, 0, 0, SIZE
			))
			if not bool(result.get("ok", false)):
				print("FAIL place %d level %d: %s" % [index, level, result.get("reason", "")])
		slowest_place = maxf(slowest_place, float(Time.get_ticks_usec() - one_started) / 1000.0)
	var place_ms := float(Time.get_ticks_usec() - place_started) / 1000.0
	var pieces := system.state.component_count()
	var nodes := system.world.node_count()
	print("place     %6.1f ms   pieces %d   nodes %d   spawned %d" % [
		place_ms, pieces, nodes, system.world.spawned_total
	])
	print("          %6.1f ms/building   worst building %6.1f ms   %.2f ms/piece" % [
		place_ms / float(BUILDINGS), slowest_place, place_ms / maxf(float(pieces), 1.0)
	])

	var fork_ms := _time_ms(func() -> void:
		var copy: BuildingState = system.state.fork()
		if copy.component_count() != pieces:
			print("FAIL fork lost pieces")
	)
	var region_ms := 0.0
	var first := system.state.get_component(system.state.slab_at(GridSystem.slab_key(_anchor(0), 0)))
	if first != null:
		region_ms = _time_ms(func() -> void:
			var ids := StructuralSolver.region(system.state, [first.id])
			var copy: BuildingState = system.state.fork_region(ids)
			if copy.component_count() != ids.size():
				print("FAIL region fork size %d != %d" % [copy.component_count(), ids.size()])
		)
	print("fork      %6.1f ms yard   %6.1f ms one building" % [fork_ms, region_ms])

	var idle := await _frame_stats(90)
	print("idle      avg %5.2f ms  p95 %5.2f ms  worst %5.2f ms  >16ms %d/%d" % [
		idle["avg"], idle["p95"], idle["worst"], idle["slow"], idle["frames"]
	])

	var kill_ms := _time_ms(func() -> void:
		for index in BUILDINGS:
			var origin := _center(index, system.grid)
			system.authority.apply_explosion(origin, 12.0, 20000, "stress-x-%d" % index)
	)
	print("blast     %6.1f ms   waiting %d   region %d   leftover %d" % [
		kill_ms,
		system.authority.collapse_waiting(),
		system.authority.last_region_count,
		system.state.component_count(),
	])

	var collapse_start := Time.get_ticks_usec()
	var collapse := await _frame_stats(600, func() -> bool:
		return (
			system.authority.collapse_waiting() == 0
			and not system.authority._in_pancake
			and system.authority._pancake_groups.is_empty()
		)
	)
	var collapse_ms := float(Time.get_ticks_usec() - collapse_start) / 1000.0
	print("collapse  wall %6.1f ms   avg %5.2f ms  p95 %5.2f ms  worst %5.2f ms  >16ms %d/%d" % [
		collapse_ms, collapse["avg"], collapse["p95"], collapse["worst"], collapse["slow"], collapse["frames"]
	])

	var wall_ids: Array[int] = []
	for component: BuildComponent in system.state.components.values():
		if BuildTypes.is_edge_kind(component.kind):
			wall_ids.append(component.id)
	var flatten_ms := _time_ms(func() -> void:
		var seeds: Array[int] = []
		for id in wall_ids:
			var applied := system.state.apply_damage(id, 10000)
			for seed in applied.get("seeds", []):
				var next := int(seed)
				if next > 0 and not seeds.has(next):
					seeds.append(next)
		system.authority.note_structural_seeds(seeds)
	)
	print("flatten   %6.1f ms   walls %d   waiting %d   leftover %d" % [
		flatten_ms, wall_ids.size(), system.authority.collapse_waiting(), system.state.component_count()
	])
	var drop := await _frame_stats(600, func() -> bool:
		return (
			system.authority.collapse_waiting() == 0
			and not system.authority._in_pancake
			and system.authority._pancake_groups.is_empty()
		)
	)
	print("drop      avg %5.2f ms  p95 %5.2f ms  worst %5.2f ms  >16ms %d/%d" % [
		drop["avg"], drop["p95"], drop["worst"], drop["slow"], drop["frames"]
	])
	var rebuild := system.authority.request_place(RoomPlacer.make_request(
		"room", Vector2i(10, 10), 0, 0, 0, 0, Vector2i.ONE
	))
	if not bool(rebuild.get("ok", false)):
		print("FAIL rebuild after flatten: %s" % rebuild.get("reason", ""))
	print("after     pieces %d   nodes %d   freed %d   pooled %d   reused %d   debris live %d / spawned %d" % [
		system.state.component_count(),
		system.world.node_count(),
		system.world.freed_total,
		system.world.pool_count(),
		system.world.reused_total,
		system.debris.alive(),
		system.debris.spawned_total,
	])
	_notes(place_ms, fork_ms, kill_ms, flatten_ms, idle, collapse, drop, pieces, system)


func _anchor(index: int) -> Vector2i:
	return Vector2i(-17 + (index % COLS) * STRIDE, -17 + int(index / COLS) * STRIDE)


func _center(index: int, grid: GridSystem) -> Vector3:
	var anchor := _anchor(index)
	return Vector3(
		grid.config.grid_origin.x + (float(anchor.x) + float(SIZE.x) * 0.5) * grid.config.cell_size,
		grid.config.grid_origin.y + grid.config.floor_height,
		grid.config.grid_origin.z + (float(anchor.y) + float(SIZE.y) * 0.5) * grid.config.cell_size
	)


func _time_ms(work: Callable) -> float:
	var started := Time.get_ticks_usec()
	work.call()
	return float(Time.get_ticks_usec() - started) / 1000.0


func _frame_stats(max_frames: int, done: Callable = Callable()) -> Dictionary:
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for _i in max_frames:
		await physics_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		if done.is_valid() and bool(done.call()):
			break
	times.sort()
	var total := 0.0
	var slow := 0
	for ms in times:
		total += ms
		if ms > 16.0:
			slow += 1
	var count := maxi(times.size(), 1)
	return {
		"avg": total / float(count),
		"p95": times[clampi(int(count * 0.95), 0, count - 1)],
		"worst": times[count - 1],
		"slow": slow,
		"frames": count,
	}


func _notes(
	place_ms: float,
	fork_ms: float,
	blast_ms: float,
	flatten_ms: float,
	idle: Dictionary,
	collapse: Dictionary,
	drop: Dictionary,
	pieces: int,
	system: BuildingSystem
) -> void:
	print("-- notes")
	if place_ms > 250.0:
		print("- placing is the heavy part (plan + commit + a node per piece). Batching mesh/body spawn or deferring collision would help.")
	if fork_ms > 40.0:
		print("- a full-yard fork is still %.0f ms. Forecasts should only copy the connected building." % fork_ms)
	if blast_ms > 200.0:
		print("- ten blasts took %.0f ms. Explosion LOS still walks every piece; collapse forecast waits for the delay so it should not run ten times." % blast_ms)
	if flatten_ms > 80.0:
		print("- flattening remaining walls still cost %.0f ms." % flatten_ms)
	if float(idle["avg"]) > 12.0:
		print("- idle sat at %.1f ms average with %d StaticBody3D nodes. Shared collision meshes or fewer bodies per piece would help standing yards." % [float(idle["avg"]), pieces])
	if float(collapse["worst"]) > 33.0 or float(drop["worst"]) > 33.0:
		print("- a collapse frame went past 33 ms (worst %.0f / %.0f). Pancake already splits storeys; the remaining cost is node free + debris + graph updates in one wave." % [float(collapse["worst"]), float(drop["worst"])])
	if system.debris.spawned_total >= system.config.debris_cap:
		print("- break chips hit the cap (%d). Mass pancake waves skip ash on purpose." % system.config.debris_cap)
	if system.state.component_count() > 80:
		print("- ground slabs stay after the walls fall (%d pieces left). Expected: floors do not need walls." % system.state.component_count())
	if system.world.freed_total > 0 and system.world.pool_count() == 0 and system.world.reused_total == 0:
		print("- piece nodes were freed but the pool stayed empty.")
