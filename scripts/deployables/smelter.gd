extends LootContainer
class_name Smelter

## A furnace, smelter, or foundry. Three slots: input, fuel, output.
## The server runs one batch at a time and writes the ingots into the output.

const QUEUE_MAX := 6

var station_kind := "furnace_scrap"

var _status := ""
var _job: Dictionary = {}
var _job_left := 0.0
var _queue: Array = []
var _mouth: MeshInstance3D
## Clients never run jobs. The server sends the queue and the running job's
## time once per change, and the client counts the timer down on its own clock.
var _remote_rows: Array = []
var _remote_total := 0.0
var _remote_left := 0.0


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
	if not has_meta(&"deployable_art"):
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


func output_index() -> int:
	return SmeltRules.OUTPUT


func queue_snapshot() -> Array:
	if not _authority():
		return _remote_rows.duplicate(true)
	var rows: Array = []
	if not _job.is_empty():
		rows.append({
			"id": str(_job.get("output_id", "")),
			"qty": int(_job.get("count", 1)),
			"active": true,
		})
	for job in _queue:
		rows.append({
			"id": str(job.get("output_id", "")),
			"qty": int(job.get("count", 1)),
			"active": false,
		})
	return rows


## Running job progress, 0..1 (0 when idle). Drives the queue progress bar.
func progress() -> float:
	var total := 0.0
	var left := 0.0
	if _authority():
		if _job.is_empty():
			return 0.0
		total = float(_job.get("seconds", 0.0))
		left = _job_left
	else:
		if _remote_rows.is_empty():
			return 0.0
		total = _remote_total
		left = _remote_left
	if total <= 0.0:
		return 1.0
	return clampf(1.0 - left / total, 0.0, 1.0)


## Client side: the server announced a new queue / running job.
func apply_job(rows: Array, total: float, left: float) -> void:
	_remote_rows = rows
	_remote_total = total
	_remote_left = left
	_paint_remote_status()
	_poke_viewers()


func _tick_remote(delta: float) -> void:
	if _remote_rows.is_empty():
		return
	_remote_left = maxf(_remote_left - delta, 0.0)
	_paint_remote_status()


func _paint_remote_status() -> void:
	if _remote_rows.is_empty():
		set_smelt_status("")
		return
	var item_id := str((_remote_rows[0] as Dictionary).get("id", ""))
	var definition := ItemCatalog.get_item(item_id)
	var label := item_id if definition == null else definition.display_name
	set_smelt_status("%s %ds" % [label, ceili(_remote_left)])


## Server side: one message when the queue or the running job changes.
func _publish_job() -> void:
	var host := get_parent()
	if host == null or not host.has_method(&"publish_job") or not has_meta(&"deployable_id"):
		return
	host.call(&"publish_job", int(get_meta(&"deployable_id")), queue_snapshot(), float(_job.get("seconds", 0.0)), _job_left)


func _advance() -> void:
	_kick_queue()
	if _job.is_empty():
		_publish_job()


