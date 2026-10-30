extends Node
class_name BuildingAuthority

## The only writer of BuildingState. A request names a blueprint id and grid
## coordinates; the authority looks the blueprint up itself, plans against the
## current state, checks physics obstructions, and commits atomically.
## Clients never send plans. In local play the Build Tool calls this node
## directly; the multiplayer phase routes the same requests through RPCs.

signal request_finished(result: Dictionary)

var state: BuildingState
var grid: GridSystem
var geometry: BuildingGeometry
var placer: RoomPlacer
## Optional resource hooks, used only when config.require_resources is on.
## wallet_count: Callable(item_id: String) -> int
## wallet_spend: Callable(item_id: String, quantity: int) -> bool
var wallet_count: Callable
var wallet_spend: Callable
var accepted := 0
var rejected := 0
## Bullet holes and break chips. Optional; damage still applies when they are missing.
var impacts: ImpactMarks
var debris: DebrisSystem

var _query_shape := BoxShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _space_source: Node3D
var _damage := DamageSystem.new()
var _next_event := 1
## Pieces waiting for the next collapse stage, always in id order.
var _pending_collapse: Array[int] = []
var _collapse_timer: Timer
var _collapse_waves := 0
## Storeys still to drop, highest first, while a pancake is in progress.
var _pancake_groups: Array = []
var _pancake_step := 0
var _in_pancake := false
## How many pieces the last structural check walked. A second building stays out.
var last_region_count := 0


func collapse_waiting() -> int:
	return _pending_collapse.size()


func setup(building_state: BuildingState, grid_system: GridSystem, building_geometry: BuildingGeometry, space_source: Node3D) -> void:
	state = building_state
	grid = grid_system
	geometry = building_geometry
	_space_source = space_source
	placer = RoomPlacer.new(grid, geometry)
	placer.obstruction_check = obstruction_at
	_query.shape = _query_shape
	_query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PLAYER | PhysicsLayers.DAMAGEABLE
	_query.collide_with_areas = false
	_query.collide_with_bodies = true


## Read-only planning, shared by the preview and by request_place.
func make_plan(request: Dictionary) -> ConstructionPlan:
	var blueprint := BlueprintCatalog.get_blueprint(str(request.get("blueprint", "")))
	if blueprint == null:
		var empty := ConstructionPlan.new()
		empty.errors.append("Unknown blueprint")
		empty.state_revision = state.revision
		return empty
	return placer.plan(state, blueprint, _sanitize(request))


func request_place(request: Dictionary, requester: int = 0) -> Dictionary:
	var plan := make_plan(request)
	var result := {"ok": false, "changed": false, "reason": "", "plan": plan, "requester": requester, "change": {}}
	if plan.blueprint != null and plan.blueprint.kind == BuildTypes.BlueprintKind.DISMANTLE:
		return _finish(_dismantle(plan, result))
	if not plan.is_valid():
		result["reason"] = plan.first_reason()
		return _finish(result)
	if not plan.has_changes():
		result["ok"] = true
		result["reason"] = "Already built"
		return _finish(result)
	if grid.config.require_resources and not plan.cost.is_empty():
		var missing := _missing_resources(plan.cost)
		if missing != "":
			result["reason"] = missing
			return _finish(result)
		for item_id in plan.cost.keys():
			if wallet_spend.is_valid():
				wallet_spend.call(str(item_id), int(plan.cost[item_id]))
	var change := state.commit(plan)
	result["ok"] = bool(change.get("ok", false))
	result["changed"] = result["ok"]
	result["change"] = change
	if not result["ok"]:
		result["reason"] = "Commit refused"
	elif not _pending_collapse.is_empty():
		_recheck_pending()
	return _finish(result)


func request_remove(component_id: int, requester: int = 0) -> Dictionary:
	return request_place({"blueprint": "dismantle", "target": component_id}, requester)


## Bullet damage. `event_id` empty means a fresh shot. The same id a second
## time is ignored, even if the first shot destroyed the piece.
func apply_bullet(component_id: int, raw: int, point: Vector3 = Vector3.ZERO, event_id: String = "") -> Dictionary:
	return _apply_scaled(component_id, raw, point, event_id, "bullet")


## Direct impact uses the profile's direct factor instead of the bullet factor.
func apply_direct(component_id: int, raw: int, point: Vector3 = Vector3.ZERO, event_id: String = "") -> Dictionary:
	return _apply_scaled(component_id, raw, point, event_id, "direct")


