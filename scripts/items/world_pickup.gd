extends Node3D
class_name WorldPickup

const _Icons = preload("res://scripts/items/item_icons.gd")

## World stack. Only the authority mutates quantity. Clients apply loot_state.

@export var pickup_id := ""
@export var item_id := ""
@export var quantity := 1

var _label: Label3D
var _mesh: MeshInstance3D
var _icon: Sprite3D


func _ready() -> void:
	add_to_group(&"loot_pickup")
	_build_visual()
	refresh()


func take_into(bag: Inventory) -> int:
	if bag == null or quantity <= 0 or pickup_id.is_empty():
		return 0
	var definition := ItemCatalog.get_item(item_id)
	if definition == null or not definition.can_pickup:
		return 0
	var amount := mini(quantity, bag.space_for(item_id))
	if amount <= 0:
		return 0
	if not bag.add_exact(item_id, amount):
		return 0
	quantity -= amount
	refresh()
	return amount


func apply_network_quantity(next_quantity: int) -> void:
	quantity = maxi(next_quantity, 0)
	refresh()


func refresh() -> void:
	visible = quantity > 0
	if _label == null:
		return
	var definition := ItemCatalog.get_item(item_id)
	var label := item_id if definition == null else definition.display_name
	_label.text = "%s x%d" % [label, quantity]
	if _mesh != null and definition != null:
		var material := _mesh.get_surface_override_material(0) as StandardMaterial3D
		if material != null:
			material.albedo_color = definition.swatch
	if _icon != null:
		_icon.texture = _Icons.texture_for(definition)


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.38, 0.28, 0.38)
	_mesh.mesh = box
	_mesh.position = Vector3(0.0, 0.2, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.72, 0.55, 1)
	_mesh.set_surface_override_material(0, material)
	add_child(_mesh)
	_icon = Sprite3D.new()
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.pixel_size = 0.008
	_icon.position = Vector3(0.0, 0.48, 0.0)
	add_child(_icon)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 0.7, 0.0)
	_label.pixel_size = 0.005
	_label.font_size = 28
	_label.outline_size = 6
	add_child(_label)
