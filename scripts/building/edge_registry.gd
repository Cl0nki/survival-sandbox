extends RefCounted
class_name EdgeRegistry

## Single owner of every wall boundary. A canonical edge key maps to at most
## one committed edge piece (wall, doorway, or window). Rooms never own walls;
## they add a reference to the boundary they share. Doorways and windows swap
## the piece on a boundary instead of being stacked on top of a wall.
##
## Stairs register rules that restrict what may stand on the edges they cross.

var _owner: Dictionary = {}
var _room_refs: Dictionary = {}
## key -> Dictionary(stairs id -> allowed kind mask)
var _rules: Dictionary = {}
## Incremented whenever a caller tried to claim a boundary that already had a
## different owner. The planner prevents this; tests assert it stays 0.
var rejected_claims := 0


func component_at(key: Vector4i) -> int:
	return int(_owner.get(key, 0))


func has_piece(key: Vector4i) -> bool:
	return _owner.has(key)


func claim(key: Vector4i, component_id: int) -> bool:
	var current := component_at(key)
	if current != 0 and current != component_id:
		rejected_claims += 1
		push_error("EdgeRegistry: boundary %s already owned by #%d, refused #%d" % [key, current, component_id])
		return false
	_owner[key] = component_id
	return true


func release(key: Vector4i, component_id: int) -> bool:
	if component_at(key) != component_id:
		return false
	_owner.erase(key)
	return true


func add_room_ref(key: Vector4i, room_id: int) -> void:
	var refs: PackedInt32Array = _room_refs.get(key, PackedInt32Array())
	if not refs.has(room_id):
		refs.append(room_id)
	_room_refs[key] = refs


func rooms_for(key: Vector4i) -> PackedInt32Array:
	return _room_refs.get(key, PackedInt32Array())


func set_rule(key: Vector4i, stairs_id: int, allowed_mask: int) -> void:
	var rules: Dictionary = _rules.get(key, {})
	rules[stairs_id] = allowed_mask
	_rules[key] = rules


func clear_rules_for(stairs_id: int) -> void:
	for key in _rules.keys():
		var rules: Dictionary = _rules[key]
		rules.erase(stairs_id)
		if rules.is_empty():
			_rules.erase(key)


## Whether a piece of this kind may stand on the boundary. EDGE_OPEN is always allowed.
func allows(key: Vector4i, kind: int) -> bool:
	if kind == BuildTypes.EDGE_OPEN or not _rules.has(key):
		return true
	var rules: Dictionary = _rules[key]
	for mask in rules.values():
		if (int(mask) & (1 << kind)) == 0:
			return false
	return true


func restricted(key: Vector4i) -> bool:
	return _rules.has(key)


func keys() -> Array:
	return _owner.keys()


func size() -> int:
	return _owner.size()
