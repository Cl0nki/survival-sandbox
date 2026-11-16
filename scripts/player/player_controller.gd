extends CharacterBody3D
class_name PlayerController

## Local play simulates this body directly.
## On a dedicated server the same motion and muzzle helpers run from validated
## input. Owning clients send input and apply server poses. Remote clients
## interpolate. Prediction can later consume authoritative_velocity and
## acked_input_seq without changing the server.

enum NetRole { LOCAL, SERVER, OWNER, PUPPET }

## Authored mesh is 1.80 m. Keep this at 1 so the capsule and the model match.
const MODEL_SCALE := 1.0
const CHEST_HEIGHT := 1.2
const CROUCH_CHEST_HEIGHT := 0.62
const BODY_RADIUS := 0.35
const STAND_HEIGHT := 1.8
## Height of the model axis above the floor when a downed body lies on its back.
const DOWN_LIFT := 0.18
const CROUCH_HEIGHT := 1.05
const CROUCH_SPEED_SCALE := 0.55
## Walk clip matches 1.25 m/s. Default pace is that clip at 1.3x, the old Shift walk.
const WALK_AUTHORED := 1.25
const WALK_PLAYBACK := 1.3
## Shift run. Pro jog feet cover about this much ground per second.
const RUN_SPEED := 3.05
const RUN_STRAFE_SPEED := 2.12
const CROUCH_SPEED := WALK_AUTHORED * CROUCH_SPEED_SCALE
## Bones overwritten by pistol aim / shoot on top of locomotion.
const UPPER_BODY_FILTER: Array[String] = [
	"Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftThumbMetacarpal", "LeftThumbProximal", "LeftThumbDistal",
	"LeftIndexProximal", "LeftIndexIntermediate", "LeftIndexDistal",
	"LeftMiddleProximal", "LeftMiddleIntermediate", "LeftMiddleDistal",
	"LeftRingProximal", "LeftRingIntermediate", "LeftRingDistal",
	"LeftLittleProximal", "LeftLittleIntermediate", "LeftLittleDistal",
	"RightThumbMetacarpal", "RightThumbProximal", "RightThumbDistal",
	"RightIndexProximal", "RightIndexIntermediate", "RightIndexDistal",
	"RightMiddleProximal", "RightMiddleIntermediate", "RightMiddleDistal",
	"RightRingProximal", "RightRingIntermediate", "RightRingDistal",
	"RightLittleProximal", "RightLittleIntermediate", "RightLittleDistal",
]
## Exponential rate for stand/crouch. Higher is snappier. About 0.4 s to settle.
## Screen distance from the cursor to a ground stack that counts as hovering it.
const PICKUP_HOVER_RADIUS_PX := 44.0
const STANCE_BLEND_SPEED := 8.0
const LEAN_DISTANCE := 0.45
const LEAN_MARGIN := 0.12
const LEAN_BLEND_SPEED := 8.0
## Seconds the gun stays raised after a shot, and blend rates in 1/s.
const AIM_HOLD_SEC := 1.6
const DRAW_HOLD_SEC := 0.9
const AIM_BLEND_SPEED := 6.0
## Default stand pace. The Walk clip is played at WALK_PLAYBACK so the feet match.
const WALK_SPEED := WALK_AUTHORED * WALK_PLAYBACK
const ACCELERATION := 28.0
const GRAVITY := 24.0
## Gun mesh pose in RightHand bone space. Bone +Y runs along the fingers.
const HAND_WEAPON_TILT := Vector3(-PI / 2.0, 0.0, 0.0)
const HAND_WEAPON_OFFSET := Vector3(0.0, 0.1, 0.0)
const WEAPON_ANCHOR := Vector3(0.22, 0.3, -0.35)
const MUZZLE_REST := Vector3(0.22, 0.3, -0.75)
const WEAPON_REST := Vector3(0.22, 0.3, -0.45)
## Footsteps. Metres of ground between footfalls, and the speed that counts as running.
## Measured from where the body is drawn, so one rule covers the local player,
## the owning client and every other player's puppet.
const STEP_STRIDE_WALK := 0.8
const STEP_STRIDE_RUN := 1.15
const STEP_RUN_SPEED := 2.4
const STEP_MIN_SPEED := 0.3
## Faster than any real move means a teleport or respawn. It makes no steps.
const STEP_TELEPORT_SPEED := 14.0
const STEP_WINDOW_SEC := 0.1
const STEP_CROUCH_GAIN_DB := -9.0
const STEP_RUN_GAIN_DB := 2.0
## A health drop this soon after the body appears is the server telling us the
## state it already has, not a new hit.
const HURT_QUIET_MSEC := 1000

@onready var _visual_root: Node3D = $VisualRoot
@onready var _lean_pivot: Node3D = $VisualRoot/LeanPivot
@onready var _muzzle: Marker3D = $VisualRoot/LeanPivot/Muzzle
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _body_mesh: MeshInstance3D = get_node_or_null("VisualRoot/LeanPivot/Body")
@onready var _character_model: Node3D = get_node_or_null("VisualRoot/LeanPivot/CharacterModel")
@onready var _weapon_mesh: MeshInstance3D = $VisualRoot/LeanPivot/WeaponMesh
@onready var _camera: OrbitCamera = $CameraRig
@onready var _weapon: HitscanWeapon = $HitscanWeapon
@onready var _aim_marker: MeshInstance3D = $AimMarker
@onready var _anim_tree: AnimationTree = get_node_or_null("AnimationTree")
@onready var _anim_player: AnimationPlayer = get_node_or_null("VisualRoot/LeanPivot/CharacterModel/AnimationPlayer")

