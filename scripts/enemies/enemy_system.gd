extends Node
class_name EnemySystem

## Home of enemy AI and creature replication.
##
## Server: spawns creatures, advances them every physics tick, drops their
## loot, and sends each player only the creatures that player can see (same
## distance + line-of-sight rule as other players).
## Client: turns those packets into CreatureView puppets. No rules run here.
##
## GameNet owns an instance on both sides and only routes RPCs to it, so
## enemy code does not grow game_net.gd.

const _Sight = preload("res://scripts/networking/line_of_sight.gd")

const SNAPSHOT_EVERY := 3
const SNAPSHOT_STRIDE := 5
const CORPSE_SEC := 12.0
const RESPAWN_SEC := 60.0
const MAX_CREATURES := 12
const HOGS_DEBUG_MAP := 2
const HOGS_SURVIVAL_MAP := 3
const SPAWN_AWAY_FROM_PLAYERS := 14.0
const SPAWN_AWAY_FROM_PADS := 12.0
const SPAWN_AWAY_FROM_CREATURES := 6.0
const SPAWN_TRIES := 40

var net: GameNet
## The dedicated server turns this on. Tests spawn creatures by hand.
var auto_spawn := false
var hurt_count := 0

var _creatures: Dictionary = {}
var _next_id := 1
var _respawns: Array[float] = []
var _spawn_clock := 1.0
var _publish_clock := 0
var _seen: Dictionary = {}
var _views: Dictionary = {}
var _folder: Node3D


func bind(game_net: GameNet) -> void:
	net = game_net
	add_to_group(&"enemy_system")


func _physics_process(delta: float) -> void:
	if net == null or not net.multiplayer.is_server():
		return
	advance(delta)


# ---------------------------------------------------------------- server

func enemy_count() -> int:
	var count := 0
	for creature in _creatures.values():
		if not (creature as Creature).is_dead():
			count += 1
	return count


func creature_by_id(id: int) -> Creature:
	return _creatures.get(id) as Creature


func creatures() -> Array:
	return _creatures.values()


func pending_respawns() -> int:
	return _respawns.size()


## Living players, for AI to look at.
func players() -> Array[PlayerController]:
	var list: Array[PlayerController] = []
	if net == null:
		return list
	for value in net.authority_players().values():
		var player := value as PlayerController
		if player != null and is_instance_valid(player) and player.health > 0:
			list.append(player)
	return list


func player_for(peer_id: int) -> PlayerController:
	for player in players():
		if player.network_id == peer_id:
			return player
	return null


func hurt_player(player: PlayerController, amount: int, _source: Creature) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.receive_damage(amount, player.global_position):
		hurt_count += 1
		net.replicate_health(player)


func spawn_hog(pos: Vector3) -> Hog:
	if _creatures.size() >= MAX_CREATURES:
		return null
	var hog := Hog.new()
	hog.name = "Hog_%d" % _next_id
	hog.system = self
	_creatures_folder().add_child(hog)
	hog.setup_hog(_next_id, pos)
	_register(hog)
	return hog


func advance(delta: float) -> void:
	for value in _creatures.values():
		var creature := value as Creature
		creature.advance(delta)
		if creature.is_dead():
			creature.corpse_left -= delta
			if creature.corpse_left <= 0.0:
				_remove(creature)
	if auto_spawn:
		_advance_respawns(delta)
	_publish_clock += 1
	if _publish_clock >= SNAPSHOT_EVERY:
		_publish_clock = 0
		_publish()


func find_spawn() -> Variant:
	var world := net.get_viewport().world_3d
	if world == null or world.direct_space_state == null:
		return null
	var space := world.direct_space_state
	var low := 10.0
	var high := 32.0
	if net.map_id() != NetConfig.MAP_SURVIVAL:
		low = 6.0
		high = 17.0
	var shape := CapsuleShape3D.new()
	shape.radius = Hog.RADIUS + 0.05
	shape.height = Hog.HEIGHT
	for _try in SPAWN_TRIES:
		var angle := randf_range(-PI, PI)
		var reach := randf_range(low, high)
		var flat := Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
		var ray := PhysicsRayQueryParameters3D.create(flat + Vector3.UP * 3.0, flat + Vector3.DOWN * 1.0)
		ray.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BUILDING
		var ground := space.intersect_ray(ray)
		if ground.is_empty():
			continue
		var floor_point: Vector3 = ground["position"]
		var floor_normal: Vector3 = ground["normal"]
		if floor_point.y < -0.05 or floor_point.y > 0.6 or floor_normal.y < 0.9:
			continue
		if not _spawn_is_clear(space, shape, floor_point):
			continue
		return floor_point + Vector3.UP * 0.02
	return null


