extends LootContainer
class_name Smelter

## A furnace, smelter, or foundry. Three slots: input, fuel, output.
## The server runs one batch at a time and writes the ingots into the output.

var station_kind := "furnace_scrap"

var _hp := 0
var _status := ""
var _job: Dictionary = {}
var _job_left := 0.0
var _mouth: MeshInstance3D


func _ready() -> void:
	slot_count = SmeltRules.SLOTS
	prompt = SmeltRules.display_name(station_kind)
	display_name = prompt
	slot_labels = PackedStringArray(["Input", "Fuel", "Out"])
	if box_color == Color(0.42, 0.3, 0.18, 1):
		box_color = SmeltRules.color_of(station_kind)
	super._ready()
	if inventory != null:
		inventory.host = self
	_dress()


func accepts_insert(index: int, item_id: String) -> bool:
	if index == SmeltRules.INPUT:
		return SmeltRules.accepts_input(station_kind, item_id)
	if index == SmeltRules.FUEL:
		return SmeltRules.accepts_fuel(station_kind, item_id)
	return false


func slot_hint() -> String:
	if _status != "":
		return _status
	return SmeltRules.hint(station_kind)


func set_deployable_health(current: int, _maximum: int) -> void:
	_hp = current
	_paint_label()


func set_smelt_status(text: String) -> void:
	if text == _status:
		return
	_status = text
	_paint_label()
	_poke_viewers()


func _process(delta: float) -> void:
	if not _authority():
		return
	if _job.is_empty():
		_try_start()
	if _job.is_empty():
		return
	if not _matches(_job):
		_job = {}
		_job_left = 0.0
		_push_status("")
		return
	_job_left -= delta
	if _job_left <= 0.0:
		_finish()
	else:
		_push_status(_job_text())


func _try_start() -> void:
	if inventory == null:
		return
	var input := _slot(SmeltRules.INPUT)
	var fuel := _slot(SmeltRules.FUEL)
	var output := _slot(SmeltRules.OUTPUT)
	var planned := SmeltRules.plan(
		station_kind,
		str(input["id"]),
		int(input["qty"]),
		str(fuel["id"]),
		int(fuel["qty"]),
		str(output["id"]),
		int(output["qty"])
	)
	if not bool(planned["ok"]):
		if _status != "":
			_push_status("")
		return
	_job = planned
	_job_left = float(planned["seconds"])
	_glow(true)
	_push_status(_job_text())


func _finish() -> void:
	var job := _job.duplicate()
	_job = {}
	_job_left = 0.0
	_glow(false)
	if not _matches(job):
		_push_status("")
		return
	inventory.remove_from_slot(SmeltRules.INPUT, int(job["count"]))
	inventory.remove_from_slot(SmeltRules.FUEL, int(job["fuel_count"]))
	var produced := str(job["output_id"])
	var made := int(job["count"])
	var slot: Dictionary = inventory.slots[SmeltRules.OUTPUT]
	if str(slot.get("id", "")) == "" or int(slot.get("qty", 0)) <= 0:
		inventory.slots[SmeltRules.OUTPUT] = {"id": produced, "qty": made}
	else:
		slot["qty"] = int(slot["qty"]) + made
		inventory.slots[SmeltRules.OUTPUT] = slot
	_push_status("")
	_publish_slots()


func _matches(job: Dictionary) -> bool:
	if inventory == null or job.is_empty():
		return false
	var input := _slot(SmeltRules.INPUT)
	var fuel := _slot(SmeltRules.FUEL)
	var output := _slot(SmeltRules.OUTPUT)
	if str(input["id"]) != str(job["input_id"]) or int(input["qty"]) < int(job["count"]):
		return false
	if str(fuel["id"]) != str(job["fuel_id"]) or int(fuel["qty"]) < int(job["fuel_count"]):
		return false
	var out_id := str(output["id"])
	if out_id == "":
		return true
	if out_id != str(job["output_id"]):
		return false
	return int(output["qty"]) + int(job["count"]) <= SmeltRules._stack_of(out_id)


func _slot(index: int) -> Dictionary:
	var slot: Dictionary = inventory.slots[index]
	var item_id := str(slot.get("id", ""))
	var qty := int(slot.get("qty", 0))
	if item_id.is_empty() or qty <= 0:
		return {"id": "", "qty": 0}
	return {"id": item_id, "qty": qty}


func _job_text() -> String:
	var item_id := str(_job.get("output_id", ""))
	var definition := ItemCatalog.get_item(item_id)
	var label := item_id if definition == null else definition.display_name
	return "%s %ds" % [label, ceili(maxf(_job_left, 0.0))]


func _push_status(text: String) -> void:
	set_smelt_status(text)
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


func _glow(hot: bool) -> void:
	if _mouth == null:
		return
	var material := _mouth.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		return
	material.emission_energy_multiplier = 2.4 if hot else 0.35


func _dress() -> void:
	var chimney := MeshInstance3D.new()
	var stack := BoxMesh.new()
	stack.size = Vector3(body_size.x * 0.28, body_size.y * 0.42, body_size.z * 0.28)
	chimney.mesh = stack
	chimney.position = Vector3(0.0, body_size.y * 0.72, -body_size.z * 0.22)
	var soot := StandardMaterial3D.new()
	soot.albedo_color = box_color.darkened(0.45)
	soot.roughness = 0.9
	chimney.set_surface_override_material(0, soot)
	add_child(chimney)
	_mouth = MeshInstance3D.new()
	var opening := BoxMesh.new()
	opening.size = Vector3(body_size.x * 0.42, body_size.y * 0.22, 0.04)
	_mouth.mesh = opening
	_mouth.position = Vector3(0.0, body_size.y * 0.28, body_size.z * 0.5 - 0.03)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.85, 0.32, 0.08)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.42, 0.08)
	glow.emission_energy_multiplier = 0.35
	glow.roughness = 0.45
	_mouth.set_surface_override_material(0, glow)
	add_child(_mouth)