var net_role: NetRole = NetRole.LOCAL
var network_id := 0
var display_name := "Player"
var max_health := 100
var health := 100
var correction_count := 0
var acked_input_seq := 0
var authoritative_velocity := Vector3.ZERO

var _lean_offset := 0.0
var _weapon_in_hand := false
var _tool_grip: Node3D
var _mounted_tool_id := ""
var _aim_ready := 0.0
var _aim_hold := 0.0
## True from the click until the harvest OneShot has finished. A second click
## must not FIRE again: that seeks the swing back to frame 0.
var _harvest_swing_lock := false
var _harvest_swing_live := false
var _harvest_swing_wait := 0.0
var _crouch := 0.0
var _sprinting := false
## 1 when the wish direction is forward or back, 0 when it is a pure strafe.
var _sprint_align := 1.0
var _run_blend := 0.0
var _aim_pitch := 0.0
var _owner_crouch := 0.0
var _owner_pitch := 0.0
var _body_shape: CapsuleShape3D
var _session: Node
var _born_msec := 0
var _step_prev := Vector3.ZERO
var _step_primed := false
var _step_travel := 0.0
var _step_window_dist := 0.0
var _step_window_time := 0.0
var _reports_input := true
var _motion := MotionBuffer.new()
var _has_authoritative_pose := false
var _last_pose_time := 0.0
var _last_snapshot := Vector3.ZERO
var _down := false
var _body_material: StandardMaterial3D
var _body_tint := Color(0.2, 0.42, 0.78, 1)
var inventory: Inventory
var container_view: Inventory
var container_view_id := ""
var cursor_item_id := ""
var cursor_qty := 0
var hotbar_index := 0
var _item_ui: InventoryUI
var _tech_ui: TechTreeUI

signal inventory_changed
signal container_changed
signal item_notice(text: String)
## Health reached zero on this body, server or client.
signal downed
## revive() ran: the body is alive again at a new place.
signal revived
## One footfall, drawn or heard. Fires on every role except the server.
signal footstep_taken(running: bool, crouching: bool)

## Seconds until respawn, as last told by the server. Only the owning client sets it.
var respawn_eta := 0.0


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
	_born_msec = Time.get_ticks_msec()
	if net_role != NetRole.SERVER:
		Sfx.warm()
	collision_layer = PhysicsLayers.PLAYER
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BUILDING
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var source_shape := _collision.shape as CapsuleShape3D
	_body_shape = source_shape.duplicate() as CapsuleShape3D
	_body_shape.radius = BODY_RADIUS
	_body_shape.height = STAND_HEIGHT
	_collision.shape = _body_shape
	_collision.position.y = STAND_HEIGHT * 0.5
	if _body_mesh != null and _body_mesh.mesh is CapsuleMesh:
		_body_mesh.mesh = (_body_mesh.mesh as CapsuleMesh).duplicate()
	_prepare_character_model()
	set_lean_visual(0.0)
	if net_role == NetRole.SERVER:
		collision_layer = PhysicsLayers.PLAYER | PhysicsLayers.DAMAGEABLE
	elif net_role == NetRole.OWNER:
		collision_layer = 0
		collision_mask = 0
	elif net_role == NetRole.PUPPET:
		# Aim rays hit this capsule. Movement masks stay empty so puppets do not push.
		collision_layer = PhysicsLayers.PLAYER
		collision_mask = 0
	if _aim_marker != null:
		_aim_marker.visible = false
	if not wants_local_camera():
		_drop_local_presentation()
	if net_role != NetRole.LOCAL:
		_setup_network_presentation()
	if wants_local_camera():
		_setup_inventory_ui()
		if net_role == NetRole.OWNER:
			_attach_build_tool.call_deferred()
			_attach_repair_tool.call_deferred()
			_attach_upgrade_tool.call_deferred()
			_attach_deploy_tool.call_deferred()


func _physics_process(delta: float) -> void:
	match net_role:
		NetRole.LOCAL:
			_run_local_frame(delta)
		NetRole.OWNER:
			_run_owner_frame(delta)
		_:
			return


func _process(delta: float) -> void:
	_poll_harvest_swing(delta)
	_update_upper_blend(delta)
	if net_role != NetRole.OWNER and net_role != NetRole.PUPPET:
		_update_footsteps(delta)
		return
	var delay := NetConfig.OWNER_INTERP_DELAY_SEC if net_role == NetRole.OWNER else NetConfig.INTERP_DELAY_SEC
	present_at(Time.get_ticks_msec() / 1000.0 - delay)
	if net_role == NetRole.OWNER and _reports_input and not _bot_controlled():
		_crouch = _owner_crouch
		_aim_pitch = _owner_pitch
		set_lean_visual(_lean_offset)
	_update_footsteps(delta)


## One footfall sound per stride of ground actually covered. Reads where the body is
## drawn, so it works the same for the local player, the owning client and puppets.
## Positions only change on physics ticks, so distance is summed over a short window.
func _update_footsteps(delta: float) -> void:
	if net_role == NetRole.SERVER or delta <= 0.0:
		return
	var here := global_position
	if not _step_primed:
		_step_prev = here
		_step_primed = true
		return
	_step_window_dist += Vector2(here.x - _step_prev.x, here.z - _step_prev.z).length()
	_step_window_time += delta
	_step_prev = here
	if _step_window_time < STEP_WINDOW_SEC:
		return
	var moved := _step_window_dist
	var speed := moved / _step_window_time
	_step_window_dist = 0.0
	_step_window_time = 0.0
	if _down or speed < STEP_MIN_SPEED or speed > STEP_TELEPORT_SPEED:
		# Standing still: the next footfall comes half a stride after the first move.
		_step_travel = STEP_STRIDE_WALK * 0.5
		return
	var running := speed >= STEP_RUN_SPEED
	var stride := STEP_STRIDE_RUN if running else STEP_STRIDE_WALK
	_step_travel += moved
	if _step_travel < stride:
		return
	_step_travel = fmod(_step_travel, stride)
	var crouching := _crouch > 0.5
	var gain := 0.0
	if crouching:
		gain = STEP_CROUCH_GAIN_DB
	elif running:
		gain = STEP_RUN_GAIN_DB
	footstep_taken.emit(running, crouching)
	Sfx.play_at(&"footstep", here, is_controlled_locally(), gain)


