extends SceneTree

## Headless checks for Phase 4 (authoritative building replication).
## godot --headless --path <project> --script res://tests/building_phase4.gd
##
## One process is the server. Each "client" is a replica BuildingSystem that
## applies only the packets the server addressed to that peer.

var _failures := PackedStringArray()
var _checks := 0
var _section := ""
var _node_reason := ""
var _port := 0
var _seq := 0


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		print("BUILDING_PHASE4 timed out in section ", _section)
		quit(2), CONNECT_ONE_SHOT)
	await _body()
	print("checks=%d failures=%d" % [_checks, _failures.size()])
	for failure in _failures:
		print("FAIL ", failure)
	if _failures.is_empty():
		print("BUILDING_PHASE4_OK")
		quit(0)
	else:
		quit(1)


func _body() -> void:
	var packed := load("res://scenes/world/test_arena.tscn") as PackedScene
	if packed == null:
		_fail("test arena failed to load")
		return
	var peer := _listen()
	if peer == null:
		_fail("could not bind a server port")
		return
	root.get_multiplayer().multiplayer_peer = peer
	var arena := packed.instantiate()
	arena.force_mode = NetConfig.MODE_SERVER
	root.add_child(arena)
	for _frame in 5:
		await physics_frame
	var net := arena.get_node("GameNet") as GameNet
	var system := arena.get_node("BuildingSystem") as BuildingSystem
	if net == null or system == null or not system.authoritative or system.relay == null:
		_fail("server building was not created")
		return
	net._spawn_authority(2)
	net._spawn_authority(3)
	for _frame in 8:
		await physics_frame
	var mirror_a := _mirror(arena, "ClientA")
	var mirror_b := _mirror(arena, "ClientB")
	_section = "authority refuses a client write"
	var before := system.state.checksum()
	system.authoritative = false
	system.authority.writes_enabled = false
	var body := _first_body(system)
	if body != null:
		_check(not body.receive_damage(40, Vector3.ZERO), "a non-authority body applied damage")
	var denied: Dictionary = system.authority.request_place({"blueprint": "room", "anchor": Vector2i.ZERO, "size": Vector2i.ONE}, 2)
	_check(not bool(denied.get("ok", true)), "client request_place was accepted")
	_check(system.state.checksum() == before, "a refused write changed state")
	system.authoritative = true
	system.authority.writes_enabled = true

	_section = "two clients place adjacent rooms"
	_tool(net, 2, 1)
	_tool(net, 3, 1)
	var first := _place(system, 2, "room", Vector2i(0, 0), Vector2i.ONE)
	_check(bool(first.get("ok", false)) and bool(first.get("changed", false)), "peer 2 room failed: %s" % first.get("reason", ""))
	_deliver(system, 2, mirror_a)
	_deliver(system, 3, mirror_b)
	var second := _place(system, 3, "room", Vector2i(1, 0), Vector2i.ONE)
	_check(bool(second.get("ok", false)) and bool(second.get("changed", false)), "peer 3 room failed: %s" % second.get("reason", ""))
	_deliver(system, 2, mirror_a)
	_deliver(system, 3, mirror_b)
	_check(system.state.count_kind(BuildTypes.Kind.WALL) == 7, "adjacent rooms did not share one wall (%d)" % system.state.count_kind(BuildTypes.Kind.WALL))
	_check(_same(system, mirror_a) and _same(system, mirror_b), "clients diverged after two rooms")
	var nodes_ok := _nodes_match(mirror_a) and _nodes_match(mirror_b)
	_check(nodes_ok, "replica nodes do not match the logical pieces (%s)" % _node_reason)
	var spawned := mirror_a.world.spawned_total
	_deliver(system, 2, mirror_a)
	_check(mirror_a.world.spawned_total == spawned, "replaying an empty delivery spawned nodes")

	_section = "duplicate and conflicting requests"
	var repeated := _place(system, 2, "room", Vector2i(0, 0), Vector2i.ONE)
	_check(bool(repeated.get("ok", false)) and not bool(repeated.get("changed", false)), "rebuilding the same room changed state")
	var stale := system.relay.handle_place(2, _seq, _request("room", Vector2i(0, 0), Vector2i.ONE))
	_check(not bool(stale.get("ok", true)) and str(stale.get("reason", "")) == "Repeated request", "duplicate seq was accepted (%s)" % stale.get("reason", ""))
	var stranger := system.relay.handle_place(9, 1, _request("room", Vector2i(4, 0), Vector2i.ONE))
	_check(str(stranger.get("reason", "")) == "No player", "unknown sender was not rejected (%s)" % stranger.get("reason", ""))
	_tool(net, 2, 0)
	var unarmed := _place(system, 2, "room", Vector2i(4, 0), Vector2i.ONE)
	_check(str(unarmed.get("reason", "")) == "Wrong tool", "pistol placed a room (%s)" % unarmed.get("reason", ""))
	_tool(net, 2, 1)
	var nonsense := _place(system, 2, "not_a_blueprint", Vector2i(4, 0), Vector2i.ONE)
	_check(not bool(nonsense.get("ok", true)), "unknown blueprint was built")
	var far := _place(system, 2, "room", Vector2i(16, 16), Vector2i.ONE)
	_check(str(far.get("reason", "")) == "Too far", "distant room was not rejected (%s)" % far.get("reason", ""))
	_check(_same(system, mirror_a), "rejected requests replicated a change")
	system.relay.clear_rate(2)
	var limited := 0
	for _try in 12:
		var burst := _place(system, 2, "room", Vector2i(0, 0), Vector2i.ONE)
		if str(burst.get("reason", "")) == "Too many requests":
			limited += 1
	_check(limited >= 1, "the request rate was not limited")
	system.relay.clear_rate(2)
	system.relay.clear_rate(3)

	_section = "damage, repair, blast, and duplicate shots"
	var wall := _near_wall(system, Vector2i(0, 0))
	_check(wall != null, "no wall to shoot")
	if wall == null:
		return
	var health_before := wall.health
	system.authority.apply_bullet(wall.id, 20, Vector3(0.2, 1.0, 0.2), "shot-a")
	system.authority.apply_bullet(wall.id, 20, Vector3(0.2, 1.0, 0.2), "shot-a")
	_check(wall.health == health_before - _taken(wall, 20), "duplicate shot id applied twice (%d -> %d)" % [health_before, wall.health])
	system.authority.apply_bullet(wall.id, 20, Vector3(0.25, 1.0, 0.2), "shot-b")
	var damage_packet := _one(system, 2)
	_check((damage_packet.get("upserts", []) as Array).is_empty(), "a bullet resent whole pieces")
	_check(not (damage_packet.get("health", []) as Array).is_empty(), "a bullet sent no health")
	BuildingRelay.present(mirror_a, damage_packet)
	_deliver(system, 3, mirror_b)
	_check(_same(system, mirror_a) and _same(system, mirror_b), "damage did not match on both clients")
	_check(mirror_a.state.get_component(wall.id).health == wall.health, "clients kept a different wall health")
	_tool(net, 2, 3)
	var repaired := system.relay.handle_repair(2, _next_seq(), wall.id)
	_check(bool(repaired.get("ok", false)) and wall.health == wall.max_health, "repair failed: %s" % repaired.get("reason", ""))
	_deliver(system, 2, mirror_a)
	_deliver(system, 3, mirror_b)
	_check(mirror_a.state.get_component(wall.id).health == wall.max_health, "repair did not replicate")
	_audit(system, "after repair")

	_section = "unchanged state is not resent"
	var quiet := system.state.checksum()
	system.relay.flush()
	var extra := system.relay.take_delivered(2)
	_check(extra.is_empty(), "a flush with no change sent %d packets" % extra.size())
	_check(system.state.checksum() == quiet, "an empty flush edited state")

	system.relay.clear_rate(2)
	_tool(net, 2, 1)
	_section = "collapse replicates and the client does not decide it"
	var span := system.config.collapse_span_sec
	var delay := system.config.collapse_delay_sec
	system.config.collapse_span_sec = 0.0
	system.config.collapse_delay_sec = 0.0
	var collapse_cell := Vector2i(-6, 4)
	var collapse_room := _place(system, 2, "room", collapse_cell, Vector2i.ONE)
	_check(bool(collapse_room.get("ok", false)), "collapse room failed: %s" % collapse_room.get("reason", ""))
	_deliver(system, 2, mirror_a)
	_deliver(system, 3, mirror_b)
	var ceiling := system.state.slab_at(GridSystem.slab_key(collapse_cell, 1))
	_check(ceiling != 0, "the room has no ceiling")
	var lower := _walls_of(system, 0, collapse_cell)
	_check(lower.size() == 4, "room walls changed (%d)" % lower.size())
	for index in lower.size():
		var piece: BuildComponent = lower[index]
		if system.state.get_component(piece.id) == null:
			continue
		system.authority.apply_bullet(piece.id, 10000, Vector3.ZERO, "drop-%d" % piece.id)
	_check(system.state.slab_at(GridSystem.slab_key(collapse_cell, 1)) == 0, "the ceiling did not fall on the server")
	_check(mirror_a.state.get_component(ceiling) != null, "the client dropped the ceiling before the server said so")
	_deliver(system, 2, mirror_a)
	_deliver(system, 3, mirror_b)
	_check(mirror_a.state.get_component(ceiling) == null and _same(system, mirror_a), "collapse did not replicate")
	system.config.collapse_span_sec = span
	system.config.collapse_delay_sec = delay
	_audit(system, "after collapse")

	_section = "falling visuals travel with the removal"
	_tool(net, 2, 1)
	var propped := _place(system, 2, "floor_1x1", Vector2i(5, 0), Vector2i.ZERO)
	_check(bool(propped.get("ok", false)), "floor for the falling test failed: %s" % propped.get("reason", ""))
	var edged := _place(system, 2, "wall", Vector2i(5, 0), Vector2i.ZERO, BuildTypes.AXIS_X)
	_check(bool(edged.get("ok", false)), "wall for the falling test failed: %s" % edged.get("reason", ""))
	_deliver(system, 2, mirror_a)
	var falling_wall := system.state.edges.component_at(Vector4i(5, 0, 0, BuildTypes.AXIS_X))
	_check(falling_wall != 0 and mirror_a.world.node_for(falling_wall) != null, "falling wall was not on the client")
	if falling_wall != 0:
		system.state.collapse_pieces([falling_wall], true, 0.14)
		var falling_packet := _one(system, 2)
		var falling_ids: Array = falling_packet.get("falling", [])
		_check(falling_ids.has(falling_wall), "falling removal was sent as an ordinary delete")
		var debris_children := mirror_a.debris.get_child_count()
		BuildingRelay.present(mirror_a, falling_packet)
		_check(mirror_a.world.node_for(falling_wall) == null, "falling wall stayed in the building")
		_check(mirror_a.debris.get_child_count() > debris_children, "falling wall was deleted instead of released")
		_deliver(system, 3, mirror_b)

	system.relay.clear_rate(2)
	_section = "a blast hits several pieces"
	_tool(net, 2, 1)
	var blast_floor := _place(system, 2, "floor_1x1", Vector2i(-4, 8), Vector2i.ZERO)
	var blast_wall := _place(system, 2, "wall", Vector2i(-4, 8), Vector2i.ZERO, BuildTypes.AXIS_X)
	_check(bool(blast_floor.get("ok", false)), "blast floor failed: %s" % blast_floor.get("reason", ""))
	_check(bool(blast_wall.get("ok", false)), "blast wall failed: %s" % blast_wall.get("reason", ""))
	_deliver(system, 2, mirror_a)
	_tool(net, 2, 2)
	var blast_id := system.state.edges.component_at(Vector4i(-4, 8, 0, BuildTypes.AXIS_X))
	var blast_node := system.world.node_for(blast_id)
	_check(blast_node != null, "blast wall has no node")
	if blast_node != null:
		var origin := blast_node.global_position + Vector3(0, 1.0, 0)
		var blasted := system.relay.handle_blast(2, _next_seq(), origin)
		_check(bool(blasted.get("ok", false)), "blast was rejected: %s" % blasted.get("reason", ""))
		var hits: Array = blasted.get("hits", [])
		_check(hits.size() >= 2, "blast hit %d pieces" % hits.size())
		_deliver(system, 2, mirror_a)
		_deliver(system, 3, mirror_b)
		_check(_same(system, mirror_a) and _same(system, mirror_b), "blast results diverged")
		_audit(system, "after blast")

	_section = "stairs keep their ids and rules"
	_tool(net, 2, 1)
	system.relay.clear_rate(2)
	for step in 3:
		var slab := _place(system, 2, "floor_1x1", Vector2i(-2, 6 + step), Vector2i.ZERO)
		_check(bool(slab.get("ok", false)), "stair floor %d failed: %s" % [step, slab.get("reason", "")])
	var stairs := _place(system, 2, "stairs_straight", Vector2i(-2, 6), Vector2i.ZERO)
	_check(bool(stairs.get("ok", false)), "stairs failed: %s" % stairs.get("reason", ""))
	_deliver(system, 2, mirror_a)
	_deliver(system, 3, mirror_b)
	_check(_same(system, mirror_a) and system.state.edges.size() == mirror_a.state.edges.size(), "stair rules did not match")

	_section = "chunks withhold distant pieces and late join catches up"
	var saved_a := net.debug_position(2)
	var distant := system.authority.request_place(_request("room", Vector2i(-17, -17), Vector2i.ONE), 2)
	_check(bool(distant.get("ok", false)), "distant room failed on the server: %s" % distant.get("reason", ""))
	var hidden := _one(system, 2)
	var hidden_ids := _ids(hidden)
	var far_id := system.state.slab_at(GridSystem.slab_key(Vector2i(-17, -17), 0))
	_check(far_id != 0 and not hidden_ids.has(far_id), "a distant room was sent to a player who cannot reach it")
	_check(system.state.get_component(far_id) != null, "withholding a chunk deleted the server piece")
	net.debug_place(2, Vector3(-16.2, 0.15, -16.2))
	for _frame in 3:
		await physics_frame
	system.relay.flush()
	var revealed := _one(system, 2)
	_check(_ids(revealed).has(far_id), "walking up to a chunk did not send it")
	BuildingRelay.present(mirror_a, revealed)
	_check(mirror_a.state.get_component(far_id) != null and mirror_a.state.get_component(far_id).id == far_id, "the revealed piece changed id")
	net.debug_place(2, Vector3(0, 0.15, 8))
	for _frame in 3:
		await physics_frame
	system.relay.flush()
	var dropped := _one(system, 2)
	var dropped_ids: Array = dropped.get("quiet_removed", [])
	_check(dropped_ids.has(far_id), "leaving a chunk did not drop it on the client")
	_check(system.state.get_component(far_id) != null, "leaving a chunk deleted the server piece")
	BuildingRelay.present(mirror_a, dropped)
	_check(mirror_a.state.get_component(far_id) == null, "the client kept a chunk it walked away from")
	net._spawn_authority(4)
	for _frame in 5:
		await physics_frame
	var mirror_c := _mirror(arena, "ClientC")
	_deliver(system, 4, mirror_c)
	_check(mirror_c.state.get_component(far_id) == null, "a late joiner received a chunk they are not standing in")
	_check(mirror_c.state.slab_at(GridSystem.slab_key(Vector2i(1, 0), 0)) != 0, "a late joiner missed the nearby room")
	net.debug_place(2, saved_a)

	_section = "disconnect keeps the building and drops the peer"
	var count := system.state.component_count()
	net._release_player(3)
	var after_leave := system.relay.handle_place(3, 1, _request("room", Vector2i(6, 0), Vector2i.ONE))
	_check(str(after_leave.get("reason", "")) == "No player", "a disconnected peer still built (%s)" % after_leave.get("reason", ""))
	_check(system.state.component_count() == count, "disconnect changed the building")
	_deliver(system, 2, mirror_a)

	_section = "costs are checked on the server"
	system.config.require_resources = true
	_tool(net, 2, 1)
	var poor := _place(system, 2, "floor_1x1", Vector2i(-5, 9), Vector2i.ZERO)
	_check(not bool(poor.get("ok", true)) and str(poor.get("reason", "")).begins_with("Needs"), "a free floor was placed without scrap (%s)" % poor.get("reason", ""))
	net.debug_grant(2, "scrap_metal", 40)
	var had := net.debug_inventory(2).count_item("scrap_metal")
	var paid := _place(system, 2, "floor_1x1", Vector2i(-5, 9), Vector2i.ZERO)
	_check(bool(paid.get("ok", false)), "paid floor failed: %s" % paid.get("reason", ""))
	var spent := had - net.debug_inventory(2).count_item("scrap_metal")
	_check(spent > 0, "the server did not charge scrap")
	system.config.require_resources = false
	_deliver(system, 2, mirror_a)
	var paid_id := system.state.slab_at(GridSystem.slab_key(Vector2i(-5, 9), 0))
	_check(paid_id != 0 and mirror_a.state.get_component(paid_id) != null, "the paid floor did not replicate")

	_section = "a shot through the server hits the wall"
	_tool(net, 2, 0)
	var target := _near_wall(system, Vector2i(1, 0))
	if target != null and system.world.node_for(target.id) != null:
		var player := net.debug_player(2)
		net.debug_place(2, system.world.node_for(target.id).global_position + Vector3(0, 0, 2.0))
		for _frame in 4:
			await physics_frame
		var aim := (system.world.node_for(target.id).global_position + Vector3(0, 1.2, 0) - player.shot_origin()).normalized()
		var before_shot := system.state.checksum()
		net.debug_reset_cooldown(2)
		net._handle_fire(2, 1, aim, 0.0, 0.0, 0.0)
		_check(system.state.checksum() != before_shot, "server shot did not damage the wall")
		_deliver(system, 2, mirror_a)
		if system.state.get_component(target.id) != null:
			_check(mirror_a.state.get_component(target.id).health == target.health, "shot damage did not replicate")

	system.relay.clear_rate(2)
	_section = "building walls block sight"
	_tool(net, 2, 1)
	net.debug_place(2, Vector3(0.5, 0.15, 2.2))
	for x in range(-3, 4):
		system.relay.clear_rate(2)
		var floor_result := _place(system, 2, "floor_1x1", Vector2i(x, 4), Vector2i.ZERO)
		_check(bool(floor_result.get("ok", false)), "sight floor %d failed: %s" % [x, floor_result.get("reason", "")])
		var wall_result := _place(system, 2, "wall", Vector2i(x, 4), Vector2i.ZERO, BuildTypes.AXIS_X)
		_check(bool(wall_result.get("ok", false)), "sight wall %d failed: %s" % [x, wall_result.get("reason", "")])
	net.debug_place(2, Vector3(0.5, 0.15, 2.2))
	net.debug_place(4, Vector3(0.5, 0.15, 6.2))
	for _frame in 5:
		await physics_frame
	net._refresh_visibility()
	_check(not net.debug_visible(2, 4), "players saw each other through the wall")
	_audit(system, "final")
	_check(mirror_a.world.node_count() == mirror_a.state.component_count(), "replica node count drifted")


