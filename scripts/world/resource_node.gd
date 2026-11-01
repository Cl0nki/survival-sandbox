extends StaticBody3D
class_name ResourceNode

## One boulder or tree. Pistol hits do nothing. Only a matching harvest tool chips it.

var node_id := ""
var deposit_id := ""
var display_name := "Node"
var max_health := 1
var health := 0
var depleted := false

var _mesh: MeshInstance3D
var _crown: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D
var _crown_material: StandardMaterial3D
var _alive_color := Color(0.52, 0.52, 0.50)
var _visual := "rock"


func _ready() -> void:
	add_to_group(&"resource_node")
	collision_layer = PhysicsLayers.WORLD | PhysicsLayers.DAMAGEABLE
	collision_mask = 0
	_apply_deposit()
	_build_visual()
	_refresh_label()


func configure(p_node_id: String, p_deposit_id: String) -> void:
	node_id = p_node_id
	deposit_id = p_deposit_id
	if is_inside_tree():
		_apply_deposit()
		_refresh_label()


func receive_damage(_amount: int, _point: Vector3) -> bool:
	return false


func harvest(tool_id: String, bag: Inventory) -> Dictionary:
	var deposit := ResourceCatalog.get_deposit(deposit_id)
	var result := {
		"ok": false,
		"notice": "Nothing to harvest.",
		"changed": false,
		"node_id": node_id,
		"deposit_id": deposit_id,
		"health": health,
		"depleted": depleted,
		"yielded": 0,
		"leftover": 0,
		"leftovers": [],
		"item_id": "" if deposit == null else deposit.item_id,
		"damage": 0,
	}
	if deposit == null:
		return result
	result["item_id"] = deposit.item_id
	if depleted or health <= 0:
		result["notice"] = "%s is depleted." % deposit.display_name
		return result
	var tool := ItemCatalog.get_item(tool_id)
	var damage := HarvestSwing.damage_for(tool, deposit)
	if damage <= 0:
		result["notice"] = "Need a %s." % HarvestSwing.tool_label(deposit.tool_kind)
		return result
	health = maxi(health - damage, 0)
	result["ok"] = true
	result["changed"] = true
	result["damage"] = damage
	result["health"] = health
	if health > 0:
		result["notice"] = "%s  %d/%d HP" % [deposit.display_name, health, max_health]
		_flash()
		_refresh_label()
		return result
	_grant_yield(deposit, bag, result)
	_mark_depleted()
	result["depleted"] = true
	if int(result["yielded"]) > 0:
		result["notice"] = "Gathered %s." % str(result.get("yield_text", deposit.display_name))
	else:
		result["notice"] = "%s is depleted." % deposit.display_name
	var leftover_parts: PackedStringArray = []
	for drop in result.get("leftovers", []):
		leftover_parts.append("%s x%d" % [_item_name(str(drop[0])), int(drop[1])])
	if not leftover_parts.is_empty():
		result["notice"] += " Dropped %s." % ", ".join(leftover_parts)
	return result


func apply_network_health(current: int, is_depleted: bool) -> void:
	health = clampi(current, 0, maxi(max_health, 1))
	if is_depleted or health <= 0:
		_mark_depleted()
	_refresh_label()


func _apply_deposit() -> void:
	var deposit := ResourceCatalog.get_deposit(deposit_id)
	if deposit == null:
		return
	display_name = deposit.display_name
	max_health = deposit.health
	_visual = deposit.visual
	if not depleted:
		if health <= 0 or health > max_health:
			health = max_health
	_alive_color = deposit.color


func _grant_yield(deposit: ResourceDeposit, bag: Inventory, result: Dictionary) -> void:
	var leftovers: Array = []
	var gathered: PackedStringArray = []
	var total_put := 0
	for entry in deposit.yield_entries():
		var item_id := str(entry[0])
		var amount := int(entry[1])
		if amount <= 0:
			continue
		var put := 0
		if bag != null:
			put = mini(amount, bag.space_for(item_id))
			if put > 0:
				bag.add_exact(item_id, put)
		total_put += put
		if put > 0:
			gathered.append("%s x%d" % [_item_name(item_id), put])
		var leftover := amount - put
		if leftover > 0:
			leftovers.append([item_id, leftover])
	result["yielded"] = total_put
	result["leftovers"] = leftovers
	result["yield_text"] = ", ".join(gathered)
	if leftovers.is_empty():
		result["leftover"] = 0
		return
	result["item_id"] = str(leftovers[0][0])
	result["leftover"] = int(leftovers[0][1])


