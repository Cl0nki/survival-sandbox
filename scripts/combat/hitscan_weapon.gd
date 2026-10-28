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

var last_feedback := "none"
var _cooldown := 0.0


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func is_ready() -> bool:
	return _cooldown <= 0.0


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
	var result := resolve_shot(world.direct_space_state, origin, direction, range_meters)
	result["damaged"] = _apply_local_damage(result)
	last_feedback = _describe(result)
	ShotVisual.spawn(_visual_parent(), origin, result["point"], result["damaged"])
	shot_resolved.emit(origin, result["point"], result["damaged"])


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
