extends RefCounted
class_name ShowcasePad

## 4x4 yard. Each tile is 10 m and shares its edge with the next, so the
## colored pads sit on the building cells. Building is the middle 2x2.
## North is -Z. Outer tile edges are at ±20. Walls sit at ±22.

const SIZE := 10.0
const BUILDING_SIZE := 20.0
const PAD_CENTER_Y := 0.02
const PAD_THICKNESS := 0.025

const WOODS := Vector3(-15.0, 0.0, -15.0)
const MINE := Vector3(-5.0, 0.0, -15.0)
const SMELTING := Vector3(5.0, 0.0, -15.0)
const GROUND := Vector3(15.0, 0.0, -15.0)
const SCAVENGE := Vector3(-15.0, 0.0, -5.0)
const BUILDING := Vector3(0.0, 0.0, 0.0)
const RANGE := Vector3(15.0, 0.0, -5.0)
const CRAFTING := Vector3(-15.0, 0.0, 5.0)
const FOOD := Vector3(15.0, 0.0, 5.0)
const DEPLOYABLES := Vector3(-15.0, 0.0, 15.0)
const SUPPLIES := Vector3(-5.0, 0.0, 15.0)
const BENCHES := Vector3(5.0, 0.0, 15.0)
const CHEM := Vector3(15.0, 0.0, 15.0)

## South-east corner of the woods tile, clear of the hatchets and the trees.
const WOODS_CRATE := Vector3(-10.8, 0.15, -11.6)


static func pad_top() -> float:
	return PAD_CENTER_Y + PAD_THICKNESS * 0.5


static func add(root: Node3D, center: Vector3, color: Color, texture_id := "") -> void:
	add_rect(root, center, SIZE, color, texture_id)


static func add_rect(root: Node3D, center: Vector3, size: float, color: Color, texture_id := "") -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size, PAD_THICKNESS, size)
	mesh.mesh = box
	mesh.position = Vector3(center.x, PAD_CENTER_Y, center.z)
	var material := StandardMaterial3D.new()
	paint(material, texture_id, Vector2(size, size), color)
	mesh.set_surface_override_material(0, material)
	root.add_child(mesh)


static func paint(material: StandardMaterial3D, texture_id: String, repeats: Vector2, fallback: Color) -> void:
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var texture := albedo(texture_id)
	if texture == null:
		material.albedo_color = fallback
		return
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	material.uv1_scale = Vector3(repeats.x, repeats.y, 1.0)


static func albedo(texture_id: String) -> Texture2D:
	if texture_id == "":
		return null
	var path := "res://assets/textures/%s/albedo.png" % texture_id
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)


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
