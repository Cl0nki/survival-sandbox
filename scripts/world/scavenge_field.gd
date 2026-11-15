extends RefCounted
class_name ScavengeField

## North 10x10. Nodes stay west of the center lane so the north shot and the
## walk to the wall stay clear. Crowbars sit on the south edge.
## Two columns of three. The west column drops its yield on its west side, the
## east column on its east side, in rows of five.

const NODE_AT := {
	"broken_car": Vector3(-17.6, 0.0, -8.4),
	"scrap_pile": Vector3(-17.6, 0.0, -5.6),
	"rubble_pile": Vector3(-17.6, 0.0, -2.8),
	"tire_pile": Vector3(-14.4, 0.0, -8.4),
	"drum_stack": Vector3(-14.4, 0.0, -5.6),
	"appliance_pile": Vector3(-14.4, 0.0, -2.8),
}
const DROP_ROWS := 5
const DROP_STEP := 0.42
const DROP_REACH := 1.6


static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("Scavenge") != null:
		return
	var root := Node3D.new()
	root.name = "Scavenge"
	arena.add_child(root)
	ShowcasePad.add(root, ShowcasePad.SCAVENGE, Color(0.28, 0.28, 0.30), "ground_asphalt", false, false)
	ShowcasePad.label(root, "SCAVENGE", ShowcasePad.SCAVENGE + Vector3(0.0, 2.6, -4.2), 52, Color(0.76, 0.62, 0.44))
	ShowcasePad.label(root, "CROWBARS", ShowcasePad.SCAVENGE + Vector3(1.4, 1.15, 3.6), 22, Color(0.80, 0.66, 0.48))
	var loot := arena.get_node_or_null("Loot") as Node3D
	if loot == null:
		loot = root
	for deposit_id in ResourceCatalog.scavenge_ids():
		var at: Vector3 = NODE_AT.get(deposit_id, ShowcasePad.SCAVENGE)
		var node := ResourceNode.new()
		node.name = deposit_id
		node.configure("scavenge_%s" % deposit_id, deposit_id)
		node.position = at
		root.add_child(node)
		var deposit := ResourceCatalog.get_deposit(deposit_id)
		if deposit == null:
			continue
		var entries := deposit.yield_entries()
		var side := -1.0 if node.position.x < -16.0 else 1.0
		var rows := mini(entries.size(), DROP_ROWS)
		var span := float(maxi(rows - 1, 0)) * DROP_STEP
		for yield_index in entries.size():
			var entry: Array = entries[yield_index]
			var column := floori(float(yield_index) / float(DROP_ROWS))
			var row := yield_index % DROP_ROWS
			_pickup(
				loot,
				"scavenge_drop_%s_%s" % [deposit_id, str(entry[0])],
				str(entry[0]),
				int(entry[1]),
				node.position + Vector3(side * (DROP_REACH + float(column) * 0.5), 0.15, -span * 0.5 + float(row) * DROP_STEP)
			)
	var tools := [
		["scavenge_crowbar_scrap", "crowbar_scrap"],
		["scavenge_crowbar_iron", "crowbar_iron"],
		["scavenge_crowbar_steel", "crowbar_steel"],
		["scavenge_crowbar_composite", "crowbar_composite"],
	]
	for index in tools.size():
		var entry: Array = tools[index]
		_pickup(loot, str(entry[0]), str(entry[1]), 1, Vector3(-15.4 + float(index) * 1.3, 0.15, -1.2))


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
