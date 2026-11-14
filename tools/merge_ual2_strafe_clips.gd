extends SceneTree

## Merge Quaternius UAL2 clips into ual_locomotion.res.
## Every UAL2 GLB imports as a real skeleton with UAL2BoneMap + rest fixer, so
## the clips sit on the same rest as the Pro mannequin (walks, mining, chopping).
## The path rewrite below only matters for a GLB that still imports as raw nodes.

const LIBRARY := "res://assets/characters/Shared/Quaternius/ual_locomotion.res"
const SOURCES := {
	"res://assets/characters/Shared/Quaternius/ual2/quaternius-ual2-walk-l-loop.glb": "Walk_L",
	"res://assets/characters/Shared/Quaternius/ual2/quaternius-ual2-walk-r-loop.glb": "Walk_R",
	"res://assets/characters/Shared/Quaternius/ual2/quaternius-ual2-walk-bwd-loop.glb": "Walk_Bwd",
	"res://assets/characters/Shared/Quaternius/ual2/quaternius-ual2-mining-loop.glb": "Mining",
	"res://assets/characters/Shared/Quaternius/ual2/quaternius-ual2-tree-chopping-loop.glb": "TreeChopping",
}


func _init() -> void:
	var lib: AnimationLibrary = load(LIBRARY) as AnimationLibrary
	if lib == null:
		push_error("Failed to load %s" % LIBRARY)
		quit(1)
		return
	for path in SOURCES.keys():
		var alias: String = SOURCES[path]
		if not ResourceLoader.exists(path):
			push_error("Missing source %s" % path)
			quit(2)
			return
		var anim := _load_clip(str(path))
		if anim == null:
			push_error("Failed to extract clip from %s" % path)
			quit(2)
			return
		if lib.has_animation(StringName(alias)):
			lib.remove_animation(StringName(alias))
		lib.add_animation(StringName(alias), anim)
		print("MERGED ", alias, " length=", anim.length, " tracks=", anim.get_track_count())
	var err := ResourceSaver.save(lib, LIBRARY)
	print("SAVE_ERR=", err, " LIB_COUNT=", lib.get_animation_list().size())
	quit(0 if err == OK else 3)


func _load_clip(path: String) -> Animation:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var root: Node = packed.instantiate()
	var player := _find_animation_player(root)
	if player == null:
		root.free()
		return null
	var names: PackedStringArray = player.get_animation_list()
	if names.is_empty():
		root.free()
		return null
	var source: Animation = player.get_animation(names[0])
	if source == null:
		root.free()
		return null
	var out := source.duplicate(true) as Animation
	_retarget_tracks(out)
	root.free()
	return out


func _retarget_tracks(anim: Animation) -> void:
	for i in anim.get_track_count():
		var path := String(anim.track_get_path(i))
		var rewritten := _rewrite_path(path)
		if rewritten != path:
			anim.track_set_path(i, NodePath(rewritten))


func _rewrite_path(path: String) -> String:
	var parts := path.split(":")
	if parts.is_empty():
		return path
	var bone := parts[0]
	if "/" in bone:
		bone = bone.get_file()
	var pascal := _to_pascal(bone)
	if pascal.is_empty():
		return path
	var rest := ""
	if parts.size() > 1:
		rest = ":" + ":".join(parts.slice(1))
	return "%%GeneralSkeleton:%s%s" % [pascal, rest]


