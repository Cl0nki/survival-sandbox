extends CharacterBody3D
class_name PlayerController

## Local play simulates this body directly.
## On a dedicated server the same motion and muzzle helpers run from validated
## input. Owning clients send input and apply server poses. Remote clients
## interpolate. Prediction can later consume authoritative_velocity and
## acked_input_seq without changing the server.

enum NetRole { LOCAL, SERVER, OWNER, PUPPET }

const CHEST_HEIGHT := 1.2
const CROUCH_CHEST_HEIGHT := 0.62
const BODY_RADIUS := 0.35
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.05
const CROUCH_SPEED_SCALE := 0.55
## Exponential rate for stand/crouch. Higher is snappier. About 0.4 s to settle.
const STANCE_BLEND_SPEED := 8.0
const LEAN_DISTANCE := 0.45
const LEAN_MARGIN := 0.12
const LEAN_BLEND_SPEED := 8.0
const WALK_SPEED := 5.0
const ACCELERATION := 28.0
const GRAVITY := 24.0
const WEAPON_ANCHOR := Vector3(0.22, 0.3, -0.35)
const MUZZLE_REST := Vector3(0.22, 0.3, -0.75)
const WEAPON_REST := Vector3(0.22, 0.3, -0.45)

@onready var _visual_root: Node3D = $VisualRoot
@onready var _lean_pivot: Node3D = $VisualRoot/LeanPivot
@onready var _muzzle: Marker3D = $VisualRoot/LeanPivot/Muzzle
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _body_mesh: MeshInstance3D = $VisualRoot/LeanPivot/Body
@onready var _weapon_mesh: MeshInstance3D = $VisualRoot/LeanPivot/WeaponMesh
@onready var _camera: OrbitCamera = $CameraRig
@onready var _weapon: HitscanWeapon = $HitscanWeapon
@onready var _aim_marker: MeshInstance3D = $AimMarker

var net_role: NetRole = NetRole.LOCAL
var network_id := 0
var display_name := "Player"
var max_health := 100
var health := 100
var correction_count := 0
var acked_input_seq := 0
var authoritative_velocity := Vector3.ZERO

var _lean_offset := 0.0
var _crouch := 0.0
var _aim_pitch := 0.0
var _owner_crouch := 0.0
var _owner_pitch := 0.0
var _body_shape: CapsuleShape3D
var _session: Node
var _reports_input := true
var _motion := MotionBuffer.new()
var _has_authoritative_pose := false
var _last_pose_time := 0.0
var _last_snapshot := Vector3.ZERO
var _down := false
var _body_material: StandardMaterial3D
var _body_tint := Color(0.2, 0.42, 0.78, 1)
var _nameplate: Label3D
var inventory: Inventory
var container_view: Inventory
var container_view_id := ""
var cursor_item_id := ""
var cursor_qty := 0
var hotbar_index := 0
var _item_ui: InventoryUI

signal inventory_changed
signal container_changed
signal item_notice(text: String)


func configure_net(role: NetRole, id: int) -> void:
	net_role = role
	network_id = id
	display_name = "Player %d" % id


func bind_session_node(node: Node) -> void:
	_session = node


func set_reports_input(enabled: bool) -> void:
	_reports_input = enabled


func wants_local_camera() -> bool:
	return net_role == NetRole.LOCAL or net_role == NetRole.OWNER


func is_controlled_locally() -> bool:
	return wants_local_camera()


func allows_local_fire() -> bool:
	return net_role == NetRole.LOCAL


func _ready() -> void:
	if has_meta(&"suppress_ready"):
		set_physics_process(false)
		set_process(false)
		return
	add_to_group(&"player")
	collision_layer = PhysicsLayers.PLAYER
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BUILDING
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var source_shape := _collision.shape as CapsuleShape3D
	_body_shape = source_shape.duplicate() as CapsuleShape3D
	_collision.shape = _body_shape
	var source_mesh := _body_mesh.mesh as CapsuleMesh
	_body_mesh.mesh = source_mesh.duplicate()
	if net_role == NetRole.SERVER:
		collision_layer = PhysicsLayers.PLAYER | PhysicsLayers.DAMAGEABLE
	elif net_role == NetRole.OWNER:
		collision_layer = 0
		collision_mask = 0
	elif net_role == NetRole.PUPPET:
		# Aim rays hit this capsule. Movement masks stay empty so puppets do not push.
		collision_layer = PhysicsLayers.PLAYER
		collision_mask = 0
	if not wants_local_camera():
		_drop_local_presentation()
	if net_role != NetRole.LOCAL:
		_setup_network_presentation()
	if wants_local_camera():
		_setup_inventory_ui()