## One blast. Obstruction is decided before any piece loses health, and the
## whole blast is refused when `event_id` was already used.
func apply_explosion(origin: Vector3, radius: float, base_damage: int, event_id: String = "") -> Dictionary:
	var id := _fresh_event(event_id, "x")
	var result := {"ok": true, "changed": false, "reason": "", "event_id": id, "hits": []}
	if not _damage.claim(id):
		result["reason"] = "Already applied"
		return result
	var space := _space()
	var seen := ExplosionSystem.collect(state, grid, geometry, origin, radius)
	var ray_origin := ExplosionSystem.los_origin(seen, origin)
	var pending: Array = []
	var structural_seeds: Array[int] = []
	for hit in seen:
		var component := state.get_component(int(hit["id"]))
		if component == null or component.destroyed:
			continue
		var point: Vector3 = hit["point"]
		if float(hit["distance"]) > 0.001 and ExplosionSystem.obstructed(state, space, ray_origin, point, component.id):
			continue
		var profile := DamageCatalog.for_kind(component.kind)
		var raw := roundi(float(base_damage) * ExplosionSystem.falloff(float(hit["distance"]), radius))
		var taken := DamageSystem.scale(raw, profile.blast_factor)
		if taken <= 0:
			continue
		pending.append({"id": component.id, "taken": taken, "distance": float(hit["distance"])})
	for hit in pending:
		var applied := state.apply_damage(int(hit["id"]), int(hit["taken"]))
		_spawn_debris(applied)
		_collect_seeds(structural_seeds, applied)
		if bool(applied.get("changed", false)):
			result["changed"] = true
		(result["hits"] as Array).append({
			"id": int(hit["id"]),
			"taken": int(hit["taken"]),
			"distance": float(hit["distance"]),
			"health": int(applied.get("health", 0)),
			"destroyed": bool(applied.get("destroyed", false)),
		})
	note_structural_seeds(structural_seeds)
	return result


func repair(component_id: int) -> Dictionary:
	var result := state.repair_component(component_id)
	return _finish_integrity(result)


func rebuild(component_id: int) -> Dictionary:
	var result := state.rebuild_component(component_id)
	return _finish_integrity(result)


## Name of a non-building body inside the box, or "".
func obstruction_at(box: AABB) -> String:
	if _space_source == null or not _space_source.is_inside_tree():
		return ""
	var world := _space_source.get_world_3d()
	if world == null or world.direct_space_state == null:
		return ""
	var margin := grid.config.obstruction_margin
	var size := box.size - Vector3.ONE * margin * 2.0
	_query_shape.size = Vector3(maxf(size.x, 0.01), maxf(size.y, 0.01), maxf(size.z, 0.01))
	_query.transform = Transform3D(Basis.IDENTITY, box.get_center())
	var hits := world.direct_space_state.intersect_shape(_query, 1)
	if hits.is_empty():
		return ""
	var collider: Object = hits[0].get("collider")
	if collider == null:
		return "something"
	var named: Variant = collider.get("display_name")
	if named != null and str(named) != "":
		return str(named)
	if collider is Node:
		return str((collider as Node).name)
	return "something"


func _dismantle(plan: ConstructionPlan, result: Dictionary) -> Dictionary:
	if not plan.is_valid():
		result["reason"] = plan.first_reason()
		return result
	var change := state.remove_piece(int(plan.request.get("target", 0)))
	result["ok"] = bool(change.get("ok", false))
	result["changed"] = result["ok"]
	result["change"] = change
	result["reason"] = str(change.get("reason", ""))
	return result


func _missing_resources(cost: Dictionary) -> String:
	if not wallet_count.is_valid():
		return ""
	for item_id in cost.keys():
		var have := int(wallet_count.call(str(item_id)))
		if have < int(cost[item_id]):
			return "Needs %d %s (have %d)" % [int(cost[item_id]), str(item_id), have]
	return ""


func _sanitize(request: Dictionary) -> Dictionary:
	var anchor: Variant = request.get("anchor", Vector2i.ZERO)
	var size: Variant = request.get("size", Vector2i.ZERO)
	return RoomPlacer.make_request(
		str(request.get("blueprint", "")),
		anchor if anchor is Vector2i else Vector2i.ZERO,
		posmod(int(request.get("rotation", 0)), 4),
		int(request.get("level", 0)),
		int(request.get("axis", 0)),
		int(request.get("target", 0)),
		size if size is Vector2i else Vector2i.ZERO
	)


