extends RefCounted
class_name AimProjector

## Client presentation. Projects the cursor onto the arena floor.
## Decision: the aim surface is the plane y = plane_y, so orbiting the camera
## cannot make the marker drift off the cursor. Milestone 5 replaces this plane
## with a floor/surface query once buildings have multiple heights.
## The server must not trust this point. Milestone 2 validates a direction.

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