func _physics_process(delta: float) -> void:
	match net_role:
		NetRole.LOCAL:
			_run_local_frame(delta)
		NetRole.OWNER:
			_run_owner_frame(delta)
		_:
			return


func _process(_delta: float) -> void:
	if net_role != NetRole.OWNER and net_role != NetRole.PUPPET:
		return
	var delay := NetConfig.OWNER_INTERP_DELAY_SEC if net_role == NetRole.OWNER else NetConfig.INTERP_DELAY_SEC
	present_at(Time.get_ticks_msec() / 1000.0 - delay)
	if net_role == NetRole.OWNER and _reports_input and not _bot_controlled():
		_crouch = _owner_crouch
		_aim_pitch = _owner_pitch
		set_lean_visual(_lean_offset)


func _run_local_frame(delta: float) -> void:
	rotation = Vector3.ZERO
	var aim_info := _cursor_aim()
	var aim: Vector3 = aim_info["point"]
	_face_toward(aim)
	_update_stance(delta)
	_move(delta)
	_update_lean(delta)
	var direction := direction_toward_aim(aim)
	set_aim_pitch(asin(clampf(direction.y, -1.0, 1.0)))
	direction = direction_toward_aim(aim)
	_show_aim_marker(aim, aim_info["normal"])
	_try_interact()
	if Input.is_action_just_pressed(&"fire") and not _pointer_over_ui():
		if holds_build_tool():
			pass
		elif not holds_debug_weapon():
			show_item_notice("No weapon in hand.")
		else:
			_weapon.try_fire(shot_origin(), direction)


func _run_owner_frame(_delta: float) -> void:
	rotation = Vector3.ZERO
	if _camera == null or _aim_marker == null or _session == null:
		return
	if _bot_controlled() or not _reports_input:
		return
	var aim_info := _cursor_aim()
	var aim: Vector3 = aim_info["point"]
	_show_aim_marker(aim, aim_info["normal"])
	var input_2d := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if container_view != null:
		input_2d = Vector2.ZERO
	var lean := Input.get_action_strength(&"lean_right") - Input.get_action_strength(&"lean_left")
	var crouch := Input.get_action_strength(&"crouch")
	var aim_yaw := _yaw_from_aim(aim)
	var direction := direction_toward_aim(aim)
	var pitch := asin(clampf(direction.y, -1.0, 1.0))
	_owner_crouch = clampf(crouch, 0.0, 1.0)
	_owner_pitch = clampf(pitch, -InputGuard.MAX_AIM_PITCH, InputGuard.MAX_AIM_PITCH)
	_session.call("send_owner_input", input_2d, _camera.get_yaw(), aim_yaw, lean, _owner_crouch, _owner_pitch)
	_try_interact()
	if Input.is_action_just_pressed(&"fire") and not _pointer_over_ui():
		if holds_build_tool():
			show_item_notice("Building runs in local play only until multiplayer building lands.")
		elif not holds_debug_weapon():
			show_item_notice("No weapon in hand.")
		else:
			_session.call("send_owner_fire", direction, aim_yaw, lean, _owner_crouch)
			_weapon.note_local_request()


func get_aim_point() -> Vector3:
	return _cursor_aim()["point"]


func apply_confirmed_inventory(item_ids: PackedStringArray, item_qtys: PackedInt32Array) -> void:
	if inventory == null:
		inventory = Inventory.new(item_ids.size())
	if inventory.capacity != item_ids.size():
		inventory.resize(item_ids.size())
	inventory.read_snapshot(item_ids, item_qtys)
	refresh_weapon_visual()
	inventory_changed.emit()


func apply_confirmed_cursor(item_id: String, quantity: int) -> void:
	cursor_qty = maxi(quantity, 0)
	cursor_item_id = "" if cursor_qty <= 0 else item_id
	inventory_changed.emit()


func apply_confirmed_container(container_id: String, item_ids: PackedStringArray, item_qtys: PackedInt32Array) -> void:
	container_view_id = container_id
	if container_view == null or container_view.capacity != item_ids.size():
		container_view = Inventory.new(item_ids.size())
	container_view.read_snapshot(item_ids, item_qtys)
	container_changed.emit()
	inventory_changed.emit()


func clear_container_view() -> void:
	container_view = null
	container_view_id = ""
	container_changed.emit()