func _apply_scaled(component_id: int, raw: int, point: Vector3, event_id: String, channel: String) -> Dictionary:
	var id := _fresh_event(event_id, channel.substr(0, 1))
	var result := {"ok": true, "changed": false, "destroyed": false, "health": 0, "taken": 0, "reason": "", "event_id": id}
	if not _damage.claim(id):
		result["reason"] = "Already applied"
		var existing := state.get_component(component_id)
		if existing != null:
			result["health"] = existing.health
			result["destroyed"] = existing.destroyed
		return result
	var component := state.get_component(component_id)
	if component == null:
		result["ok"] = false
		result["reason"] = "Missing piece"
		return result
	var profile := DamageCatalog.for_kind(component.kind)
	var factor := profile.bullet_factor if channel == "bullet" else profile.direct_factor
	var taken := DamageSystem.scale(raw, factor)
	result["taken"] = taken
	var applied := state.apply_damage(component_id, taken)
	result["ok"] = bool(applied.get("ok", false))
	result["changed"] = bool(applied.get("changed", false))
	result["destroyed"] = bool(applied.get("destroyed", false))
	result["health"] = int(applied.get("health", 0))
	result["reason"] = str(applied.get("reason", ""))
	_spawn_debris(applied)
	note_structural_seeds(applied.get("seeds", []))
	if result["changed"] and channel == "bullet" and impacts != null and not bool(applied.get("destroyed", false)):
		impacts.add_hole(point, _surface_normal(component, point))
	return result


## Starts or updates a collapse from the pieces that touched a destroyed support.
## Building a replacement while a stage is waiting can cancel it. Dismantle
## never calls this.
func note_structural_seeds(seeds: Array) -> void:
	if seeds.is_empty() and _pending_collapse.is_empty():
		return
	var combined: Array[int] = []
	_collect_seeds(combined, {"seeds": seeds})
	_collect_seeds(combined, {"seeds": _pending_collapse})
	_arm_collapse(combined)


func _recheck_pending() -> void:
	if _pending_collapse.is_empty() or _in_pancake:
		return
	if grid.config.collapse_span_sec > 0.0:
		_recheck_pancake()
		return
	var region := StructuralSolver.region(state, _pending_collapse)
	last_region_count = region.size()
	var still := {}
	for id in StructuralSolver.failing(state, region, grid.config):
		still[int(id)] = true
	var kept: Array[int] = []
	for id in _pending_collapse:
		if still.has(int(id)) and state.get_component(int(id)) != null:
			kept.append(int(id))
	_pending_collapse = kept
	if _pending_collapse.is_empty():
		_stop_collapse_timer()
		_collapse_waves = 0


func _arm_collapse(seeds: Array) -> void:
	if grid.config.collapse_span_sec > 0.0:
		_arm_pancake(seeds)
		return
	var region := StructuralSolver.region(state, seeds)
	last_region_count = region.size()
	_pending_collapse.clear()
	for id in StructuralSolver.failing(state, region, grid.config):
		_pending_collapse.append(int(id))
	if _pending_collapse.is_empty():
		_stop_collapse_timer()
		_collapse_waves = 0
		return
	if grid.config.collapse_delay_sec <= 0.0:
		_run_collapse_wave()
		return
	_ensure_collapse_timer()
	if _collapse_timer.is_stopped():
		_collapse_timer.start(grid.config.collapse_delay_sec)


func _run_collapse_wave() -> void:
	if _pending_collapse.is_empty():
		_collapse_waves = 0
		return
	_collapse_waves += 1
	if _collapse_waves > grid.config.collapse_max_waves:
		_pending_collapse.clear()
		_stop_collapse_timer()
		return
	var wave := _pending_collapse.duplicate()
	_pending_collapse.clear()
	var collapsed: Dictionary = state.collapse_pieces(wave)
	_spawn_debris(collapsed)
	var seeds: Array = collapsed.get("seeds", [])
	if seeds.is_empty():
		_collapse_waves = 0
		return
	var region := StructuralSolver.region(state, seeds)
	last_region_count = region.size()
	for id in StructuralSolver.failing(state, region, grid.config):
		_pending_collapse.append(int(id))
	if _pending_collapse.is_empty():
		_collapse_waves = 0
		_stop_collapse_timer()
		return
	if grid.config.collapse_delay_sec <= 0.0:
		_run_collapse_wave()
		return
	_ensure_collapse_timer()
	_collapse_timer.start(grid.config.collapse_delay_sec)


func _ensure_collapse_timer() -> void:
	if _collapse_timer != null:
		return
	_collapse_timer = Timer.new()
	_collapse_timer.one_shot = true
	_collapse_timer.name = "CollapseTimer"
	add_child(_collapse_timer)
	_collapse_timer.timeout.connect(_on_collapse_timer)


func _stop_collapse_timer() -> void:
	if _collapse_timer != null:
		_collapse_timer.stop()


func _collect_seeds(into: Array[int], applied: Dictionary) -> void:
	for id in applied.get("seeds", []):
		var next := int(id)
		if next > 0 and not into.has(next):
			into.append(next)


func _spawn_debris(applied: Dictionary, collapse := false) -> void:
	if debris == null:
		return
	for snap in applied.get("removed", []):
		var kind := int(snap["kind"])
		var origin := geometry.world_aabb(kind, grid.transform_for(kind, snap["key"])).get_center()
		if collapse:
			debris.spawn_collapse(origin, int(snap["id"]))
		else:
			debris.spawn(origin, DamageCatalog.for_kind(kind).debris_count, int(snap["id"]))


