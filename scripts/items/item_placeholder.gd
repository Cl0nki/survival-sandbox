extends RefCounted
class_name ItemPlaceholder

## 3D stand-in for a ground item that has no mesh yet.
## WorldPickup uses it while HeldToolArt finds no res://assets/props/<id>.glb.
## The Ingame tab of the asset pipeline lists the same items as "Placeholder"
## until the model is approved. Approving it removes the stand-in on its own.
##
## One simple silhouette per category, tinted with the item swatch, so a pile
## of loot still reads at a glance. Everything rests on y = 0 and fits inside
## roughly 0.4 x 0.3 x 0.4 m, which is the box the old pickup used.
## No collision, no text, no 2D sprite.

const NODE_NAME := "Placeholder"

static var _materials: Dictionary = {}


static func build(definition: ItemDefinition) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var base := Color(0.7, 0.7, 0.7, 1.0)
	var category := "misc"
	if definition != null:
		base = definition.swatch
		category = definition.category
	var dark := base.darkened(0.35)
	var light := base.lightened(0.45)
	match category:
		"ammo":
			_box(root, Vector3(0.34, 0.12, 0.2), Vector3(0.0, 0.06, 0.0), base)
			_box(root, Vector3(0.36, 0.03, 0.08), Vector3(0.0, 0.1, 0.0), light)
		"food":
			_cylinder(root, 0.1, 0.18, Vector3(0.0, 0.09, 0.0), base)
			_cylinder(root, 0.105, 0.025, Vector3(0.0, 0.19, 0.0), light)
			_cylinder(root, 0.105, 0.025, Vector3(0.0, 0.015, 0.0), dark)
		"medical":
			_box(root, Vector3(0.32, 0.14, 0.22), Vector3(0.0, 0.07, 0.0), base)
			_box(root, Vector3(0.14, 0.02, 0.04), Vector3(0.0, 0.15, 0.0), light)
			_box(root, Vector3(0.04, 0.02, 0.14), Vector3(0.0, 0.15, 0.0), light)
		"weapon":
			_box(root, Vector3(0.5, 0.06, 0.07), Vector3(0.0, 0.04, 0.0), base)
			_box(root, Vector3(0.09, 0.12, 0.07), Vector3(-0.14, 0.06, 0.0), dark)
		"tool":
			_box(root, Vector3(0.5, 0.04, 0.04), Vector3(0.0, 0.03, 0.0), dark)
			_box(root, Vector3(0.14, 0.07, 0.05), Vector3(0.22, 0.045, 0.0), base)
		"harvest":
			_sphere(root, Vector3(0.3, 0.18, 0.26), Vector3(0.0, 0.08, 0.0), base)
			_sphere(root, Vector3(0.16, 0.12, 0.14), Vector3(0.1, 0.16, 0.04), light)
		"refined":
			_box(root, Vector3(0.36, 0.09, 0.2), Vector3(0.0, 0.045, 0.0), base)
			_box(root, Vector3(0.28, 0.05, 0.14), Vector3(0.0, 0.115, 0.0), light)
		"component":
			_box(root, Vector3(0.28, 0.08, 0.28), Vector3(0.0, 0.04, 0.0), dark)
			_cylinder(root, 0.09, 0.1, Vector3(0.0, 0.13, 0.0), base)
		"explosive":
			_cylinder(root, 0.1, 0.24, Vector3(0.0, 0.12, 0.0), base)
			_cylinder(root, 0.04, 0.06, Vector3(0.0, 0.27, 0.0), light)
		"container":
			_box(root, Vector3(0.36, 0.22, 0.28), Vector3(0.0, 0.11, 0.0), base)
			_box(root, Vector3(0.38, 0.04, 0.3), Vector3(0.0, 0.24, 0.0), dark)
		_:
			_box(root, Vector3(0.3, 0.22, 0.3), Vector3(0.0, 0.11, 0.0), base)
			_box(root, Vector3(0.18, 0.03, 0.18), Vector3(0.0, 0.235, 0.0), light)
	return root


static func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	_materials[key] = material
	return material


static func _add(root: Node3D, mesh: Mesh, at: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(instance)


static func _box(root: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add(root, mesh, at, color)


static func _cylinder(root: Node3D, radius: float, height: float, at: Vector3, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	_add(root, mesh, at, color)


static func _sphere(root: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.scale = size
	instance.material_override = _material(color)
	root.add_child(instance)