func _place(system: BuildingSystem, sender: int, blueprint: String, anchor: Vector2i, size: Vector2i, axis: int = 0) -> Dictionary:
	return system.relay.handle_place(sender, _next_seq(), _request(blueprint, anchor, size, axis))


func _request(blueprint: String, anchor: Vector2i, size: Vector2i, axis: int = 0) -> Dictionary:
	return {
		"blueprint": blueprint,
		"anchor": anchor,
		"rotation": 0,
		"level": 0,
		"axis": axis,
		"target": 0,
		"size": size,
	}


func _next_seq() -> int:
	_seq += 1
	return _seq


func _tool(net: GameNet, peer_id: int, index: int) -> void:
	var player := net.debug_player(peer_id)
	if player != null:
		player.hotbar_index = index


func _deliver(system: BuildingSystem, peer_id: int, mirror: BuildingSystem) -> String:
	system.relay.flush()
	var text := ""
	for packet in system.relay.take_delivered(peer_id):
		text += var_to_str(packet)
		BuildingRelay.present(mirror, packet)
	return text


func _one(system: BuildingSystem, peer_id: int) -> Dictionary:
	system.relay.flush()
	var packets := system.relay.take_delivered(peer_id)
	if packets.is_empty():
		return {}
	return packets[packets.size() - 1]


