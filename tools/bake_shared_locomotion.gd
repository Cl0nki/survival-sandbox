extends SceneTree

## Copy already-retargeted clips into ual_locomotion.res.
## The importer (retarget_method = Use Retarget Modifier) rewrites rotations
## into profile space. This script must not rewrite track paths.

const LIBRARY := "res://assets/characters/Shared/Quaternius/ual_locomotion.res"
const PRO := "res://assets/characters/Shared/Quaternius/AnimationLibrary_Godot_Pro.glb"

const PRO_WANTED := {
	"Idle": "Idle",
	"Walk": "Walk",
	"Walk_LeanL": "Jog_Fwd_LeanL",
	"Walk_LeanR": "Jog_Fwd_LeanR",
	"Crouch_Idle": "Crouch_Idle",
	"Crouch_Fwd": "Crouch_Fwd",
	"Crouch_Bwd": "Crouch_Bwd",
	"Crouch_Left": "Crouch_Left",
	"Crouch_Right": "Crouch_Right",
	"Crouch_Fwd_L": "Crouch_Fwd_L",
	"Crouch_Fwd_R": "Crouch_Fwd_R",
	"Crouch_Bwd_L": "Crouch_Bwd_L",
	"Crouch_Bwd_R": "Crouch_Bwd_R",
	"Crouch_Enter": "Crouch_Enter",
	"Crouch_Exit": "Crouch_Exit",
	"Pistol_Idle": "Pistol_Idle",
	"Pistol_Aim_Down": "Pistol_Aim_Down",
	"Pistol_Aim_Neutral": "Pistol_Aim_Neutral",
	"Pistol_Aim_Up": "Pistol_Aim_Up",
	"Pistol_Shoot": "Pistol_Shoot",
	"Pistol_Reload": "Pistol_Reload",
}

const UAL2 := {
	"res://assets/characters/Shared/Quaternius/ual2/quaternius-ual2-walk-l-loop.glb": "Walk_L",
	"res://assets/characters/Shared/Quaternius/ual2/quaternius-ual2-walk-r-loop.glb": "Walk_R",
	"res://assets/characters/Shared/Quaternius/ual2/quaternius-ual2-walk-bwd-loop.glb": "Walk_Bwd",
	"res://assets/characters/Shared/Quaternius/ual2/quaternius-ual2-mining-loop.glb": "Mining",
	"res://assets/characters/Shared/Quaternius/ual2/quaternius-ual2-tree-chopping-loop.glb": "TreeChopping",
}

const REQUIRED := [
	"Idle", "Walk", "Walk_Bwd", "Walk_L", "Walk_R",
	"Walk_LeanL", "Walk_LeanR",
	"Crouch_Idle", "Crouch_Fwd", "Crouch_Bwd", "Crouch_Left", "Crouch_Right",
	"Crouch_Fwd_L", "Crouch_Fwd_R", "Crouch_Bwd_L", "Crouch_Bwd_R",
	"Pistol_Aim_Down", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Shoot",
	"Mining", "TreeChopping",
]

const LOOP_LINEAR := [
	"Idle", "Walk", "Walk_Bwd", "Walk_L", "Walk_R",
	"Walk_LeanL", "Walk_LeanR",
	"Crouch_Idle", "Crouch_Fwd", "Crouch_Bwd", "Crouch_Left", "Crouch_Right",
	"Crouch_Fwd_L", "Crouch_Fwd_R", "Crouch_Bwd_L", "Crouch_Bwd_R",
	"Pistol_Idle", "Pistol_Aim_Down", "Pistol_Aim_Neutral", "Pistol_Aim_Up",
	"Mining", "TreeChopping",
]

const MATCH_WALK_LENGTH := ["Walk_LeanL", "Walk_LeanR"]


