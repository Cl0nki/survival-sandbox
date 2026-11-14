extends SceneTree

const SOURCE := "res://assets/characters/Shared/Quaternius/AnimationLibrary_Godot_Standard.glb"
const OUTPUT := "res://assets/characters/Shared/Quaternius/ual_locomotion.res"
const WANTED := ["Idle_Loop", "Walk_Loop", "Pistol_Aim_Down", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Shoot"]


func _init() -> void:
	var packed: PackedScene = load(SOURCE) as PackedScene
	if packed == null:
		push_error("Failed to load Quaternius PackedScene")
		quit(1)
		return
	var root: Node = packed.instantiate()
	var player := _find_animation_player(root)
	if player == null:
		push_error("No AnimationPlayer in Quaternius scene")
		quit(1)
		return
	var lib := AnimationLibrary.new()
	var names: PackedStringArray = player.get_animation_list()
	print("FOUND_CLIPS=", names.size())
	for anim_name in names:
		var anim: Animation = player.get_animation(anim_name)
		if anim == null:
			continue
		lib.add_animation(StringName(anim_name), anim.duplicate(true))
		if str(anim_name) in WANTED:
			print("PACKED ", anim_name, " tracks=", anim.get_track_count())
	var err := ResourceSaver.save(lib, OUTPUT)
	print("SAVE_ERR=", err, " PATH=", OUTPUT, " LIB_COUNT=", lib.get_animation_list().size())
	root.free()
	quit(0 if err == OK else 2)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
