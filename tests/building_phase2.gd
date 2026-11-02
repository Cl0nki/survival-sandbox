extends SceneTree

## Headless regression suite for Phase 2 (damage, explosions, repair, debris).
## godot --headless --path <project> --script res://tests/building_phase2.gd

var _stage: Node3D
var _failures := PackedStringArray()
var _checks := 0
var _section := ""


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("BUILDING_PHASE2 timed out in section ", _section)
		quit(2), CONNECT_ONE_SHOT)
	await _body()
	print("checks=%d failures=%d" % [_checks, _failures.size()])
	for failure in _failures:
		print("FAIL ", failure)
	if _failures.is_empty():
		print("BUILDING_PHASE2_OK")
		quit(0)
	else:
		quit(1)


func _body() -> void:
	_test_profiles_and_falloff()
	_test_spawn_health()
	await _test_bullets_repair_rebuild()
	_test_destroyed_wall_and_room()
	await _test_explosions()
	await _test_blast_reaches_neighbours()
	await _test_debris_and_impacts()
	await _test_aim_skips_hidden_ceiling()
	_test_cutaway_stays_in_one_building()
	_test_upgrade_tiers()
	if _stage != null:
		_stage.free()
		_stage = null


func _begin(section: String, config: BuildingConfig = null) -> BuildingSystem:
	_section = section
	print("-- ", section)
	if _stage != null:
		_stage.free()
	_stage = Node3D.new()
	_stage.name = "Stage"
	root.add_child(_stage)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = PhysicsLayers.WORLD
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	_stage.add_child(ground)
	var system := BuildingSystem.new()
	if config != null:
		system.config = config
	_stage.add_child(system)
	return system


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append("[%s] %s" % [_section, message])
	return condition


func _place(system: BuildingSystem, id: String, anchor: Vector2i, rotation: int = 0, level: int = 0, axis: int = 0, size := Vector2i.ZERO) -> Dictionary:
	return system.authority.request_place(RoomPlacer.make_request(id, anchor, rotation, level, axis, 0, size))


func _built(system: BuildingSystem, id: String, anchor: Vector2i, rotation: int = 0, level: int = 0, axis: int = 0, size := Vector2i.ZERO) -> Dictionary:
	var result := _place(system, id, anchor, rotation, level, axis, size)
	_check(bool(result["ok"]) and bool(result["changed"]), "%s at %s was not built: %s" % [id, anchor, result.get("reason", "")])
	return result


func _audit(system: BuildingSystem, label: String) -> void:
	var report := GeometryAudit.run(system)
	_check(bool(report["ok"]), "%s\n%s" % [label, GeometryAudit.describe(report, 12)])


func _edge(system: BuildingSystem, key: Vector4i) -> BuildComponent:
	return system.state.get_component(system.state.edges.component_at(key))


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := _stage.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PhysicsLayers.BUILDING
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query)


func _test_profiles_and_falloff() -> void:
	_section = "profiles"
	print("-- ", _section)
	_check(DamageCatalog.load_problems().is_empty(), "damage profiles: %s" % ", ".join(DamageCatalog.load_problems()))
	_check(ExplosionSystem.falloff(0.0, 4.0) == 1.0, "falloff at the origin")
	_check(is_equal_approx(ExplosionSystem.falloff(2.0, 4.0), 0.5), "falloff at half radius")
	_check(ExplosionSystem.falloff(4.0, 4.0) == 0.0, "falloff at the radius")
	_check(ExplosionSystem.falloff(6.0, 4.0) == 0.0, "falloff past the radius")
	_check(DamageSystem.scale(40, 0.5) == 20, "half resistance")
	_check(DamageSystem.scale(20, 1.5) == 30, "glass takes extra blast")
	_check(DamageSystem.scale(40, 0.0) == 0, "immune material")
	_check(DamageSystem.scale(0, 1.0) == 0, "zero raw damage")
	var wall := DamageCatalog.for_kind(BuildTypes.Kind.WALL)
	var window := DamageCatalog.for_kind(BuildTypes.Kind.WINDOW)
	_check(wall.bullet_factor < window.bullet_factor, "window bullet resistance is not lower than a wall")
	_check(wall.obstructs_blast and not window.obstructs_blast, "window should let a blast through")
	_check(BuildingTier.health_of(1) == 200 and BuildingTier.display_name(1) == "Scrap", "scrap hp")
	_check(BuildingTier.health_of(2) == 400, "wood hp")
	_check(BuildingTier.health_of(3) == 800 and BuildingTier.health_of(4) == 1600, "brick and stone hp")
	_check(BuildingTier.health_of(5) == 3600 and BuildingTier.health_of(6) == 8000, "concrete and composite hp")
	_check(BuildingTier.next_of(6) == 6, "composite still had a next tier")
	for tier in range(BuildingTier.MIN, BuildingTier.MAX + 1):
		var face := BuildingTier.color_for(tier, BuildTypes.Kind.WALL)
		var post_colour := BuildingTier.color_for(tier, BuildTypes.Kind.POST)
		var slab_colour := BuildingTier.color_for(tier, BuildTypes.Kind.SLAB)
		_check(post_colour.get_luminance() < face.get_luminance(), "tier %d post was not darker than the wall" % tier)
		_check(slab_colour.get_luminance() < face.get_luminance(), "tier %d floor was not darker than the wall" % tier)


