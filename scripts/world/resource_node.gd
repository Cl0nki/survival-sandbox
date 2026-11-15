extends StaticBody3D
class_name ResourceNode

## One boulder or tree. Pistol hits do nothing. Only a matching harvest tool chips it.

var node_id := ""
var deposit_id := ""
var display_name := "Node"
var max_health := 1
var health := 0
var depleted := false

const _CANOPY_MATERIALS := {
	"oak": "canopy_oak",
	"birch": "canopy_birch",
	"spruce": "canopy_spruce",
}
## Leaf-clump density on the crown sphere/cone. Matches soft ground carpets.
const _CANOPY_UV_SCALE := 2.2

var _mesh: MeshInstance3D
var _crown: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D
var _crown_material: StandardMaterial3D
var _alive_color := Color(0.52, 0.52, 0.50)
var _crown_tint := Color.WHITE
var _visual := "rock"
## Salvage props are built from several parts under one root, so a depleted
## heap can be squashed and darkened as a whole.
var _prop_root: Node3D
var _prop_materials: Array[StandardMaterial3D] = []
## Holder for the published mesh. Null while the primitive meshes are in use.
var _art_root: Node3D


func _ready() -> void:
	add_to_group(&"resource_node")
	collision_layer = PhysicsLayers.WORLD | PhysicsLayers.DAMAGEABLE
	collision_mask = 0
	_apply_deposit()
	_build_visual()
	if depleted:
		_mark_depleted()
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
	if _art_root != null:
		_art_root.scale = Vector3(1.0, 0.3, 1.0)
		_refresh_label()
		return
	if _material != null:
		_material.albedo_color = Color(0.16, 0.15, 0.14)
	if _visual == "tree" or _visual == "cactus":
		if _mesh != null:
			_mesh.scale = Vector3(1.15, 0.22, 1.15)
			_mesh.position.y = 0.32
		if _crown != null:
			_crown.visible = false
	elif _visual == "bush":
		if _mesh != null:
			_mesh.scale = Vector3(1.1, 0.28, 1.1)
			_mesh.position.y = 0.18
		if _crown != null:
			_crown.visible = false
	elif _prop_root != null:
		_prop_root.scale = Vector3(1.0, 0.3, 1.0)
		for part_material in _prop_materials:
			part_material.albedo_color = part_material.albedo_color.darkened(0.55)
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
		_crown_material.albedo_color = Color(1.0, 0.95, 0.85)
		tween.parallel().tween_property(_crown_material, "albedo_color", _crown_tint, 0.12)


func _build_visual() -> void:
	match _visual:
		"tree":
			_build_tree()
		"cactus":
			_build_cactus()
		"bush":
			_build_bush()
		"car", "tires", "scrap", "rubble", "drums", "appliances":
			_build_prop(_visual)
		_:
			_build_rock()
	_attach_art()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, _label_height(), 0.0)
	_label.pixel_size = 0.008
	_label.font_size = 28
	_label.outline_size = 6
	_label.visible = false
	_label.add_to_group(&"resource_info")
	add_child(_label)


## A published Meshy mesh (WorldPropArt) replaces the primitive meshes. The
## collision hulls the builders made stay, and the mesh is fitted to the
## prop's body box from WorldPropCatalog.
func _attach_art() -> void:
	var prop_id := WorldPropCatalog.id_for_deposit(deposit_id)
	if prop_id.is_empty() or not WorldPropArt.has_art(prop_id):
		return
	var holder := Node3D.new()
	holder.name = "ArtRoot"
	add_child(holder)
	if WorldPropArt.attach(holder, prop_id) == null:
		holder.queue_free()
		return
	_art_root = holder
	for primitive in [_mesh, _crown, _prop_root]:
		if primitive != null:
			primitive.visible = false
	_material = null
	_crown_material = null
	_prop_materials.clear()


