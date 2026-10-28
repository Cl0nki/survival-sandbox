extends RefCounted
class_name BuildTypes

## Shared enums for the building system. Blueprint resources and logical state
## store these numbers, so append new values instead of renumbering.

enum Kind { SLAB, WALL, DOORWAY, WINDOW, POST, STAIRS }
enum BlueprintKind { ROOM, EDGE, SLAB, STAIRS, SUPPORT, DISMANTLE }
enum Action { CREATE, REUSE, REPLACE, REMOVE, SKIP, CONFLICT }
enum Side { NORTH, EAST, SOUTH, WEST }

## Edge axes. AXIS_X runs along +X between cell rows z-1 and z. AXIS_Z runs
## along +Z between cell columns x-1 and x. The diagonal axes reserve key space
## for later diagonal walls; no planner or mesh produces them yet.
const AXIS_X := 0
const AXIS_Z := 1
const AXIS_DIAG_POS := 2
const AXIS_DIAG_NEG := 3

## Blueprint opening value meaning "leave this boundary open".
const EDGE_OPEN := -1

const KIND_NAMES := ["Slab", "Wall", "Doorway", "Window", "Post", "Stairs"]
const ACTION_NAMES := ["create", "reuse", "replace", "remove", "skip", "conflict"]


static func is_edge_kind(kind: int) -> bool:
	return kind == Kind.WALL or kind == Kind.DOORWAY or kind == Kind.WINDOW


static func is_vertical_kind(kind: int) -> bool:
	return is_edge_kind(kind) or kind == Kind.POST


static func kind_name(kind: int) -> String:
	if kind < 0 or kind >= KIND_NAMES.size():
		return "Open"
	return KIND_NAMES[kind]


static func action_name(action: int) -> String:
	if action < 0 or action >= ACTION_NAMES.size():
		return "?"
	return ACTION_NAMES[action]
