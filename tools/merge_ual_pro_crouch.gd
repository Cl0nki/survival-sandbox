extends SceneTree

## Merge UAL1 Pro clips into ual_locomotion.res for the Pro mannequin.
## Stand base: Idle + Walk + forward leans (Jog_Fwd_Lean stretched to
## Walk length). Strafe/back walks come from merge_ual2_strafe_clips.gd.
## Crouch + pistol stay Pro-native.

const SOURCE := "res://assets/characters/Shared/Quaternius/AnimationLibrary_Godot_Pro.glb"
const LIBRARY := "res://assets/characters/Shared/Quaternius/ual_locomotion.res"

const WANTED := {
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

const MATCH_WALK_LENGTH := [
	"Walk_LeanL", "Walk_LeanR",
]


func _init() -> void:
	var lib: AnimationLibrary = load(LIBRARY) as AnimationLibrary
	if lib == null:
		push_error("Failed to load %s" % LIBRARY)
		quit(1)
		return
	var packed: PackedScene = load(SOURCE) as PackedScene
	if packed == null:
		push_error("Failed to load Pro GLB %s" % SOURCE)
		quit(2)
		return
	var root: Node = packed.instantiate()
	var player := _find_animation_player(root)
	if player == null:
		push_error("No AnimationPlayer in Pro scene")
		quit(2)
		return
	var found: PackedStringArray = player.get_animation_list()
	print("PRO_CLIPS=", found.size())
	var walk_len := 0.0
	var walk_src := _resolve_name(found, "Walk")
	if not walk_src.is_empty():
		var walk_anim: Animation = player.get_animation(walk_src)
		if walk_anim != null:
			walk_len = walk_anim.length
	var merged := 0
	for alias in WANTED.keys():
		var want: String = WANTED[alias]
		var src_name := _resolve_name(found, want)
		if src_name.is_empty():
			push_warning("Pro missing clip for %s (alias %s)" % [want, alias])
			continue
		var anim: Animation = player.get_animation(src_name)
		if anim == null:
			continue
		var copy := anim.duplicate(true) as Animation
		if alias in MATCH_WALK_LENGTH and walk_len > 0.01 and copy.length > 0.01:
			_stretch_animation(copy, walk_len)
			print("STRETCH ", alias, " ", snapped(anim.length, 0.001), "→", snapped(copy.length, 0.001))
		copy.loop_mode = Animation.LOOP_LINEAR
		if lib.has_animation(StringName(alias)):
			lib.remove_animation(StringName(alias))
		lib.add_animation(StringName(alias), copy)
		print("MERGED ", alias, " from ", src_name, " tracks=", copy.get_track_count())
		merged += 1
	for stale in ["Jog_Fwd", "Jog_Fwd_LeanL", "Jog_Fwd_LeanR", "Walk_Fwd_L", "Walk_Fwd_R", "Walk_Bwd_L", "Walk_Bwd_R", "Walk_Bwd", "Walk_L", "Walk_R", "Sprint"]:
		if lib.has_animation(StringName(stale)):
			lib.remove_animation(StringName(stale))
			print("REMOVED ", stale)
	var err := ResourceSaver.save(lib, LIBRARY)
	print("SAVE_ERR=", err, " MERGED=", merged, " LIB_COUNT=", lib.get_animation_list().size())
	root.free()
	quit(0 if err == OK and merged > 0 else 3)


func _stretch_animation(anim: Animation, target_len: float) -> void:
	if anim.length <= 0.001 or is_equal_approx(anim.length, target_len):
		anim.length = target_len
		return
	var scale := target_len / anim.length
	for track_i in anim.get_track_count():
		var key_count := anim.track_get_key_count(track_i)
		if scale >= 1.0:
			for key_i in range(key_count - 1, -1, -1):
				var t := anim.track_get_key_time(track_i, key_i)
				anim.track_set_key_time(track_i, key_i, t * scale)
		else:
			for key_i in key_count:
				var t := anim.track_get_key_time(track_i, key_i)
				anim.track_set_key_time(track_i, key_i, t * scale)
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


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