func _label_height() -> float:
	match _visual:
		"tree":
			return 5.8
		"cactus":
			return 2.4
		"bush":
			return 1.6
		"car":
			return 2.1
		"tires":
			return 1.6
		"scrap":
			return 1.7
		"rubble":
			return 1.6
		"drums":
			return 2.0
		"appliances":
			return 2.2
		_:
			return 1.35


## Low-poly salvage props out of primitives, the same way trees and cacti are
## built. The yaw comes from the node id, so every peer turns a wreck the same way.
func _build_prop(kind: String) -> void:
	_prop_root = Node3D.new()
	_prop_root.name = "Prop"
	var yaw := 0.0
	if not node_id.is_empty():
		yaw = float(absi(node_id.hash()) % 628) / 100.0
	_prop_root.rotation.y = yaw
	add_child(_prop_root)
	var hull := Vector3.ONE
	var hull_at := Vector3.ZERO
	match kind:
		"car":
			_build_car()
			hull = Vector3(2.2, 1.3, 1.1)
		"tires":
			_build_tires()
			hull = Vector3(1.9, 0.85, 1.6)
			hull_at.x = 0.1
		"scrap":
			_build_scrap()
			hull = Vector3(1.6, 0.9, 1.4)
		"rubble":
			_build_rubble()
			hull = Vector3(1.5, 1.0, 1.3)
		"drums":
			_build_drums()
			hull = Vector3(1.1, 1.5, 1.0)
		"appliances":
			_build_appliances()
			hull = Vector3(1.5, 1.55, 1.0)
	var box := BoxShape3D.new()
	box.size = hull
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.rotation.y = yaw
	## Keep the off-center hull offset on the same side as the visual.
	shape.position = Vector3(hull_at.x, 0.0, hull_at.z).rotated(Vector3.UP, yaw) + Vector3(0.0, hull.y * 0.5, 0.0)
	add_child(shape)


