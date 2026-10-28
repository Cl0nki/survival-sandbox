extends RefCounted
class_name SpawnPoints

## Fixed south-yard pads. They sit clear of the divider, both crates, and both dummies.
## Separation is above two capsule diameters so spawned bodies do not overlap.

const POINTS: Array[Vector3] = [
	Vector3(-6, 0.15, 10),
	Vector3(6, 0.15, 10),
	Vector3(-10, 0.15, 8),
	Vector3(10, 0.15, 8),
	Vector3(-6, 0.15, 13),
	Vector3(6, 0.15, 13),
	Vector3(0, 0.15, 12),
	Vector3(-12, 0.15, 12),
	Vector3(12, 0.15, 12),
	Vector3(0, 0.15, 8),
]

const MIN_SEPARATION := 2.0


static func separated(min_distance: float = MIN_SEPARATION) -> bool:
	for i in POINTS.size():
		for j in range(i + 1, POINTS.size()):
			if POINTS[i].distance_to(POINTS[j]) < min_distance:
				return false
	return true