func show_item_notice(text: String) -> void:
	item_notice.emit(text)


func close_container_view() -> void:
	if net_role == NetRole.LOCAL:
		clear_container_view()
		return
	if _session != null:
		_session.call("send_close_container")


func request_item_transfer(to_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	if net_role == NetRole.LOCAL:
		_local_transfer(to_container, source_slot, dest_slot, quantity)
		return
	if _session != null:
		_session.call("send_item_transfer", container_view_id, to_container, source_slot, dest_slot, quantity)


func request_item_drop(to_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	if net_role == NetRole.LOCAL:
		_local_drop(to_container, source_slot, dest_slot, quantity)
		return
	if _session != null:
		_session.call("send_item_drop", container_view_id, to_container, source_slot, dest_slot, quantity)


func request_slot_click(area: int, index: int, right: bool, shift: bool, collect: bool) -> void:
	if net_role == NetRole.LOCAL:
		_local_slot_click(area, index, right, shift, collect)
		return
	if _session != null:
		_session.call("send_slot_click", area, index, right, shift, collect)


func request_slot_spread(areas: PackedInt32Array, indices: PackedInt32Array, right: bool) -> void:
	if net_role == NetRole.LOCAL:
		_local_slot_spread(areas, indices, right)
		return
	if _session != null:
		_session.call("send_slot_spread", areas, indices, right)


func request_slot_throw(area: int, index: int, whole: bool) -> void:
	if net_role == NetRole.LOCAL:
		_local_slot_throw(area, index, whole)
		return
	if _session != null:
		_session.call("send_slot_throw", area, index, whole)


func request_hotbar_swap(area: int, index: int, hotbar_slot: int) -> void:
	if net_role == NetRole.LOCAL:
		_local_hotbar_swap(area, index, hotbar_slot)
		return
	if _session != null:
		_session.call("send_hotbar_swap", area, index, hotbar_slot)


func _cursor_dict() -> Dictionary:
	return {"id": cursor_item_id, "qty": cursor_qty}


func _apply_local_cursor(cursor: Dictionary) -> void:
	apply_confirmed_cursor(str(cursor.get("id", "")), int(cursor.get("qty", 0)))
	inventory_changed.emit()


func _local_slot_click(area: int, index: int, right: bool, shift: bool, collect: bool) -> void:
	var cursor := _cursor_dict()
	var crate := container_view if area == SlotOps.AREA_CONTAINER or container_view != null else null
	var reason := ""
	if collect:
		reason = SlotOps.collect_same(inventory, container_view, cursor, area, index)
	else:
		reason = SlotOps.click(inventory, crate if area == SlotOps.AREA_CONTAINER else container_view, cursor, area, index, right, shift)
	if reason != "":
		show_item_notice("Transfer failed (%s)." % reason)
		return
	_apply_local_cursor(cursor)


func _local_slot_spread(areas: PackedInt32Array, indices: PackedInt32Array, right: bool) -> void:
	var cursor := _cursor_dict()
	var reason := SlotOps.spread(inventory, container_view, cursor, areas, indices, right)
	if reason != "":
		show_item_notice("Transfer failed (%s)." % reason)
		return
	_apply_local_cursor(cursor)


func _local_slot_throw(area: int, index: int, whole: bool) -> void:
	var cursor := _cursor_dict()
	var thrown := SlotOps.throw_stack(inventory, container_view, cursor, area, index, whole)
	if int(thrown.get("qty", 0)) <= 0:
		show_item_notice("Nothing to drop.")
		return
	_apply_local_cursor(cursor)
	var pickup := WorldPickup.new()
	pickup.pickup_id = "local_drop_%d" % Time.get_ticks_msec()
	pickup.item_id = str(thrown["id"])
	pickup.quantity = int(thrown["qty"])
	var folder := get_tree().root.find_child("Loot", true, false)
	if folder == null:
		folder = get_parent()
	folder.add_child(pickup)
	var forward := -Basis(Vector3.UP, get_facing_yaw()).z
	pickup.global_position = global_position + forward * 0.9
	pickup.global_position.y = 0.15
	show_item_notice("Dropped x%d." % int(thrown["qty"]))


func _local_hotbar_swap(area: int, index: int, hotbar_slot: int) -> void:
	var reason := SlotOps.swap_hotbar(inventory, container_view, area, index, hotbar_slot)
	if reason != "":
		show_item_notice("Transfer failed (%s)." % reason)
		return
	inventory_changed.emit()


func request_item_rearrange(in_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	if net_role == NetRole.LOCAL:
		_local_rearrange(in_container, source_slot, dest_slot, quantity)
		return
	if _session != null:
		_session.call("send_item_rearrange", in_container, source_slot, dest_slot, quantity)


func _setup_inventory_ui() -> void:
	if inventory == null:
		inventory = Inventory.new(NetConfig.INVENTORY_SLOTS)
		inventory.grant_loadout()
	refresh_weapon_visual()
	_item_ui = InventoryUI.new()
	add_child(_item_ui)
	_item_ui.bind_player(self)
	if net_role == NetRole.LOCAL:
		_attach_build_tool.call_deferred()


## Local play only. The tool finds the arena's BuildingSystem by group.
func _attach_build_tool() -> void:
	var system := get_tree().get_first_node_in_group(&"building_system") as BuildingSystem
	if system == null or get_node_or_null("BuildTool") != null:
		return
	var tool := BuildTool.new()
	add_child(tool)
	tool.setup(system, self)


func current_camera() -> Camera3D:
	if _camera == null:
		return null
	return _camera.get_camera()


func _try_interact() -> void:
	if not Input.is_action_just_pressed(&"interact"):
		return
	var target := _nearest_loot()
	if target == null:
		show_item_notice("Nothing in reach.")
		return
	if net_role == NetRole.OWNER:
		if target is WorldPickup:
			_session.call("send_pickup", (target as WorldPickup).pickup_id)
		elif target is LootContainer:
			_session.call("send_open_container", (target as LootContainer).container_id)
		return
	if target is WorldPickup:
		_local_collect(target as WorldPickup)
	elif target is LootContainer:
		_local_open(target as LootContainer)


func _local_collect(pickup: WorldPickup) -> void:
	var before := pickup.quantity
	var taken := pickup.take_into(inventory)
	if taken <= 0:
		if before > 0:
			show_item_notice("Inventory full.")
		else:
			show_item_notice("Nothing left to pick up.")
		return
	var definition := ItemCatalog.get_item(pickup.item_id)
	var label := pickup.item_id if definition == null else definition.display_name
	show_item_notice("Picked up %s x%d." % [label, taken])
	inventory_changed.emit()


func _local_open(crate: LootContainer) -> void:
	if container_view == crate.inventory:
		clear_container_view()
		return
	container_view = crate.inventory
	container_view_id = crate.container_id
	container_changed.emit()
	show_item_notice("Opened crate.")


func _local_transfer(to_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	if container_view == null:
		show_item_notice("No crate open.")
		return
	var source := inventory if to_container else container_view
	var dest := container_view if to_container else inventory
	var reason := Inventory.move(source, source_slot, dest, dest_slot, quantity, to_container)
	if reason != "":
		show_item_notice("Transfer failed (%s)." % reason)
		return
	show_item_notice("Moved x%d." % quantity)
	inventory_changed.emit()


func _local_drop(to_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	if container_view == null:
		show_item_notice("No crate open.")
		return
	var source := inventory if to_container else container_view
	var dest := container_view if to_container else inventory
	var reason := Inventory.drop(source, source_slot, dest, dest_slot, quantity, to_container)
	if reason != "":
		show_item_notice("Transfer failed (%s)." % reason)
		return
	show_item_notice("Moved x%d." % quantity)
	inventory_changed.emit()


func _local_rearrange(in_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	var bag := container_view if in_container else inventory
	if bag == null:
		show_item_notice("No crate open.")
		return
	var reason := Inventory.drop(bag, source_slot, bag, dest_slot, quantity, false)
	if reason != "":
		show_item_notice("Transfer failed (%s)." % reason)
		return
	show_item_notice("Moved x%d." % quantity)
	inventory_changed.emit()


func _nearest_loot() -> Node3D:
	var best: Node3D = null
	var best_distance := NetConfig.INTERACT_RANGE
	for node in get_tree().get_nodes_in_group(&"loot_pickup"):
		var pickup := node as WorldPickup
		if pickup == null or not pickup.visible or pickup.quantity <= 0:
			continue
		var distance := _flat_distance(pickup.global_position)
		if distance <= best_distance:
			best = pickup
			best_distance = distance
	for node in get_tree().get_nodes_in_group(&"loot_container"):
		var crate := node as LootContainer
		if crate == null:
			continue
		var distance := _flat_distance(crate.global_position)
		if distance <= best_distance:
			best = crate
			best_distance = distance
	return best


func _flat_distance(point: Vector3) -> float:
	return Vector2(global_position.x - point.x, global_position.z - point.z).length()


func _pointer_over_ui() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	return viewport.gui_get_hovered_control() != null


func _cursor_aim() -> Dictionary:
	var camera := _camera.get_camera() if _camera != null else null
	if camera == null:
		return {
			"point": global_position + Vector3(0.0, CHEST_HEIGHT, -2.0),
			"normal": Vector3.UP,
		}
	var space: PhysicsDirectSpaceState3D = null
	var world := get_world_3d()
	if world != null:
		space = world.direct_space_state
	return AimProjector.query(camera, get_viewport().get_mouse_position(), space, [get_rid()])


func get_lean_offset() -> float:
	return _lean_offset


func get_crouch() -> float:
	return _crouch


func holds_debug_weapon() -> bool:
	if inventory == null or hotbar_index < 0 or hotbar_index >= inventory.capacity:
		return false
	var slot: Dictionary = inventory.slots[hotbar_index]
	return str(slot["id"]) == "debugweapon" and int(slot["qty"]) > 0


func holds_build_tool() -> bool:
	if inventory == null or hotbar_index < 0 or hotbar_index >= inventory.capacity:
		return false
	var slot: Dictionary = inventory.slots[hotbar_index]
	return str(slot["id"]) == "build_tool" and int(slot["qty"]) > 0


func select_hotbar(index: int) -> void:
	hotbar_index = clampi(index, 0, NetConfig.HOTBAR_SLOTS - 1)
	refresh_weapon_visual()
	if net_role == NetRole.OWNER and _session != null:
		_session.call("send_hotbar_select", hotbar_index)
	inventory_changed.emit()


func set_weapon_drawn(drawn: bool) -> void:
	if _weapon_mesh != null:
		_weapon_mesh.visible = drawn


func refresh_weapon_visual() -> void:
	if net_role == NetRole.PUPPET:
		return
	set_weapon_drawn(holds_debug_weapon())


func get_aim_pitch() -> float:
	return _aim_pitch


func body_height() -> float:
	return lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch)


func eye_height() -> float:
	return lerpf(1.45, 0.78, _crouch)


func current_speed() -> float:
	return lerpf(WALK_SPEED, WALK_SPEED * CROUCH_SPEED_SCALE, _crouch)


func get_facing_yaw() -> float:
	if _visual_root == null:
		return 0.0
	return _visual_root.rotation.y


func remote_sample_count() -> int:
	return _motion.size()


func mark_authoritative_pose() -> void:
	_has_authoritative_pose = true
	_last_pose_time = Time.get_ticks_msec() / 1000.0
	_last_snapshot = global_position


func seed_motion(pos: Vector3, yaw: float) -> void:
	_motion.push(Time.get_ticks_msec() / 1000.0, pos, yaw, _lean_offset, _crouch, _aim_pitch)


func consume_snapshot(
	time_sec: float,
	pos: Vector3,
	yaw: float,
	lean: float,
	hp: int,
	velocity: Vector3,
	seq: int,
	crouch: float = 0.0,
	pitch: float = 0.0
) -> void:
	# Stored for a later prediction pass. Gameplay still renders server poses.
	acked_input_seq = seq
	authoritative_velocity = velocity
	apply_authoritative_health(hp)
	if net_role != NetRole.OWNER and net_role != NetRole.PUPPET:
		return
	if net_role == NetRole.OWNER:
		_note_owner_gap(time_sec, pos)
	_motion.push(time_sec, pos, yaw, lean, crouch, pitch)


func apply_facing_yaw(yaw: float) -> void:
	if _visual_root == null or not is_finite(yaw):
		return
	_visual_root.rotation.y = yaw
	_visual_root.force_update_transform()


func snap_lean_for_shot(lean_axis: float) -> void:
	set_lean_visual(clamped_lean_offset(lean_axis * LEAN_DISTANCE))


func simulate_authored_motion(
	delta: float,
	input_2d: Vector2,
	camera_yaw: float,
	aim_yaw: float,
	lean_axis: float,
	crouch_amount: float = 0.0,
	aim_pitch: float = 0.0
) -> void:
	rotation = Vector3.ZERO
	apply_facing_yaw(aim_yaw)
	set_aim_pitch(aim_pitch)
	apply_stance(crouch_amount, delta)
	var speed := current_speed()
	var direction := wish_direction(input_2d, camera_yaw)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(direction * speed, ACCELERATION * delta)
	var planar := Vector2(horizontal.x, horizontal.z)
	if planar.length() > speed:
		planar = planar.normalized() * speed
		horizontal = Vector3(planar.x, 0.0, planar.y)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	var before := global_position
	move_and_slide()
	var step := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	var cap := speed * delta + 0.08
	if step > cap and step > 0.001:
		var planar_delta := Vector3(global_position.x - before.x, 0.0, global_position.z - before.z)
		var pulled := before + planar_delta.normalized() * cap
		global_position = Vector3(pulled.x, global_position.y, pulled.z)
	var allowed := clamped_lean_offset(lean_axis * LEAN_DISTANCE)
	set_lean_visual(move_toward(_lean_offset, allowed, LEAN_BLEND_SPEED * delta))


func receive_damage(amount: int, _point: Vector3) -> bool:
	if _down or amount <= 0:
		return false
	var next := maxi(health - amount, 0)
	if next >= health:
		return false
	apply_authoritative_health(next)
	return true


func apply_authoritative_health(current: int) -> void:
	current = clampi(current, 0, max_health)
	if current >= health:
		return
	health = current
	_down = health == 0
	_refresh_nameplate()
	if _body_material == null:
		return
	if _down:
		_body_material.albedo_color = Color(0.16, 0.15, 0.15, 1)
		return
	_flash_body()


func clamped_lean_offset(desired: float) -> float:
	## Largest visual sideways shift that keeps the body mesh on the near side
	## of world geometry. Two heights so a low crate and a tall wall both count.
	if is_zero_approx(desired):
		return 0.0
	var sign_dir := 1.0 if desired > 0.0 else -1.0
	var direction := _visual_root.global_basis.x * sign_dir
	var reach := absf(desired) + BODY_RADIUS + LEAN_MARGIN
	var allowance := absf(desired)
	var height_scale := body_height() / STAND_HEIGHT
	var sample_heights: Array[float] = [0.7 * height_scale, 1.35 * height_scale]
	for sample_height: float in sample_heights:
		var origin := global_position + Vector3(0.0, sample_height, 0.0)
		var hit := _raycast_world(origin, origin + direction * reach)
		if hit.is_empty():
			continue
		var hit_position := hit["position"] as Vector3
		var clear := origin.distance_to(hit_position) - BODY_RADIUS - LEAN_MARGIN
		allowance = minf(allowance, maxf(clear, 0.0))
	return sign_dir * allowance


static func wish_direction(input_2d: Vector2, camera_yaw: float) -> Vector3:
	## input_2d matches Input.get_vector(left, right, forward, back):
	## +x is right, -y is forward. The result is camera-relative on the XZ plane.
	var planar := Basis(Vector3.UP, camera_yaw)
	var forward := -planar.z
	var right := planar.x
	var direction := right * input_2d.x + forward * (-input_2d.y)
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return Vector3.ZERO


func visibility_origins() -> PackedVector3Array:
	## Where this player can see and shoot from. The eye follows the lean.
	## The muzzle is the point a bullet actually leaves.
	var eye := global_position + Vector3(0.0, eye_height(), 0.0)
	if _visual_root != null:
		eye += _visual_root.global_basis.x * _lean_offset
	return PackedVector3Array([eye, shot_origin()])


func visibility_points() -> PackedVector3Array:
	## Points on the hurt capsule a shot can strike. The center of the head
	## can be behind cover while the shoulder or the top of the body is not.
	var origin := global_position
	var top := origin.y + body_height() - 0.05
	var chest := origin.y + _chest_height()
	var hip := origin.y + maxf(0.3, body_height() * 0.25)
	return PackedVector3Array([
		origin + Vector3(0.0, eye_height(), 0.0),
		Vector3(origin.x, chest, origin.z),
		Vector3(origin.x, hip, origin.z),
		Vector3(origin.x, top, origin.z),
	])


func shot_origin() -> Vector3:
	## Muzzle after the current lean. A blocked segment from the chest to the
	## muzzle means the barrel is inside cover, so the shot starts on the near face.
	var muzzle := _muzzle.global_position
	var chest := global_position + Vector3(0.0, _chest_height(), 0.0)
	if muzzle.distance_squared_to(chest) < 0.0001:
		return chest
	var hit := _raycast_world(chest, muzzle)
	if hit.is_empty():
		return muzzle
	var hit_position := hit["position"] as Vector3
	var toward_chest := chest - muzzle
	if toward_chest.length_squared() < 0.0001:
		return chest
	return hit_position + toward_chest.normalized() * 0.06


func set_lean_visual(offset: float) -> void:
	_lean_offset = offset
	var ratio := 0.0 if is_zero_approx(LEAN_DISTANCE) else clampf(offset / LEAN_DISTANCE, -1.0, 1.0)
	var height := body_height()
	if _body_shape != null:
		_body_shape.height = height
	if _body_mesh != null and _body_mesh.mesh is CapsuleMesh:
		(_body_mesh.mesh as CapsuleMesh).height = height
	if _collision != null:
		_collision.position.y = height * 0.5
	if _lean_pivot != null:
		_lean_pivot.position = Vector3(offset, height * 0.5 + absf(ratio) * 0.04, 0.0)
		_lean_pivot.rotation = Vector3(0.0, 0.0, deg_to_rad(-6.0) * ratio)
		_lean_pivot.force_update_transform()
	if _camera != null:
		var lean_shift := Vector3.ZERO
		if _visual_root != null:
			lean_shift = _visual_root.transform.basis.x * offset
		_camera.position = Vector3(lean_shift.x, -0.45 * _crouch, lean_shift.z)
	if _nameplate != null:
		_nameplate.position.y = height + 0.35
	_apply_weapon_pitch()


func set_aim_pitch(pitch: float) -> void:
	_aim_pitch = clampf(pitch, -InputGuard.MAX_AIM_PITCH, InputGuard.MAX_AIM_PITCH)
	_apply_weapon_pitch()


func apply_stance(target: float, delta: float) -> void:
	var desired := clampf(target, 0.0, 1.0)
	if desired > _crouch and _headroom_blocked():
		desired = _crouch
	var blend := 1.0 - exp(-STANCE_BLEND_SPEED * delta)
	_crouch = lerpf(_crouch, desired, blend)
	if absf(_crouch - desired) < 0.004:
		_crouch = desired
	set_lean_visual(_lean_offset)


func snap_stance_for_shot(crouch_amount: float) -> void:
	var desired := clampf(crouch_amount, 0.0, 1.0)
	if desired > _crouch and _headroom_blocked():
		desired = _crouch
	_crouch = desired
	set_lean_visual(_lean_offset)


func direction_toward_aim(aim: Vector3) -> Vector3:
	var origin := shot_origin()
	var toward := aim - origin
	if toward.length_squared() < 0.04:
		toward = -_visual_root.global_basis.z
	if toward.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	var clean := InputGuard.sanitize_aim(toward.normalized(), 0.0, 0.0)
	if bool(clean.get("ok", false)):
		return clean["direction"]
	toward.y = 0.0
	if toward.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return toward.normalized()


func _face_toward(aim: Vector3) -> void:
	var flat := Vector3(aim.x - global_position.x, 0.0, aim.z - global_position.z)
	if flat.length_squared() < 0.04:
		return
	# Node forward is -Z. This yaw is the aim, not the camera orbit.
	_visual_root.rotation.y = atan2(-flat.x, -flat.z)


func _move(delta: float) -> void:
	var input_2d := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if container_view != null:
		input_2d = Vector2.ZERO
	var direction := wish_direction(input_2d, _camera.get_yaw())
	var speed := current_speed()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(direction * speed, ACCELERATION * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


func _update_stance(delta: float) -> void:
	apply_stance(Input.get_action_strength(&"crouch"), delta)


func _update_lean(delta: float) -> void:
	var lean_input := Input.get_action_strength(&"lean_right") - Input.get_action_strength(&"lean_left")
	var allowed := clamped_lean_offset(lean_input * LEAN_DISTANCE)
	set_lean_visual(move_toward(_lean_offset, allowed, LEAN_BLEND_SPEED * delta))


func _yaw_from_aim(aim: Vector3) -> float:
	var flat := Vector3(aim.x - global_position.x, 0.0, aim.z - global_position.z)
	if flat.length_squared() < 0.04:
		return get_facing_yaw()
	return atan2(-flat.x, -flat.z)


func present_at(time_sec: float) -> void:
	var rendered := _motion.sample(time_sec)
	if rendered.is_empty():
		return
	global_position = rendered["position"]
	apply_facing_yaw(float(rendered["yaw"]))
	_crouch = float(rendered["crouch"])
	_aim_pitch = float(rendered["pitch"])
	set_lean_visual(float(rendered["lean"]))


func _note_owner_gap(time_sec: float, pos: Vector3) -> void:
	if _has_authoritative_pose:
		var dt := maxf(time_sec - _last_pose_time, 1.0 / 60.0)
		var gap := Vector2(_last_snapshot.x - pos.x, _last_snapshot.z - pos.z).length()
		var allowance := WALK_SPEED * dt + 0.6
		if gap > allowance:
			correction_count += 1
			print("[client] server correction peer=%d gap=%.2f" % [network_id, gap])
	_has_authoritative_pose = true
	_last_pose_time = time_sec
	_last_snapshot = pos


func _drop_local_presentation() -> void:
	if _camera != null:
		var camera := _camera.get_camera()
		if camera != null:
			camera.current = false
		_camera.queue_free()
		_camera = null
	if _aim_marker != null:
		_aim_marker.queue_free()
		_aim_marker = null


func _setup_network_presentation() -> void:
	var mesh := get_node_or_null("VisualRoot/LeanPivot/Body") as MeshInstance3D
	if mesh != null:
		var source := mesh.get_surface_override_material(0) as StandardMaterial3D
		if source != null:
			_body_material = source.duplicate() as StandardMaterial3D
			_body_tint = _color_for(network_id)
			_body_material.albedo_color = _body_tint
			mesh.set_surface_override_material(0, _body_material)
	_nameplate = Label3D.new()
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.position = Vector3(0.0, 2.15, 0.0)
	_nameplate.pixel_size = 0.008
	_nameplate.font_size = 48
	_nameplate.outline_size = 8
	_nameplate.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	add_child(_nameplate)
	_refresh_nameplate()


func _refresh_nameplate() -> void:
	if _nameplate == null:
		return
	if _down:
		_nameplate.text = "P%d\nDOWN" % network_id
	else:
		_nameplate.text = "P%d\n%d HP" % [network_id, health]


func _flash_body() -> void:
	if _body_material == null:
		return
	_body_material.albedo_color = Color(1.0, 0.95, 0.85, 1.0)
	var tween := create_tween()
	tween.tween_property(_body_material, "albedo_color", _body_tint, 0.12)


func _color_for(id: int) -> Color:
	var palette: Array[Color] = [
		Color(0.20, 0.42, 0.78),
		Color(0.86, 0.32, 0.22),
		Color(0.22, 0.68, 0.38),
		Color(0.78, 0.62, 0.18),
		Color(0.55, 0.35, 0.78),
		Color(0.18, 0.65, 0.70),
	]
	var index := 0
	if id >= 2:
		index = (id - 2) % palette.size()
	return palette[index]


func _bot_controlled() -> bool:
	var session := get_node_or_null("/root/NetSession")
	return session != null and bool(session.get("bot"))


func _chest_height() -> float:
	return lerpf(CHEST_HEIGHT, CROUCH_CHEST_HEIGHT, _crouch)


func _headroom_blocked() -> bool:
	var current_top := body_height() - 0.08
	var stand_top := STAND_HEIGHT - 0.08
	if stand_top <= current_top + 0.04:
		return false
	var hit := _raycast_world(
		global_position + Vector3(0.0, current_top, 0.0),
		global_position + Vector3(0.0, stand_top, 0.0)
	)
	return not hit.is_empty()


func _apply_weapon_pitch() -> void:
	if _muzzle == null:
		return
	var muzzle_offset := MUZZLE_REST - WEAPON_ANCHOR
	_muzzle.position = WEAPON_ANCHOR + muzzle_offset.rotated(Vector3.RIGHT, _aim_pitch)
	if _weapon_mesh != null:
		var weapon_offset := WEAPON_REST - WEAPON_ANCHOR
		_weapon_mesh.position = WEAPON_ANCHOR + weapon_offset.rotated(Vector3.RIGHT, _aim_pitch)
		_weapon_mesh.rotation = Vector3(_aim_pitch, 0.0, 0.0)
	_muzzle.force_update_transform()


func _show_aim_marker(point: Vector3, normal: Vector3) -> void:
	if _aim_marker == null:
		return
	var n := normal
	if n.length_squared() < 0.0001:
		n = Vector3.UP
	n = n.normalized()
	_aim_marker.global_position = point + n * 0.03
	var guide := Vector3.FORWARD if absf(n.dot(Vector3.UP)) > 0.92 else Vector3.UP
	var x_axis := guide.cross(n).normalized()
	var z_axis := x_axis.cross(n).normalized()
	_aim_marker.global_basis = Basis(x_axis, n, z_axis)


func _raycast_world(from: Vector3, to: Vector3) -> Dictionary:
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BUILDING
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	return world.direct_space_state.intersect_ray(query)
