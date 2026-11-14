extends SceneTree

## Headless locomotion QA for stand BlendSpace clips on the Pro mannequin.
## Catches the bugs we kept hitting: unbound tracks, rest explosions, root-motion hips.
##
## godot --headless --path <project> --script res://tests/loco_qa.gd
##
## Exit 0 + LOCO_QA_OK on pass. Exit 1 + LOCO_QA_FAIL with reasons on fail.

const LIBRARY_PATH := "res://assets/characters/Shared/Quaternius/ual_locomotion.res"
const PRO_PATH := "res://assets/characters/Shared/Quaternius/AnimationLibrary_Godot_Pro.glb"
const REPORT_PATH := "user://loco_qa_report.json"

const STAND_CLIPS := [
	"Idle", "Walk", "Walk_Bwd", "Walk_L", "Walk_R",
]

## Empirically: Pro Jog dirs vs Idle were ~0.2–0.7 rad. Meshy after retarget ~0.3–1.2.
## >2.5 rad was the “exploded legs” failure mode.
const MAX_LEG_VS_IDLE_RAD := 1.55
const MAX_HIP_BOB_M := 0.35
const MIN_HIPS_Y := 0.55
const MAX_HIPS_Y := 1.35
const MIN_WALK_LEG_AMP_RAD := 0.20
const MIN_WALK_FOOT_SPREAD := 0.18
const MAX_WALK_FOOT_SPREAD := 1.40
## Knee pole: 0 means the bend axis is the body's left-right axis.
## The broken local-quaternion retarget folded knees sideways (pole near 1).
const MAX_KNEE_POLE_ERR := 0.65


