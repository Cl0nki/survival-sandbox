extends RefCounted
class_name GroundDepositField

## North-east 10x10. Each patch is one or more building cells.
## The well is 1x1, the gas pump is 3x3, and the oil pump is 2x2.
## Shovels sit on the south edge.

const PATCHES := [
	["sand", Vector2i(11, -19), Vector2i(1, 1)],
	["clay", Vector2i(13, -19), Vector2i(1, 1)],
	["gravel", Vector2i(15, -19), Vector2i(1, 1)],
	["ground_water", Vector2i(17, -19), Vector2i(1, 1)],
	["natural_gas", Vector2i(11, -17), Vector2i(3, 3)],
	["crude_oil", Vector2i(16, -17), Vector2i(2, 2)],
]


static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("GroundDeposits") != null:
		return
	var root := Node3D.new()
	root.name = "GroundDeposits"
	arena.add_child(root)
	ShowcasePad.add(root, ShowcasePad.GROUND, Color(0.42, 0.36, 0.24), "ground_dirt")
	ShowcasePad.label(root, "GROUND", ShowcasePad.GROUND + Vector3(0.0, 2.5, -4.2), 52, Color(0.82, 0.74, 0.48))
	ShowcasePad.label(root, "SHOVELS", ShowcasePad.GROUND + Vector3(0.0, 1.15, 3.6), 22, Color(0.84, 0.76, 0.56))
	var loot := arena.get_node_or_null("Loot") as Node3D
	if loot == null:
		loot = root
	for entry in PATCHES:
		var deposit_id := str(entry[0])
		var anchor: Vector2i = entry[1]
		var size: Vector2i = entry[2]
		var deposit := GroundDeposit.new()
		deposit.name = deposit_id
		deposit.set_footprint(anchor, size)
		deposit.configure("ground_%s" % deposit_id, deposit_id)
		root.add_child(deposit)
		var definition := GroundDepositCatalog.get_definition(deposit_id)
		if definition != null and definition.item_id != "" and ItemCatalog.known(definition.item_id):
			_pickup(loot, "ground_drop_%s" % deposit_id, definition.item_id, 8, deposit.position + Vector3(0.0, 0.15, float(size.y) * 0.5 + 0.35))
	var tools := [
		["ground_shovel_scrap", "shovel_scrap"],
		["ground_shovel_iron", "shovel_iron"],
		["ground_shovel_steel", "shovel_steel"],
		["ground_shovel_composite", "shovel_composite"],
	]
	for index in tools.size():
		var tool: Array = tools[index]
		_pickup(loot, str(tool[0]), str(tool[1]), 1, Vector3(12.0 + float(index) * 1.3, 0.15, -10.6))


static func _pickup(folder: Node3D, pickup_id: String, item_id: String, quantity: int, pos: Vector3) -> void:
	if folder.get_node_or_null(pickup_id) != null:
		return
	var pickup := WorldPickup.new()
	pickup.name = pickup_id
	pickup.pickup_id = pickup_id
	pickup.item_id = item_id
	pickup.quantity = quantity
	pickup.position = pos
	folder.add_child(pickup)