func blocks_camera_input() -> bool:
	return (_item_ui != null and _item_ui.is_open()) or (_tech_ui != null and _tech_ui.is_open())


func _inventory_open() -> bool:
	return blocks_camera_input()


func close_inventory() -> void:
	if _item_ui != null:
		_item_ui.close()


func close_tech_tree() -> void:
	if _tech_ui != null:
		_tech_ui.close()


func _run_local_frame(delta: float) -> void:
	rotation = Vector3.ZERO
	var inventory_open := _inventory_open()
	var aim_info := _cursor_aim()
	var aim: Vector3 = aim_info["point"]
	if not inventory_open:
		_face_toward(aim)
	_update_stance(delta)
	_move(delta)
	_update_lean(delta)
	var direction := direction_toward_aim(aim)
	if not inventory_open:
		set_aim_pitch(asin(clampf(direction.y, -1.0, 1.0)))
		direction = direction_toward_aim(aim)
		_present_aim_marker(aim, aim_info["normal"], false)
	else:
		_present_aim_marker(aim, aim_info["normal"], true)
	_try_interact()
	if inventory_open:
		return
	if Input.is_action_just_pressed(&"fire") and not _pointer_over_ui():
		if holds_build_tool() or holds_repair_tool() or holds_upgrade_tool() or holds_deployable():
			pass
		elif holds_blast_gun():
			_try_local_blast()
		elif holds_harvest_tool():
			_try_local_harvest()
		elif holds_pistol():
			if not _spend_ammo("ammo_9mm", 1):
				show_item_notice("No 9mm ammunition.")
			else:
				_weapon.try_fire(shot_origin(), direction)
				_request_shoot_anim()
		elif holds_debug_weapon():
			_weapon.try_fire(shot_origin(), direction)
			_request_shoot_anim()
		else:
			show_item_notice("No weapon in hand.")



func _run_owner_frame(_delta: float) -> void:
	rotation = Vector3.ZERO
	if _camera == null or _aim_marker == null or _session == null:
		return
	if _bot_controlled() or not _reports_input:
		return
	var inventory_open := _inventory_open()
	var aim_info := _cursor_aim()
	var aim: Vector3 = aim_info["point"]
	_present_aim_marker(aim, aim_info["normal"], inventory_open)
	var input_2d := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if container_view != null or inventory_open:
		input_2d = Vector2.ZERO
	var lean := 0.0 if inventory_open else Input.get_action_strength(&"lean_right") - Input.get_action_strength(&"lean_left")
	var crouch := 0.0 if inventory_open else Input.get_action_strength(&"crouch")
	var sprinting := _read_sprint(inventory_open or container_view != null, crouch)
	_sprinting = sprinting
	_set_sprint_align(wish_direction(input_2d, _camera.get_yaw()))
	var aim_yaw := get_facing_yaw() if inventory_open else _yaw_from_aim(aim)
	var direction := direction_toward_aim(aim)
	var pitch := _aim_pitch if inventory_open else asin(clampf(direction.y, -1.0, 1.0))
	_owner_crouch = clampf(crouch, 0.0, 1.0)
	_owner_pitch = clampf(pitch, -InputGuard.MAX_AIM_PITCH, InputGuard.MAX_AIM_PITCH)
	_session.call("send_owner_input", input_2d, _camera.get_yaw(), aim_yaw, lean, _owner_crouch, _owner_pitch, sprinting)
	_try_interact()
	if inventory_open:
		return
	if Input.is_action_just_pressed(&"fire") and not _pointer_over_ui():
		if holds_build_tool() or holds_repair_tool() or holds_upgrade_tool() or holds_deployable():
			pass
		elif holds_blast_gun():
			_try_network_blast()
		elif holds_harvest_tool() or holds_debug_weapon() or holds_pistol():
			_session.call("send_owner_fire", direction, aim_yaw, lean, _owner_crouch)
			_weapon.note_local_request()
			if holds_harvest_tool():
				_request_harvest_anim()
			elif holds_debug_weapon() or holds_pistol():
				_request_shoot_anim()
		else:
			show_item_notice("No weapon in hand.")



func get_aim_point() -> Vector3:
	return _cursor_aim()["point"]


func _hidden_building_pieces() -> Callable:
	var nodes := get_tree().get_nodes_in_group(&"building_system")
	if nodes.is_empty():
		return Callable()
	var system := nodes[0] as BuildingSystem
	if system == null or system.world == null:
		return Callable()
	return Callable(system.world, &"collider_is_hidden")


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


func request_craft(input_id: String, extra_id: String, amount: int = 1) -> void:
	if net_role == NetRole.LOCAL:
		_local_craft(input_id, extra_id, amount)
		return
	if _session != null:
		_session.call("send_craft", input_id, extra_id, amount)


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


