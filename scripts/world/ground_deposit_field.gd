extends RefCounted
class_name GroundDepositField

## North-east 10x10. Clay digs like sand. Shovels sit on the south edge.

const ORDER: PackedStringArray = [
	"sand",
	"clay",
	"gravel",
	"ground_water",
	"natural_gas",
	"crude_oil",
]
const ORIGIN := Vector3(8.6, 0.0, -12.8)
const COL_SPACING := 2.4
const ROW_SPACING := 2.4
const COLS := 3


static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("GroundDeposits") != null:
		return
	var root := Node3D.new()
	root.name = "GroundDeposits"
	arena.add_child(root)
	ShowcasePad.add(root, ShowcasePad.GROUND, Color(0.42, 0.36, 0.24))
	ShowcasePad.label(root, "GROUND", ShowcasePad.GROUND + Vector3(0.0, 2.5, -4.2), 52, Color(0.82, 0.74, 0.48))
	ShowcasePad.label(root, "SHOVELS", ShowcasePad.GROUND + Vector3(0.0, 1.15, 3.6), 22, Color(0.84, 0.76, 0.56))
	var loot := arena.get_node_or_null("Loot") as Node3D
	if loot == null:
		loot = root
	for index in ORDER.size():
		var deposit_id := ORDER[index]
		var col := index % COLS
		var row := int(index / COLS)
		var deposit := GroundDeposit.new()
		deposit.name = deposit_id
		deposit.configure("ground_%s" % deposit_id, deposit_id)
		deposit.position = Vector3(
			ORIGIN.x + float(col) * COL_SPACING,
			0.0,
			ORIGIN.z + float(row) * ROW_SPACING
		)
		root.add_child(deposit)
		var definition := GroundDepositCatalog.get_definition(deposit_id)
		if definition != null:
			_pickup(loot, "ground_drop_%s" % deposit_id, definition.item_id, 8, deposit.position + Vector3(0.0, 0.15, 0.85))
	var tools := [
		["ground_shovel_scrap", "shovel_scrap"],
		["ground_shovel_iron", "shovel_iron"],
		["ground_shovel_steel", "shovel_steel"],
		["ground_shovel_composite", "shovel_composite"],
	]
	for index in tools.size():
		var tool: Array = tools[index]
		_pickup(loot, str(tool[0]), str(tool[1]), 1, Vector3(8.6 + float(index) * 1.3, 0.15, -7.2))


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
