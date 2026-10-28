extends RefCounted
class_name BlueprintCatalog

## Loads blueprint resources once. Requests name a blueprint by id; the
## authority never accepts a blueprint definition from a caller.

const CATEGORY_ORDER: Array[String] = ["Rooms", "Walls", "Openings", "Floors & Ceilings", "Stairs", "Supports", "Tools"]
const FILES: Array[String] = [
	"res://resources/blueprints/room.tres",
	"res://resources/blueprints/wall.tres",
	"res://resources/blueprints/doorway.tres",
	"res://resources/blueprints/window.tres",
	"res://resources/blueprints/floor_1x1.tres",
	"res://resources/blueprints/stairs_straight.tres",
	"res://resources/blueprints/dismantle.tres",
]

static var _by_id: Dictionary = {}
static var _ordered: Array[BlueprintDefinition] = []
static var _ready := false


static func get_blueprint(blueprint_id: String) -> BlueprintDefinition:
	_ensure()
	return _by_id.get(blueprint_id) as BlueprintDefinition


static func all() -> Array[BlueprintDefinition]:
	_ensure()
	return _ordered.duplicate()


static func load_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	for path in FILES:
		var loaded := load(path) as BlueprintDefinition
		if loaded == null:
			problems.append("missing or wrong type: %s" % path)
			continue
		problems.append_array(loaded.validate())
	return problems


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	for path in FILES:
		var loaded := load(path) as BlueprintDefinition
		if loaded == null:
			push_error("blueprint catalog missing %s" % path)
			continue
		var problems := loaded.validate()
		if not problems.is_empty():
			push_error("blueprint %s invalid: %s" % [path, ", ".join(problems)])
			continue
		_by_id[loaded.id] = loaded
		_ordered.append(loaded)
	_ordered.sort_custom(_before)


static func _before(a: BlueprintDefinition, b: BlueprintDefinition) -> bool:
	var ca := CATEGORY_ORDER.find(a.category)
	var cb := CATEGORY_ORDER.find(b.category)
	if ca != cb:
		return ca < cb
	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order
	return a.id < b.id
