extends RefCounted
class_name SpawnPoints

## South deployables tile. Clear of the deployables chest and the other showcase chests.
## Separation is above two capsule diameters so spawned bodies do not overlap.

const POINTS: Array[Vector3] = [
	Vector3(-3.0, 0.15, 8.0),
	Vector3(0.0, 0.15, 8.0),
	Vector3(3.0, 0.15, 8.0),
	Vector3(-3.0, 0.15, 11.0),
	Vector3(0.0, 0.15, 11.0),
	Vector3(3.0, 0.15, 11.0),
	Vector3(-3.0, 0.15, 14.0),
	Vector3(0.0, 0.15, 14.0),
	Vector3(3.0, 0.15, 14.0),
	Vector3(0.0, 0.15, 5.0),
]

const MIN_SEPARATION := 2.0


static func separated(min_distance: float = MIN_SEPARATION) -> bool:
	for i in POINTS.size():
		for j in range(i + 1, POINTS.size()):
			if POINTS[i].distance_to(POINTS[j]) < min_distance:
				return false
	return true
