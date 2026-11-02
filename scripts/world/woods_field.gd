extends RefCounted
class_name WoodsField

## North-west 10x10 grove. Hatches sit on the south edge, beside the woods chest.

const TREE_AT := {
	"oak": Vector3(-17.6, 0.0, -16.6),
	"birch": Vector3(-13.4, 0.0, -17.0),
	"spruce": Vector3(-15.6, 0.0, -14.2),
}


static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("Woods") != null:
		return
	var root := Node3D.new()
	root.name = "Woods"
	arena.add_child(root)
	ShowcasePad.add(root, ShowcasePad.WOODS, Color(0.26, 0.34, 0.20))
	ShowcasePad.label(root, "WOODS", ShowcasePad.WOODS + Vector3(0.0, 3.2, -4.2), 52, Color(0.56, 0.72, 0.44))
	ShowcasePad.label(root, "HATCHETS", ShowcasePad.WOODS + Vector3(-1.6, 1.15, 3.6), 22, Color(0.64, 0.76, 0.48))
	var loot := arena.get_node_or_null("Loot") as Node3D
	if loot == null:
		loot = root
	for tree_id in ResourceCatalog.tree_ids():
		var at: Vector3 = TREE_AT.get(tree_id, ShowcasePad.WOODS)
		var node := ResourceNode.new()
		node.name = tree_id
		node.configure("woods_%s" % tree_id, tree_id)
		node.position = at
		root.add_child(node)
		var deposit := ResourceCatalog.get_deposit(tree_id)
		if deposit == null:
			continue
		var entries := deposit.yield_entries()
		for yield_index in entries.size():
			var entry: Array = entries[yield_index]
			_pickup(
				loot,
				"woods_drop_%s_%s" % [tree_id, str(entry[0])],
				str(entry[0]),
				int(entry[1]),
				node.position + Vector3(-0.45 + float(yield_index) * 0.55, 0.15, 1.2)
			)
	var tools := [
		["woods_hatchet_scrap", "hatchet_scrap"],
		["woods_hatchet_iron", "hatchet_iron"],
		["woods_hatchet_steel", "hatchet_steel"],
		["woods_hatchet_composite", "hatchet_composite"],
	]
	for index in tools.size():
		var entry: Array = tools[index]
		_pickup(loot, str(entry[0]), str(entry[1]), 1, Vector3(-18.6 + float(index) * 1.3, 0.15, -11.2))


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
