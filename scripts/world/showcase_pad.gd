extends RefCounted
class_name ShowcasePad

## 10x10 yard tiles. The arena floor is 36 m, so three tiles and a 1 m gap fit
## between the outer walls. Centers are the tile middles.

const SIZE := 10.0

const WOODS := Vector3(-11.0, 0.0, -11.0)
const SCAVENGE := Vector3(0.0, 0.0, -11.0)
const GROUND := Vector3(11.0, 0.0, -11.0)
const MINE := Vector3(-11.0, 0.0, 0.0)
const BUILDING := Vector3(0.0, 0.0, 0.0)
const RANGE := Vector3(11.0, 0.0, 0.0)
const CRAFTING := Vector3(-11.0, 0.0, 11.0)
const DEPLOYABLES := Vector3(0.0, 0.0, 11.0)
const SUPPLIES := Vector3(11.0, 0.0, 11.0)

## South-east corner of the woods tile, clear of the hatchets and the trees.
const WOODS_CRATE := Vector3(-6.8, 0.15, -7.6)


static func add(root: Node3D, center: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(SIZE, 0.025, SIZE)
	mesh.mesh = box
	mesh.position = Vector3(center.x, 0.02, center.z)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.set_surface_override_material(0, material)
	root.add_child(mesh)


static func label(root: Node3D, text: String, at: Vector3, size: int, color: Color) -> void:
	var mark := Label3D.new()
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.position = at
	mark.pixel_size = 0.012
	mark.font_size = size
	mark.outline_size = 8
	mark.text = text
	mark.modulate = color
	root.add_child(mark)