func _to_pascal(bone: String) -> String:
	match bone:
		"hips", "Hips":
			return "Hips"
		"spine", "Spine":
			return "Spine"
		"chest", "Chest":
			return "Chest"
		"upperChest", "UpperChest":
			return "UpperChest"
		"neck", "Neck":
			return "Neck"
		"head", "Head":
			return "Head"
		"leftShoulder", "LeftShoulder":
			return "LeftShoulder"
		"leftUpperArm", "LeftUpperArm":
			return "LeftUpperArm"
		"leftLowerArm", "LeftLowerArm":
			return "LeftLowerArm"
		"leftHand", "LeftHand":
			return "LeftHand"
		"rightShoulder", "RightShoulder":
			return "RightShoulder"
		"rightUpperArm", "RightUpperArm":
			return "RightUpperArm"
		"rightLowerArm", "RightLowerArm":
			return "RightLowerArm"
		"rightHand", "RightHand":
			return "RightHand"
		"leftUpperLeg", "LeftUpperLeg":
			return "LeftUpperLeg"
		"leftLowerLeg", "LeftLowerLeg":
			return "LeftLowerLeg"
		"leftFoot", "LeftFoot":
			return "LeftFoot"
		"leftToes", "LeftToes":
			return "LeftToes"
		"rightUpperLeg", "RightUpperLeg":
			return "RightUpperLeg"
		"rightLowerLeg", "RightLowerLeg":
			return "RightLowerLeg"
		"rightFoot", "RightFoot":
			return "RightFoot"
		"rightToes", "RightToes":
			return "RightToes"
		"leftThumbMetacarpal", "LeftThumbMetacarpal":
			return "LeftThumbMetacarpal"
		"leftThumbProximal", "LeftThumbProximal":
			return "LeftThumbProximal"
		"leftThumbDistal", "LeftThumbDistal":
			return "LeftThumbDistal"
		"leftIndexProximal", "LeftIndexProximal":
			return "LeftIndexProximal"
		"leftIndexIntermediate", "LeftIndexIntermediate":
			return "LeftIndexIntermediate"
		"leftIndexDistal", "LeftIndexDistal":
			return "LeftIndexDistal"
		"leftMiddleProximal", "LeftMiddleProximal":
			return "LeftMiddleProximal"
		"leftMiddleIntermediate", "LeftMiddleIntermediate":
			return "LeftMiddleIntermediate"
		"leftMiddleDistal", "LeftMiddleDistal":
			return "LeftMiddleDistal"
		"leftRingProximal", "LeftRingProximal":
			return "LeftRingProximal"
		"leftRingIntermediate", "LeftRingIntermediate":
			return "LeftRingIntermediate"
		"leftRingDistal", "LeftRingDistal":
			return "LeftRingDistal"
		"leftLittleProximal", "LeftLittleProximal":
			return "LeftLittleProximal"
		"leftLittleIntermediate", "LeftLittleIntermediate":
			return "LeftLittleIntermediate"
		"leftLittleDistal", "LeftLittleDistal":
			return "LeftLittleDistal"
		"rightThumbMetacarpal", "RightThumbMetacarpal":
			return "RightThumbMetacarpal"
		"rightThumbProximal", "RightThumbProximal":
			return "RightThumbProximal"
		"rightThumbDistal", "RightThumbDistal":
			return "RightThumbDistal"
		"rightIndexProximal", "RightIndexProximal":
			return "RightIndexProximal"
		"rightIndexIntermediate", "RightIndexIntermediate":
			return "RightIndexIntermediate"
		"rightIndexDistal", "RightIndexDistal":
			return "RightIndexDistal"
		"rightMiddleProximal", "RightMiddleProximal":
			return "RightMiddleProximal"
		"rightMiddleIntermediate", "RightMiddleIntermediate":
			return "RightMiddleIntermediate"
		"rightMiddleDistal", "RightMiddleDistal":
			return "RightMiddleDistal"
		"rightRingProximal", "RightRingProximal":
			return "RightRingProximal"
		"rightRingIntermediate", "RightRingIntermediate":
			return "RightRingIntermediate"
		"rightRingDistal", "RightRingDistal":
			return "RightRingDistal"
		"rightLittleProximal", "RightLittleProximal":
			return "RightLittleProximal"
		"rightLittleIntermediate", "RightLittleIntermediate":
			return "RightLittleIntermediate"
		"rightLittleDistal", "RightLittleDistal":
			return "RightLittleDistal"
		_:
			return ""


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
