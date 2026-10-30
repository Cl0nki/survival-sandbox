extends RefCounted
class_name AimProjector

## Client presentation. The cursor ray hits world geometry so the weapon can
## aim up and down. project() remains the flat floor query used by the local check.
## The server must not trust this point. It receives a direction only.
## `ignore` skips a collider and the ray continues. Indoor aim uses it so a
## ceiling the camera is looking through does not become the target.

const _SKIP_STEPS := 16


static func query(
	camera: Camera3D,
	screen_position: Vector2,
	space: PhysicsDirectSpaceState3D,
	exclude: Array = [],
	ignore: Callable = Callable()
) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var missed := {
		"point": origin + direction * 40.0,
		"normal": -direction,
	}
	if space != null and direction.length_squared() > 0.000001:
		var hit := first_solid(
			space,
			origin,
			origin + direction * 80.0,
			PhysicsLayers.WORLD | PhysicsLayers.PLAYER | PhysicsLayers.DAMAGEABLE | PhysicsLayers.BUILDING,
			exclude,
			ignore
		)
		if not hit.is_empty():
			return {"point": hit["position"], "normal": hit["normal"], "collider": hit.get("collider")}
	var floor_hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if floor_hit != null:
		return {"point": floor_hit, "normal": Vector3.UP}
	return missed


## First solid hit from `from` to `to`. A collider `ignore` accepts is skipped.
static func first_solid(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	mask: int,
	exclude: Array = [],
	ignore: Callable = Callable()
) -> Dictionary:
	if space == null:
		return {}
	var skip: Array[RID] = []
	for item in exclude:
		if item is RID:
			skip.append(item)
	for _step in _SKIP_STEPS:
		var ray := PhysicsRayQueryParameters3D.create(from, to)
		ray.collision_mask = mask
		ray.collide_with_areas = false
		ray.collide_with_bodies = true
		ray.hit_from_inside = false
		ray.exclude = skip
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			return {}
		var collider: Object = hit.get("collider")
		if ignore.is_valid() and bool(ignore.call(collider)):
			var rid := RID()
			if collider is CollisionObject3D:
				rid = (collider as CollisionObject3D).get_rid()
			if not rid.is_valid():
				return {}
			skip.append(rid)
			continue
		return hit
	return {}


static func project(camera: Camera3D, screen_position: Vector2, plane_y: float) -> Vector3:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var hit: Variant = Plane(Vector3.UP, plane_y).intersects_ray(origin, direction)
	if hit == null:
		var flat := Vector3(direction.x, 0.0, direction.z)
		if flat.length_squared() < 0.000001:
			flat = Vector3(0.0, 0.0, -1.0)
		return Vector3(origin.x, plane_y, origin.z) + flat.normalized() * 24.0
	return hit as Vector3