func _item_name(item_id: String) -> String:
	var definition := ItemCatalog.get_item(item_id)
	if definition == null:
		return item_id
	return definition.display_name


func _mark_depleted() -> void:
	depleted = true
	health = 0
	if _material != null:
		_material.albedo_color = Color(0.16, 0.15, 0.14)
	if _visual == "tree":
		if _mesh != null:
			_mesh.scale = Vector3(1.15, 0.22, 1.15)
			_mesh.position.y = 0.32
		if _crown != null:
			_crown.visible = false
	elif _mesh != null:
		_mesh.scale = Vector3(1.0, 0.35, 1.0)
		_mesh.position.y = 0.12
	_refresh_label()


func _flash() -> void:
	if _material == null:
		return
	_material.albedo_color = Color(1.0, 0.95, 0.85)
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color", _alive_color, 0.12)
	if _crown_material != null:
		var foliage := _crown_material.albedo_color
		_crown_material.albedo_color = Color(1.0, 0.95, 0.85)
		tween.parallel().tween_property(_crown_material, "albedo_color", foliage, 0.12)


func _build_visual() -> void:
	if _visual == "tree":
		_build_tree()
	else:
		_build_rock()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 5.8 if _visual == "tree" else 1.35, 0.0)
	_label.pixel_size = 0.008
	_label.font_size = 28
	_label.outline_size = 6
	_label.visible = false
	_label.add_to_group(&"resource_info")
	add_child(_label)


func _build_rock() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.95, 0.85, 0.95)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.position.y = 0.42
	_material = StandardMaterial3D.new()
	_material.roughness = 0.92
	_material.albedo_color = _alive_color
	_mesh.set_surface_override_material(0, _material)
	add_child(_mesh)
	var hull := BoxShape3D.new()
	hull.size = box.size
	var shape := CollisionShape3D.new()
	shape.shape = hull
	shape.position.y = 0.42
	add_child(shape)


func _build_tree() -> void:
	var deposit := ResourceCatalog.get_deposit(deposit_id)
	var foliage := Color(0.22, 0.42, 0.18)
	if deposit != null:
		foliage = deposit.foliage_color
	const SCALE := 1.3
	const CROWN_BOTTOM := 2.15
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16 * SCALE
	trunk.bottom_radius = 0.22 * SCALE
	trunk.height = 2.2 * SCALE
	trunk.radial_segments = 8
	_mesh = MeshInstance3D.new()
	_mesh.mesh = trunk
	_mesh.position.y = trunk.height * 0.5
	_material = StandardMaterial3D.new()
	_material.roughness = 0.94
	_material.albedo_color = _alive_color
	_mesh.set_surface_override_material(0, _material)
	add_child(_mesh)
	_crown = MeshInstance3D.new()
	if deposit_id == "spruce":
		var cone := CylinderMesh.new()
		cone.top_radius = 0.02
		cone.bottom_radius = 0.95 * SCALE
		cone.height = 2.1 * SCALE
		cone.radial_segments = 8
		_crown.mesh = cone
		_crown.position.y = CROWN_BOTTOM + cone.height * 0.5
	else:
		var ball := SphereMesh.new()
		ball.radius = (1.15 if deposit_id == "oak" else 0.95) * SCALE
		ball.height = ball.radius * 2.0
		_crown.mesh = ball
		_crown.position.y = CROWN_BOTTOM + ball.radius
	_crown_material = StandardMaterial3D.new()
	_crown_material.roughness = 0.88
	_crown_material.albedo_color = foliage
	_crown.set_surface_override_material(0, _crown_material)
	add_child(_crown)
	var hull := CylinderShape3D.new()
	hull.radius = 0.42
	hull.height = trunk.height
	var shape := CollisionShape3D.new()
	shape.shape = hull
	shape.position.y = trunk.height * 0.5
	add_child(shape)


func _refresh_label() -> void:
	if _label == null:
		return
	var deposit := ResourceCatalog.get_deposit(deposit_id)
	if deposit == null:
		_label.text = display_name
		return
	if depleted:
		_label.text = "%s\nDEPLETED" % deposit.display_name
		return
	_label.text = "%s\n%d/%d HP\n%s\n%s  resist %.1f  x%.1f" % [
		deposit.display_name,
		health,
		max_health,
		deposit.yield_label(),
		deposit.tool_kind,
		deposit.resistance,
		deposit.tool_multiplier,
	]
