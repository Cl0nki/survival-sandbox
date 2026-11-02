extends LootContainer
class_name Crafter

## A crafting station, campfire, or cooking station.
## Four slots: input, the other part, fuel, and output. One batch at a time.

var station_kind := "workbench"

var _hp := 0
var _status := ""
var _job: Dictionary = {}
var _job_left := 0.0
var _flame: MeshInstance3D


func _ready() -> void:
	slot_count = CraftRules.SLOTS
	prompt = CraftRules.display_name(station_kind)
	display_name = prompt
	slot_labels = PackedStringArray(["Input", "Part", "Fuel", "Out"])
	if box_color == Color(0.42, 0.3, 0.18, 1):
		box_color = CraftRules.color_of(station_kind)
	super._ready()
	if inventory != null:
		inventory.host = self
	_dress()


func accepts_insert(index: int, item_id: String) -> bool:
	if index == CraftRules.INPUT:
		return CraftRules.accepts_input(station_kind, item_id)
	if index == CraftRules.EXTRA:
		return CraftRules.accepts_extra(station_kind, item_id)
	if index == CraftRules.FUEL:
		return CraftRules.accepts_fuel(station_kind, item_id)
	return false


func slot_hint() -> String:
	if _status != "":
		return _status
	return CraftRules.hint(station_kind)


func set_deployable_health(current: int, _maximum: int) -> void:
	_hp = current
	_paint_label()


func set_craft_status(text: String) -> void:
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
	var input := _slot(CraftRules.INPUT)
	var extra := _slot(CraftRules.EXTRA)
	var fuel := _slot(CraftRules.FUEL)
	var output := _slot(CraftRules.OUTPUT)
	var planned := CraftRules.plan(
		station_kind,
		str(input["id"]),
		int(input["qty"]),
		str(extra["id"]),
		int(extra["qty"]),
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
	inventory.remove_from_slot(CraftRules.INPUT, int(job["in_count"]))
	if int(job["extra_count"]) > 0:
		inventory.remove_from_slot(CraftRules.EXTRA, int(job["extra_count"]))
	inventory.remove_from_slot(CraftRules.FUEL, int(job["fuel_count"]))
	var produced := str(job["output_id"])
	var made := int(job["output_count"])
	var slot: Dictionary = inventory.slots[CraftRules.OUTPUT]
	if str(slot.get("id", "")) == "" or int(slot.get("qty", 0)) <= 0:
		inventory.slots[CraftRules.OUTPUT] = {"id": produced, "qty": made}
	else:
		slot["qty"] = int(slot["qty"]) + made
		inventory.slots[CraftRules.OUTPUT] = slot
	_push_status("")
	_publish_slots()


func _matches(job: Dictionary) -> bool:
	if inventory == null or job.is_empty():
		return false
	var input := _slot(CraftRules.INPUT)
	var extra := _slot(CraftRules.EXTRA)
	var fuel := _slot(CraftRules.FUEL)
	var output := _slot(CraftRules.OUTPUT)
	if str(input["id"]) != str(job["input_id"]) or int(input["qty"]) < int(job["in_count"]):
		return false
	if int(job["extra_count"]) > 0:
		if str(extra["id"]) != str(job["extra_id"]) or int(extra["qty"]) < int(job["extra_count"]):
			return false
	elif str(extra["id"]) != "":
		return false
	if str(fuel["id"]) != str(job["fuel_id"]) or int(fuel["qty"]) < int(job["fuel_count"]):
		return false
	var out_id := str(output["id"])
	if out_id == "":
		return true
	if out_id != str(job["output_id"]):
		return false
	return int(output["qty"]) + int(job["output_count"]) <= _stack_of(out_id)


func _slot(index: int) -> Dictionary:
	var slot: Dictionary = inventory.slots[index]
	var item_id := str(slot.get("id", ""))
	var qty := int(slot.get("qty", 0))
	if item_id.is_empty() or qty <= 0:
		return {"id": "", "qty": 0}
	return {"id": item_id, "qty": qty}


func _stack_of(item_id: String) -> int:
	var definition := ItemCatalog.get_item(item_id)
	if definition == null or definition.max_stack <= 0:
		return 50
	return definition.max_stack


func _job_text() -> String:
	var item_id := str(_job.get("output_id", ""))
	var definition := ItemCatalog.get_item(item_id)
	var label := item_id if definition == null else definition.display_name
	return "%s %ds" % [label, ceili(maxf(_job_left, 0.0))]


func _push_status(text: String) -> void:
	set_craft_status(text)
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
	if _flame == null:
		return
	var material := _flame.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		return
	material.emission_energy_multiplier = 2.2 if hot else 0.45


func _dress() -> void:
	var cook := CraftRules.group_of(station_kind) == "cook"
	_flame = MeshInstance3D.new()
	var mark := BoxMesh.new()
	if cook and body_size.y < 0.6:
		mark.size = Vector3(body_size.x * 0.46, body_size.y * 0.34, body_size.z * 0.46)
		_flame.position = Vector3(0.0, body_size.y * 0.62, 0.0)
	else:
		mark.size = Vector3(body_size.x * 0.55, body_size.y * 0.12, body_size.z * 0.46)
		_flame.position = Vector3(0.0, body_size.y * 0.78, body_size.z * 0.12)
	_flame.mesh = mark
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.85, 0.42, 0.12) if cook else box_color.darkened(0.25)
	glow.emission_enabled = cook
	glow.emission = Color(1.0, 0.46, 0.12)
	glow.emission_energy_multiplier = 0.45 if cook else 0.0
	glow.roughness = 0.7
	_flame.set_surface_override_material(0, glow)
	add_child(_flame)
