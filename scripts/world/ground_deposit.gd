extends Node3D
class_name GroundDeposit

## One-meter colored square on the floor. Not a terrain material.
## Wells and pumps later call covering() / compatible_at() / take().

## Thick enough to sit clear of the dirt pad and avoid z-fighting.
const PATCH_THICKNESS := 0.06

var node_id := ""
var definition_id := ""
var display_name := "Deposit"
var remaining := 0
var yield_amount := 0
var resistance := 0
var depleted := false

var footprint := Vector2i(1, 1)
var cells: Array[Vector2i] = []

var _mesh: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D
var _alive_color := Color(0.85, 0.76, 0.54)


func _ready() -> void:
	add_to_group(&"ground_deposit")
	_apply_definition()
	_build_visual()
	_refresh_label()


func configure(p_node_id: String, p_definition_id: String) -> void:
	node_id = p_node_id
	definition_id = p_definition_id
	if is_inside_tree():
		_apply_definition()
		_refresh_label()


func definition() -> GroundDepositDefinition:
	return GroundDepositCatalog.get_definition(definition_id)


## Anchor is the minimum cell. The mesh center sits on the middle of that rectangle.
func set_footprint(anchor: Vector2i, size: Vector2i) -> void:
	footprint = Vector2i(maxi(size.x, 1), maxi(size.y, 1))
	cells.clear()
	for x in footprint.x:
		for y in footprint.y:
			cells.append(anchor + Vector2i(x, y))
	position = Vector3(float(anchor.x) + float(footprint.x) * 0.5, 0.0, float(anchor.y) + float(footprint.y) * 0.5)


func covers_cell(cell: Vector2i) -> bool:
	return cells.has(cell)


func covers_world_point(point: Vector3) -> bool:
	if depleted:
		return false
	var half_x := float(footprint.x) * 0.5
	var half_z := float(footprint.y) * 0.5
	return absf(point.x - global_position.x) <= half_x and absf(point.z - global_position.z) <= half_z


func can_extract_with(kind: String) -> bool:
	var spec := definition()
	return spec != null and not depleted and remaining > 0 and spec.can_extract_with(kind)


func take(amount: int) -> int:
	if depleted or amount <= 0 or remaining <= 0:
		return 0
	var got := mini(amount, remaining)
	remaining -= got
	if remaining <= 0:
		_mark_depleted()
	else:
		_refresh_label()
	return got


func harvest(tool_id: String, bag: Inventory) -> Dictionary:
	var spec := definition()
	var result := {
		"ok": false,
		"notice": "Nothing to harvest.",
		"changed": false,
		"kind": "ground",
		"node_id": node_id,
		"deposit_id": definition_id,
		"health": remaining,
		"depleted": depleted,
		"yielded": 0,
		"leftover": 0,
		"leftovers": [],
		"item_id": "" if spec == null else spec.item_id,
		"damage": 0,
	}
	if spec == null:
		return result
	result["item_id"] = spec.item_id
	if depleted or remaining <= 0:
		result["notice"] = "%s is depleted." % spec.display_name
		return result
	if spec.harvest_kind == "":
		result["notice"] = _extractor_notice(spec)
		return result
	var tool := ItemCatalog.get_item(tool_id)
	var amount := HarvestSwing.ground_extract(tool, spec)
	if amount <= 0:
		result["notice"] = "Need a %s." % HarvestSwing.tool_label(spec.harvest_kind)
		return result
	var got := take(amount)
	result["ok"] = got > 0
	result["changed"] = got > 0
	result["damage"] = got
	result["health"] = remaining
	result["depleted"] = depleted
	_grant(spec.item_id, got, bag, result)
	if got > 0 and not depleted:
		result["notice"] = "%s  %d/%d left" % [spec.display_name, remaining, yield_amount]
	elif int(result["yielded"]) > 0:
		result["notice"] = "Gathered %s." % str(result.get("yield_text", spec.display_name))
	else:
		result["notice"] = "%s is depleted." % spec.display_name
	var leftover_parts: PackedStringArray = []
	for drop in result.get("leftovers", []):
		leftover_parts.append("x%d" % int(drop[1]))
	if not leftover_parts.is_empty():
		result["notice"] += " Dropped %s." % ", ".join(leftover_parts)
	return result


