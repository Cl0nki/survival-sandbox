extends RefCounted
class_name BuildingScenarios

## The Phase 1 geometry scenarios at fixed arena coordinates. The headless
## suite, the manual test scene, and the screenshot capture all build the same
## list, so what is checked automatically is what you look at by hand.
## Each step: [label, blueprint id, anchor, rotation, level, axis, room size].
## A "dismantle" step removes the edge piece at (anchor, level, axis).

const STEPS: Array = [
	["A single room", "room", Vector2i(-14, -14), 0, 0, 0, Vector2i(1, 1)],
	["B two rooms share a wall", "room", Vector2i(-11, -14), 0, 0, 0, Vector2i(1, 1)],
	["", "room", Vector2i(-10, -14), 0, 0, 0, Vector2i(1, 1)],
	["C four rooms meet at a corner", "room", Vector2i(-7, -14), 0, 0, 0, Vector2i(1, 1)],
	["", "room", Vector2i(-6, -14), 0, 0, 0, Vector2i(1, 1)],
	["", "room", Vector2i(-7, -13), 0, 0, 0, Vector2i(1, 1)],
	["", "room", Vector2i(-6, -13), 0, 0, 0, Vector2i(1, 1)],
	["D two 3x3 rooms form a 6x3 rectangle", "room", Vector2i(-2, -14), 0, 0, 0, Vector2i(3, 3)],
	["", "room", Vector2i(1, -14), 0, 0, 0, Vector2i(3, 3)],
	["E doorway and window replace walls", "room", Vector2i(6, -14), 0, 0, 0, Vector2i(2, 2)],
	["", "doorway", Vector2i(8, -13), 0, 0, BuildTypes.AXIS_Z],
	["", "window", Vector2i(6, -14), 0, 0, BuildTypes.AXIS_X],
	["F 3x3 room on a 3x3 room", "room", Vector2i(-14, -9), 0, 0, 0, Vector2i(3, 3)],
	["", "room", Vector2i(-14, -9), 0, 1, 0, Vector2i(3, 3)],
	["G three stacked levels", "room", Vector2i(-9, -9), 0, 0, 0, Vector2i(2, 2)],
	["", "room", Vector2i(-9, -9), 0, 1, 0, Vector2i(2, 2)],
	["", "room", Vector2i(-9, -9), 0, 2, 0, Vector2i(2, 2)],
	["H stairs through two rooms", "room", Vector2i(-6, -9), 0, 0, 0, Vector2i(3, 3)],
	["", "room", Vector2i(-3, -9), 0, 0, 0, Vector2i(3, 3)],
	["", "dismantle", Vector2i(-3, -8), 0, 0, BuildTypes.AXIS_Z],
	["", "stairs_straight", Vector2i(-5, -8), 1, 0, 0],
	["", "room", Vector2i(-6, -9), 0, 1, 0, Vector2i(3, 3)],
	["", "room", Vector2i(-3, -9), 0, 1, 0, Vector2i(3, 3)],
	["I 3x3, 2x2 and 1x1 side by side", "room", Vector2i(2, -9), 0, 0, 0, Vector2i(3, 3)],
	["", "room", Vector2i(5, -9), 0, 0, 0, Vector2i(2, 2)],
	["", "room", Vector2i(7, -9), 0, 0, 0, Vector2i(1, 1)],
	["J walls on single floor slabs", "floor_1x1", Vector2i(10, -9), 0, 0, 0],
	["", "floor_1x1", Vector2i(11, -9), 0, 0, 0],
	["", "wall", Vector2i(10, -9), 0, 0, BuildTypes.AXIS_X],
	["", "wall", Vector2i(11, -9), 0, 0, BuildTypes.AXIS_X],
	["", "floor_1x1", Vector2i(10, -9), 0, 1, 0],
	["K dragged 5x2 room", "room", Vector2i(-14, -4), 0, 0, 0, Vector2i(5, 2)],
]


static func request_of(step: Array) -> Dictionary:
	var size: Vector2i = step[6] if step.size() > 6 else Vector2i.ZERO
	return RoomPlacer.make_request(str(step[1]), step[2], int(step[3]), int(step[4]), int(step[5]), 0, size)


## Builds every step. Returns the failed steps as "label: reason" strings.
static func build_all(authority: BuildingAuthority) -> PackedStringArray:
	var failures := PackedStringArray()
	for step: Array in STEPS:
		var result: Dictionary
		if str(step[1]) == "dismantle":
			var anchor: Vector2i = step[2]
			var edge := Vector4i(anchor.x, anchor.y, int(step[4]), int(step[5]))
			result = authority.request_remove(authority.state.edges.component_at(edge))
		else:
			result = authority.request_place(request_of(step))
		if not bool(result["ok"]) or not bool(result["changed"]):
			failures.append("%s %s at %s: %s" % [step[0], step[1], step[2], result["reason"]])
	return failures


## World position for a sign above the first step of each labelled scenario.
static func sign_positions(grid: GridSystem) -> Array:
	var signs: Array = []
	for step: Array in STEPS:
		if str(step[0]) == "":
			continue
		var anchor: Vector2i = step[2]
		var at := grid.doubled_to_world(anchor * 2 + Vector2i(1, -1), 0)
		at.y = 3.6
		signs.append([str(step[0]), at])
	return signs
