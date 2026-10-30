extends StaticBody3D
class_name BuildingPieceBody

## Collision body of one committed piece. Shots already call receive_damage
## on whatever they hit; this forwards that call to the building authority
## instead of keeping a second health pool on the node.

var display_name := "Piece"


func receive_damage(amount: int, point: Vector3) -> bool:
	var system := _system()
	if system == null or not system.authoritative or amount <= 0 or not has_meta(&"component_id"):
		return false
	var result: Dictionary = system.authority.apply_bullet(int(get_meta(&"component_id")), amount, point)
	return bool(result.get("changed", false))


func _system() -> BuildingSystem:
	var nodes := get_tree().get_nodes_in_group(&"building_system")
	if nodes.is_empty():
		return null
	return nodes[0] as BuildingSystem