## One primitive part. The first part with `primary` set drives the flash and
## the depleted tint, so it carries the deposit color.
func _part(
	mesh: Mesh,
	color: Color,
	at: Vector3,
	rot_deg := Vector3.ZERO,
	primary := false,
	metallic := 0.0,
	rough := 0.9
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.rotation_degrees = rot_deg
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = rough
	part.set_surface_override_material(0, material)
	_prop_root.add_child(part)
	_prop_materials.append(material)
	if primary:
		_mesh = part
		_material = material
	return part


static func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


static func _cylinder(radius: float, height: float, segments := 10) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = segments
	return cylinder


static func _tire_mesh() -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.17
	torus.outer_radius = 0.40
	torus.rings = 14
	torus.ring_segments = 8
	return torus


## Car wreck. Long axis on X. One wheel is gone and a door hangs open.
func _build_car() -> void:
	var body := _alive_color
	_part(_box(Vector3(2.1, 0.5, 1.0)), body, Vector3(0.0, 0.5, 0.0), Vector3.ZERO, true, 0.35, 0.7)
	_part(_box(Vector3(0.75, 0.12, 0.92)), body.darkened(0.12), Vector3(0.72, 0.82, 0.0), Vector3(0.0, 0.0, -9.0), false, 0.35, 0.7)
	_part(_box(Vector3(1.05, 0.5, 0.88)), body.darkened(0.08), Vector3(-0.25, 0.98, 0.0), Vector3.ZERO, false, 0.35, 0.7)
	_part(_box(Vector3(0.9, 0.26, 0.9)), Color(0.12, 0.16, 0.2), Vector3(-0.25, 1.0, 0.0), Vector3.ZERO, false, 0.1, 0.25)
	_part(_box(Vector3(1.0, 0.06, 0.84)), Color(0.38, 0.2, 0.12), Vector3(-0.25, 1.25, 0.0), Vector3.ZERO, false, 0.4, 0.9)
	_part(_box(Vector3(0.7, 0.4, 0.05)), body.darkened(0.05), Vector3(-0.05, 0.66, 0.66), Vector3(0.0, -28.0, 0.0), false, 0.35, 0.7)
	_part(_box(Vector3(0.12, 0.14, 1.04)), Color(0.5, 0.5, 0.52), Vector3(1.08, 0.36, 0.0), Vector3.ZERO, false, 0.6, 0.5)
	var tire_color := Color(0.08, 0.08, 0.09)
	var wheel := _cylinder(0.32, 0.2, 10)
	for wheel_at in [Vector3(-0.7, 0.32, 0.5), Vector3(-0.7, 0.32, -0.5), Vector3(0.7, 0.32, -0.5)]:
		_part(wheel, tire_color, wheel_at, Vector3(90.0, 0.0, 0.0), false, 0.0, 0.95)
	_part(_box(Vector3(0.1, 0.1, 0.1)), Color(0.4, 0.4, 0.42), Vector3(0.7, 0.18, 0.46), Vector3.ZERO, false, 0.6, 0.6)


## A heap of tires. The fallen-over one leans on the side.
func _build_tires() -> void:
	var tire := _tire_mesh()
	var base := _alive_color
	var layers := [
		[Vector3(0.45, 0.115, 0.0), Vector3.ZERO],
		[Vector3(-0.225, 0.115, 0.39), Vector3(0.0, 40.0, 0.0)],
		[Vector3(-0.225, 0.115, -0.39), Vector3(0.0, 80.0, 0.0)],
		[Vector3(0.2, 0.345, 0.12), Vector3(3.0, 20.0, -3.0)],
		[Vector3(-0.2, 0.345, -0.12), Vector3(-3.0, 60.0, 4.0)],
		[Vector3(0.0, 0.575, 0.0), Vector3(8.0, 10.0, -6.0)],
		[Vector3(0.98, 0.4, 0.2), Vector3(78.0, 0.0, 14.0)],
	]
	for index in layers.size():
		var entry: Array = layers[index]
		var tint := base.lightened(0.03 * float(index % 3))
		_part(tire, tint, entry[0], entry[1], index == 0, 0.0, 0.95)


func _build_scrap() -> void:
	_part(_box(Vector3(1.5, 0.3, 1.2)), _alive_color, Vector3(0.0, 0.15, 0.0), Vector3(0.0, 10.0, 0.0), true, 0.6, 0.6)
	var sheets := [
		[Vector3(-0.2, 0.42, 0.1), Vector3(1.1, 0.08, 0.8), Vector3(8.0, -25.0, 6.0), Color(0.55, 0.35, 0.22)],
		[Vector3(0.25, 0.5, -0.15), Vector3(0.9, 0.06, 0.7), Vector3(-10.0, 40.0, 12.0), Color(0.6, 0.62, 0.64)],
		[Vector3(-0.35, 0.3, -0.4), Vector3(0.8, 0.06, 0.5), Vector3(20.0, 70.0, -5.0), Color(0.42, 0.26, 0.18)],
		[Vector3(0.4, 0.3, 0.4), Vector3(0.6, 0.5, 0.6), Vector3(0.0, 25.0, 0.0), Color(0.34, 0.36, 0.38)],
		[Vector3(-0.5, 0.6, 0.25), Vector3(0.06, 0.8, 0.7), Vector3(0.0, 15.0, 12.0), Color(0.5, 0.3, 0.2)],
	]
	for sheet in sheets:
		_part(_box(sheet[1]), sheet[3], sheet[0], sheet[2], false, 0.6, 0.65)
	_part(_cylinder(0.06, 1.4, 6), Color(0.4, 0.38, 0.34), Vector3(0.0, 0.62, 0.1), Vector3(0.0, 35.0, 80.0), false, 0.6, 0.6)


func _build_rubble() -> void:
	_part(_box(Vector3(1.4, 0.4, 1.2)), _alive_color, Vector3(0.0, 0.2, 0.0), Vector3(0.0, 8.0, 0.0), true, 0.0, 0.95)
	var chunks := [
		[Vector3(0.3, 0.55, 0.2), Vector3(0.55, 0.4, 0.45), Vector3(12.0, 30.0, 8.0), Color(0.62, 0.58, 0.52)],
		[Vector3(-0.35, 0.5, -0.15), Vector3(0.5, 0.35, 0.5), Vector3(-8.0, 55.0, 15.0), Color(0.5, 0.47, 0.44)],
		[Vector3(0.1, 0.78, -0.1), Vector3(0.4, 0.3, 0.38), Vector3(20.0, 10.0, -10.0), Color(0.66, 0.62, 0.56)],
		[Vector3(-0.45, 0.3, 0.4), Vector3(0.4, 0.3, 0.55), Vector3(5.0, 70.0, 0.0), Color(0.45, 0.44, 0.42)],
		[Vector3(0.55, 0.25, -0.4), Vector3(0.5, 0.25, 0.4), Vector3(0.0, -20.0, 6.0), Color(0.58, 0.5, 0.46)],
		[Vector3(0.1, 0.38, 0.5), Vector3(0.35, 0.2, 0.2), Vector3(0.0, 15.0, 0.0), Color(0.62, 0.3, 0.24)],
	]
	for chunk in chunks:
		_part(_box(chunk[1]), chunk[3], chunk[0], chunk[2], false, 0.0, 0.95)
	_part(_cylinder(0.025, 1.1, 6), Color(0.45, 0.25, 0.15), Vector3(-0.1, 0.9, 0.1), Vector3(0.0, 0.0, 70.0), false, 0.5, 0.7)


## Three drums standing, one lying across the top.
func _build_drums() -> void:
	var drum := _cylinder(0.3, 0.9, 10)
	var lid := _cylinder(0.28, 0.02, 10)
	var standing := [
		[Vector3(-0.32, 0.45, -0.2), _alive_color],
		[Vector3(0.32, 0.45, -0.2), Color(0.2, 0.32, 0.5)],
		[Vector3(0.0, 0.45, 0.35), Color(0.25, 0.38, 0.28)],
	]
	for index in standing.size():
		var entry: Array = standing[index]
		var at: Vector3 = entry[0]
		_part(drum, entry[1], at, Vector3.ZERO, index == 0, 0.5, 0.65)
		_part(lid, Color(0.14, 0.14, 0.15), at + Vector3(0.0, 0.46, 0.0), Vector3.ZERO, false, 0.6, 0.5)
	_part(drum, Color(0.5, 0.34, 0.2), Vector3(0.0, 1.2, -0.1), Vector3(0.0, 15.0, 90.0), false, 0.5, 0.65)


## A fridge leaning, a washer, and a microwave on top.
func _build_appliances() -> void:
	_part(_box(Vector3(0.7, 1.5, 0.7)), _alive_color, Vector3(-0.4, 0.75, 0.0), Vector3(0.0, 0.0, -6.0), true, 0.2, 0.55)
	_part(_box(Vector3(0.04, 0.45, 0.06)), Color(0.4, 0.4, 0.42), Vector3(-0.02, 1.0, 0.22), Vector3(0.0, 0.0, -6.0), false, 0.6, 0.4)
	_part(_box(Vector3(0.7, 0.8, 0.7)), Color(0.72, 0.74, 0.76), Vector3(0.4, 0.4, 0.15), Vector3(0.0, 0.0, 0.0), false, 0.2, 0.55)
	_part(_cylinder(0.22, 0.04, 12), Color(0.18, 0.22, 0.26), Vector3(0.4, 0.45, 0.51), Vector3(90.0, 0.0, 0.0), false, 0.1, 0.25)
	_part(_box(Vector3(0.45, 0.28, 0.35)), Color(0.3, 0.3, 0.32), Vector3(0.4, 0.94, 0.15), Vector3(0.0, 15.0, 0.0), false, 0.3, 0.6)


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


func _build_cactus() -> void:
	var deposit := ResourceCatalog.get_deposit(deposit_id)
	var pads := Color(0.34, 0.56, 0.34)
	if deposit != null:
		pads = deposit.foliage_color
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.20
	trunk.height = 1.55
	trunk.radial_segments = 8
	_mesh = MeshInstance3D.new()
	_mesh.mesh = trunk
	_mesh.position.y = trunk.height * 0.5
	_material = StandardMaterial3D.new()
	_material.roughness = 0.9
	_material.albedo_color = _alive_color
	_mesh.set_surface_override_material(0, _material)
	add_child(_mesh)
	_crown = MeshInstance3D.new()
	var arm := CylinderMesh.new()
	arm.top_radius = 0.10
	arm.bottom_radius = 0.12
	arm.height = 0.7
	arm.radial_segments = 6
	_crown.mesh = arm
	_crown.position = Vector3(0.28, 1.05, 0.0)
	_crown.rotation_degrees = Vector3(0.0, 0.0, 55.0)
	_crown_material = StandardMaterial3D.new()
	_crown_material.roughness = 0.9
	_crown_material.albedo_color = pads
	_crown.set_surface_override_material(0, _crown_material)
	add_child(_crown)
	var hull := CylinderShape3D.new()
	hull.radius = 0.28
	hull.height = trunk.height
	var shape := CollisionShape3D.new()
	shape.shape = hull
	shape.position.y = trunk.height * 0.5
	add_child(shape)


func _build_bush() -> void:
	var deposit := ResourceCatalog.get_deposit(deposit_id)
	var twig := Color(0.50, 0.38, 0.22)
	if deposit != null:
		twig = deposit.foliage_color
	var stem := CylinderMesh.new()
	stem.top_radius = 0.04
	stem.bottom_radius = 0.07
	stem.height = 0.55
	stem.radial_segments = 6
	_mesh = MeshInstance3D.new()
	_mesh.mesh = stem
	_mesh.position.y = stem.height * 0.5
	_material = StandardMaterial3D.new()
	_material.roughness = 0.95
	_material.albedo_color = _alive_color
	_mesh.set_surface_override_material(0, _material)
	add_child(_mesh)
	_crown = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.42
	ball.height = 0.55
	_crown.mesh = ball
	_crown.position.y = 0.72
	_crown_material = StandardMaterial3D.new()
	_crown_material.roughness = 0.96
	_crown_material.albedo_color = twig
	_crown.set_surface_override_material(0, _crown_material)
	add_child(_crown)
	var hull := SphereShape3D.new()
	hull.radius = 0.45
	var shape := CollisionShape3D.new()
	shape.shape = hull
	shape.position.y = 0.55
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
	_apply_canopy_material(foliage)
	add_child(_crown)
	var hull := CylinderShape3D.new()
	hull.radius = 0.42
	hull.height = trunk.height
	var shape := CollisionShape3D.new()
	shape.shape = hull
	shape.position.y = trunk.height * 0.5
	add_child(shape)


func _apply_canopy_material(foliage: Color) -> void:
	_crown_tint = foliage
	_crown_material = StandardMaterial3D.new()
	_crown_material.roughness = 0.88
	_crown_material.albedo_color = foliage
	var mat_id := str(_CANOPY_MATERIALS.get(deposit_id, ""))
	if mat_id != "":
		var path := "res://assets/materials/%s.tres" % mat_id
		if ResourceLoader.exists(path):
			var published := load(path) as StandardMaterial3D
			if published != null:
				_crown_material = published.duplicate() as StandardMaterial3D
				_crown_material.uv1_scale = Vector3(_CANOPY_UV_SCALE, _CANOPY_UV_SCALE, _CANOPY_UV_SCALE)
				_crown_material.albedo_color = Color.WHITE
				_crown_tint = Color.WHITE
	_crown.set_surface_override_material(0, _crown_material)


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
