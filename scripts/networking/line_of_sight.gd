extends RefCounted
class_name LineOfSight

## Server-only sight test. A ray between the two eye points must reach the
## target without hitting world geometry, and the eyes must be inside the
## configured distance. If that center ray hits a wall, two more rays check
## points beside the target, offset by VISIBILITY_EDGE_MARGIN of the
## distance. A player only slightly past a corner stays visible. A player
## standing fully behind a wall does not. Clients never call this to decide
## replication.

const EYE_CLEARANCE := 0.15

static func can_see(
	space: PhysicsDirectSpaceState3D,
	from_eye: Vector3,
	to_eye: Vector3,
	max_distance: float
) -> bool:
	if space == null or max_distance <= 0.0:
		return false
	if not NetConfig.finite_vector(from_eye) or not NetConfig.finite_vector(to_eye):
		return false
	var span := from_eye.distance_to(to_eye)
	if span > max_distance:
		return false
	if _reaches(space, from_eye, to_eye):
		return true
	var radius := span * NetConfig.VISIBILITY_EDGE_MARGIN
	if radius <= 0.02:
		return false
	var flat := Vector3(to_eye.x - from_eye.x, 0.0, to_eye.z - from_eye.z)
	if flat.length_squared() < 0.0001:
		return false
	var side := flat.cross(Vector3.UP).normalized()
	return (
		_reaches(space, from_eye, to_eye + side * radius)
		or _reaches(space, from_eye, to_eye - side * radius)
	)


static func _reaches(
	space: PhysicsDirectSpaceState3D,
	from_eye: Vector3,
	to_eye: Vector3
) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from_eye, to_eye)
	query.collision_mask = PhysicsLayers.WORLD
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var point: Vector3 = hit["position"]
	return point.distance_to(to_eye) <= EYE_CLEARANCE
