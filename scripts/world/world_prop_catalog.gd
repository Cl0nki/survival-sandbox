extends RefCounted
class_name WorldPropCatalog

## Every non-placeable world object in one table, keyed like the deployables:
## one id for the definition, the gameplay box, the mesh and the Meshy job.
## The .tres files in resources/world_props are written by tools/gen_world_props.py.
## Health, tool and yield for harvest nodes stay in ResourceCatalog.
## Clients never accept a definition from the net.

const ROOT := "res://resources/world_props"
## Listed by id so an exported build finds every file without scanning.
const ORDER: PackedStringArray = [
	"stone_node",
	"iron_ore_node",
	"copper_ore_node",
	"coal_node",
	"limestone_node",
	"sulfur_node",
	"bauxite_node",
	"lead_ore_node",
	"quartz_node",
	"tree_oak",
	"tree_birch",
	"tree_spruce",
	"cactus",
	"dead_bush",
	"broken_car",
	"scrap_pile",
	"rubble_pile",
	"tire_pile",
	"drum_stack",
	"appliance_pile",
	"loot_crate",
]

const KIND_RESOURCE := "resource"
const KIND_CRATE := "crate"

static var _by_id: Dictionary = {}
static var _by_deposit: Dictionary = {}
static var _ready := false


static func get_definition(prop_id: String) -> WorldPropDefinition:
	_ensure()
	return _by_id.get(prop_id) as WorldPropDefinition


static func known(prop_id: String) -> bool:
	return get_definition(prop_id) != null


static func all_ids() -> PackedStringArray:
	_ensure()
	var ids := PackedStringArray()
	for prop_id in ORDER:
		if _by_id.has(prop_id):
			ids.append(prop_id)
	return ids


static func display_name(prop_id: String) -> String:
	var definition := get_definition(prop_id)
	return prop_id if definition == null else definition.display_name


static func kind_of(prop_id: String) -> String:
	var definition := get_definition(prop_id)
	return "" if definition == null else definition.kind


## The visual box in meters. Vector3.ZERO for an unknown id.
static func body_size(prop_id: String) -> Vector3:
	var definition := get_definition(prop_id)
	return Vector3.ZERO if definition == null else definition.body_size


## Harvest nodes take health from ResourceCatalog. Crates cannot be damaged, so 0.
static func max_health(prop_id: String) -> int:
	var definition := get_definition(prop_id)
	if definition == null or definition.deposit_id.is_empty():
		return 0
	var deposit := ResourceCatalog.get_deposit(definition.deposit_id)
	return 0 if deposit == null else deposit.health


## Prop id for a ResourceCatalog deposit, or "" when the deposit has none.
static func id_for_deposit(deposit_id: String) -> String:
	_ensure()
	return str(_by_deposit.get(deposit_id, ""))


static func art_path(prop_id: String) -> String:
	return WorldPropArt.path_for(prop_id)


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	for prop_id in ORDER:
		var path := "%s/%s.tres" % [ROOT, prop_id]
		var loaded := load(path) as WorldPropDefinition
		if loaded == null or loaded.id != prop_id:
			push_error("world prop catalog missing or mismatched %s" % path)
			continue
		_by_id[prop_id] = loaded
		if not loaded.deposit_id.is_empty():
			_by_deposit[loaded.deposit_id] = prop_id
