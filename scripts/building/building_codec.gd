extends RefCounted
class_name BuildingCodec

## RPC-safe copies of logical pieces and rooms. Clients rebuild slots from
## these records. They never receive scene nodes or construction plans.


static func piece(state: BuildingState, component: BuildComponent) -> Dictionary:
	var record := {
		"id": component.id,
		"kind": component.kind,
		"health": component.health,
		"max_health": component.max_health,
		"material": component.material,
		"pinned": component.pinned,
		"rooms": component.rooms.duplicate(),
		"cells": PackedInt32Array(),
		"exit": PackedInt32Array(),
		"rules": [],
	}
	if component.key is Vector3i:
		var key: Vector3i = component.key
		record["rank"] = 3
		record["kx"] = key.x
		record["ky"] = key.y
		record["kz"] = key.z
		record["kw"] = 0
	else:
		var key: Vector4i = component.key
		record["rank"] = 4
		record["kx"] = key.x
		record["ky"] = key.y
		record["kz"] = key.z
		record["kw"] = key.w
	if component.kind != BuildTypes.Kind.STAIRS:
		return record
	var cells := PackedInt32Array()
	for cell in component.cells:
		cells.append_array(PackedInt32Array([cell.x, cell.y, cell.z]))
	record["cells"] = cells
	for exit_key in state.stair_exits.keys():
		if int(state.stair_exits[exit_key]) != component.id:
			continue
		var exit: Vector3i = exit_key
		record["exit"] = PackedInt32Array([exit.x, exit.y, exit.z])
		break
	var rules: Array = []
	for rule in state.edges.rules_for(component.id):
		var edge: Vector4i = rule[0]
		rules.append(PackedInt32Array([edge.x, edge.y, edge.z, edge.w, int(rule[1])]))
	record["rules"] = rules
	return record


static func room(state: BuildingState, room_id: int) -> Dictionary:
	var src: Dictionary = state.rooms.get(room_id, {})
	if src.is_empty():
		return {}
	var request: Dictionary = src.get("request", {})
	var anchor: Vector2i = request.get("anchor", Vector2i.ZERO)
	var size: Vector2i = request.get("size", Vector2i.ZERO)
	var cells := PackedInt32Array()
	for cell in src.get("cells", []):
		var key: Vector3i = cell
		cells.append_array(PackedInt32Array([key.x, key.y, key.z]))
	return {
		"id": room_id,
		"blueprint": str(src.get("blueprint", "")),
		"ax": anchor.x,
		"ay": anchor.y,
		"rotation": int(request.get("rotation", 0)),
		"level": int(request.get("level", 0)),
		"axis": int(request.get("axis", 0)),
		"target": int(request.get("target", 0)),
		"sx": size.x,
		"sy": size.y,
		"cells": cells,
	}