func apply_network_remaining(current: int) -> void:
	remaining = maxi(current, 0)
	if remaining <= 0:
		_mark_depleted()
	else:
		_refresh_label()


static func covering_cell(from: Node, cell: Vector2i) -> GroundDeposit:
	if from == null or from.get_tree() == null:
		return null
	for node in from.get_tree().get_nodes_in_group(&"ground_deposit"):
		var deposit := node as GroundDeposit
		if deposit != null and deposit.covers_cell(cell):
			return deposit
	return null


static func covering(from: Node, point: Vector3) -> GroundDeposit:
	if from == null or from.get_tree() == null:
		return null
	for node in from.get_tree().get_nodes_in_group(&"ground_deposit"):
		var deposit := node as GroundDeposit
		if deposit != null and deposit.covers_world_point(point):
			return deposit
	return null


static func compatible_at(from: Node, point: Vector3, extractor_kind: String) -> GroundDeposit:
	var deposit := covering(from, point)
	if deposit != null and deposit.can_extract_with(extractor_kind):
		return deposit
	return null


func _apply_definition() -> void:
	var spec := definition()
	if spec == null:
		return
	display_name = spec.display_name
	yield_amount = spec.yield_amount
	resistance = spec.resistance
	_alive_color = spec.color
	if remaining <= 0 and not depleted:
		remaining = spec.yield_amount


func _extractor_notice(spec: GroundDepositDefinition) -> String:
	if spec.can_extract_with("pump_jack_oil") or spec.can_extract_with("pump"):
		return "Needs a pump."
	if spec.can_extract_with("pump_jack_gas"):
		return "Needs a gas pump."
	if spec.can_extract_with("water_well") or spec.can_extract_with("well"):
		return "Needs a well."
	return "Cannot harvest by hand."


func _grant(item_id: String, amount: int, bag: Inventory, result: Dictionary) -> void:
	if amount <= 0:
		return
	var put := 0
	if bag != null:
		put = mini(amount, bag.space_for(item_id))
		if put > 0:
			bag.add_exact(item_id, put)
	result["yielded"] = put
	result["yield_text"] = "%s x%d" % [_item_name(item_id), put]
	var leftover := amount - put
	if leftover > 0:
		result["leftovers"] = [[item_id, leftover]]
		result["item_id"] = item_id
		result["leftover"] = leftover


func _item_name(item_id: String) -> String:
	var item := ItemCatalog.get_item(item_id)
	if item == null:
		return item_id
	return item.display_name


func _mark_depleted() -> void:
	depleted = true
	remaining = 0
	if _material != null:
		_material.albedo_color = Color(0.18, 0.17, 0.16)
	_refresh_label()


func _build_visual() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(float(footprint.x), PATCH_THICKNESS, float(footprint.y))
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.position.y = ShowcasePad.pad_top() + PATCH_THICKNESS * 0.5
	_material = StandardMaterial3D.new()
	var texture_id := str({
		"sand": "ground_sand",
		"clay": "ground_clay",
		"gravel": "ground_gravel",
		"ground_water": "ground_water",
		"natural_gas": "ground_gas",
		"crude_oil": "ground_oil",
	}.get(definition_id, ""))
	ShowcasePad.paint(_material, texture_id, Vector2(footprint), _alive_color)
	_mesh.set_surface_override_material(0, _material)
	add_child(_mesh)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 1.35, 0.0)
	_label.pixel_size = 0.008
	_label.font_size = 26
	_label.outline_size = 6
	_label.visible = false
	_label.add_to_group(&"resource_info")
	add_child(_label)


func _refresh_label() -> void:
	if _label == null:
		return
	var spec := definition()
	if spec == null:
		_label.text = display_name
		return
	if depleted:
		_label.text = "%s\nDEPLETED" % spec.display_name
		return
	var tool_line := spec.harvest_kind
	if tool_line == "":
		tool_line = " ".join(spec.extractor_kinds)
	_label.text = "%s\n%d/%d  resist %d\n%s" % [
		spec.display_name,
		remaining,
		yield_amount,
		resistance,
		tool_line,
	]
