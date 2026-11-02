extends RefCounted
class_name SpawnPoints

## South-west deployables tile. Clear of the station chests.
## Separation is above two capsule diameters so spawned bodies do not overlap.

const POINTS: Array[Vector3] = [
	Vector3(-18.0, 0.15, 12.2),
	Vector3(-15.0, 0.15, 12.2),
	Vector3(-12.0, 0.15, 12.2),
	Vector3(-18.0, 0.15, 14.6),
	Vector3(-15.0, 0.15, 14.6),
	Vector3(-12.0, 0.15, 14.6),
	Vector3(-18.0, 0.15, 18.2),
	Vector3(-15.0, 0.15, 18.2),
	Vector3(-12.0, 0.15, 18.2),
]


const MIN_SEPARATION := 2.0


static func separated(min_distance: float = MIN_SEPARATION) -> bool:
	for i in POINTS.size():
		for j in range(i + 1, POINTS.size()):
			if POINTS[i].distance_to(POINTS[j]) < min_distance:
				return false
	return true
