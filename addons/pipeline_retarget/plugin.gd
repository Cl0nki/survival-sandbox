@tool
extends EditorPlugin

const QuaterniusImport := preload("res://addons/pipeline_retarget/retarget_import_plugin.gd")

var _import_plugin: EditorScenePostImportPlugin
var _reimport_queued := false


func _enter_tree() -> void:
	_import_plugin = QuaterniusImport.new()
	add_scene_post_import_plugin(_import_plugin)
	# Defer so the filesystem is ready after plugin load.
	call_deferred("_queue_reimport")


func _exit_tree() -> void:
	if _import_plugin:
		remove_scene_post_import_plugin(_import_plugin)
		_import_plugin = null


func _queue_reimport() -> void:
	if _reimport_queued:
		return
	_reimport_queued = true
	var stamp_path := "res://addons/pipeline_retarget/.reimport_stamp"
	var expected := "quaternius-v1"
	if FileAccess.file_exists(stamp_path):
		var existing_stamp := FileAccess.get_file_as_string(stamp_path).strip_edges()
		if existing_stamp == expected:
			return
	var paths: PackedStringArray = PackedStringArray([
		"res://assets/characters/Shared/Quaternius/AnimationLibrary_Godot_Standard.glb",
		"res://assets/characters/workshop_survivor_01.glb",
	])
	var existing: PackedStringArray = PackedStringArray()
	for path in paths:
		if FileAccess.file_exists(path):
			existing.append(path)
	if existing.is_empty():
		return
	print("Pipeline Retarget: reimporting ", existing)
	EditorInterface.get_resource_filesystem().reimport_files(existing)
	var file := FileAccess.open(stamp_path, FileAccess.WRITE)
	if file:
		file.store_string(expected)
		file.close()

