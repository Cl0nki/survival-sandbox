extends Resource
class_name BlueprintDefinition

## Reusable placement data. A blueprint never contains geometry or walls of its
## own: a room lists occupied cells and boundary overrides, and the planner
## derives the walls through the shared EdgeRegistry. Shared walls therefore
## exist once no matter how many rooms reference them.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var category := "Rooms"
@export var sort_order := 0
@export var kind: BuildTypes.BlueprintKind = BuildTypes.BlueprintKind.ROOM
## Rectangular footprint in cells, before rotation.
@export var footprint := Vector2i(1, 1)
@export var rotatable := true
## Rooms and floors: the player drags the footprint, from 1x1 up to max_size.
## footprint is then only the size of a plain click.
@export var resizable := false
@export var max_size := Vector2i(8, 8)
@export var has_floor := true
@export var has_ceiling := false
## Edge blueprints: which piece goes on the targeted boundary.
@export var edge_kind := BuildTypes.Kind.WALL as int
## Slab blueprints: 0 places a floor on the build level, 1 a ceiling above it.
@export var slab_level_offset := 0
## BlueprintOpening resources. Untyped so .tres files stay simple.
@export var openings: Array = []
## Shown in the selection UI. Enforced rules live in RoomPlacer.
@export var restrictions := ""


func cells() -> Array[Vector2i]:
	return cells_of(footprint)


static func cells_of(size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in size.y:
		for x in size.x:
			result.append(Vector2i(x, z))
	return result


## The footprint a request gets: the requested size for resizable blueprints
## (clamped to 1x1..max_size), else the fixed footprint.
func size_for(requested: Vector2i) -> Vector2i:
	if not resizable or requested.x < 1 or requested.y < 1:
		return footprint
	return requested.clamp(Vector2i.ONE, max_size)


func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < footprint.x and cell.y < footprint.y


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("blueprint without id")
	if footprint.x < 1 or footprint.y < 1:
		problems.append("%s footprint must be at least 1x1" % id)
	var can_resize := kind == BuildTypes.BlueprintKind.ROOM or kind == BuildTypes.BlueprintKind.SLAB
	if resizable and (not can_resize or max_size.x < footprint.x or max_size.y < footprint.y or not openings.is_empty()):
		problems.append("%s: only rooms and floors without openings resize, and max_size must hold the footprint" % id)
	var seen := {}
	for item in openings:
		var opening := item as BlueprintOpening
		if opening == null:
			problems.append("%s has a non-opening entry" % id)
			continue
		if not has_cell(opening.cell):
			problems.append("%s opening cell %s is outside the footprint" % [id, opening.cell])
		if opening.kind != BuildTypes.EDGE_OPEN and not BuildTypes.is_edge_kind(opening.kind):
			problems.append("%s opening kind %d is not an edge piece" % [id, opening.kind])
		var local_edge := GridSystem.side_doubled(opening.cell, opening.side)
		if seen.has(local_edge):
			problems.append("%s lists boundary %s twice" % [id, local_edge])
		seen[local_edge] = true
	if kind == BuildTypes.BlueprintKind.EDGE and not BuildTypes.is_edge_kind(edge_kind):
		problems.append("%s edge blueprint needs a wall, doorway, or window" % id)
	return problems