func _test_spawn_health() -> void:
	var system := _begin("spawn health")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	var keys: Array[Vector4i] = []
	for component: BuildComponent in system.state.components.values():
		if component.kind == BuildTypes.Kind.WALL:
			keys.append(component.key)
	_check(keys.size() >= 2, "room did not build two walls")
	_built(system, "doorway", Vector2i(keys[0].x, keys[0].y), 0, keys[0].z, keys[0].w)
	_built(system, "window", Vector2i(keys[1].x, keys[1].y), 0, keys[1].z, keys[1].w)
	for z in 3:
		_built(system, "floor_1x1", Vector2i(8, z))
	_built(system, "stairs_straight", Vector2i(8, 0))
	var seen := {}
	for component: BuildComponent in system.state.components.values():
		var profile := DamageCatalog.for_kind(component.kind)
		seen[component.kind] = true
		var hp := BuildingTier.health_of(BuildingTier.MIN)
		_check(component.tier == BuildingTier.MIN, "%s started at tier %d" % [component.describe(), component.tier])
		_check(component.health == hp and component.max_health == hp and not component.destroyed, "%s did not start at %d hp" % [component.describe(), hp])
		_check(component.material == profile.id, "%s material %s" % [component.describe(), component.material])
	for kind in [BuildTypes.Kind.SLAB, BuildTypes.Kind.WALL, BuildTypes.Kind.DOORWAY, BuildTypes.Kind.WINDOW, BuildTypes.Kind.POST, BuildTypes.Kind.STAIRS]:
		_check(seen.has(kind), "no %s was built to check its profile" % BuildTypes.kind_name(kind))
	_audit(system, "undamaged building")


