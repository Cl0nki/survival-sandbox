extends RefCounted
class_name ConstructionPlan

## Every change a placement would make, computed before anything is written.
## A plan is read-only data: building it never touches BuildingState. The
## authority commits a plan only if it is valid and was planned against the
## current state revision, so a commit is all-or-nothing.
##
## Entry fields:
##   action    BuildTypes.Action
##   kind      BuildTypes.Kind
##   key       canonical slot key
##   existing  id of the committed piece reused, replaced, or removed (0 if none)
##   reason    short text for the preview and for rejections
##   cells     stairs only: covered cells
##   pinned    posts only: explicit support placement

var blueprint: BlueprintDefinition
var request: Dictionary = {}
var level := 0
var rotation := 0
var state_revision := -1
var entries: Array[Dictionary] = []
## Plan-level problems that are not tied to a single slot.
var errors: PackedStringArray = []
## Room claim: cells as Vector3i(x, level, z). Empty for non-room blueprints.
var room_cells: Array[Vector3i] = []
## Id of an identical room already standing here (repeat placement).
var reused_room := 0
## World footprint cells, for the preview outline.
var footprint_cells: Array[Vector2i] = []
## Blueprint front direction in world space (local +Z after rotation).
var front := Vector2i(0, 1)
var cost: Dictionary = {}
## Existing posts that this plan turns into explicit supports.
var pin_changes := 0
var _index: Dictionary = {}


func entry_for(kind: int, key: Variant) -> Dictionary:
	var slot := _slot_name(kind, key)
	if not _index.has(slot):
		return {}
	return entries[int(_index[slot])]


func add_entry(action: int, kind: int, key: Variant, existing: int = 0, reason: String = "") -> Dictionary:
	var slot := _slot_name(kind, key)
	if _index.has(slot):
		return entries[int(_index[slot])]
	var entry := {
		"action": action,
		"kind": kind,
		"key": key,
		"existing": existing,
		"reason": reason,
		"cells": [],
		"pinned": false,
	}
	_index[slot] = entries.size()
	entries.append(entry)
	return entry


static func conflict(entry: Dictionary, reason: String) -> void:
	entry["action"] = BuildTypes.Action.CONFLICT
	entry["reason"] = reason


func is_valid() -> bool:
	if not errors.is_empty():
		return false
	for entry in entries:
		if int(entry["action"]) == BuildTypes.Action.CONFLICT:
			return false
	return true


func has_changes() -> bool:
	if pin_changes > 0 or (not room_cells.is_empty() and reused_room == 0):
		return true
	for entry in entries:
		var action := int(entry["action"])
		if action == BuildTypes.Action.CREATE or action == BuildTypes.Action.REPLACE or action == BuildTypes.Action.REMOVE:
			return true
	return false


func count(action: int, kind: int = -1) -> int:
	var total := 0
	for entry in entries:
		if int(entry["action"]) == action and (kind < 0 or int(entry["kind"]) == kind):
			total += 1
	return total


func reasons() -> PackedStringArray:
	var result := PackedStringArray()
	for message in errors:
		if not result.has(message):
			result.append(message)
	for entry in entries:
		if int(entry["action"]) != BuildTypes.Action.CONFLICT:
			continue
		var message := str(entry["reason"])
		if not result.has(message):
			result.append(message)
	return result


func first_reason() -> String:
	var all := reasons()
	return "" if all.is_empty() else all[0]


func sort_entries() -> void:
	entries.sort_custom(_entry_before)
	_index.clear()
	for i in entries.size():
		_index[_slot_name(int(entries[i]["kind"]), entries[i]["key"])] = i


## Short summary lines for the HUD and the world label.
func summary_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var parts := PackedStringArray()
	for kind in [BuildTypes.Kind.SLAB, BuildTypes.Kind.WALL, BuildTypes.Kind.DOORWAY, BuildTypes.Kind.WINDOW, BuildTypes.Kind.POST, BuildTypes.Kind.STAIRS]:
		var made := count(BuildTypes.Action.CREATE, kind) + count(BuildTypes.Action.REPLACE, kind)
		if made > 0:
			parts.append("+%d %s" % [made, BuildTypes.kind_name(kind).to_lower()])
	if not parts.is_empty():
		lines.append("New: " + ", ".join(parts))
	var reused := count(BuildTypes.Action.REUSE)
	var replaced := count(BuildTypes.Action.REPLACE)
	var removed := count(BuildTypes.Action.REMOVE)
	var shared := PackedStringArray()
	if reused > 0:
		shared.append("%d reused" % reused)
	if replaced > 0:
		shared.append("%d replaced" % replaced)
	if removed > 0:
		shared.append("%d opened" % removed)
	if not shared.is_empty():
		lines.append("Existing: " + ", ".join(shared))
	var skipped := count(BuildTypes.Action.SKIP)
	if skipped > 0:
		lines.append("%d stairwell cell(s) left open" % skipped)
	if not cost.is_empty():
		var costs := PackedStringArray()
		for item_id in cost.keys():
			costs.append("%d %s" % [int(cost[item_id]), str(item_id)])
		lines.append("Cost: " + ", ".join(costs))
	if is_valid() and not has_changes():
		lines.append("Already built here - nothing to add")
	return lines


static func _slot_name(kind: int, key: Variant) -> String:
	var family := kind
	if BuildTypes.is_edge_kind(kind):
		family = BuildTypes.Kind.WALL
	return "%d|%s" % [family, str(key)]


static func _entry_before(a: Dictionary, b: Dictionary) -> bool:
	var pa := _phase(a)
	var pb := _phase(b)
	if pa != pb:
		return pa < pb
	var ka := _kind_order(int(a["kind"]))
	var kb := _kind_order(int(b["kind"]))
	if ka != kb:
		return ka < kb
	return _key_before(a["key"], b["key"])


static func _phase(entry: Dictionary) -> int:
	return 0 if int(entry["action"]) == BuildTypes.Action.REMOVE else 1


static func _kind_order(kind: int) -> int:
	match kind:
		BuildTypes.Kind.SLAB:
			return 0
		BuildTypes.Kind.POST:
			return 1
		BuildTypes.Kind.STAIRS:
			return 3
		_:
			return 2


static func _key_before(a: Variant, b: Variant) -> bool:
	if a is Vector4i and b is Vector4i:
		var va: Vector4i = a
		var vb: Vector4i = b
		return va < vb
	if a is Vector3i and b is Vector3i:
		var wa: Vector3i = a
		var wb: Vector3i = b
		return wa < wb
	return str(a) < str(b)