func _local_craft(input_id: String, extra_id: String, amount: int = 1) -> void:
	if container_view == null or container_view_id.is_empty():
		show_item_notice("No station open.")
		return
	var station: LootContainer = null
	for node in get_tree().get_nodes_in_group(&"loot_container"):
		var crate := node as LootContainer
		if crate != null and crate.container_id == container_view_id:
			station = crate
			break
	if station == null:
		show_item_notice("No station open.")
		return
	var reason := ""
	if station is Crafter:
		reason = (station as Crafter).craft_from_bag(inventory, input_id, extra_id, amount)
	elif station is Smelter:
		reason = (station as Smelter).smelt_from_bag(inventory, input_id, amount)
	else:
		show_item_notice("Not a crafting station.")
		return
	if reason != "":
		show_item_notice(reason)
		return
	inventory_changed.emit()
	container_changed.emit()
	show_item_notice("Queued.")


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
		inventory.grant_loadout(_local_map_id())
	refresh_weapon_visual()
	_item_ui = InventoryUI.new()
	add_child(_item_ui)
	_item_ui.bind_player(self)
	_tech_ui = TechTreeUI.new()
	add_child(_tech_ui)
	_tech_ui.bind_player(self)
	if net_role == NetRole.OWNER:
		var vitals_hud := VitalsHud.new()
		vitals_hud.name = "VitalsHud"
		add_child(vitals_hud)
		vitals_hud.bind_player(self)
	if net_role == NetRole.LOCAL:
		## Survival starts with the hut workbench already placed. DeployTool stays
		## so crafted stations can still be planted later.
		if _local_map_id() != NetConfig.MAP_SURVIVAL:
			_attach_build_tool.call_deferred()
			_attach_repair_tool.call_deferred()
			_attach_upgrade_tool.call_deferred()
		_attach_deploy_tool.call_deferred()


## The tool finds the arena's BuildingSystem by group. Local play commits
## directly. A network owner sends the same request to the server.
func _attach_build_tool() -> void:
	var system := get_tree().get_first_node_in_group(&"building_system") as BuildingSystem
	if system == null or get_node_or_null("BuildTool") != null:
		return
	var tool := BuildTool.new()
	add_child(tool)
	tool.setup(system, self)


func _attach_deploy_tool() -> void:
	var system := get_tree().get_first_node_in_group(&"deployable_system") as DeployableSystem
	var building := get_tree().get_first_node_in_group(&"building_system") as BuildingSystem
	if system == null or building == null or get_node_or_null("DeployTool") != null:
		return
	var tool := DeployTool.new()
	add_child(tool)
	tool.setup(system, building, self)


func _attach_repair_tool() -> void:
	var system := get_tree().get_first_node_in_group(&"building_system") as BuildingSystem
	if system == null or get_node_or_null("RepairTool") != null:
		return
	var tool := RepairTool.new()
	add_child(tool)
	tool.setup(system, self)


func _attach_upgrade_tool() -> void:
	var system := get_tree().get_first_node_in_group(&"building_system") as BuildingSystem
	if system == null or get_node_or_null("UpgradeTool") != null:
		return
	var tool := UpgradeTool.new()
	add_child(tool)
	tool.setup(system, self)


func current_camera() -> Camera3D:
	if _camera == null:
		return null
	return _camera.get_camera()


## Names on ground stacks show only for the stack under the cursor and for the
## nearest one in reach, the same one F would pick up. Deployables use the
## same rule, and F1 adds the name plus HP on every placed piece.
func _update_pickup_focus() -> void:
	var near := _nearest_loot() as WorldPickup
	var hovered: WorldPickup = null
	var camera := current_camera()
	if camera != null and not _pointer_over_ui():
		var mouse := get_viewport().get_mouse_position()
		var best := PICKUP_HOVER_RADIUS_PX
		for node in get_tree().get_nodes_in_group(&"loot_pickup"):
			var pickup := node as WorldPickup
			if pickup == null or not pickup.visible or pickup.quantity <= 0:
				continue
			var point := pickup.global_position + Vector3(0.0, 0.15, 0.0)
			if camera.is_position_behind(point):
				continue
			var distance := camera.unproject_position(point).distance_to(mouse)
			if distance <= best:
				hovered = pickup
				best = distance
	for node in get_tree().get_nodes_in_group(&"loot_pickup"):
		var pickup := node as WorldPickup
		if pickup != null:
			pickup.set_focus(pickup == hovered or pickup == near, pickup == near)
	_update_deployable_labels()


func _update_deployable_labels() -> void:
	var debug := DebugFlags.enabled()
	var hovered := _hovered_deployable()
	var prompt := _deployable_prompt_target()
	for node in get_tree().get_nodes_in_group(&"deployable"):
		if not node.has_method(&"set_label_focus"):
			continue
		var body := node as Node3D
		if body == null:
			continue
		var close := _flat_distance(body.global_position) <= NetConfig.INTERACT_RANGE
		node.call(&"set_label_focus", debug or node == hovered or close, node == prompt, debug)


func _hovered_deployable() -> Node:
	var camera := current_camera()
	if camera == null or _pointer_over_ui():
		return null
	var hovered := _as_deployable(_cursor_aim().get("collider"))
	if hovered != null:
		return hovered
	var mouse := get_viewport().get_mouse_position()
	var best: Node = null
	var best_px := PICKUP_HOVER_RADIUS_PX
	for node in get_tree().get_nodes_in_group(&"deployable"):
		var body := node as Node3D
		if body == null or not body.visible:
			continue
		var point := body.global_position + Vector3(0.0, 0.9, 0.0)
		if camera.is_position_behind(point):
			continue
		var distance := camera.unproject_position(point).distance_to(mouse)
		if distance <= best_px:
			best = body
			best_px = distance
	return best


