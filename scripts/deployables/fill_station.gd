extends LootContainer
class_name FillStation

## A well or a pump jack. One slot. An empty container left there becomes full.

var station_kind := "water_well"

var _hp := 0
var _status := ""
var _job_id := ""
var _job_left := 0.0


func _ready() -> void:
	slot_count = FillRules.SLOTS
	prompt = FillRules.display_name(station_kind)
	display_name = prompt
	slot_labels = PackedStringArray(["Container"])
	if box_color == Color(0.42, 0.3, 0.18, 1):
		box_color = FillRules.color_of(station_kind)
	super._ready()
	if inventory != null:
		inventory.host = self
	_dress()


func accepts_insert(index: int, item_id: String) -> bool:
	if index != FillRules.SLOT:
		return false
	return FillRules.accepts(station_kind, item_id)


func slot_hint() -> String:
	if _status != "":
		return _status
	return FillRules.hint(station_kind)


func set_deployable_health(current: int, _maximum: int) -> void:
	_hp = current
	_paint_label()


func set_fill_status(text: String) -> void:
	if text == _status:
		return
	_status = text
	_paint_label()
	_poke_viewers()


func _process(delta: float) -> void:
	if not _authority():
		return
	var loaded := _loaded_id()
	var full := FillRules.filled_id(station_kind, loaded)
	if full == "":
		_job_id = ""
		_job_left = 0.0
		if _status != "":
			_push_status("")
		return
	if _job_id != loaded:
		_job_id = loaded
		_job_left = FillRules.seconds(station_kind)
	_job_left -= delta
	if _job_left <= 0.0:
		_finish(full)
		return
	_push_status("Filling %ds" % ceili(_job_left))


func _finish(full_id: String) -> void:
	_job_id = ""
	_job_left = 0.0
	if inventory == null:
		_push_status("")
		return
	var slot: Dictionary = inventory.slots[FillRules.SLOT]
	if FillRules.filled_id(station_kind, str(slot.get("id", ""))) != full_id:
		_push_status("")
		return
	if int(slot.get("qty", 0)) <= 0:
		_push_status("")
		return
	inventory.slots[FillRules.SLOT] = {"id": full_id, "qty": 1}
	_push_status("")
	_publish_slots()


func _loaded_id() -> String:
	if inventory == null:
		return ""
	var slot: Dictionary = inventory.slots[FillRules.SLOT]
	var item_id := str(slot.get("id", ""))
	if item_id.is_empty() or int(slot.get("qty", 0)) <= 0:
		return ""
	return item_id


func _push_status(text: String) -> void:
	set_fill_status(text)
	var host := get_parent()
	if host != null and host.has_method(&"publish_smelt") and has_meta(&"deployable_id"):
		host.call(&"publish_smelt", int(get_meta(&"deployable_id")), text)


func _publish_slots() -> void:
	var arena := get_parent().get_parent() if get_parent() != null else null
	var net := arena.get_node_or_null("GameNet") if arena != null else null
	if net != null and net.has_method(&"notify_container"):
		net.call(&"notify_container", self)
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as PlayerController
		if player == null or player.container_view_id != container_id:
			continue
		if player.container_view == inventory:
			player.container_changed.emit()
		else:
			player.apply_confirmed_container(container_id, inventory.ids(), inventory.quantities())


func _poke_viewers() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as PlayerController
		if player != null and player.container_view_id == container_id:
			player.container_changed.emit()


func _authority() -> bool:
	var host := get_parent()
	if host != null and host.has_method(&"local_authority"):
		return bool(host.call(&"local_authority"))
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return true
	return multiplayer.is_server()


func _paint_label() -> void:
	if _label == null:
		return
	var text := "%s  [F]\n%d HP" % [prompt, _hp]
	if _status != "":
		text += "\n" + _status
	_label.text = text


func _dress() -> void:
	var mark := MeshInstance3D.new()
	var box := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.roughness = 0.8
	match station_kind:
		"pump_jack_gas":
			box.size = Vector3(0.16, body_size.y * 0.72, 0.16)
			mark.position = Vector3(body_size.x * 0.22, body_size.y * 0.55, 0.0)
			material.albedo_color = Color(0.78, 0.76, 0.28)
		"pump_jack_oil":
			box.size = Vector3(body_size.x * 0.62, 0.08, 0.1)
			mark.position = Vector3(0.0, body_size.y - 0.06, 0.0)
			material.albedo_color = Color(0.12, 0.1, 0.08)
		_:
			box.size = Vector3(body_size.x * 0.46, 0.05, body_size.z * 0.46)
			mark.position = Vector3(0.0, body_size.y - 0.04, 0.0)
			material.albedo_color = Color(0.2, 0.45, 0.62)
	mark.mesh = box
	mark.set_surface_override_material(0, material)
	add_child(mark)
