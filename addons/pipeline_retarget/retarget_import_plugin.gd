@tool
extends EditorScenePostImportPlugin

const QUATERNIUS_GLB := "res://assets/characters/Shared/Quaternius/AnimationLibrary_Godot_Standard.glb"
const QUATERNIUS_PRO_GLB := "res://assets/characters/Shared/Quaternius/AnimationLibrary_Godot_Pro.glb"
const UAL2_DIR := "res://assets/characters/Shared/Quaternius/ual2/"
const QUATERNIUS_BONE_MAP := "res://assets/characters/Shared/Quaternius/QuaterniusBoneMap.tres"
const QUATERNIUS_PRO_BONE_MAP := "res://assets/characters/Shared/Quaternius/QuaterniusProBoneMap.tres"
const UAL2_BONE_MAP := "res://assets/characters/Shared/Quaternius/ual2/UAL2BoneMap.tres"
const CHARACTER_BONE_MAP := "res://assets/characters/Shared/GodotHumanoidBoneMap.tres"


func _get_internal_import_options(category: int) -> void:
	pass


func _pre_process(scene: Node) -> void:
	var source := _source_path()
	if source.is_empty():
		return
	var bone_map_path := ""
	var fix_silhouette := false
	var is_anim_lib := false
	if source == QUATERNIUS_GLB or source.ends_with("/Quaternius/AnimationLibrary_Godot_Standard.glb"):
		bone_map_path = QUATERNIUS_BONE_MAP
		is_anim_lib = true
	elif source == QUATERNIUS_PRO_GLB or source.ends_with("/Quaternius/AnimationLibrary_Godot_Pro.glb"):
		bone_map_path = QUATERNIUS_PRO_BONE_MAP
		is_anim_lib = true
	elif source.begins_with(UAL2_DIR) and source.ends_with(".glb"):
		bone_map_path = UAL2_BONE_MAP
		is_anim_lib = true
	elif source.begins_with("res://assets/characters/") and source.ends_with(".glb") and not "/Shared/" in source:
		bone_map_path = CHARACTER_BONE_MAP
		fix_silhouette = true
	else:
		return
	if not ResourceLoader.exists(bone_map_path):
		push_warning("Pipeline Retarget: missing BoneMap at %s" % bone_map_path)
		return
	var bone_map: BoneMap = load(bone_map_path)
	if bone_map == null:
		push_warning("Pipeline Retarget: failed to load %s" % bone_map_path)
		return

	var subresources: Dictionary = get_option_value("_subresources")
	if subresources.is_empty():
		subresources = {}
	if not subresources.has("nodes"):
		subresources["nodes"] = {}
	var nodes: Dictionary = subresources["nodes"]

	var skeleton_paths := _find_skeleton_paths(scene)
	if skeleton_paths.is_empty():
		skeleton_paths = ["Skeleton3D", "Rig/Skeleton3D", "Armature/Skeleton3D"]

	for skel_path in skeleton_paths:
		var key := "PATH:%s" % skel_path
		var entry: Dictionary = nodes.get(key, {})
		if typeof(entry) != TYPE_DICTIONARY:
			entry = {}
		entry["rest_pose/external_animation_library"] = null
		entry["retarget/bone_map"] = bone_map
		entry["retarget/bone_renamer/rename_bones"] = true
		entry["retarget/bone_renamer/unique_node/make_unique"] = true
		entry["retarget/bone_renamer/unique_node/skeleton_name"] = "GeneralSkeleton"
		# 2 = Use Retarget Modifier. Clips land in profile space and share
		# across meshes. Overwrite Axis rewrites the skin and still depends
		# on the source rest, which is what folded the copied walks.
		entry["retarget/rest_fixer/apply_node_transforms"] = true
		entry["retarget/rest_fixer/normalize_position_tracks"] = true
		entry["retarget/rest_fixer/reset_all_bone_poses_after_import"] = true
		entry["retarget/rest_fixer/retarget_method"] = 2
		entry["retarget/rest_fixer/keep_global_rest_on_leftovers"] = true
		entry["retarget/rest_fixer/use_global_pose"] = false
		entry["retarget/rest_fixer/original_skeleton_name"] = "OriginalSkeleton"
		entry["retarget/rest_fix_silhouette"] = fix_silhouette
		entry["retarget/rest_fixer/fix_silhouette/enable"] = fix_silhouette
		if is_anim_lib:
			entry["retarget/remove_tracks_unmapped_bones"] = true
			entry["retarget/remove_tracks_unimportant_positions"] = true
			# 1 = Remove. The 4.7 option is an enum, not a bool.
			entry["retarget/remove_tracks/unmapped_bones"] = 1
			entry["retarget/remove_tracks/unimportant_positions"] = true
		nodes[key] = entry

	subresources["nodes"] = nodes
	# Keep the mutated dictionary on the importer options object.
	# get_option_value returns the live dictionary for _subresources when present.


func _source_path() -> String:
	if has_method("get_source_file"):
		return str(call("get_source_file"))
	return ""


func _find_skeleton_paths(root: Node) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	_walk(root, root, found)
	return found


func _walk(root: Node, node: Node, found: PackedStringArray) -> void:
	if node is Skeleton3D:
		found.append(str(root.get_path_to(node)))
	for child in node.get_children():
		_walk(root, child, found)
