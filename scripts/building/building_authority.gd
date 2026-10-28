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

var _query_shape := BoxShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _space_source: Node3D


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
	return _finish(result)


func request_remove(component_id: int, requester: int = 0) -> Dictionary:
	return request_place({"blueprint": "dismantle", "target": component_id}, requester)


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


func _finish(result: Dictionary) -> Dictionary:
	if bool(result["ok"]):
		accepted += 1
	else:
		rejected += 1
	request_finished.emit(result)
	return result