func _arm_pancake(seeds: Array) -> void:
	_in_pancake = false
	_pancake_groups.clear()
	_pancake_step = 0
	_stop_collapse_timer()
	var combined: Array[int] = []
	_collect_seeds(combined, {"seeds": seeds})
	_collect_seeds(combined, {"seeds": _pending_collapse})
	last_region_count = StructuralSolver.region(state, combined).size()
	_pending_collapse.clear()
	for id in StructuralSolver.cascade(state, combined, grid.config):
		if state.get_component(int(id)) != null:
			_pending_collapse.append(int(id))
	if _pending_collapse.is_empty():
		_collapse_waves = 0
		return
	if grid.config.collapse_delay_sec <= 0.0:
		_begin_pancake()
		return
	_ensure_collapse_timer()
	_collapse_timer.start(grid.config.collapse_delay_sec)


func _recheck_pancake() -> void:
	var doomed := StructuralSolver.cascade(state, _pending_collapse, grid.config)
	_pending_collapse.clear()
	for id in doomed:
		if state.get_component(int(id)) != null:
			_pending_collapse.append(int(id))
	if _pending_collapse.is_empty():
		_stop_collapse_timer()
		_collapse_waves = 0


func _begin_pancake() -> void:
	_pancake_groups = _storey_groups(_pending_collapse)
	_pancake_step = 0
	_in_pancake = true
	_collapse_waves = 0
	if _pancake_groups.is_empty():
		_finish_pancake()
		return
	_drop_pancake_step()


func _drop_pancake_step() -> void:
	if _pancake_step >= _pancake_groups.size():
		_finish_pancake()
		return
	var ids: Array = _pancake_groups[_pancake_step]
	_pancake_step += 1
	_collapse_waves += 1
	var alive: Array[int] = []
	for id in ids:
		if state.get_component(int(id)) != null:
			alive.append(int(id))
	var step_sec := grid.config.collapse_span_sec
	if not alive.is_empty():
		var collapsed := state.collapse_pieces(alive, true, step_sec)
		_spawn_debris(collapsed, true)
		_forget_pending(collapsed.get("removed", []))
	if _pancake_step >= _pancake_groups.size() or _pending_collapse.is_empty():
		_finish_pancake()
		return
	_ensure_collapse_timer()
	_collapse_timer.start(maxf(step_sec, 0.001))


func _finish_pancake() -> void:
	_in_pancake = false
	_pancake_groups.clear()
	_pancake_step = 0
	_pending_collapse.clear()
	_collapse_waves = 0
	_stop_collapse_timer()


func _on_collapse_timer() -> void:
	if grid.config.collapse_span_sec <= 0.0:
		_run_collapse_wave()
		return
	if not _in_pancake:
		_recheck_pancake()
		if _pending_collapse.is_empty():
			return
		_begin_pancake()
		return
	_drop_pancake_step()


func _storey_groups(ids: Array) -> Array:
	var buckets := {}
	var heights: Array[int] = []
	for raw in ids:
		var component := state.get_component(int(raw))
		if component == null:
			continue
		var storey := StructuralSolver.storey_of(component)
		if not buckets.has(storey):
			buckets[storey] = []
			heights.append(storey)
		(buckets[storey] as Array).append(component.id)
	heights.sort()
	heights.reverse()
	var groups: Array = []
	for storey in heights:
		var group: Array = buckets[storey]
		group.sort()
		groups.append(group)
	return groups


func _forget_pending(removed: Array) -> void:
	var drop := {}
	for snap in removed:
		drop[int(snap["id"])] = true
	var kept: Array[int] = []
	for id in _pending_collapse:
		if not drop.has(id) and state.get_component(id) != null:
			kept.append(id)
	_pending_collapse = kept


func _fresh_event(event_id: String, prefix: String) -> String:
	if not event_id.is_empty():
		return event_id
	var id := "%s%d" % [prefix, _next_event]
	_next_event += 1
	return id


func _surface_normal(component: BuildComponent, point: Vector3) -> Vector3:
	var center := geometry.world_aabb(component.kind, grid.component_transform(component)).get_center()
	var normal := point - center
	if normal.length_squared() < 0.000001:
		return Vector3.UP
	return normal.normalized()


func _space() -> PhysicsDirectSpaceState3D:
	if _space_source == null or not _space_source.is_inside_tree():
		return null
	var world := _space_source.get_world_3d()
	if world == null:
		return null
	return world.direct_space_state


func _finish_integrity(result: Dictionary) -> Dictionary:
	if bool(result.get("ok", false)):
		accepted += 1
	else:
		rejected += 1
	return result


func _finish(result: Dictionary) -> Dictionary:
	if bool(result["ok"]):
		accepted += 1
	else:
		rejected += 1
	request_finished.emit(result)
	return result
