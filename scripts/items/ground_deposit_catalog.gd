extends RefCounted
class_name GroundDepositCatalog

## Loads GroundDepositDefinition resources. Clients never accept a definition from the net.

const ROOT := "res://resources/ground_deposits"
const ORDER: PackedStringArray = [
	"sand",
	"clay",
	"gravel",
	"ground_water",
	"natural_gas",
	"crude_oil",
]

static var _by_id: Dictionary = {}
static var _ready := false


static func get_definition(deposit_id: String) -> GroundDepositDefinition:
	_ensure()
	return _by_id.get(deposit_id) as GroundDepositDefinition


static func known(deposit_id: String) -> bool:
	return get_definition(deposit_id) != null


static func all_ids() -> PackedStringArray:
	_ensure()
	var ids := PackedStringArray()
	for deposit_id in ORDER:
		if _by_id.has(deposit_id):
			ids.append(deposit_id)
	return ids


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	var script := load("res://scripts/items/ground_deposit_definition.gd") as Script
	var dir := DirAccess.open(ROOT)
	if dir == null:
		push_error("ground deposit catalog missing folder %s" % ROOT)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with(".") and name.ends_with(".tres"):
			_load_file(ROOT.path_join(name), script)
		name = dir.get_next()
	dir.list_dir_end()


static func _load_file(path: String, script: Script) -> void:
	var loaded: Resource = load(path)
	if loaded == null or not is_instance_of(loaded, script):
		push_error("ground deposit catalog missing %s" % path)
		return
	var definition := loaded as GroundDepositDefinition
	if definition.id.is_empty():
		push_error("ground deposit catalog blank id %s" % path)
		return
	_by_id[definition.id] = definition
