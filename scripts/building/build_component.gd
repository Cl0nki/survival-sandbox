extends RefCounted
class_name BuildComponent

## Logical record of one committed building piece. It holds no nodes.
## The key is the canonical slot (see GridSystem); the id stays stable for the
## lifetime of the piece and is what later phases replicate and damage.

var id := 0
var kind := 0
## Vector3i(x, level, z) for slabs and posts, Vector4i(x, z, level, axis) for
## edge pieces, Vector4i(anchor_x, anchor_z, level, rotation) for stairs.
var key: Variant
var level := 0
var rotation := 0
## Cells covered by stairs, as Vector3i(x, level, z).
var cells: Array[Vector3i] = []
## Rooms that reference this piece. Shared boundaries list every room.
var rooms := PackedInt32Array()
## Posts placed explicitly as supports stay when their walls go away.
var pinned := false


func add_room(room_id: int) -> void:
	if room_id > 0 and not rooms.has(room_id):
		rooms.append(room_id)


func describe() -> String:
	return "%s#%d %s" % [BuildTypes.kind_name(kind), id, str(key)]
