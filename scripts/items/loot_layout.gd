extends RefCounted
class_name LootLayout

## Deterministic test loot. The same nodes are created in local play and on
## every peer. Container contents are authoritative only on the server.

static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("Loot") != null:
		return
	var folder := Node3D.new()
	folder.name = "Loot"
	arena.add_child(folder)
	_pickup(folder, "scrap_pile", "scrap_metal", 8, Vector3(10.0, 0.15, 12.0))
	_pickup(folder, "scrap_north", "scrap_metal", 12, Vector3(0.0, 0.15, -8.0))
	_pickup(folder, "scrap_east", "scrap_metal", 12, Vector3(6.0, 0.15, -4.0))
	_pickup(folder, "cloth_pile", "cloth", 6, Vector3(12.0, 0.15, 10.0))
	_pickup(folder, "food_pile", "canned_food", 3, Vector3(10.0, 0.15, 8.0))
	var crate := LootContainer.new()
	crate.name = "SupplyCrate"
	crate.container_id = "supply_crate"
	crate.slot_count = NetConfig.CONTAINER_SLOTS
	crate.position = Vector3(-12.0, 0.15, 12.0)
	folder.add_child(crate)
	crate.inventory.add_exact("medical_supplies", 2)
	crate.inventory.add_exact("ammunition", 20)


static func _pickup(folder: Node3D, pickup_id: String, item_id: String, quantity: int, pos: Vector3) -> void:
	var pickup := WorldPickup.new()
	pickup.name = pickup_id
	pickup.pickup_id = pickup_id
	pickup.item_id = item_id
	pickup.quantity = quantity
	pickup.position = pos
	folder.add_child(pickup)