func _as_deployable(collider: Variant) -> Node:
	var node := collider as Node
	while node != null:
		if node.is_in_group(&"deployable"):
			return node
		node = node.get_parent()
	return null


## The piece F would use. Pickups win when they are closer, so a chest behind
## a stack does not show the use hint.
func _deployable_prompt_target() -> Node:
	var target := _nearest_loot()
	if target != null and target.is_in_group(&"deployable"):
		return target
	return null


func _try_interact() -> void:
	_update_pickup_focus()
	if not Input.is_action_just_pressed(&"interact"):
		return
	var target := _nearest_loot()
	if target == null:
		show_item_notice("Nothing in reach.")
		return
	if target.is_in_group(&"deployable_door"):
		_use_door(target)
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
	show_item_notice("Opened %s." % crate.prompt)


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
	for node in get_tree().get_nodes_in_group(&"deployable_door"):
		var door := node as Node3D
		if door == null:
			continue
		var door_distance := _flat_distance(door.global_position)
		if door_distance <= best_distance:
			best = door
			best_distance = door_distance
	return best


func _use_door(door: Node3D) -> void:
	if not door.has_meta(&"deployable_id"):
		return
	var piece_id := int(door.get_meta(&"deployable_id"))
	if net_role == NetRole.OWNER:
		if _session != null:
			_session.call(&"send_toggle_door", piece_id)
		return
	var host := door.get_parent()
	if host == null or not host.has_method(&"toggle_door"):
		return
	if not bool(host.call(&"toggle_door", piece_id, global_position)):
		return
	show_item_notice("Opened the door." if bool(door.get(&"open")) else "Closed the door.")


func _flat_distance(point: Vector3) -> float:
	return Vector2(global_position.x - point.x, global_position.z - point.z).length()


func _pointer_over_ui() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	return viewport.gui_get_hovered_control() != null


func cursor_aim() -> Dictionary:
	return _cursor_aim()


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
	return AimProjector.query(camera, get_viewport().get_mouse_position(), space, [get_rid()], _hidden_building_pieces())


func get_lean_offset() -> float:
	return _lean_offset


func get_crouch() -> float:
	return _crouch


func _try_network_blast() -> void:
	var nodes := get_tree().get_nodes_in_group(&"building_system")
	if nodes.is_empty():
		return
	var building := nodes[0] as BuildingSystem
	if building == null or building.relay == null:
		return
	var aim: Vector3 = _cursor_aim()["point"]
	show_debug_beam(aim, ShotVisual.BLAST)
	building.relay.request_blast(aim)


func _try_local_blast() -> void:
	var nodes := get_tree().get_nodes_in_group(&"building_system")
	if nodes.is_empty():
		return
	var system := nodes[0] as BuildingSystem
	if system == null:
		return
	var aim: Vector3 = _cursor_aim()["point"]
	show_debug_beam(aim, ShotVisual.BLAST)
	var result: Dictionary = system.authority.apply_explosion(aim, system.config.blast_radius, system.config.blast_damage)
	var hits: Array = result.get("hits", [])
	if hits.is_empty():
		show_item_notice("Blast hit nothing.")
	else:
		show_item_notice("Blast hit %d piece%s." % [hits.size(), "" if hits.size() == 1 else "s"])


func holds_blast_gun() -> bool:
	return _hotbar_is("blast_gun")


func holds_repair_tool() -> bool:
	return _hotbar_is("repair_tool") or _hotbar_is("repair_trowel")


func holds_upgrade_tool() -> bool:
	return _hotbar_is("upgrade_tool") or _hotbar_is("upgrade_hammer")


func holds_debug_weapon() -> bool:
	return _hotbar_is("debugweapon")


func holds_pistol() -> bool:
	return _hotbar_is("pistol")


func charges_build_cost() -> bool:
	return _hotbar_is("building_plan")


func charges_repair_cost() -> bool:
	return _hotbar_is("repair_trowel")


func charges_upgrade_cost() -> bool:
	return _hotbar_is("upgrade_hammer")


func uses_craft_tool_reach() -> bool:
	return charges_repair_cost() or charges_upgrade_cost()



func held_item_id() -> String:
	if inventory == null or hotbar_index < 0 or hotbar_index >= inventory.capacity:
		return ""
	var slot: Dictionary = inventory.slots[hotbar_index]
	if int(slot.get("qty", 0)) <= 0:
		return ""
	return str(slot.get("id", ""))


func holds_harvest_tool() -> bool:
	var definition := ItemCatalog.get_item(held_item_id())
	return definition != null and definition.harvest_kind != ""


func _try_local_harvest() -> void:
	if _weapon == null or not _weapon.is_ready():
		return
	var origin := shot_origin()
	var direction := direction_toward_aim(get_aim_point())
	var result := HarvestSwing.try_strike(self, origin, direction, held_item_id(), inventory)
	_weapon.note_local_request()
	_request_harvest_anim()
	_weapon.last_feedback = str(result.get("notice", "harvest"))
	var end_point: Vector3 = result.get("point", origin)
	if bool(result.get("changed", false)):
		var definition := ItemCatalog.get_item(held_item_id())
		var kind := "" if definition == null else definition.harvest_kind
		var normal: Vector3 = result.get("normal", Vector3.UP)
		HitBurst.spawn(_visual_parent(), end_point, -normal, HitBurst.color_for(kind))
	if DebugFlags.enabled():
		ShotVisual.spawn(_visual_parent(), origin, end_point, bool(result.get("changed", false)))
	var leftovers: Array = result.get("leftovers", [])
	if leftovers.is_empty() and int(result.get("leftover", 0)) > 0:
		leftovers = [[str(result.get("item_id", "")), int(result.get("leftover", 0))]]
	for drop in leftovers:
		_spawn_local_pickup(str(drop[0]), int(drop[1]))
	var notice := str(result.get("notice", ""))
	if notice != "":
		show_item_notice(notice)
	inventory_changed.emit()


