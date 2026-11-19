extends Node3D
class_name HitscanWeapon

## Hitscan query shared by local play and the dedicated server.
## Local play still applies damage in try_fire(). Networked clients must not.
## The server passes an origin it derived itself and is the only networked
## caller of receive_damage(). A shot event is not damage.

signal shot_resolved(origin: Vector3, end_point: Vector3, did_damage: bool)

@export var damage: int = 34
@export var range_meters: float = 40.0
@export var cooldown_seconds: float = 0.35

## Per-weapon shape, set by configure(). A plain node keeps the pistol defaults.
var pellets := 1
var spread_deg := 0.0
var automatic := false
var melee := false
var ammo_id := ""

var last_feedback := "none"
var _cooldown := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func is_ready() -> bool:
	return _cooldown <= 0.0


## Take the stats of the weapon now in hand. The server calls this before every
## shot with the item it read from the shooter's own bag.
func configure(spec: WeaponSpec) -> void:
	if spec == null:
		return
	damage = spec.damage
	range_meters = spec.range_meters
	cooldown_seconds = spec.cooldown_seconds
	pellets = spec.pellets
	spread_deg = spec.spread_deg
	automatic = spec.automatic
	melee = spec.is_melee()
	ammo_id = spec.ammo_id


## One direction per pellet, scattered inside the spread cone. A single accurate
## shot returns the aim unchanged.
func shot_directions(direction: Vector3) -> Array[Vector3]:
	var aim := direction.normalized()
	var shots: Array[Vector3] = []
	var count := maxi(pellets, 1)
	if spread_deg <= 0.0:
		for _i in count:
			shots.append(aim)
		return shots
	for _i in count:
		shots.append(scatter(aim, spread_deg, _rng))
	return shots


## A direction inside a cone of half-angle spread_deg around aim, evenly over
## the cone's disc.
static func scatter(aim: Vector3, spread_deg: float, rng: RandomNumberGenerator) -> Vector3:
	var dir := aim.normalized()
	if spread_deg <= 0.0:
		return dir
	var helper := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side := dir.cross(helper).normalized()
	var up := side.cross(dir).normalized()
	var angle := deg_to_rad(spread_deg) * sqrt(rng.randf())
	var around := rng.randf() * TAU
	var offset := (side * cos(around) + up * sin(around)) * tan(angle)
	return (dir + offset).normalized()


func try_fire(origin: Vector3, direction: Vector3) -> void:
	## Local prototype only. Networked players send a fire request instead.
	var body := get_parent()
	if body != null and body.has_method("allows_local_fire") and not bool(body.call("allows_local_fire")):
		last_feedback = "rejected local fire"
		return
	if not is_ready():
		return
	if direction.length_squared() < 0.000001:
		return
	var world := get_world_3d()
	if world == null:
		return
	_cooldown = cooldown_seconds
	if melee:
		_swing_local(world, origin, direction)
		return
	# Local play only, so the shooter is always this player: flat, not placed in the world.
	Sfx.gunshot(origin, true)
	var space := world.direct_space_state
	var any_damaged := false
	var heard_hit := false
	var heard_impact := false
	var first_text := ""
	for pellet_dir in shot_directions(direction):
		var result := resolve_shot(space, origin, pellet_dir, range_meters)
		result["damaged"] = _apply_local_damage(result)
		var damaged := bool(result["damaged"])
		# One thud and one crack per trigger pull, not one per pellet.
		if damaged and not heard_hit:
			heard_hit = true
			Sfx.bullet_lands(origin, result["point"], true)
		elif not damaged and not heard_impact:
			heard_impact = true
			Sfx.bullet_lands(origin, result["point"], false)
		if first_text.is_empty() or (damaged and not any_damaged):
			first_text = _describe(result)
		any_damaged = any_damaged or damaged
		ShotVisual.spawn(_visual_parent(), origin, result["point"], damaged)
		shot_resolved.emit(origin, result["point"], damaged)
	last_feedback = first_text


