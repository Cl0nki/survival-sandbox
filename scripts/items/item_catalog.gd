extends RefCounted
class_name ItemCatalog

## Loads every ItemDefinition under resources/items. Unknown ids are rejected.

const ROOT := "res://resources/items"

static var _items: Dictionary = {}
static var _ready := false


static func get_item(item_id: String) -> ItemDefinition:
	_ensure()
	return _items.get(item_id) as ItemDefinition


static func known(item_id: String) -> bool:
	return get_item(item_id) != null


static func all_ids() -> PackedStringArray:
	_ensure()
	var ids := PackedStringArray()
	for item_id in _items.keys():
		ids.append(str(item_id))
	ids.sort()
	return ids


static func debug_register(definition: ItemDefinition) -> void:
	_ensure()
	if definition == null or definition.id.is_empty():
		return
	_items[definition.id] = definition


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	_scan(ROOT)


static func _scan(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("item catalog missing folder %s" % path)
		return
	var script := load("res://scripts/items/item_definition.gd") as Script
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var child := path.path_join(name)
		if dir.current_is_dir():
			_scan(child)
		elif name.ends_with(".tres"):
			_load_file(child, script)
		name = dir.get_next()
	dir.list_dir_end()


static func _load_file(path: String, script: Script) -> void:
	var loaded: Resource = load(path)
	if loaded == null or not is_instance_of(loaded, script):
		push_error("item catalog missing %s" % path)
		return
	var definition := loaded as ItemDefinition
	if definition.id.is_empty():
		push_error("item catalog blank id %s" % path)
		return
	_items[definition.id] = definition