func _spawn_is_clear(space: PhysicsDirectSpaceState3D, shape: Shape3D, floor_point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, floor_point + Vector3.UP * (Hog.HEIGHT * 0.5 + 0.1))
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BUILDING
	if not space.intersect_shape(query, 1).is_empty():
		return false
	for player in players():
		if _flat(player.global_position, floor_point) < SPAWN_AWAY_FROM_PLAYERS:
			return false
	for pad in SpawnPoints.POINTS:
		if _flat(pad, floor_point) < SPAWN_AWAY_FROM_PADS:
			return false
	for value in _creatures.values():
		if _flat((value as Creature).global_position, floor_point) < SPAWN_AWAY_FROM_CREATURES:
			return false
	return true


func _target_hogs() -> int:
	if net.map_id() == NetConfig.MAP_SURVIVAL:
		return HOGS_SURVIVAL_MAP
	return HOGS_DEBUG_MAP


func _advance_respawns(delta: float) -> void:
	for index in _respawns.size():
		_respawns[index] -= delta
	_spawn_clock -= delta
	if _spawn_clock > 0.0:
		return
	_spawn_clock = 1.0
	var filled := 0
	for value in _creatures.values():
		if value is Hog and not (value as Hog).is_dead():
			filled += 1
	for left in _respawns:
		if left > 0.0:
			filled += 1
	if filled >= _target_hogs():
		_drop_due_timers()
		return
	var spot: Variant = find_spawn()
	if spot == null:
		return
	if spawn_hog(spot as Vector3) != null:
		_drop_due_timers(1)


## Due timers are respawns that already came up. Spent when a hog appears.
func _drop_due_timers(limit: int = 1000) -> void:
	var removed := 0
	for index in range(_respawns.size() - 1, -1, -1):
		if removed >= limit:
			break
		if _respawns[index] <= 0.0:
			_respawns.remove_at(index)
			removed += 1

func _register(creature: Creature) -> void:
	_creatures[creature.creature_id] = creature
	_next_id += 1
	creature.health_changed.connect(_on_health_changed)
	creature.died.connect(_on_died)


func _on_health_changed(creature: Creature) -> void:
	for peer_key in _seen.keys():
		var row: Dictionary = _seen[peer_key]
		if row.has(creature.creature_id):
			net.creature_health.rpc_id(int(peer_key), creature.creature_id, creature.health)


func _on_died(creature: Creature) -> void:
	creature.corpse_left = CORPSE_SEC
	var drops := creature.roll_loot()
	for index in drops.size():
		var drop: Array = drops[index]
		var angle := TAU * float(index) / float(maxi(drops.size(), 1))
		var spot := creature.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 0.7
		net.spawn_loot(str(drop[0]), int(drop[1]), spot)
	_respawns.append(RESPAWN_SEC)


func _remove(creature: Creature) -> void:
	_creatures.erase(creature.creature_id)
	for peer_key in _seen.keys():
		var row: Dictionary = _seen[peer_key]
		if row.erase(creature.creature_id) and not net.multiplayer.get_peers().is_empty():
			net.creature_despawn.rpc_id(int(peer_key), creature.creature_id)
	creature.queue_free()


func _creatures_folder() -> Node3D:
	if _folder != null and is_instance_valid(_folder):
		return _folder
	var parent := net.get_parent()
	_folder = parent.get_node_or_null("Creatures") as Node3D
	if _folder == null:
		_folder = Node3D.new()
		_folder.name = "Creatures"
		parent.add_child(_folder)
	return _folder


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ----------------------------------------------------------- replication

