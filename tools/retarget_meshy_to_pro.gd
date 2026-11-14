extends SceneTree

## Bake Meshy strafe clips onto the Pro mannequin.
## Copying local quaternions twists the knees: Meshy and Pro use different
## rest axes for the same bone. This applies each bone's change-from-rest
## in world space, so a knee that bends around world X still bends around
## world X on the Pro body. Idle, Walk, and the lean clips stay Pro.
## A pose gate rejects twisted knees and keeps the Pro fallback.

const LIBRARY := "res://assets/characters/Shared/Quaternius/ual_locomotion.res"
const PRO_SCENE := "res://assets/characters/Shared/Quaternius/AnimationLibrary_Godot_Pro.glb"
const REPORT := "user://meshy_retarget_report.json"

const SOURCES := {
	"res://assets/characters/Shared/Quaternius/meshy_walk_strafe/Walk_L.glb": "Walk_L",
	"res://assets/characters/Shared/Quaternius/meshy_walk_strafe/Walk_R.glb": "Walk_R",
	"res://assets/characters/Shared/Quaternius/meshy_walk_strafe/Walk_Bwd.glb": "Walk_Bwd",
	"res://assets/characters/Shared/Quaternius/meshy_walk_strafe/Walk_Fwd_L.glb": "Walk_Fwd_L",
	"res://assets/characters/Shared/Quaternius/meshy_walk_strafe/Walk_Fwd_R.glb": "Walk_Fwd_R",
	"res://assets/characters/Shared/Quaternius/meshy_walk_strafe/Walk_Bwd_L.glb": "Walk_Bwd_L",
	"res://assets/characters/Shared/Quaternius/meshy_walk_strafe/Walk_Bwd_R.glb": "Walk_Bwd_R",
}

const BONES := [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
]

const LEGS := ["LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"]
## World-space bakes stay under ~1.21 rad. The old local copy reached ~1.6–2.9.
const MAX_VS_REST_RAD := 1.35
## 0 = knee pole along the body's left-right axis. 1 = knee bent straight up.
const MAX_POLE_ERR := 0.55


func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var code := await _run()
	quit(code)


func _run() -> int:
	var lib: AnimationLibrary = load(LIBRARY) as AnimationLibrary
	if lib == null:
		push_error("Missing library")
		return 1
	var pro := (load(PRO_SCENE) as PackedScene).instantiate()
	pro.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(pro)
	var pro_sk := _find_skeleton(pro)
	var pro_ap := _find_player(pro)
	_manual(pro_ap)
	if not lib.has_animation(&""):
		pass
	for existing in pro_ap.get_animation_library_list():
		pro_ap.remove_animation_library(existing)
	pro_ap.add_animation_library(&"pro", lib)

	var accepted := 0
	var report := {"clips": {}}
	for path in SOURCES.keys():
		var alias: String = SOURCES[path]
		if not ResourceLoader.exists(path):
			print("SKIP missing ", path)
			report["clips"][alias] = {"ok": false, "reason": "missing glb"}
			continue
		if not lib.has_animation(StringName(alias)):
			print("SKIP no Pro fallback ", alias)
			report["clips"][alias] = {"ok": false, "reason": "no pro fallback"}
			continue
		var target_length := lib.get_animation(StringName(alias)).length
		var baked := _bake(str(path), pro_sk, target_length)
		if baked == null:
			print("FAIL ", alias, " bake")
			report["clips"][alias] = {"ok": false, "reason": "bake failed"}
			continue
		var gate := _gate(pro_ap, pro_sk, lib.get_animation(StringName(alias)), baked)
		report["clips"][alias] = gate
		if not bool(gate["ok"]):
			print("KEEP_PRO ", alias, " ", gate["reason"], " vs_rest=", snapped(float(gate["max_vs_rest"]), 0.001), " pole=", snapped(float(gate["pole_err"]), 0.001))
			continue
		lib.remove_animation(StringName(alias))
		lib.add_animation(StringName(alias), baked)
		accepted += 1
		print("ACCEPT ", alias, " vs_rest=", snapped(float(gate["max_vs_rest"]), 0.001), " pole=", snapped(float(gate["pole_err"]), 0.001), " feet=", snapped(float(gate["foot_y"]), 0.001))

	var err := ResourceSaver.save(lib, LIBRARY)
	_write_report(report)
	print("SAVE_ERR=", err, " ACCEPTED=", accepted, "/", SOURCES.size())
	pro.queue_free()
	return 0 if err == OK else 1