func _spawn_local_pickup(item_id: String, quantity: int) -> void:
	if item_id.is_empty() or quantity <= 0:
		return
	var pickup := WorldPickup.new()
	pickup.pickup_id = "local_drop_%d" % Time.get_ticks_msec()
	pickup.item_id = item_id
	pickup.quantity = quantity
	var folder := get_tree().root.find_child("Loot", true, false)
	if folder == null:
		folder = get_parent()
	folder.add_child(pickup)
	var forward := -Basis(Vector3.UP, get_facing_yaw()).z
	pickup.global_position = global_position + forward * 0.9
	pickup.global_position.y = 0.15


func show_debug_beam(end_point: Vector3, tint: Color) -> void:
	ShotVisual.spawn(_visual_parent(), shot_origin(), end_point, false, tint, 0.25)


func _visual_parent() -> Node:
	var tree := get_tree()
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root


func _hotbar_is(item_id: String) -> bool:
	if inventory == null or hotbar_index < 0 or hotbar_index >= inventory.capacity:
		return false
	var slot: Dictionary = inventory.slots[hotbar_index]
	return str(slot["id"]) == item_id and int(slot["qty"]) > 0


func holds_build_tool() -> bool:
	return _hotbar_is("build_tool") or _hotbar_is("building_plan")


func holds_deployable() -> bool:
	return DeployableCatalog.known(held_item_id())


func _spend_ammo(item_id: String, quantity: int) -> bool:
	if inventory == null or quantity <= 0:
		return false
	if not inventory.take_item(item_id, quantity):
		return false
	inventory_changed.emit()
	return true



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
	_refresh_held_tool()
	if net_role == NetRole.PUPPET:
		return
	set_weapon_drawn(holds_debug_weapon() or holds_pistol() or holds_blast_gun())
	if holds_debug_weapon() or holds_pistol():
		_aim_hold = maxf(_aim_hold, DRAW_HOLD_SEC)
	_update_aim_anim()
	if _weapon_mesh == null:
		return
	var material := _weapon_mesh.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		return
	if not _weapon_mesh.has_meta(&"pistol_color"):
		_weapon_mesh.set_meta(&"pistol_color", material.albedo_color)
	material.albedo_color = Color(0.95, 0.42, 0.12) if holds_blast_gun() else _weapon_mesh.get_meta(&"pistol_color")


func get_aim_pitch() -> float:
	return _aim_pitch


func body_height() -> float:
	return lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch)


func eye_height() -> float:
	return lerpf(1.45, 0.78, _crouch)


func current_speed() -> float:
	var stand := WALK_SPEED
	if _sprinting:
		stand = lerpf(RUN_STRAFE_SPEED, RUN_SPEED, _sprint_align)
	return lerpf(stand, CROUCH_SPEED, _crouch)


func _set_sprint_align(direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		_sprint_align = 1.0
		return
	var local := Basis(Vector3.UP, get_facing_yaw()).inverse() * direction
	var planar := Vector2(local.x, -local.z)
	if planar.length_squared() < 0.0001:
		_sprint_align = 1.0
		return
	_sprint_align = absf(planar.normalized().y)


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
	aim_pitch: float = 0.0,
	sprinting: bool = false
) -> void:
	rotation = Vector3.ZERO
	apply_facing_yaw(aim_yaw)
	set_aim_pitch(aim_pitch)
	apply_stance(crouch_amount, delta)
	_sprinting = sprinting and _crouch < 0.5
	var direction := wish_direction(input_2d, camera_yaw)
	_set_sprint_align(direction)
	var speed := current_speed()
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
	var was_down := _down
	_down = health == 0
	if net_role != NetRole.SERVER and Time.get_ticks_msec() - _born_msec > HURT_QUIET_MSEC:
		Sfx.play_at(&"hurt", global_position, is_controlled_locally())
	_apply_down_pose()
	if _down and not was_down:
		if net_role == NetRole.OWNER:
			close_inventory()
			close_tech_tree()
		downed.emit()
	if _body_material == null:
		return
	if _down:
		_body_material.albedo_color = Color(0.16, 0.15, 0.15, 1)
		return
	_flash_body()


func is_down() -> bool:
	return _down


## The one way back to life. apply_authoritative_health never raises health,
## so a stale snapshot cannot heal anyone. The server calls this directly on its
## own pawn; clients call it when the server sends player_respawned.
func revive(pos: Vector3, yaw: float) -> void:
	health = max_health
	_down = false
	respawn_eta = 0.0
	velocity = Vector3.ZERO
	authoritative_velocity = Vector3.ZERO
	_crouch = 0.0
	_owner_crouch = 0.0
	_aim_pitch = 0.0
	_owner_pitch = 0.0
	_sprinting = false
	global_position = pos
	apply_facing_yaw(yaw)
	_apply_down_pose()
	set_lean_visual(0.0)
	_motion.clear()
	seed_motion(pos, yaw)
	mark_authoritative_pose()
	if _body_material != null:
		_body_material.albedo_color = _body_tint
	revived.emit()


