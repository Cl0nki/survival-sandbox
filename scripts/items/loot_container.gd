extends StaticBody3D
class_name LootContainer

## Storage crate. Contents live on the server copy. Clients clear theirs at boot
## and only receive a snapshot while the server says they have it open.
## The box matches the mesh, so the body stops on it and a standing shot
## passes over the lid.

@export var container_id := ""
@export var slot_count := 8
@export var prompt := "Crate"
@export var box_color := Color(0.42, 0.3, 0.18, 1)

var inventory: Inventory
var _label: Label3D
## When set before the node enters the tree, the box uses this size instead of
## the small yard crate. Y is the height. The mesh sits on the node origin.
var body_size := Vector3.ZERO
var display_name := ""
## Empty slot captions. Stations use Input, Fuel, and Out.
var slot_labels := PackedStringArray()


func _ready() -> void:
	add_to_group(&"loot_container")
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0
	if display_name.is_empty():
		display_name = prompt
	if inventory == null:
		inventory = Inventory.new(slot_count)
	_build_visual()


func clear_contents() -> void:
	if inventory == null:
		inventory = Inventory.new(slot_count)
	else:
		inventory.resize(slot_count)


func _build_visual() -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = body_size if body_size.x > 0.0 else Vector3(1.15, 0.72, 0.8)
	mesh.mesh = box
	mesh.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = box_color
	mesh.set_surface_override_material(0, material)
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = box.size
	shape.shape = hull
	shape.position = mesh.position
	add_child(shape)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, box.size.y + 0.33, 0.0)
	_label.pixel_size = 0.005
	_label.font_size = 32
	_label.outline_size = 6
	_label.text = "%s  [F]" % prompt
	add_child(_label)


func set_deployable_health(current: int, _maximum: int) -> void:
	if _label == null:
		return
	_label.text = "%s  [F]\n%d HP" % [prompt, current]


func receive_damage(amount: int, _point: Vector3) -> bool:
	return DeployableSystem.forward_damage(self, amount)