func _init() -> void:
	var lib := AnimationLibrary.new()
	var pro_scene := _load_scene(PRO)
	if pro_scene == null:
		quit(2)
		return
	if pro_scene.find_child("RetargetModifier3D", true, false) == null:
		push_error("Pro GLB has no RetargetModifier3D. Reimport with retarget_method 2 before baking.")
		pro_scene.free()
		quit(2)
		return
	var pro_player := _find_animation_player(pro_scene)
	if pro_player == null:
		push_error("No AnimationPlayer in Pro scene")
		pro_scene.free()
		quit(2)
		return
	var found: PackedStringArray = pro_player.get_animation_list()
	print("PRO_CLIPS=", found.size())
	var walk_len := 0.0
	var walk_src := _resolve_name(found, "Walk")
	if not walk_src.is_empty():
		var walk_anim := pro_player.get_animation(walk_src)
		if walk_anim != null:
			walk_len = walk_anim.length
	for alias in PRO_WANTED.keys():
		var src_name := _resolve_name(found, str(PRO_WANTED[alias]))
		if src_name.is_empty():
			push_warning("Pro missing %s" % str(PRO_WANTED[alias]))
			continue
		var copy := pro_player.get_animation(src_name).duplicate(true) as Animation
		if str(alias) in MATCH_WALK_LENGTH and walk_len > 0.01 and copy.length > 0.01:
			_stretch_animation(copy, walk_len)
		_finish_clip(copy, str(alias))
		if not _tracks_are_profile(copy, str(alias)):
			pro_scene.free()
			quit(2)
			return
		lib.add_animation(StringName(str(alias)), copy)
		print("BAKED ", alias, " from ", src_name, " tracks=", copy.get_track_count())
	pro_scene.free()

	for path in UAL2.keys():
		var alias := str(UAL2[path])
		var scene := _load_scene(str(path))
		if scene == null:
			quit(2)
			return
		if scene.find_child("RetargetModifier3D", true, false) == null:
			push_error("%s has no RetargetModifier3D" % path)
			scene.free()
			quit(2)
			return
		var player := _find_animation_player(scene)
		var clip := _primary_clip(player)
		if clip == null:
			push_error("No clip in %s" % path)
			scene.free()
			quit(2)
			return
		var copy := clip.duplicate(true) as Animation
		_finish_clip(copy, alias)
		if not _tracks_are_profile(copy, alias):
			scene.free()
			quit(2)
			return
		lib.add_animation(StringName(alias), copy)
		print("BAKED ", alias, " tracks=", copy.get_track_count(), " len=", snapped(copy.length, 0.001))
		scene.free()

	var missing: PackedStringArray = []
	for name in REQUIRED:
		if not lib.has_animation(StringName(name)):
			missing.append(name)
	if not missing.is_empty():
		push_error("Bake missing required clips: %s" % ", ".join(missing))
		quit(2)
		return
	var err := ResourceSaver.save(lib, LIBRARY)
	print("SAVE_ERR=", err, " LIB_COUNT=", lib.get_animation_list().size())
	quit(0 if err == OK else 3)


func _load_scene(path: String) -> Node:
	if not ResourceLoader.exists(path):
		push_error("Missing %s" % path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Failed to load %s" % path)
		return null
	return packed.instantiate()


func _finish_clip(anim: Animation, alias: String) -> void:
	if alias in LOOP_LINEAR:
		anim.loop_mode = Animation.LOOP_LINEAR
	else:
		anim.loop_mode = Animation.LOOP_NONE


func _tracks_are_profile(anim: Animation, alias: String) -> bool:
	var profile_tracks := 0
	for i in anim.get_track_count():
		var path := String(anim.track_get_path(i))
		if path.contains("pelvis") or path.contains("thigh_") or path.contains("DEF-") or path.contains("leftUpper"):
			push_error("%s still has a raw bone path: %s" % [alias, path])
			return false
		if path.begins_with("%GeneralSkeleton:"):
			profile_tracks += 1
	if profile_tracks == 0:
		push_error("%s has no %%GeneralSkeleton tracks" % alias)
		return false
	return true


func _stretch_animation(anim: Animation, target_len: float) -> void:
	if anim.length <= 0.001 or is_equal_approx(anim.length, target_len):
		anim.length = target_len
		return
	var scale := target_len / anim.length
	for track_i in anim.get_track_count():
		var key_count := anim.track_get_key_count(track_i)
		if scale >= 1.0:
			for key_i in range(key_count - 1, -1, -1):
				anim.track_set_key_time(track_i, key_i, anim.track_get_key_time(track_i, key_i) * scale)
		else:
			for key_i in key_count:
				anim.track_set_key_time(track_i, key_i, anim.track_get_key_time(track_i, key_i) * scale)
	anim.length = target_len


func _resolve_name(found: PackedStringArray, want: String) -> String:
	if found.has(want):
		return want
	var with_loop := want + "_Loop"
	if found.has(with_loop):
		return with_loop
	for name in found:
		var s := str(name)
		if s == want or s == with_loop:
			return s
		if s.begins_with(want) and (s.ends_with("_Loop") or s == want):
			return s
	return ""


func _primary_clip(player: AnimationPlayer) -> Animation:
	if player == null:
		return null
	for name in player.get_animation_list():
		if str(name) == "RESET":
			continue
		return player.get_animation(name)
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