func _swing_local(world: World3D, origin: Vector3, direction: Vector3) -> void:
	var result := resolve_melee(world.direct_space_state, origin, direction, range_meters)
	result["damaged"] = _apply_local_damage(result)
	if result["damaged"]:
		Sfx.bullet_lands(origin, result["point"], true)
	last_feedback = _describe(result)
	shot_resolved.emit(origin, result["point"], bool(result["damaged"]))


## A swing hits the nearest damageable thing in a short arc in front of the
## attacker. Three rays make it forgiving without a wide sweep. Anything that
## blocks the middle ray first, such as a wall, blocks the swing.
static func resolve_melee(
	space: PhysicsDirectSpaceState3D,
	origin: Vector3,
	direction: Vector3,
	reach: float,
	exclude: Array = []
) -> Dictionary:
	var centre := resolve_shot(space, origin, direction, reach, exclude)
	if direction.length_squared() < 0.000001:
		return centre
	var best: Dictionary = centre
	var best_distance := INF
	if _is_damageable(centre["collider"]):
		best_distance = origin.distance_to(centre["point"])
	var dir := direction.normalized()
	var wall_distance := INF
	if centre["collider"] != null and bool(centre["blocked"]):
		wall_distance = origin.distance_to(centre["point"])
	for turn in [-1.0, 1.0]:
		var edge := dir.rotated(Vector3.UP, WeaponSpec.MELEE_ARC_RAD * float(turn))
		var side := resolve_shot(space, origin, edge, reach, exclude)
		if not _is_damageable(side["collider"]):
			continue
		var distance := origin.distance_to(side["point"])
		if distance < best_distance and distance < wall_distance:
			best = side
			best_distance = distance
	return best


static func resolve_shot(
	space: PhysicsDirectSpaceState3D,
	origin: Vector3,
	direction: Vector3,
	range_meters: float = 40.0,
	exclude: Array = []
) -> Dictionary:
	var miss := {
		"collider": null,
		"point": origin,
		"normal": Vector3.UP,
		"blocked": false,
		"damaged": false,
	}
	if space == null or direction.length_squared() < 0.000001 or range_meters <= 0.0:
		return miss
	var dir := direction.normalized()
	miss["point"] = origin + dir * range_meters
	var query := PhysicsRayQueryParameters3D.create(origin, miss["point"])
	query.collision_mask = PhysicsLayers.HITS_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = false
	var skip: Array[RID] = []
	for item in exclude:
		if item is RID:
			skip.append(item)
	query.exclude = skip
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return miss
	var collider: Object = hit["collider"]
	return {
		"collider": collider,
		"point": hit["position"],
		"normal": hit["normal"],
		"blocked": not _is_damageable(collider),
		"damaged": false,
	}


static func _is_damageable(collider: Object) -> bool:
	return collider != null and collider.has_method("receive_damage")


func note_local_request() -> void:
	## Presentation cooldown only. The server enforces the real interval.
	_cooldown = cooldown_seconds
	last_feedback = "request sent"


func _apply_local_damage(result: Dictionary) -> bool:
	var collider: Object = result["collider"]
	if not _is_damageable(collider):
		return false
	return bool(collider.call("receive_damage", damage, result["point"]))


func _describe(result: Dictionary) -> String:
	var collider: Object = result["collider"]
	if result["damaged"]:
		return "hit %s" % _label_of(collider)
	if collider == null:
		return "miss"
	if _is_damageable(collider):
		return "no damage %s" % _label_of(collider)
	return "blocked by %s" % _label_of(collider)


func _label_of(collider: Object) -> String:
	var named: Variant = collider.get("display_name")
	if named != null and str(named) != "":
		return str(named)
	if collider is Node:
		return (collider as Node).name
	return "object"


func _visual_parent() -> Node:
	var tree := get_tree()
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root
