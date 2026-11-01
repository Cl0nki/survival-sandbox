extends StaticBody3D
class_name Workbench

## Solid bench. It has no crafting use yet. body_size is the full box, set
## before the node enters the tree. X is the long axis.

var display_name := "Workbench"
var body_size := Vector3(1.5, 0.84, 0.78)

var _label: Label3D


func _ready() -> void:
	add_to_group(&"deployable")
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0
	_build_visual()


func _build_visual() -> void:
	var length := body_size.x
	var height := body_size.y
	var depth := body_size.z
	var cabinet := MeshInstance3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(length * 0.9, height - 0.08, depth * 0.8)
	cabinet.mesh = body
	cabinet.position = Vector3(0.0, body.size.y * 0.5, 0.0)
	var cabinet_mat := StandardMaterial3D.new()
	cabinet_mat.albedo_color = Color(0.38, 0.26, 0.16)
	cabinet_mat.roughness = 0.9
	cabinet.set_surface_override_material(0, cabinet_mat)
	add_child(cabinet)
	var top := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(length, 0.08, depth)
	top.mesh = slab
	top.position = Vector3(0.0, height - 0.04, 0.0)
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Color(0.52, 0.36, 0.2)
	top_mat.roughness = 0.82
	top.set_surface_override_material(0, top_mat)
	add_child(top)
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = body_size
	shape.shape = hull
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(shape)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, height + 0.28, 0.0)
	label.pixel_size = 0.005
	label.font_size = 32
	label.outline_size = 6
	label.text = display_name
	add_child(label)
	_label = label


func set_deployable_health(current: int, _maximum: int) -> void:
	if _label == null:
		return
	_label.text = "%s\n%d HP" % [display_name, current]


func receive_damage(amount: int, _point: Vector3) -> bool:
	return DeployableSystem.forward_damage(self, amount)
