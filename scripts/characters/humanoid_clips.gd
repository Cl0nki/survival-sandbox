extends RefCounted
class_name HumanoidClips

## One profile-space clip set for every humanoid mesh.
## Import those GLBs with Retarget Method = Use Retarget Modifier, then bake
## with tools/bake_shared_locomotion.gd. Do not rewrite track paths: the
## importer already stored rotations in SkeletonProfileHumanoid space.

const LIBRARY_PATH := "res://assets/characters/Shared/Quaternius/ual_locomotion.res"


static func install(model: Node) -> AnimationPlayer:
	if model == null:
		return null
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var lib := load(LIBRARY_PATH) as AnimationLibrary
	if player == null or lib == null:
		return null
	for lib_name in player.get_animation_library_list():
		player.remove_animation_library(lib_name)
	player.add_animation_library(&"", lib)
	player.root_node = player.get_path_to(model)
	player.active = true
	return player


## The mesh is skinned to OriginalSkeleton. GeneralSkeleton is the profile
## the clips drive, and RetargetModifier3D copies that pose onto the skin.
static func skinned_skeleton(model: Node) -> Skeleton3D:
	if model == null:
		return null
	var original := model.find_child("OriginalSkeleton", true, false) as Skeleton3D
	if original != null:
		return original
	return model.find_child("GeneralSkeleton", true, false) as Skeleton3D