## The character model comes from a glTF and ignores the capsule material, so a
## downed player is laid on their back instead of only being tinted.
func _apply_down_pose() -> void:
	if _character_model == null:
		return
	_character_model.rotation.x = deg_to_rad(-90.0) if _down else 0.0
	set_lean_visual(_lean_offset)


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
	if _character_model != null:
		# Keep feet on the ground while LeanPivot sits at capsule center.
		# A downed model lies flat, so its axis sits one body radius up.
		_character_model.position.y = -height * 0.5 + (DOWN_LIFT if _down else 0.0)
	if _camera != null:
		var lean_shift := Vector3.ZERO
		if _visual_root != null:
			lean_shift = _visual_root.transform.basis.x * offset
		_camera.position = Vector3(lean_shift.x, -0.45 * _crouch, lean_shift.z)
	_apply_weapon_pitch()
	_update_locomotion_anim()


func set_aim_pitch(pitch: float) -> void:
	_aim_pitch = clampf(pitch, -InputGuard.MAX_AIM_PITCH, InputGuard.MAX_AIM_PITCH)
	_apply_weapon_pitch()
	_update_aim_anim()


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
	var blocked := container_view != null or _inventory_open()
	if blocked:
		input_2d = Vector2.ZERO
	_sprinting = _read_sprint(blocked, Input.get_action_strength(&"crouch"))
	var direction := wish_direction(input_2d, _camera.get_yaw())
	_set_sprint_align(direction)
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


func _read_sprint(blocked: bool, crouch_amount: float) -> bool:
	if blocked or crouch_amount > 0.5:
		return false
	return Input.is_action_pressed(&"sprint")


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
		var allowance := RUN_SPEED * dt + 0.6
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


func _local_map_id() -> String:
	var arena := get_parent()
	if arena != null and str(arena.get("force_map")) != "":
		var forced := NetConfig.normalize_map(str(arena.get("force_map")))
		if not forced.is_empty():
			return forced
	var session := get_node_or_null("/root/NetSession")
	if session != null:
		var mapped := NetConfig.normalize_map(str(session.get("map_id")))
		if not mapped.is_empty():
			return mapped
	return NetConfig.DEFAULT_MAP


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
	if _weapon_mesh != null and not _weapon_in_hand:
		var weapon_offset := WEAPON_REST - WEAPON_ANCHOR
		_weapon_mesh.position = WEAPON_ANCHOR + weapon_offset.rotated(Vector3.RIGHT, _aim_pitch)
		_weapon_mesh.rotation = Vector3(_aim_pitch, 0.0, 0.0)
	_muzzle.force_update_transform()


func _prepare_character_model() -> void:
	if _character_model == null:
		return
	# Clips use %GeneralSkeleton, which only resolves inside the instanced model.
	# Mesh faces +Z; VisualRoot forward is -Z — yaw 180° to match aim.
	_character_model.scale = Vector3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	_character_model.rotation.y = PI
	var embedded := HumanoidClips.install(_character_model)
	if embedded == null:
		return
	_anim_player = embedded
	_attach_weapon_to_hand()
	if _anim_tree != null:
		_anim_tree.anim_player = _anim_tree.get_path_to(embedded)
		_anim_tree.active = true
		_configure_upper_body_filters()
		_anim_tree.set("parameters/stand_loco/blend_position", Vector2.ZERO)
		_anim_tree.set("parameters/crouch_loco/blend_position", Vector2.ZERO)
		_anim_tree.set("parameters/stance/blend_amount", 0.0)
		_anim_tree.set("parameters/aim/blend_position", 0.0)
		_anim_tree.set("parameters/upper/blend_amount", 0.0)
	_update_locomotion_anim()
	_update_aim_anim()


## The gun mesh rides on the right hand so it hangs at the side while the arms
## are down and points where the aimed pose points. The muzzle marker stays on
## LeanPivot: shots still start from the server-checked aim origin.
func _attach_weapon_to_hand() -> void:
	if _weapon_mesh == null or _character_model == null or _weapon_in_hand:
		return
	var skeleton := HumanoidClips.skinned_skeleton(_character_model)
	if skeleton == null or skeleton.find_bone("RightHand") < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "RightHandAttachment"
	skeleton.add_child(attach)
	attach.bone_name = "RightHand"
	_weapon_mesh.get_parent().remove_child(_weapon_mesh)
	attach.add_child(_weapon_mesh)
	_weapon_mesh.transform = Transform3D(Basis.from_euler(HAND_WEAPON_TILT), HAND_WEAPON_OFFSET)
	var grip := Node3D.new()
	grip.name = "ToolGrip"
	attach.add_child(grip)
	_tool_grip = grip
	_weapon_in_hand = true


## Right-hand socket for res://assets/equipment/<id>.glb. The gun box stays
## on its own tilt. The tool grip uses the bone as-is: +Y along the fingers.
func _refresh_held_tool() -> void:
	var grip := _ensure_tool_grip()
	if grip == null:
		return
	var item_id := held_item_id()
	if item_id == _mounted_tool_id:
		return
	var shown := HeldToolArt.mount(grip, item_id)
	grip.visible = shown
	_mounted_tool_id = item_id


func _ensure_tool_grip() -> Node3D:
	if _tool_grip != null and is_instance_valid(_tool_grip):
		return _tool_grip
	_attach_weapon_to_hand()
	if _tool_grip != null and is_instance_valid(_tool_grip):
		return _tool_grip
	return null


func _configure_upper_body_filters() -> void:
	if _anim_tree == null or _anim_tree.tree_root == null:
		return
	var tree := _anim_tree.tree_root as AnimationNodeBlendTree
	if tree == null:
		return
	for node_name in [&"upper", &"shoot", &"harvest"]:
		var node: AnimationNode = tree.get_node(node_name)
		if node == null:
			continue
		node.filter_enabled = true
		for bone in UPPER_BODY_FILTER:
			node.set_filter_path(NodePath("%%GeneralSkeleton:%s" % bone), true)


