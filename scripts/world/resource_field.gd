extends RefCounted
class_name ResourceField

## West 10x10 mine. Nine pickaxe nodes, pickaxes along the south edge.

const ORIGIN := Vector3(-7.3, 0.0, -17.3)
const SPACING := 2.3
const COLS := 3


static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("Mine") != null:
		return
	var root := Node3D.new()
	root.name = "Mine"
	arena.add_child(root)
	ShowcasePad.add(root, ShowcasePad.MINE, Color(0.36, 0.30, 0.24))
	ShowcasePad.label(root, "MINE", ShowcasePad.MINE + Vector3(0.0, 2.6, -4.2), 52, Color(0.82, 0.74, 0.58))
	ShowcasePad.label(root, "PICKAXES", ShowcasePad.MINE + Vector3(0.0, 1.15, 3.7), 22, Color(0.84, 0.76, 0.62))
	var ids := ResourceCatalog.mineral_ids()
	var loot := arena.get_node_or_null("Loot") as Node3D
	if loot == null:
		loot = root
	for index in ids.size():
		var col := index % COLS
		var row := int(index / COLS)
		var node := ResourceNode.new()
		node.name = ids[index]
		node.configure("mine_%s" % ids[index], ids[index])
		node.position = Vector3(ORIGIN.x + float(col) * SPACING, 0.0, ORIGIN.z + float(row) * SPACING)
		root.add_child(node)
		var deposit := ResourceCatalog.get_deposit(ids[index])
		if deposit != null:
			_pickup(loot, "mine_drop_%s" % ids[index], deposit.item_id, maxi(deposit.yield_amount, 1), node.position + Vector3(1.0, 0.15, 0.0))
	var tools := [
		["mine_pickaxe_scrap", "pickaxe_scrap"],
		["mine_pickaxe_iron", "pickaxe_iron"],
		["mine_pickaxe_steel", "pickaxe_steel"],
		["mine_pickaxe_composite", "pickaxe_composite"],
	]
	for index in tools.size():
		var entry: Array = tools[index]
		_pickup(loot, str(entry[0]), str(entry[1]), 1, Vector3(-7.6 + float(index) * 1.3, 0.15, -11.1))


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
