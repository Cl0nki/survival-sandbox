extends RefCounted
class_name ItemCatalog

## Loads the prototype item resources once. Unknown ids are rejected.

const FILES: Array[String] = [
	"res://resources/items/scrap_metal.tres",
	"res://resources/items/cloth.tres",
	"res://resources/items/medical_supplies.tres",
	"res://resources/items/ammunition.tres",
	"res://resources/items/canned_food.tres",
	"res://resources/items/debug_weapon.tres",
	"res://resources/items/build_tool.tres",
]

static var _items: Dictionary = {}
static var _ready := false


static func get_item(item_id: String) -> ItemDefinition:
	_ensure()
	return _items.get(item_id) as ItemDefinition


static func known(item_id: String) -> bool:
	return get_item(item_id) != null


static func debug_register(definition: ItemDefinition) -> void:
	_ensure()
	if definition == null or definition.id.is_empty():
		return
	_items[definition.id] = definition


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	var script := load("res://scripts/items/item_definition.gd") as Script
	for path in FILES:
		var loaded: Resource = load(path)
		if loaded == null or not is_instance_of(loaded, script):
			push_error("item catalog missing %s" % path)
			continue
		var definition := loaded as ItemDefinition
		if definition.id.is_empty():
			push_error("item catalog blank id %s" % path)
			continue
		_items[definition.id] = definition
