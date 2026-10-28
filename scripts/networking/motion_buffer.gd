extends RefCounted
class_name MotionBuffer

## Remote-player interpolation. Samples are stamped when they arrive.
## A large gap snaps once; ordinary updates lerp so puppets do not pop every tick.

const MAX_SAMPLES := 48
const SNAP_DISTANCE := 8.0

var _samples: Array[Dictionary] = []


func clear() -> void:
	_samples.clear()


func size() -> int:
	return _samples.size()


func push(time_sec: float, position: Vector3, yaw: float, lean: float, crouch: float = 0.0, pitch: float = 0.0) -> void:
	if not is_finite(time_sec) or not NetConfig.finite_vector(position) or not is_finite(yaw) or not is_finite(lean):
		return
	if not is_finite(crouch) or not is_finite(pitch):
		return
	if not _samples.is_empty() and time_sec < float(_samples[-1]["t"]):
		return
	_samples.append({
		"t": time_sec,
		"p": position,
		"y": yaw,
		"l": lean,
		"c": clampf(crouch, 0.0, 1.0),
		"pitch": pitch,
	})
	while _samples.size() > MAX_SAMPLES:
		_samples.remove_at(0)


func sample(render_time: float) -> Dictionary:
	if _samples.is_empty():
		return {}
	var first: Dictionary = _samples[0]
	if _samples.size() == 1 or render_time <= float(first["t"]):
		return _pose(first, true)
	var last: Dictionary = _samples[-1]
	if render_time >= float(last["t"]):
		return _pose(last, false)
	for index in range(1, _samples.size()):
		var newer: Dictionary = _samples[index]
		if float(newer["t"]) < render_time:
			continue
		var older: Dictionary = _samples[index - 1]
		var span := float(newer["t"]) - float(older["t"])
		var weight := 0.0 if span <= 0.0001 else clampf((render_time - float(older["t"])) / span, 0.0, 1.0)
		var from_pos: Vector3 = older["p"]
		var to_pos: Vector3 = newer["p"]
		if from_pos.distance_to(to_pos) > SNAP_DISTANCE:
			return _pose(newer, true)
		return {
			"position": from_pos.lerp(to_pos, weight),
			"yaw": lerp_angle(float(older["y"]), float(newer["y"]), weight),
			"lean": lerpf(float(older["l"]), float(newer["l"]), weight),
			"crouch": lerpf(float(older["c"]), float(newer["c"]), weight),
			"pitch": lerpf(float(older["pitch"]), float(newer["pitch"]), weight),
			"snapped": false,
		}
	return _pose(last, false)


func _pose(entry: Dictionary, snapped: bool) -> Dictionary:
	return {
		"position": entry["p"],
		"yaw": float(entry["y"]),
		"lean": float(entry["l"]),
		"crouch": float(entry["c"]),
		"pitch": float(entry["pitch"]),
		"snapped": snapped,
	}