func _ids(packet: Dictionary) -> Dictionary:
	var found := {}
	for record in packet.get("upserts", []):
		if record is Dictionary:
			found[int(record.get("id", 0))] = true
	return found


func _same(server: BuildingSystem, mirror: BuildingSystem) -> bool:
	return server.state.checksum() == mirror.state.checksum()


func _nodes_match(mirror: BuildingSystem) -> bool:
	_node_reason = ""
	if mirror.world.node_count() != mirror.state.component_count():
		_node_reason = "nodes %d pieces %d" % [mirror.world.node_count(), mirror.state.component_count()]
		return false
	for component: BuildComponent in mirror.state.components.values():
		var node := mirror.world.node_for(component.id)
		if node == null:
			_node_reason = "missing node %s" % component.describe()
			return false
		var expected := mirror.grid.component_transform(component)
		if node.transform.origin.distance_to(expected.origin) > 0.001:
			_node_reason = "transform %s %s vs %s" % [component.describe(), node.transform.origin, expected.origin]
			return false
		var body := node.get_node_or_null("Body") as StaticBody3D
		if body != null and body.collision_layer != 0:
			_node_reason = "collision layer %d on %s" % [body.collision_layer, component.describe()]
			return false
	return true


func _mirror(arena: Node, node_name: String) -> BuildingSystem:
	var mirror := BuildingSystem.new()
	mirror.name = node_name
	mirror.force_replica = true
	arena.add_child(mirror)
	mirror.world.collision_enabled = false
	return mirror