func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(45.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	var code := await _run()
	quit(code)


func _run() -> int:
	var failures: PackedStringArray = []
	var warnings: PackedStringArray = []
	var metrics: Dictionary = {"clips": {}, "thresholds": {
		"max_leg_vs_idle_rad": MAX_LEG_VS_IDLE_RAD,
		"max_hip_bob_m": MAX_HIP_BOB_M,
		"hips_y": [MIN_HIPS_Y, MAX_HIPS_Y],
		"min_walk_leg_amp_rad": MIN_WALK_LEG_AMP_RAD,
		"walk_foot_spread": [MIN_WALK_FOOT_SPREAD, MAX_WALK_FOOT_SPREAD],
	}}

	var lib: AnimationLibrary = load(LIBRARY_PATH) as AnimationLibrary
	if lib == null:
		return _finish(1, ["library missing: %s" % LIBRARY_PATH], warnings, metrics)

	var packed: PackedScene = load(PRO_PATH) as PackedScene
	if packed == null:
		return _finish(1, ["pro mannequin missing"], warnings, metrics)
	var model: Node = packed.instantiate()
	root.add_child(model)
	await process_frame

	var sk := _find_skeleton(model)
	var player := _find_animation_player(model)
	if sk == null or player == null:
		return _finish(1, ["mannequin missing Skeleton3D or AnimationPlayer"], warnings, metrics)

	## Install shared library as the sole library on the player.
	for lib_name in player.get_animation_library_list():
		player.remove_animation_library(lib_name)
	player.add_animation_library(&"", lib)
	player.active = true
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	var idle: Animation = lib.get_animation(&"Idle") if lib.has_animation(&"Idle") else null
	var idle_leg := _rot_track(idle, "LeftUpperLeg") if idle else -1

	for clip_name in STAND_CLIPS:
		var entry: Dictionary = {"name": clip_name}
		if not lib.has_animation(StringName(clip_name)):
			failures.append("missing clip %s" % clip_name)
			metrics["clips"][clip_name] = {"missing": true}
			continue
		var anim: Animation = lib.get_animation(StringName(clip_name))
		entry["length"] = anim.length
		entry["tracks"] = anim.get_track_count()
		entry["loop"] = anim.loop_mode

		var bad_paths := 0
		for ti in anim.get_track_count():
			var path := String(anim.track_get_path(ti))
			if not path.begins_with("%GeneralSkeleton:"):
				bad_paths += 1
		entry["bad_paths"] = bad_paths
		if bad_paths > 0:
			failures.append("%s has %d tracks not on %%GeneralSkeleton" % [clip_name, bad_paths])
		if anim.loop_mode != Animation.LOOP_LINEAR:
			warnings.append("%s loop_mode=%d (expected LOOP_LINEAR)" % [clip_name, anim.loop_mode])

		var hip_i := _pos_track(anim, "Hips")
		var bob := 0.0
		var hip0 := Vector3.ZERO
		if hip_i >= 0 and anim.track_get_key_count(hip_i) > 0:
			hip0 = anim.track_get_key_value(hip_i, 0)
			for ki in anim.track_get_key_count(hip_i):
				bob = maxf(bob, hip0.distance_to(anim.track_get_key_value(hip_i, ki)))
		entry["hip0"] = [hip0.x, hip0.y, hip0.z]
		entry["hip_bob"] = bob
		if bob > MAX_HIP_BOB_M:
			failures.append("%s hip bob %.3fm > %.3fm (root motion?)" % [clip_name, bob, MAX_HIP_BOB_M])

		var leg_i := _rot_track(anim, "LeftUpperLeg")
		var vs_idle := -1.0
		if leg_i >= 0 and idle_leg >= 0:
			vs_idle = (anim.track_get_key_value(leg_i, 0) as Quaternion).angle_to(
				idle.track_get_key_value(idle_leg, 0) as Quaternion
			)
		entry["leg_vs_idle_rad"] = vs_idle
		if vs_idle > MAX_LEG_VS_IDLE_RAD:
			failures.append("%s LeftUpperLeg vs Idle %.3frad > %.3f (rest mismatch)" % [
				clip_name, vs_idle, MAX_LEG_VS_IDLE_RAD
			])

		var leg_amp := _rotation_amp(anim, leg_i)
		entry["leg_amp_rad"] = leg_amp
		var is_walk: bool = str(clip_name) != "Idle"
		if is_walk and leg_amp < MIN_WALK_LEG_AMP_RAD:
			failures.append("%s LeftUpperLeg amp %.3frad < %.3f (looks like standing)" % [
				clip_name, leg_amp, MIN_WALK_LEG_AMP_RAD
			])

		## Pose samples on the live skeleton. One frame is not enough:
		## the twisted retarget passed a single hip/foot check.
		var pose := {}
		var worst_pole := 0.0
		var widest_feet := 0.0
		for sample_i in 4:
			var sample_t := anim.length * (float(sample_i) + 0.5) / 4.0
			player.play(StringName(clip_name))
			player.seek(sample_t, true)
			player.advance(0.0)
			sk.force_update_all_bone_transforms()
			pose = _sample_pose(sk)
			worst_pole = maxf(worst_pole, float(pose["knee_pole_err"]))
			widest_feet = maxf(widest_feet, float(pose["foot_spread"]))
			if pose["hips_y"] < MIN_HIPS_Y or pose["hips_y"] > MAX_HIPS_Y:
				failures.append("%s hips_y=%.3f outside [%.2f,%.2f]" % [
					clip_name, pose["hips_y"], MIN_HIPS_Y, MAX_HIPS_Y
				])
			if pose["foot_spread"] > MAX_WALK_FOOT_SPREAD:
				failures.append("%s foot_spread=%.3f looks exploded" % [clip_name, pose["foot_spread"]])
			if pose["max_leg_bone_y"] > pose["hips_y"] + 0.35:
				failures.append("%s leg bone above hips (y=%.3f hips=%.3f)" % [
					clip_name, pose["max_leg_bone_y"], pose["hips_y"]
				])
			if float(pose["knee_pole_err"]) > MAX_KNEE_POLE_ERR:
				failures.append("%s knee bends sideways pole=%.3f > %.2f" % [
					clip_name, pose["knee_pole_err"], MAX_KNEE_POLE_ERR
				])
		if is_walk and widest_feet < MIN_WALK_FOOT_SPREAD:
			failures.append("%s widest foot_spread=%.3f < %.3f (feet glued / dead clip)" % [
				clip_name, widest_feet, MIN_WALK_FOOT_SPREAD
			])
		entry["pose"] = pose
		entry["knee_pole_err"] = worst_pole
		entry["widest_feet"] = widest_feet

		metrics["clips"][clip_name] = entry
		print(
			"CLIP ", clip_name,
			" tracks=", entry["tracks"],
			" bob=", snapped(bob, 0.001),
			" vsIdle=", snapped(vs_idle, 0.001),
			" amp=", snapped(leg_amp, 0.001),
			" hips_y=", snapped(pose["hips_y"], 0.001),
			" feet=", snapped(pose["foot_spread"], 0.001),
			" pole=", snapped(worst_pole, 0.001)
		)

	## Neighbor blend sanity: average Idle+Walk at mid shouldn't explode vs Idle alone.
	if lib.has_animation(&"Idle") and lib.has_animation(&"Walk"):
		player.play(&"Idle")
		player.seek(0.1, true)
		player.advance(0.0)
		sk.force_update_all_bone_transforms()
		var idle_pose := _sample_pose(sk)
		player.play(&"Walk")
		player.seek(0.2, true)
		player.advance(0.0)
		sk.force_update_all_bone_transforms()
		var walk_pose := _sample_pose(sk)
		var hip_delta: float = absf(idle_pose["hips_y"] - walk_pose["hips_y"])
		metrics["idle_walk_hips_delta"] = hip_delta
		if hip_delta > 0.45:
			failures.append("Idle↔Walk hips_y jump %.3f looks like rest clash" % hip_delta)

	model.queue_free()
	return _finish(0 if failures.is_empty() else 1, failures, warnings, metrics)


func _sample_pose(sk: Skeleton3D) -> Dictionary:
	sk.force_update_transform()
	var hips_i := sk.find_bone("Hips")
	var lf := sk.find_bone("LeftFoot")
	var rf := sk.find_bone("RightFoot")
	var lul := sk.find_bone("LeftUpperLeg")
	var rul := sk.find_bone("RightUpperLeg")
	var lll := sk.find_bone("LeftLowerLeg")
	var rll := sk.find_bone("RightLowerLeg")
	var hips_y := sk.get_bone_global_pose(hips_i).origin.y if hips_i >= 0 else 0.0
	var foot_spread := 0.0
	if lf >= 0 and rf >= 0:
		foot_spread = sk.get_bone_global_pose(lf).origin.distance_to(sk.get_bone_global_pose(rf).origin)
	var max_leg_y := -INF
	for bi in [lul, rul, lll, rll, lf, rf]:
		if bi >= 0:
			max_leg_y = maxf(max_leg_y, sk.get_bone_global_pose(bi).origin.y)
	var pole_err := 0.0
	for side in ["Left", "Right"]:
		var upper_i := sk.find_bone(side + "UpperLeg")
		var knee_i := sk.find_bone(side + "LowerLeg")
		var foot_i := sk.find_bone(side + "Foot")
		if upper_i < 0 or knee_i < 0 or foot_i < 0:
			continue
		var upper := sk.get_bone_global_pose(upper_i).origin
		var knee := sk.get_bone_global_pose(knee_i).origin
		var foot := sk.get_bone_global_pose(foot_i).origin
		var flex := (upper - knee).normalized().angle_to((foot - knee).normalized())
		if flex >= 2.6:
			continue
		var pole := (knee - upper).cross(foot - knee)
		if pole.length() > 0.001:
			pole_err = maxf(pole_err, 1.0 - absf(pole.normalized().dot(Vector3.RIGHT)))
	return {
		"hips_y": hips_y,
		"foot_spread": foot_spread,
		"max_leg_bone_y": max_leg_y if max_leg_y > -INF else 0.0,
		"knee_pole_err": pole_err,
	}


func _finish(code: int, failures: PackedStringArray, warnings: PackedStringArray, metrics: Dictionary) -> int:
	metrics["failures"] = Array(failures)
	metrics["warnings"] = Array(warnings)
	metrics["ok"] = code == 0
	var report := JSON.stringify(metrics, "\t")
	var abs_path := ProjectSettings.globalize_path(REPORT_PATH)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(report)
		f.close()
	print("LOCO_QA_REPORT ", abs_path)
	for w in warnings:
		print("WARN ", w)
	if code == 0:
		print("LOCO_QA_OK clips=", STAND_CLIPS.size())
	else:
		print("LOCO_QA_FAIL count=", failures.size())
		for reason in failures:
			print("  - ", reason)
	return code


func _rot_track(anim: Animation, bone: String) -> int:
	if anim == null:
		return -1
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		if String(anim.track_get_path(ti)).ends_with(bone):
			return ti
	return -1


func _pos_track(anim: Animation, bone: String) -> int:
	if anim == null:
		return -1
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		if String(anim.track_get_path(ti)).ends_with(bone):
			return ti
	return -1


func _rotation_amp(anim: Animation, track_i: int) -> float:
	if anim == null or track_i < 0 or anim.track_get_key_count(track_i) == 0:
		return 0.0
	var q0: Quaternion = anim.track_get_key_value(track_i, 0)
	var amp := 0.0
	for ki in anim.track_get_key_count(track_i):
		amp = maxf(amp, q0.angle_to(anim.track_get_key_value(track_i, ki)))
	return amp


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
