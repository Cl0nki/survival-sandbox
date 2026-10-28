extends RefCounted
class_name AimProjector

## Client presentation. The cursor ray hits world geometry so the weapon can
## aim up and down. project() remains the flat floor query used by the local check.
## The server must not trust this point. It receives a direction only.

static func query(
	camera: Camera3D,
	screen_position: Vector2,
	space: PhysicsDirectSpaceState3D,
	exclude: Array = []
) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var missed := {
		"point": origin + direction * 40.0,
		"normal": -direction,
	}
	if space != null and direction.length_squared() > 0.000001:
		var ray := PhysicsRayQueryParameters3D.create(origin, origin + direction * 80.0)
		ray.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PLAYER | PhysicsLayers.DAMAGEABLE | PhysicsLayers.BUILDING
		ray.collide_with_areas = false
		ray.collide_with_bodies = true
		ray.hit_from_inside = false
		var skip: Array[RID] = []
		for item in exclude:
			if item is RID:
				skip.append(item)
		ray.exclude = skip
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			return {"point": hit["position"], "normal": hit["normal"]}
	var floor_hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if floor_hit != null:
		return {"point": floor_hit, "normal": Vector3.UP}
	return missed


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