func _test_bullets_repair_rebuild() -> void:
	var system := _begin("bullets, repair, rebuild")
	_built(system, "floor_1x1", Vector2i(0, 0))
	_built(system, "floor_1x1", Vector2i(0, -1))
	_built(system, "floor_1x1", Vector2i(2, 0))
	_built(system, "floor_1x1", Vector2i(2, -1))
	_built(system, "wall", Vector2i(0, 0), 0, 0, BuildTypes.AXIS_X)
	_built(system, "wall", Vector2i(2, 0), 0, 0, BuildTypes.AXIS_X)
	var wall := _edge(system, Vector4i(0, 0, 0, BuildTypes.AXIS_X))
	var neighbour := _edge(system, Vector4i(2, 0, 0, BuildTypes.AXIS_X))
	_check(wall != null and neighbour != null, "test walls missing")
	if wall == null or neighbour == null:
		return
	var wall_profile := DamageCatalog.for_kind(BuildTypes.Kind.WALL)
	var spawned := system.world.spawned_total
	var freed := system.world.freed_total
	var masks := system.world.mask_updates
	var nodes := system.world.node_count()
	var wall_node := system.world.node_for(wall.id)
	var neighbour_node := system.world.node_for(neighbour.id)
	var wall_xform := wall_node.transform
	var neighbour_xform := neighbour_node.transform
	var mesh_before: Mesh = (wall_node.get_node("Mesh") as MeshInstance3D).mesh
	var shared_before := system.geometry.material_for(BuildTypes.Kind.WALL).albedo_color
	var first := system.authority.apply_bullet(wall.id, 20, wall_xform.origin + Vector3(0, 1.0, -1.0), "shot-1")
	_check(int(first["taken"]) == DamageSystem.scale(20, wall_profile.bullet_factor), "bullet taken %s" % str(first))
	_check(wall.health == wall.max_health - int(first["taken"]) and not wall.destroyed, "wall health %d" % wall.health)
	var again := system.authority.apply_bullet(wall.id, 20, Vector3.ZERO, "shot-1")
	_check(not bool(again["changed"]) and wall.health == wall.max_health - int(first["taken"]), "duplicate shot changed health")
	var direct := system.authority.apply_direct(neighbour.id, 20, Vector3.ZERO, "hit-1")
	var neighbour_profile := DamageCatalog.for_kind(BuildTypes.Kind.POST if neighbour.kind != BuildTypes.Kind.WALL else BuildTypes.Kind.WALL)
	_check(int(direct["taken"]) == DamageSystem.scale(20, neighbour_profile.direct_factor), "direct taken %s" % str(direct))
	_check(int(direct["taken"]) > int(first["taken"]), "direct impact did not ignore bullet resistance")
	_check(system.world.spawned_total == spawned and system.world.freed_total == freed and system.world.mask_updates == masks, "a bullet rebuilt building nodes")
	_check(system.world.node_count() == nodes, "node count changed on damage")
	_check(wall_node.transform == wall_xform and neighbour_node.transform == neighbour_xform, "damage moved a transform")
	_check((wall_node.get_node("Mesh") as MeshInstance3D).mesh == mesh_before, "damage replaced the wall mesh")
	_check(system.geometry.material_for(BuildTypes.Kind.WALL).albedo_color == shared_before, "damage tinted the shared material")
	_check(system.impacts.alive() == 1, "bullet left %d marks" % system.impacts.alive())
	_check(system.impacts.get_parent() == system and wall_node.get_node_or_null("Impacts") == null, "bullet hole was parented to the wall")
	var body := wall_node.get_node("Body") as BuildingPieceBody
	var before_body := wall.health
	_check(body.receive_damage(20, wall_xform.origin + Vector3(0, 1.0, -1.0)), "piece body did not accept a shot")
	_check(wall.health == before_body - DamageSystem.scale(20, wall_profile.bullet_factor), "body shot health %d" % wall.health)
	var repaired := system.authority.repair(wall.id)
	_check(bool(repaired["ok"]) and wall.health == wall.max_health and not wall.destroyed, "repair failed: %s" % repaired.get("reason", ""))
	_check(not bool(system.authority.repair(wall.id)["ok"]), "repairing a healthy wall succeeded")
	_check(not bool(system.authority.rebuild(wall.id)["ok"]), "rebuilding a standing wall succeeded")
	for _i in 2:
		await physics_frame
	var center := system.geometry.world_aabb(wall.kind, system.grid.component_transform(wall)).get_center()
	_check(not _ray(center + Vector3(0, 0, -1.0), center + Vector3(0, 0, 1.0)).is_empty(), "ray missed the standing wall")
	var wall_key: Vector4i = wall.key
	var id_before := wall.id
	var killed := system.authority.apply_bullet(id_before, 10000, center, "kill-1")
	_check(bool(killed["destroyed"]) and system.state.get_component(id_before) == null, "destroyed wall was kept: %s" % str(killed))
	_check(system.state.edges.component_at(wall_key) == 0, "destroyed wall still owns its boundary")
	_check(system.world.node_for(id_before) == null, "destroyed wall node is still in the world")
	_check(not bool(system.authority.repair(id_before)["ok"]), "repair restored a removed wall")
	for _i in 2:
		await physics_frame
	_check(_ray(center + Vector3(0, 0, -1.0), center + Vector3(0, 0, 1.0)).is_empty(), "ray still hit the removed wall")
	var placed := _place(system, "wall", Vector2i(0, 0), 0, 0, BuildTypes.AXIS_X)
	_check(bool(placed["ok"]) and bool(placed["changed"]) and system.state.edges.component_at(wall_key) != 0, "the gap did not accept a new wall: %s" % placed.get("reason", ""))
	_check(neighbour_node.transform == neighbour_xform, "neighbour moved during destruction")
	_audit(system, "after a wall was destroyed and replaced")