func _bake(path: String, pro_sk: Skeleton3D, target_length: float) -> Animation:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(model)
	var src_sk := _find_skeleton(model)
	var src_ap := _find_player(model)
	if src_sk == null or src_ap == null:
		model.free()
		return null
	_manual(src_ap)
	var names := src_ap.get_animation_list()
	if names.is_empty():
		model.free()
		return null
	var src_name := names[0]
	var src_anim: Animation = src_ap.get_animation(src_name)
	var length := src_anim.length
	var samples := 24
	src_sk.reset_bone_poses()
	src_sk.force_update_all_bone_transforms()
	var src_rest := _globals(src_sk)
	pro_sk.reset_bone_poses()
	pro_sk.force_update_all_bone_transforms()
	var pro_rest := _globals(pro_sk)
	if not src_rest.has("Hips") or not pro_rest.has("Hips"):
		model.free()
		return null
	var src_leg := _leg_length(src_sk, src_rest)
	var pro_leg := _leg_length(pro_sk, pro_rest)
	var scale := 1.0 if src_leg < 0.001 else pro_leg / src_leg

	var hip_deltas: Array[Vector3] = []
	var src_frames: Array = []
	for i in samples:
		var t := length * float(i) / float(samples)
		_seek(src_ap, src_sk, src_name, t)
		var frame := _globals(src_sk)
		src_frames.append(frame)
		var hip: Transform3D = frame["Hips"]
		var rest: Transform3D = src_rest["Hips"]
		hip_deltas.append(hip.origin - rest.origin)
	var drift_end: Vector3 = hip_deltas[samples - 1] - hip_deltas[0]
	var mean := Vector3.ZERO
	var detrended: Array[Vector3] = []
	for i in samples:
		var t := float(i) / float(samples - 1)
		var d: Vector3 = hip_deltas[i] - hip_deltas[0] - drift_end * t
		detrended.append(d)
		mean += d
	mean /= float(samples)

	var out := Animation.new()
	out.length = target_length
	out.loop_mode = Animation.LOOP_LINEAR
	var rot_tracks := {}
	for bone in BONES:
		if pro_sk.find_bone(bone) < 0 or src_sk.find_bone(bone) < 0:
			continue
		var ti := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(ti, NodePath("%GeneralSkeleton:" + bone))
		out.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
		rot_tracks[bone] = ti
	var hip_ti := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hip_ti, NodePath("%GeneralSkeleton:Hips"))
	out.track_set_interpolation_type(hip_ti, Animation.INTERPOLATION_LINEAR)

	var pro_hip_rest: Vector3 = (pro_rest["Hips"] as Transform3D).origin
	for i in samples:
		var desired := {}
		var frame: Dictionary = src_frames[i]
		for bone in rot_tracks.keys():
			var src_r: Transform3D = src_rest[bone]
			var src_a: Transform3D = frame[bone]
			var world_delta := (src_a.basis * src_r.basis.inverse()).orthonormalized()
			var pro_r: Transform3D = pro_rest[bone]
			desired[bone] = (world_delta * pro_r.basis).orthonormalized()
		var key_t := target_length * float(i) / float(samples)
		for bone in rot_tracks.keys():
			var quat := _local_quat(pro_sk, bone, desired, pro_rest)
			out.track_insert_key(rot_tracks[bone], key_t, quat)
		var bob: Vector3 = (detrended[i] - mean) * scale
		out.track_insert_key(hip_ti, key_t, pro_hip_rest + bob)
	model.free()
	return out


