extends RefCounted
class_name ResourceDeposit

## One harvestable deposit type. Nodes look this up by id.

var id := ""
var display_name := ""
var item_id := ""
var health := 40
var yield_amount := 8
var tool_kind := "pickaxe"
var resistance := 1.0
var tool_multiplier := 1.0
var color := Color(0.52, 0.52, 0.50)
var visual := "rock"
var foliage_color := Color(0.22, 0.42, 0.18)
var yields: Array = []


func yield_entries() -> Array:
	if not yields.is_empty():
		return yields
	if item_id != "" and yield_amount > 0:
		return [[item_id, yield_amount]]
	return []


func yield_label() -> String:
	var parts: PackedStringArray = []
	for entry in yield_entries():
		parts.append("%s %d" % [str(entry[0]).replace("_", " "), int(entry[1])])
	return "  ".join(parts)