func _update_locomotion_anim() -> void:
	if _anim_tree == null:
		return
	if not _anim_tree.active:
		_anim_tree.active = true
	# Local/server simulate CharacterBody3D.velocity. Owner/puppet clients
	# teleport via present_at and only receive speed in authoritative_velocity.
	var source := velocity
	if net_role == NetRole.OWNER or net_role == NetRole.PUPPET:
		source = authoritative_velocity
	# Facing stays on aim. Blend X/Y is velocity in that facing frame so
	# strafe and back keep their own clips. Lean clips are off for now;
	# LeanPivot still shifts the camera and the mesh.
	var local := Basis(Vector3.UP, get_facing_yaw()).inverse() * source
	var planar := Vector2(local.x, -local.z)
	var speed := planar.length()
	var blend := Vector2.ZERO
	var max_speed := maxf(current_speed(), 0.01)
	if speed >= 0.08:
		blend = planar / speed * clampf(speed / max_speed, 0.0, 1.0)
	var running := _sprinting and _crouch < 0.5 and speed >= 0.2
	if net_role == NetRole.PUPPET:
		running = _crouch < 0.5 and speed > WALK_SPEED * 1.25
	var dt := maxf(get_physics_process_delta_time(), 1.0 / 60.0)
	_run_blend = move_toward(_run_blend, 1.0 if running else 0.0, 8.0 * dt)
	var cycle := 1.0
	if speed > WALK_AUTHORED * 1.02:
		cycle = clampf(speed / WALK_AUTHORED, 1.0, WALK_PLAYBACK)
	_anim_tree.set("parameters/stand_speed/scale", cycle)
	_anim_tree.set("parameters/stand_loco/blend_position", blend)
	_anim_tree.set("parameters/run_loco/blend_position", blend)
	_anim_tree.set("parameters/gait/blend_amount", _run_blend)
	_anim_tree.set("parameters/stand_lean/blend_position", 0.0)
	_anim_tree.set("parameters/stand_body/blend_amount", 0.0)
	_anim_tree.set("parameters/crouch_loco/blend_position", blend)
	_anim_tree.set("parameters/stance/blend_amount", _crouch)


func _update_aim_anim() -> void:
	if _anim_tree == null:
		return
	if not (holds_pistol() or holds_debug_weapon()):
		return
	var max_pitch := maxf(InputGuard.MAX_AIM_PITCH, 0.001)
	var aim_blend := clampf(_aim_pitch / max_pitch, -1.0, 1.0)
	_anim_tree.set("parameters/aim/blend_position", aim_blend)


## Upper body: the arms follow normal locomotion unless the gun is raised.
## Drawing a gun or firing raises it to the aimed pose for a moment, then the
## arms lower again with the gun still in the hand.
func _update_upper_blend(delta: float) -> void:
	if _anim_tree == null or not _anim_tree.active:
		return
	var armed := holds_pistol() or holds_debug_weapon()
	_aim_hold = maxf(_aim_hold - delta, 0.0)
	_aim_ready = move_toward(_aim_ready, 1.0 if armed and _aim_hold > 0.0 else 0.0, AIM_BLEND_SPEED * delta)
	_anim_tree.set("parameters/upper/blend_amount", _aim_ready)


func _request_shoot_anim() -> void:
	if _anim_tree == null:
		return
	if not (holds_pistol() or holds_debug_weapon()):
		return
	_aim_hold = AIM_HOLD_SEC
	_anim_tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _harvest_clip_name() -> StringName:
	var definition := ItemCatalog.get_item(held_item_id())
	var kind := "" if definition == null else definition.harvest_kind
	match kind:
		"hatchet":
			return &"TreeChopping"
		"pickaxe", "shovel", "crowbar":
			return &"Mining"
		_:
			return &"Mining"


func _poll_harvest_swing(delta: float) -> void:
	if not _harvest_swing_lock or _anim_tree == null:
		return
	if bool(_anim_tree.get("parameters/harvest/active")):
		_harvest_swing_live = true
		_harvest_swing_wait = 0.0
		return
	# The tree has played it and then cleared it. The next click may start a new swing.
	if _harvest_swing_live:
		_harvest_swing_lock = false
		_harvest_swing_live = false
		return
	# FIRE was sent, but the OneShot never became active.
	_harvest_swing_wait += delta
	if _harvest_swing_wait > 0.25:
		_harvest_swing_lock = false
		_harvest_swing_wait = 0.0


func _request_harvest_anim() -> void:
	if _anim_tree == null or _anim_tree.tree_root == null:
		return
	_poll_harvest_swing(0.0)
	if _harvest_swing_lock or bool(_anim_tree.get("parameters/harvest/active")):
		return
	var tree := _anim_tree.tree_root as AnimationNodeBlendTree
	if tree == null:
		return
	var clip := tree.get_node(&"harvest_clip") as AnimationNodeAnimation
	if clip != null:
		clip.animation = _harvest_clip_name()
	_harvest_swing_lock = true
	_harvest_swing_live = false
	_harvest_swing_wait = 0.0
	_anim_tree.set("parameters/harvest/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _present_aim_marker(aim: Vector3, normal: Vector3, inventory_open: bool) -> void:
	if _aim_marker == null:
		return
	if inventory_open or not DebugFlags.enabled():
		_aim_marker.visible = false
		return
	var point := aim
	if holds_harvest_tool():
		var origin := shot_origin()
		var direction := direction_toward_aim(aim)
		var cap := HarvestSwing.reach_point(global_position, origin, direction)
		if origin.distance_squared_to(aim) > origin.distance_squared_to(cap):
			point = cap
			normal = Vector3.UP
	_aim_marker.visible = true
	_show_aim_marker(point, normal)


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
