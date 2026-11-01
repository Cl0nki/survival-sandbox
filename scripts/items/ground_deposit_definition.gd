extends Resource
class_name GroundDepositDefinition

## One ground-patch type. Resistance and yield are independent.
## Wells and pumps later call extractor_kinds; they do not read the floor material.

@export var id := ""
@export var display_name := ""
@export var item_id := ""
@export var resistance := 100
@export var yield_amount := 500
@export var color := Color(0.85, 0.76, 0.54)
@export var harvest_kind := ""
@export var extractor_kinds: PackedStringArray = []


func can_extract_with(kind: String) -> bool:
	return kind != "" and extractor_kinds.has(kind)