func _test_destroyed_wall_and_room() -> void:
	var system := _begin("destroyed wall and room are removed")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	_check(system.state.rooms.size() == 1, "room was not recorded")
	var wall: BuildComponent = null
	for component: BuildComponent in system.state.components.values():
		if component.kind == BuildTypes.Kind.WALL:
			wall = component
			break
	_check(wall != null, "room has no wall")
	if wall == null:
		return
	var key: Vector4i = wall.key
	var before := system.state.component_count()
	system.authority.apply_bullet(wall.id, 10000, Vector3.ZERO, "room-wall")
	_check(system.state.edges.component_at(key) == 0 and system.state.get_component(wall.id) == null, "destroyed room wall stayed")
	_check(system.state.rooms.size() == 1 and system.state.component_count() < before, "one wall removed the rest of the room")
	var structural: Array[int] = []
	for component: BuildComponent in system.state.components.values():
		if component.kind != BuildTypes.Kind.POST:
			structural.append(component.id)
	for component_id in structural:
		if system.state.get_component(component_id) != null:
			system.authority.apply_bullet(component_id, 10000, Vector3.ZERO, "clear-%d" % component_id)
	_check(system.state.rooms.is_empty(), "room with nothing left was kept")
	_check(system.state.component_count() == 0 and system.world.node_count() == 0, "room left pieces or nodes behind")
	var replaced := _place(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	_check(bool(replaced["ok"]) and bool(replaced["changed"]), "could not build where the room was: %s" % replaced.get("reason", ""))
	_audit(system, "room rebuilt after it was destroyed")


func _test_explosions() -> void:
	var system := _begin("explosions")
	for cell in [Vector2i(0, -1), Vector2i(0, 0), Vector2i(3, -1), Vector2i(3, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(12, 1), Vector2i(12, 2), Vector2i(12, 3), Vector2i(12, 4)]:
		_built(system, "floor_1x1", cell)
	_built(system, "wall", Vector2i(0, 0), 0, 0, BuildTypes.AXIS_X)
	_built(system, "wall", Vector2i(3, 0), 0, 0, BuildTypes.AXIS_X)
	_built(system, "wall", Vector2i(0, 2), 0, 0, BuildTypes.AXIS_X)
	_built(system, "wall", Vector2i(0, 4), 0, 0, BuildTypes.AXIS_X)
	_built(system, "window", Vector2i(12, 2), 0, 0, BuildTypes.AXIS_X)
	_built(system, "wall", Vector2i(12, 4), 0, 0, BuildTypes.AXIS_X)
	for _i in 3:
		await physics_frame
	var near := _edge(system, Vector4i(0, 0, 0, BuildTypes.AXIS_X))
	var far := _edge(system, Vector4i(3, 0, 0, BuildTypes.AXIS_X))
	var front := _edge(system, Vector4i(0, 2, 0, BuildTypes.AXIS_X))
	var back := _edge(system, Vector4i(0, 4, 0, BuildTypes.AXIS_X))
	var glass := _edge(system, Vector4i(12, 2, 0, BuildTypes.AXIS_X))
	var behind := _edge(system, Vector4i(12, 4, 0, BuildTypes.AXIS_X))
	_check(near != null and far != null and front != null and back != null and glass != null and behind != null, "explosion layout missing a piece")
	if near == null:
		return
	var spawned := system.world.spawned_total
	var nodes := system.world.node_count()
	var blast := system.authority.apply_explosion(Vector3(0.5, 1.5, -2.0), 8.0, 40, "blast-falloff")
	var near_hit := _hit(blast, near.id)
	var far_hit := _hit(blast, far.id)
	_check(not near_hit.is_empty() and not far_hit.is_empty(), "falloff blast missed a wall: %s" % str(blast["hits"]))
	if not near_hit.is_empty() and not far_hit.is_empty():
		_check(int(near_hit["taken"]) > int(far_hit["taken"]), "near wall took %s, far took %s" % [str(near_hit), str(far_hit)])
		var profile := DamageCatalog.for_kind(BuildTypes.Kind.WALL)
		var expected := DamageSystem.scale(roundi(40.0 * ExplosionSystem.falloff(float(near_hit["distance"]), 8.0)), profile.blast_factor)
		_check(int(near_hit["taken"]) == expected and near.health == near.max_health - expected, "near falloff taken %s expected %d" % [str(near_hit), expected])
	var blocked := system.authority.apply_explosion(Vector3(0.5, 1.5, 0.5), 8.0, 80, "blast-block")
	_check(_hit(blocked, front.id).is_empty() == false and front.health < front.max_health, "front wall was not hit")
	_check(_hit(blocked, back.id).is_empty() and back.health == back.max_health, "blast passed through a solid wall: %s" % str(blocked["hits"]))
	var repeat := system.authority.apply_explosion(Vector3(0.5, 1.5, 0.5), 8.0, 80, "blast-block")
	_check(not bool(repeat["changed"]) and str(repeat["reason"]) == "Already applied" and front.health == _health_after(blocked, front.id, front.health), "duplicate blast applied again")
	var through := system.authority.apply_explosion(Vector3(12.5, 0.4, 0.5), 8.0, 40, "blast-glass")
	_check(not _hit(through, glass.id).is_empty(), "blast missed the window")
	_check(not _hit(through, behind.id).is_empty() and behind.health < behind.max_health, "blast did not pass the window: %s" % str(through["hits"]))
	for i in 5:
		system.authority.apply_explosion(Vector3(0.5, 1.5, -2.0), 8.0, 30, "blast-repeat-%d" % i)
	_check(system.world.node_count() == system.state.component_count(), "repeated blasts left pieces without nodes, or extra nodes")
	_check(system.world.spawned_total == spawned, "blasts spawned replacement building nodes")
	_check(system.world.node_count() <= nodes, "blasts added building nodes")
	_audit(system, "after explosions")


func _test_blast_reaches_neighbours() -> void:
	var system := _begin("blast reaches neighbouring walls")
	for cell in [Vector2i(-10, -1), Vector2i(-10, 0), Vector2i(-9, -1), Vector2i(-9, 0), Vector2i(-8, -1), Vector2i(-8, 0), Vector2i(-9, 1), Vector2i(-9, 2)]:
		_built(system, "floor_1x1", cell)
	_built(system, "wall", Vector2i(-10, 0), 0, 0, BuildTypes.AXIS_X)
	_built(system, "wall", Vector2i(-9, 0), 0, 0, BuildTypes.AXIS_X)
	_built(system, "wall", Vector2i(-8, 0), 0, 0, BuildTypes.AXIS_X)
	_built(system, "wall", Vector2i(-9, 2), 0, 0, BuildTypes.AXIS_X)
	for _i in 3:
		await physics_frame
	var left := _edge(system, Vector4i(-10, 0, 0, BuildTypes.AXIS_X))
	var middle := _edge(system, Vector4i(-9, 0, 0, BuildTypes.AXIS_X))
	var right := _edge(system, Vector4i(-8, 0, 0, BuildTypes.AXIS_X))
	var behind := _edge(system, Vector4i(-9, 2, 0, BuildTypes.AXIS_X))
	_check(left != null and middle != null and right != null and behind != null, "neighbour layout missing a wall")
	if left == null or middle == null or right == null or behind == null:
		return
	var blast := system.authority.apply_explosion(Vector3(-8.5, 1.5, -0.075), 4.0, 120, "blast-neighbours")
	var middle_hit := _hit(blast, middle.id)
	var left_hit := _hit(blast, left.id)
	var right_hit := _hit(blast, right.id)
	_check(not middle_hit.is_empty(), "blast missed the aimed wall: %s" % str(blast["hits"]))
	_check(not left_hit.is_empty() and int(left_hit["taken"]) > 0, "left wall took no damage: %s" % str(blast["hits"]))
	_check(not right_hit.is_empty() and int(right_hit["taken"]) > 0, "right wall took no damage: %s" % str(blast["hits"]))
	if not middle_hit.is_empty() and not left_hit.is_empty() and not right_hit.is_empty():
		_check(int(middle_hit["taken"]) >= int(left_hit["taken"]) and int(middle_hit["taken"]) >= int(right_hit["taken"]), "a side wall took more than the aimed wall")
	_check(_hit(blast, behind.id).is_empty() and behind.health == behind.max_health, "blast passed through the aimed wall: %s" % str(blast["hits"]))


func _hit(result: Dictionary, component_id: int) -> Dictionary:
	for hit in result.get("hits", []):
		if int(hit["id"]) == component_id:
			return hit
	return {}


func _health_after(result: Dictionary, component_id: int, fallback: int) -> int:
	var hit := _hit(result, component_id)
	return int(hit["health"]) if not hit.is_empty() else fallback


func _test_debris_and_impacts() -> void:
	var config := BuildingConfig.new()
	config.debris_lifetime_sec = 0.25
	config.debris_cap = 6
	config.impact_lifetime_sec = 0.25
	config.impact_cap = 3
	var system := _begin("debris and impacts", config)
	for cell in [Vector2i(0, -1), Vector2i(0, 0), Vector2i(1, -1), Vector2i(1, 0), Vector2i(2, -1), Vector2i(2, 0)]:
		_built(system, "floor_1x1", cell)
	var walls: Array[BuildComponent] = []
	for x in 3:
		_built(system, "wall", Vector2i(x, 0), 0, 0, BuildTypes.AXIS_X)
		walls.append(_edge(system, Vector4i(x, 0, 0, BuildTypes.AXIS_X)))
	var profile := DamageCatalog.for_kind(BuildTypes.Kind.WALL)
	_check(profile.debris_count > 0 and walls[0] != null, "walls spawn no debris")
	if walls[0] == null:
		return
	for i in 5:
		system.authority.apply_bullet(walls[0].id, 20, Vector3(0.5, 1.0, -1.0) + Vector3(0.01 * i, 0, 0), "mark-%d" % i)
	_check(system.impacts.alive() == config.impact_cap, "impacts grew to %d" % system.impacts.alive())
	var wall_id := walls[0].id
	system.authority.apply_bullet(wall_id, 10000, Vector3(0.5, 1.0, -1.0), "debris-1")
	_check(system.state.get_component(wall_id) == null, "broken wall was not removed")
	_check(system.debris.alive() > 0 and system.debris.alive() <= config.debris_cap, "first break left %d chips" % system.debris.alive())
	_check(system.debris.get_parent() == system, "debris was parented under the building world")
	for wall in walls:
		system.authority.apply_bullet(wall.id, 10000, Vector3.ZERO, "debris-%d" % wall.id)
	_check(system.debris.alive() <= config.debris_cap, "debris grew to %d over the cap %d" % [system.debris.alive(), config.debris_cap])
	await create_timer(0.45).timeout
	_check(system.debris.alive() == 0, "debris still alive: %d" % system.debris.alive())
	_check(system.impacts.alive() == 0, "impacts still alive: %d" % system.impacts.alive())
	_audit(system, "after debris cleanup")


func _test_aim_skips_hidden_ceiling() -> void:
	var system := _begin("aim skips a hidden ceiling")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	for _i in 3:
		await physics_frame
	var above := Vector3(0.5, 8.0, 0.5)
	var below := Vector3(0.5, -1.0, 0.5)
	var blocked := _ray(above, below)
	var blocked_id := _component_id(blocked.get("collider"))
	var ceiling := system.state.get_component(blocked_id)
	_check(ceiling != null and ceiling.kind == BuildTypes.Kind.SLAB and ceiling.level == 1, "a raw ray did not hit the ceiling")
	system.world.set_cut_level(0)
	var space := _stage.get_world_3d().direct_space_state
	var aimed := AimProjector.first_solid(
		space,
		above,
		below,
		PhysicsLayers.BUILDING,
		[],
		Callable(system.world, &"collider_is_hidden")
	)
	var floor := system.state.get_component(_component_id(aimed.get("collider")))
	_check(floor != null and floor.kind == BuildTypes.Kind.SLAB and floor.level == 0, "aim still hit the hidden ceiling: %s" % str(aimed.get("position", Vector3.ZERO)))
	var still_solid := _ray(above, below)
	var solid := system.state.get_component(_component_id(still_solid.get("collider")))
	_check(solid != null and solid.level == 1, "hiding the ceiling removed its collision")


func _test_cutaway_stays_in_one_building() -> void:
	var system := _begin("cutaway stays in one building")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(4, 4))
	_built(system, "room", Vector2i(6, 0), 0, 0, 0, Vector2i(2, 2))
	_built(system, "room", Vector2i(4, 0), 0, 0, 0, Vector2i(1, 2))
	var home := system.state.building_ids_at(Vector2i(1, 1), 0)
	var neighbour := system.state.building_ids_at(Vector2i(6, 0), 0)
	var joined := system.state.building_ids_at(Vector2i(4, 0), 0)
	var home_roof := system.state.slab_at(GridSystem.slab_key(Vector2i(0, 0), 1))
	var far_roof := system.state.slab_at(GridSystem.slab_key(Vector2i(3, 3), 1))
	var join_roof := system.state.slab_at(GridSystem.slab_key(Vector2i(4, 0), 1))
	var other_roof := system.state.slab_at(GridSystem.slab_key(Vector2i(6, 0), 1))
	_check(home.has(home_roof) and home.has(far_roof) and home.has(join_roof), "the whole roof of this building was not included")
	_check(not home.has(other_roof) and neighbour.has(other_roof), "a gap still merged two buildings")
	_check(joined.has(home_roof) and joined.has(far_roof), "standing in the attached room left the first room")
	system.world.set_cut_level(0, home)
	var home_mesh := system.world.node_for(home_roof).get_node("Mesh") as MeshInstance3D
	var far_mesh := system.world.node_for(far_roof).get_node("Mesh") as MeshInstance3D
	var other_mesh := system.world.node_for(other_roof).get_node("Mesh") as MeshInstance3D
	_check(home_mesh != null and not home_mesh.visible, "the building you are in kept its roof")
	_check(far_mesh != null and not far_mesh.visible, "only the tile above you opened")
	_check(other_mesh != null and other_mesh.visible, "the neighbour roof was cut away")
	_check(system.world.collider_is_hidden(system.world.node_for(home_roof).get_node("Body")), "aim still hits your hidden roof")
	_check(not system.world.collider_is_hidden(system.world.node_for(other_roof).get_node("Body")), "aim skipped the neighbour roof")
	_check(system.state.building_ids_at(Vector2i(1, 1), 1).has(far_roof), "page-up left the building")
	system.cut_override = 0
	system.cut_aim_cell = Vector2i(1, 1)
	var at_floor: Array = system.active_cut()
	_check(int(at_floor[0]) == 0 and at_floor[1].has(far_roof), "build level 0 did not open this building")
	system.world.set_cut_level(int(at_floor[0]), at_floor[1])
	_check(not far_mesh.visible, "build mode still hid only one tile")
	_check(other_mesh.visible, "build mode opened the neighbour")
	system.cut_override = 1
	var at_roof: Array = system.active_cut()
	_check(int(at_roof[0]) == 1 and at_roof[1].has(far_roof), "build level 1 lost the building")
	system.world.set_cut_level(int(at_roof[0]), at_roof[1])
	_check(far_mesh.visible, "page-up did not show this building's floor")
	_check(other_mesh.visible, "page-up opened the neighbour")
	var tool := BuildTool.new()
	_stage.add_child(tool)
	tool.setup(system)
	tool.set_equipped(true)
	tool.follow_stand_from_height(0.2)
	tool.update_aim(Vector3(1.5, 0.2, 1.5))
	_check(tool.level == 0 and system.cut_override == 0, "the tool did not start on the floor you stood on")
	tool.follow_stand_from_height(3.2)
	tool.update_aim(Vector3(1.5, 3.2, 1.5))
	_check(tool.level == 1 and system.cut_override == 1, "walking a ramp with the tool open kept the starting floor")
	var after_ramp: Array = system.active_cut()
	_check(int(after_ramp[0]) == 1 and after_ramp[1].has(far_roof), "the cut stayed on the starting floor after the ramp")
	system.world.set_cut_level(int(after_ramp[0]), after_ramp[1])
	_check(far_mesh.visible, "the upper floor stayed hidden after the ramp")
	_check(other_mesh.visible, "the neighbour opened after the ramp")
	tool.change_level(1)
	tool.follow_stand_from_height(3.2)
	_check(tool.level == 2, "page-up was reset without leaving the floor")


func _test_upgrade_tiers() -> void:
	var system := _begin("upgrade tiers")
	_built(system, "floor_1x1", Vector2i(0, 0))
	_built(system, "floor_1x1", Vector2i(0, -1))
	_built(system, "wall", Vector2i(0, 0), 0, 0, BuildTypes.AXIS_X)
	var wall := _edge(system, Vector4i(0, 0, 0, BuildTypes.AXIS_X))
	_check(wall != null, "no wall to upgrade")
	if wall == null:
		return
	_check(wall.tier == 1 and wall.max_health == 200, "new wall was not Scrap")
	var post := system.state.get_component(system.state.post_at(GridSystem.post_key(Vector2i(0, 0), 0)))
	_check(post != null and system.state.is_joint_post(post), "wall had no corner post")
	if post != null:
		var refused := system.authority.upgrade(post.id)
		_check(not bool(refused.get("ok", false)), "a corner post accepted its own upgrade")
	var mesh := system.world.node_for(wall.id).get_node("Mesh") as MeshInstance3D
	_check(mesh != null, "wall had no mesh")
	var first := system.authority.upgrade(wall.id)
	_check(bool(first.get("ok", false)) and wall.tier == 2 and wall.max_health == 400 and wall.health == 400, "upgrade to wood failed: %s" % first.get("reason", ""))
	var wood := mesh.get_surface_override_material(0) as StandardMaterial3D
	_check(wood != null, "wood wall had no material")
	if wood != null and wood.albedo_texture == null:
		_check(wood.albedo_color.is_equal_approx(BuildingTier.color_for(2, BuildTypes.Kind.WALL)), "wood wall kept the scrap colour")
	if post != null:
		var post_mesh := system.world.node_for(post.id).get_node("Mesh") as MeshInstance3D
		var post_mat := post_mesh.get_surface_override_material(0) as StandardMaterial3D if post_mesh != null else null
		_check(post_mat != null, "corner post had no material")
		if post_mat != null:
			var floor_mat := BuildingTier.make_material(2, BuildTypes.Kind.SLAB)
			if floor_mat.albedo_texture != null:
				_check(post_mat.albedo_texture == floor_mat.albedo_texture, "corner post did not use the floor texture")
			else:
				_check(post_mat.albedo_color.is_equal_approx(BuildingTier.color_for(2, BuildTypes.Kind.SLAB)), "corner post did not follow the floor colour")
		_check(system.state.display_tier(post) == 2 and post.tier == 1, "corner post stored its own wood tier")
		var before := wall.health
		system.authority.apply_bullet(post.id, 20, Vector3.ZERO, "post-chip")
		_check(wall.health == before - DamageSystem.scale(20, DamageCatalog.for_kind(BuildTypes.Kind.WALL).bullet_factor), "a shot on the post did not hurt the wall")
		_check(post.health == post.max_health, "the post kept its own damage")
	system.authority.apply_bullet(wall.id, 40, Vector3.ZERO, "tier-chip")
	_check(wall.health < wall.max_health, "chip did not land")
	var stone := system.authority.upgrade(wall.id)
	_check(bool(stone.get("ok", false)) and wall.tier == 3 and wall.health == 800, "upgrade did not heal to the next tier")
	for _step in 3:
		system.authority.upgrade(wall.id)
	_check(wall.tier == 6 and wall.max_health == 8000 and wall.health == 8000, "did not reach composite")
	var composite := mesh.get_surface_override_material(0) as StandardMaterial3D
	_check(composite != null and composite.albedo_color.is_equal_approx(BuildingTier.color_for(6, BuildTypes.Kind.WALL)), "composite wall was not distinct")
	var capped := system.authority.upgrade(wall.id)
	_check(not bool(capped.get("ok", false)) and wall.tier == 6, "composite accepted another upgrade")
	_built(system, "floor_1x1", Vector2i(4, 0))
	_built(system, "floor_1x1", Vector2i(4, -1))
	var brick := system.authority.request_place(RoomPlacer.make_request("wall", Vector2i(4, 0), 0, 0, BuildTypes.AXIS_X, 0, Vector2i.ZERO, 3))
	_check(bool(brick.get("ok", false)), "brick wall was not built: %s" % brick.get("reason", ""))
	var brick_wall := _edge(system, Vector4i(4, 0, 0, BuildTypes.AXIS_X))
	_check(brick_wall != null and brick_wall.tier == 3 and brick_wall.max_health == 800, "the selected build tier was ignored")
	var floor_id := system.state.slab_at(GridSystem.slab_key(Vector2i(4, 0), 0))
	var floor_mesh := system.world.node_for(floor_id).get_node("Mesh") as MeshInstance3D if floor_id != 0 else null
	var floor_mat := floor_mesh.get_surface_override_material(0) as StandardMaterial3D if floor_mesh != null else null
	_check(floor_mat != null and floor_mat.albedo_color.is_equal_approx(BuildingTier.color_for(1, BuildTypes.Kind.SLAB)), "floor lost its darker tint")
	_audit(system, "after upgrades")


func _component_id(collider: Object) -> int:
	if collider != null and collider.has_meta(&"component_id"):
		return int(collider.get_meta(&"component_id"))
	return 0