## Queue bag smelts. Output lands in the Out slot.
func smelt_from_bag(bag: Inventory, input_id: String, amount: int = 1) -> String:
	if bag == null or inventory == null:
		return "Missing"
	amount = clampi(amount, 1, QUEUE_MAX)
	var queued := 0
	var last_reason := "Cannot smelt"
	for _i in amount:
		if _queue.size() + (0 if _job.is_empty() else 1) >= QUEUE_MAX:
			break
		var fuel_id := ""
		var fuel_qty := 0
		if bag.count_item("coal") > 0:
			fuel_id = "coal"
			fuel_qty = bag.count_item("coal")
		elif bag.count_item("fuel") > 0:
			fuel_id = "fuel"
			fuel_qty = bag.count_item("fuel")
		if fuel_id == "":
			last_reason = "Needs fuel"
			break
		var out_slot := _slot(SmeltRules.OUTPUT)
		var out_id := str(out_slot["id"])
		var out_qty := int(out_slot["qty"])
		var planned := SmeltRules.plan(
			station_kind,
			input_id,
			bag.count_item(input_id),
			fuel_id,
			fuel_qty,
			"",
			0,
			1
		)
		if not bool(planned["ok"]):
			last_reason = str(planned["reason"]) if str(planned["reason"]) != "" else "Cannot smelt"
			break
		var produced := str(planned["output_id"])
		if out_id != "" and out_id != produced:
			last_reason = "Output full"
			break
		var reserved := out_qty + _reserved_output(produced)
		if reserved + int(planned["count"]) > SmeltRules._stack_of(produced):
			last_reason = "Output full"
			break
		if not bag.take_item(input_id, int(planned["count"])):
			last_reason = "Not enough"
			break
		if not bag.take_item(str(planned["fuel_id"]), int(planned["fuel_count"])):
			bag.add_exact(input_id, int(planned["count"]))
			last_reason = "Needs fuel"
			break
		planned["from_bag"] = true
		_queue.append(planned)
		queued += 1
	if queued <= 0:
		return last_reason
	var had_job := not _job.is_empty()
	_kick_queue()
	if had_job:
		_publish_job()
	_publish_slots()
	_poke_viewers()
	return ""


func _kick_queue() -> void:
	if not _job.is_empty() or _queue.is_empty():
		return
	_job = _queue.pop_front()
	_job_left = float(_job["seconds"])
	_glow(true)
	_push_status(_job_text())
	_publish_job()


func _reserved_output(output_id: String) -> int:
	var total := 0
	if not _job.is_empty() and bool(_job.get("from_bag", false)):
		if output_id == "" or str(_job.get("output_id", "")) == output_id:
			total += int(_job.get("count", 0))
	for job in _queue:
		if output_id == "" or str(job.get("output_id", "")) == output_id:
			total += int(job.get("count", 0))
	return total


func set_smelt_status(text: String) -> void:
	if text == _status:
		return
	## Timer text changes every second; only poke viewers when a job starts or ends
	## so the inventory UI is not rebuilt mid-click.
	var busy_changed := (_status == "") != (text == "")
	_status = text
	_apply_label()
	if busy_changed:
		_poke_viewers()


func _process(delta: float) -> void:
	if not _authority():
		_tick_remote(delta)
		return
	if _job.is_empty():
		_kick_queue()
	if _job.is_empty():
		_try_start()
	if _job.is_empty():
		return
	if not _matches(_job):
		_job = {}
		_job_left = 0.0
		_push_status("")
		_advance()
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
	_publish_job()


func _finish() -> void:
	var job := _job.duplicate()
	_job = {}
	_job_left = 0.0
	_glow(false)
	if not _matches(job):
		_push_status("")
		_advance()
		return
	if not bool(job.get("from_bag", false)):
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
	_advance()
	_poke_viewers()


func _matches(job: Dictionary) -> bool:
	if inventory == null or job.is_empty():
		return false
	var output := _slot(SmeltRules.OUTPUT)
	var out_id := str(output["id"])
	if out_id != "" and out_id != str(job["output_id"]):
		return false
	if out_id != "" and int(output["qty"]) + int(job["count"]) > SmeltRules._stack_of(out_id):
		return false
	if bool(job.get("from_bag", false)):
		return true
	var input := _slot(SmeltRules.INPUT)
	var fuel := _slot(SmeltRules.FUEL)
	if str(input["id"]) != str(job["input_id"]) or int(input["qty"]) < int(job["count"]):
		return false
	if str(fuel["id"]) != str(job["fuel_id"]) or int(fuel["qty"]) < int(job["fuel_count"]):
		return false
	return true


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


## Local label only. Clients get the job via `_publish_job`, not per-frame text.
func _push_status(text: String) -> void:
	set_smelt_status(text)


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


func _label_extra() -> String:
	return _status


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
