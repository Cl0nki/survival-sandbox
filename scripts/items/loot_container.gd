extends Node3D
class_name LootContainer

## Storage crate. Contents live on the server copy. Clients clear theirs at boot
## and only receive a snapshot while the server says they have it open.

@export var container_id := ""
@export var slot_count := 8

var inventory: Inventory
var _label: Label3D


func _ready() -> void:
	add_to_group(&"loot_container")
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
	box.size = Vector3(1.15, 0.72, 0.8)
	mesh.mesh = box
	mesh.position = Vector3(0.0, 0.36, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.3, 0.18, 1)
	mesh.set_surface_override_material(0, material)
	add_child(mesh)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 1.05, 0.0)
	_label.pixel_size = 0.005
	_label.font_size = 32
	_label.outline_size = 6
	_label.text = "Crate  [F]"
	add_child(_label)