func _gate(ap: AnimationPlayer, sk: Skeleton3D, _pro_anim: Animation, baked: Animation) -> Dictionary:
	var temp := AnimationLibrary.new()
	temp.add_animation(&"baked", baked)
	if ap.has_animation_library(&"gate"):
		ap.remove_animation_library(&"gate")
	ap.add_animation_library(&"gate", temp)
	var max_vs_rest := 0.0
	var max_pole := 0.0
	var foot_sum := 0.0
	var samples := 8
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	var rest_q := {}
	for bone in LEGS:
		rest_q[bone] = sk.get_bone_pose_rotation(sk.find_bone(bone))
	for i in samples:
		var t := baked.length * (float(i) + 0.5) / float(samples)
		_seek(ap, sk, "gate/baked", t)
		var foot_y := 0.0
		for bone in LEGS:
			var pose_q: Quaternion = sk.get_bone_pose_rotation(sk.find_bone(bone))
			max_vs_rest = maxf(max_vs_rest, pose_q.angle_to(rest_q[bone]))
		var hips := sk.find_bone("Hips")
		var hip_y := sk.get_bone_global_pose(hips).origin.y if hips >= 0 else 0.0
		var lf := sk.find_bone("LeftFoot")
		var rf := sk.find_bone("RightFoot")
		if lf >= 0 and rf >= 0:
			foot_y = 0.5 * (sk.get_bone_global_pose(lf).origin.y + sk.get_bone_global_pose(rf).origin.y)
		foot_sum += foot_y
		for side in ["Left", "Right"]:
			var upper := sk.get_bone_global_pose(sk.find_bone(side + "UpperLeg")).origin
			var knee := sk.get_bone_global_pose(sk.find_bone(side + "LowerLeg")).origin
			var foot := sk.get_bone_global_pose(sk.find_bone(side + "Foot")).origin
			if knee.y > hip_y - 0.02 or foot.y > knee.y + 0.02:
				ap.remove_animation_library(&"gate")
				return {"ok": false, "reason": "knee or foot above the joint", "max_vs_rest": max_vs_rest, "pole_err": max_pole, "foot_y": foot_y}
			var flex := (upper - knee).normalized().angle_to((foot - knee).normalized())
			if flex < 2.6:
				var pole := (knee - upper).cross(foot - knee)
				if pole.length() > 0.001:
					max_pole = maxf(max_pole, 1.0 - absf(pole.normalized().dot(Vector3.RIGHT)))
	ap.remove_animation_library(&"gate")
	var foot_y_mean := foot_sum / float(samples)
	var result := {"ok": true, "reason": "", "max_vs_rest": max_vs_rest, "pole_err": max_pole, "foot_y": foot_y_mean}
	if max_vs_rest > MAX_VS_REST_RAD:
		result["ok"] = false
		result["reason"] = "rest delta too large"
	elif max_pole > MAX_POLE_ERR:
		result["ok"] = false
		result["reason"] = "knee bends sideways"
	elif foot_y_mean < -0.05 or foot_y_mean > 0.45:
		result["ok"] = false
		result["reason"] = "feet off ground"
	return result


func _local_quat(sk: Skeleton3D, bone: String, desired: Dictionary, pro_rest: Dictionary) -> Quaternion:
	var bi := sk.find_bone(bone)
	var parent := sk.get_bone_parent(bi)
	var parent_basis := Basis.IDENTITY
	if parent >= 0:
		var pname := String(sk.get_bone_name(parent))
		if desired.has(pname):
			parent_basis = desired[pname]
		elif pro_rest.has(pname):
			parent_basis = (pro_rest[pname] as Transform3D).basis
		else:
			parent_basis = sk.get_bone_global_rest(parent).basis
	var local: Basis = parent_basis.inverse() * desired[bone]
	return local.orthonormalized().get_rotation_quaternion()


func _globals(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for bone in BONES:
		var bi := sk.find_bone(bone)
		if bi >= 0:
			out[bone] = sk.get_bone_global_pose(bi)
	return out


func _leg_length(sk: Skeleton3D, globals: Dictionary) -> float:
	if not globals.has("Hips") or not globals.has("LeftFoot"):
		return 1.0
	return (globals["Hips"] as Transform3D).origin.distance_to((globals["LeftFoot"] as Transform3D).origin)


func _seek(ap: AnimationPlayer, sk: Skeleton3D, anim: String, t: float) -> void:
	ap.play(StringName(anim))
	ap.seek(t, true)
	ap.advance(0.0)
	sk.force_update_all_bone_transforms()


func _manual(ap: AnimationPlayer) -> void:
	ap.active = true
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func _write_report(report: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(REPORT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	print("RETARGET_REPORT ", path)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null