func _near_wall(system: BuildingSystem, cell: Vector2i) -> BuildComponent:
	for edge in GridSystem.cell_edges(cell, 0):
		var component := system.state.get_component(system.state.edges.component_at(edge))
		if component != null and component.kind == BuildTypes.Kind.WALL:
			return component
	return null


func _walls_of(system: BuildingSystem, level: int, cell: Vector2i) -> Array[BuildComponent]:
	var found: Array[BuildComponent] = []
	for edge in GridSystem.cell_edges(cell, level):
		var component := system.state.get_component(system.state.edges.component_at(edge))
		if component != null and component.kind == BuildTypes.Kind.WALL:
			found.append(component)
	return found


func _taken(component: BuildComponent, raw: int) -> int:
	return DamageSystem.scale(raw, DamageCatalog.for_kind(component.kind).bullet_factor)


func _first_body(system: BuildingSystem) -> BuildingPieceBody:
	var bodies := system.find_children("*", "BuildingPieceBody", true, false)
	if bodies.is_empty():
		return null
	return bodies[0] as BuildingPieceBody


func _audit(system: BuildingSystem, label: String) -> void:
	var report := GeometryAudit.run(system)
	if bool(report.get("ok", false)):
		_check(true, "")
		return
	var issues: Array = report.get("issues", [])
	_check(false, "%s audit: %s" % [label, str(issues[0]) if not issues.is_empty() else "failed"])


func _listen() -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	for port in range(38000, 38040):
		if peer.create_server(port, 4) == OK:
			_port = port
			return peer
	return null


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("[%s] %s" % [_section, message])


func _fail(message: String) -> void:
	_failures.append(message)
	print("FAIL ", message)