## Creature ids this player may see right now.
func visible_ids_for(observer: PlayerController) -> Array[int]:
	var ids: Array[int] = []
	var world := observer.get_world_3d()
	if world == null or world.direct_space_state == null:
		return ids
	var space := world.direct_space_state
	var reach := net.view_distance()
	var origins := observer.visibility_origins()
	for value in _creatures.values():
		var creature := value as Creature
		if _flat(observer.global_position, creature.global_position) > reach:
			continue
		var points: Array[Vector3] = [
			creature.global_position + Vector3.UP * 0.45,
			creature.global_position + Vector3.UP * 0.85,
		]
		var seen := false
		for origin in origins:
			for point in points:
				if _Sight.can_see(space, origin, point, reach):
					seen = true
					break
			if seen:
				break
		if seen:
			ids.append(creature.creature_id)
	return ids


func pack(ids: Array[int]) -> Dictionary:
	var out_ids := PackedInt32Array()
	var data := PackedFloat32Array()
	for id in ids:
		var creature := _creatures.get(id) as Creature
		if creature == null:
			continue
		var pos := creature.global_position
		out_ids.append(id)
		data.append(pos.x)
		data.append(pos.y)
		data.append(pos.z)
		data.append(creature.rotation.y)
		data.append(float(creature.state))
	return {"ids": out_ids, "data": data}


func _publish() -> void:
	var peers := net.multiplayer.get_peers()
	for key in _seen.keys():
		if not peers.has(int(key)):
			_seen.erase(key)
	if peers.is_empty():
		return
	for peer_key in peers:
		var peer := int(peer_key)
		var observer := net.authority_players().get(peer) as PlayerController
		if observer == null or not is_instance_valid(observer):
			continue
		var visible := visible_ids_for(observer)
		var before: Dictionary = _seen.get(peer, {})
		var after := {}
		for id in visible:
			after[id] = true
			if before.has(id):
				continue
			var creature := _creatures[id] as Creature
			net.creature_spawn.rpc_id(
				peer, id, creature.kind, creature.global_position, creature.rotation.y,
				creature.health, creature.max_health, creature.state
			)
		for id in before.keys():
			if not after.has(id):
				net.creature_despawn.rpc_id(peer, int(id))
		_seen[peer] = after
		if visible.is_empty():
			continue
		var packet := pack(visible)
		net.creature_snapshot.rpc_id(peer, net.server_tick(), packet["ids"], packet["data"])


# ---------------------------------------------------------------- client

func view(id: int) -> CreatureView:
	return _views.get(id) as CreatureView


func view_count() -> int:
	return _views.size()


func client_spawn(id: int, kind: int, pos: Vector3, yaw: float, hp: int, max_hp: int, state_id: int) -> void:
	if id <= 0 or max_hp <= 0 or max_hp > 10000:
		return
	if not NetConfig.finite_vector(pos) or not is_finite(yaw):
		return
	var existing := _views.get(id) as CreatureView
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	var puppet := CreatureView.new()
	_creatures_folder().add_child(puppet)
	puppet.setup(id, kind, clampi(hp, 0, max_hp), max_hp, state_id, pos, yaw)
	_views[id] = puppet


func client_despawn(id: int) -> void:
	var puppet := _views.get(id) as CreatureView
	_views.erase(id)
	if puppet != null and is_instance_valid(puppet):
		puppet.queue_free()


func client_health(id: int, hp: int) -> void:
	var puppet := _views.get(id) as CreatureView
	if puppet != null and is_instance_valid(puppet):
		puppet.set_health(hp)


func client_snapshot(stamp: float, ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	if data.size() != ids.size() * SNAPSHOT_STRIDE:
		return
	for index in ids.size():
		var puppet := _views.get(ids[index]) as CreatureView
		if puppet == null or not is_instance_valid(puppet):
			continue
		var offset := index * SNAPSHOT_STRIDE
		var pos := Vector3(data[offset], data[offset + 1], data[offset + 2])
		var state_id := int(round(data[offset + 4]))
		puppet.push_pose(stamp, pos, data[offset + 3], state_id)
