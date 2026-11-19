extends SceneTree

## Headless check that every non-placeable world object has a definition, a
## gameplay box, and an art slot, the way deployables do.
## godot --headless --path <project> --script res://tests/world_props.gd

const KINDS := ["resource", "crate"]


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var code := _run()
	if code == 0:
		print("WORLD_PROPS_OK count=%d" % WorldPropCatalog.all_ids().size())
	quit(code)


func _run() -> int:
	var ids := WorldPropCatalog.all_ids()
	if ids.size() != WorldPropCatalog.ORDER.size():
		return _fail("only %d of %d definitions loaded" % [ids.size(), WorldPropCatalog.ORDER.size()])
	var files := _tres_names(WorldPropCatalog.ROOT)
	if files.size() != ids.size():
		return _fail("%d .tres files but %d catalog ids" % [files.size(), ids.size()])
	for prop_id in ids:
		var spec := WorldPropCatalog.get_definition(prop_id)
		if spec.id != prop_id or spec.display_name.is_empty() or spec.description.is_empty():
			return _fail("%s has a blank id, name or description" % prop_id)
		if spec.category != "world_prop" or not KINDS.has(spec.kind):
			return _fail("%s category %s kind %s" % [prop_id, spec.category, spec.kind])
		if spec.body_size.x <= 0.0 or spec.body_size.y <= 0.0 or spec.body_size.z <= 0.0:
			return _fail("%s has no body size" % prop_id)
		if ItemCatalog.known(prop_id) or DeployableCatalog.known(prop_id):
			return _fail("%s collides with an item or deployable id" % prop_id)
		if not files.has(prop_id + ".tres"):
			return _fail("%s has no file" % prop_id)
	for deposit_id in ResourceCatalog.all_ids():
		var prop_id := WorldPropCatalog.id_for_deposit(deposit_id)
		if prop_id.is_empty():
			return _fail("deposit %s has no world prop" % deposit_id)
		var deposit := ResourceCatalog.get_deposit(deposit_id)
		if WorldPropCatalog.max_health(prop_id) != deposit.health:
			return _fail("%s health does not follow the deposit" % prop_id)
		if WorldPropCatalog.kind_of(prop_id) != WorldPropCatalog.KIND_RESOURCE:
			return _fail("%s should be a resource prop" % prop_id)
	if WorldPropCatalog.max_health("loot_crate") != 0:
		return _fail("a crate cannot be damaged")
	if WorldPropCatalog.kind_of("loot_crate") != WorldPropCatalog.KIND_CRATE:
		return _fail("loot_crate kind")
	for nexus_id in ["nexus_shipping_container", "nexus_supply_chest", "nexus_parts_chest", "nexus_security_lockbox"]:
		if WorldPropCatalog.kind_of(nexus_id) != WorldPropCatalog.KIND_CRATE:
			return _fail("%s should be a crate" % nexus_id)
		if WorldPropCatalog.max_health(nexus_id) != 0:
			return _fail("%s cannot be damaged" % nexus_id)
	if WorldPropCatalog.known("nope") or WorldPropCatalog.body_size("nope") != Vector3.ZERO:
		return _fail("unknown id must stay unknown")
	if not WorldPropArt.path_for("").is_empty() or not WorldPropArt.path_for("nope").is_empty():
		return _fail("no art expected for an unknown id")
	return _check_fit()


## A one-meter cube saved as a scene must come out at the prop's body box,
## standing on y = 0 and centered on x and z.
func _check_fit() -> int:
	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	cube.mesh = box
	cube.position = Vector3(0.0, 0.5, 0.0)
	var root := Node3D.new()
	root.add_child(cube)
	cube.owner = root
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return _fail("could not pack the test scene")
	var path := "user://world_prop_fit_test.tscn"
	if ResourceSaver.save(packed, path) != OK:
		return _fail("could not save the test scene")
	root.free()
	var host := Node3D.new()
	get_root().add_child(host)
	var size := Vector3(3.0, 5.0, 2.0)
	if not DeployableArt.attach_path(host, path, size):
		return _fail("attach_path failed")
	var art := host.get_node_or_null("WorldArt") as Node3D
	var mesh := art.get_child(0) as MeshInstance3D
	var bounds := mesh.get_aabb()
	var scaled := Vector3(bounds.size.x * art.scale.x, bounds.size.y * art.scale.y, bounds.size.z * art.scale.z)
	if not scaled.is_equal_approx(size):
		return _fail("fitted size %s, wanted %s" % [scaled, size])
	if absf(art.position.y + bounds.position.y * art.scale.y + mesh.position.y * art.scale.y) > 0.01:
		return _fail("fitted mesh does not stand on the ground")
	host.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return 0


func _tres_names(folder: String) -> PackedStringArray:
	var names := PackedStringArray()
	var dir := DirAccess.open(folder)
	if dir == null:
		return names
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".tres"):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	return names


func _fail(message: String) -> int:
	print("FAIL %s" % message)
	return 1
