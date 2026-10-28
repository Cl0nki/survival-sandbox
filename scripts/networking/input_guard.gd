extends RefCounted
class_name InputGuard

## Rejects malformed client requests before the server simulates them.
## Movement axes are clamped only after they pass the finite/range checks.
## Nothing in the sanitized command is a world position, hit, or damage value.

const MAX_AXIS_MAGNITUDE := 2.0
const MAX_ABS_YAW := 64.0
## About 62 degrees. Steeper than that is rejected or clamped so a shot stays
## a direction, not a straight-up or straight-down ray.
const MAX_AIM_PITCH := 1.0821041362364843

static func sanitize_move(
	move_x: float,
	move_y: float,
	camera_yaw: float,
	aim_yaw: float,
	lean: float,
	crouch: float = 0.0,
	aim_pitch: float = 0.0
) -> Dictionary:
	if not _numbers([move_x, move_y, camera_yaw, aim_yaw, lean, crouch, aim_pitch]):
		return _reject("non_finite")
	if absf(move_x) > MAX_AXIS_MAGNITUDE or absf(move_y) > MAX_AXIS_MAGNITUDE or absf(lean) > MAX_AXIS_MAGNITUDE:
		return _reject("axis_range")
	if crouch < -0.05 or crouch > 1.05 or absf(aim_pitch) > 3.0:
		return _reject("axis_range")
	if absf(camera_yaw) > MAX_ABS_YAW or absf(aim_yaw) > MAX_ABS_YAW:
		return _reject("yaw_range")
	return {
		"ok": true,
		"axes": Vector2(clampf(move_x, -1.0, 1.0), clampf(move_y, -1.0, 1.0)),
		"camera_yaw": wrapf(camera_yaw, -PI, PI),
		"aim_yaw": wrapf(aim_yaw, -PI, PI),
		"lean": clampf(lean, -1.0, 1.0),
		"crouch": clampf(crouch, 0.0, 1.0),
		"aim_pitch": clampf(aim_pitch, -MAX_AIM_PITCH, MAX_AIM_PITCH),
	}


static func sanitize_aim(aim: Vector3, aim_yaw: float, lean: float, crouch: float = 0.0) -> Dictionary:
	if not NetConfig.finite_vector(aim) or not is_finite(aim_yaw) or not is_finite(lean) or not is_finite(crouch):
		return _reject("non_finite")
	if absf(aim_yaw) > MAX_ABS_YAW or absf(lean) > MAX_AXIS_MAGNITUDE or crouch < -0.05 or crouch > 1.05:
		return _reject("axis_range")
	# A world position or an unnormalized payload is not an aim direction.
	var length := aim.length()
	if length < 0.5 or length > 1.5:
		return _reject("invalid_aim")
	var dir := aim / length
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.25:
		return _reject("invalid_aim")
	var pitch := clampf(asin(clampf(dir.y, -1.0, 1.0)), -MAX_AIM_PITCH, MAX_AIM_PITCH)
	var planar := flat.normalized()
	var aimed := Vector3(planar.x * cos(pitch), sin(pitch), planar.z * cos(pitch))
	return {
		"ok": true,
		"direction": aimed,
		"aim_yaw": wrapf(aim_yaw, -PI, PI),
		"lean": clampf(lean, -1.0, 1.0),
		"crouch": clampf(crouch, 0.0, 1.0),
	}


static func _numbers(values: Array) -> bool:
	for value in values:
		if not is_finite(float(value)):
			return false
	return true


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
