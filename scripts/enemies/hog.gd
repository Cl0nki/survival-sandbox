extends Creature
class_name Hog

## A wild hog. It grazes near its home and leaves you alone until you shoot
## it or walk up to it. Then it telegraphs, locks a direction, and charges
## in a straight line. Sidestep and it overshoots. If it hits you it gores
## once; if it hits a wall it is stunned and wide open.
##
## States, in the order a fight goes:
##   IDLE/WALK -> WINDUP (aim, then lock) -> CHARGE -> RECOVER or STUNNED
##   -> WINDUP again while angry and a target is near, else IDLE.
## Crouching halves how close you can get before it notices you.

const S_WINDUP := 10
const S_CHARGE := 11
const S_RECOVER := 12
const S_STUNNED := 13
const S_WALK := 14

const MAX_HEALTH := 80
const RADIUS := 0.5
const HEIGHT := 0.95

const WALK_SPEED := 0.9
const WANDER_RADIUS := 6.0

const TRIGGER_STAND := 3.5
const TRIGGER_CROUCH := 2.0
const ANGER_SEC := 10.0
const GIVE_UP_DISTANCE := 18.0

const WINDUP_SEC := 0.9
const AIM_FRACTION := 0.6
const CHARGE_SPEED := 5.0
const CHARGE_MAX := 8.0
const GORE_DAMAGE := 25
const GORE_REACH := 1.0
const GORE_HEIGHT := 1.4
const GORE_RECOVER_SEC := 1.0
const RECOVER_SEC := 1.4
const STUN_SEC := 2.5

var _anger := 0.0
var _target_peer := 0
var _aim := Vector3.FORWARD
var _charge_dir := Vector3.FORWARD
var _charge_left := 0.0
var _recover_len := RECOVER_SEC
var _hit: Dictionary = {}
var _goal := Vector3.ZERO
var _pause := 0.0
var _stuck := 0.0


func _init() -> void:
	display_name = "Hog"
	max_health = MAX_HEALTH
	health = MAX_HEALTH


func setup_hog(id: int, spawn: Vector3) -> void:
	setup(id, KIND_HOG, spawn, RADIUS, HEIGHT)
	rotation.y = random_range(-PI, PI)
	_goal = _pick_goal()


func is_angry() -> bool:
	return _anger > 0.0


func roll_loot() -> Array:
	return [["raw_meat", random_int(2, 3)]]


func _think(delta: float) -> void:
	_anger = maxf(_anger - delta, 0.0)
	match state:
		S_IDLE, S_WALK:
			_graze(delta)
		S_WINDUP:
			_windup(delta)
		S_CHARGE:
			velocity.x = _charge_dir.x * CHARGE_SPEED
			velocity.z = _charge_dir.z * CHARGE_SPEED
		S_RECOVER:
			_stand_still()
			if state_time >= _recover_len:
				_after_fight()
		S_STUNNED:
			_stand_still()
			if state_time >= STUN_SEC:
				_after_fight()


func _after_move(delta: float) -> void:
	match state:
		S_WALK:
			if get_real_velocity().length() < 0.2:
				_stuck += delta
			else:
				_stuck = 0.0
		S_CHARGE:
			_charge_after_move(delta)


func _on_state(next: int) -> void:
	match next:
		S_WINDUP:
			_stand_still()
		S_CHARGE:
			_hit.clear()
			_charge_left = CHARGE_MAX
			_charge_dir = _aim
			rotation.y = atan2(-_aim.x, -_aim.z)
		S_RECOVER, S_STUNNED, S_IDLE:
			_stand_still()


func _on_hurt(_amount: int) -> void:
	_anger = ANGER_SEC
	if last_attacker > 1:
		_target_peer = last_attacker


func _graze(delta: float) -> void:
	var provoker := _provoker()
	if provoker != null:
		_begin_windup(provoker)
		return
	if _pause > 0.0:
		_pause -= delta
		_stand_still()
		set_state(S_IDLE)
		return
	var offset := Vector3(_goal.x - global_position.x, 0.0, _goal.z - global_position.z)
	if offset.length() < 0.4 or _stuck > 0.6:
		_pause = random_range(1.5, 4.0)
		_goal = _pick_goal()
		_stuck = 0.0
		_stand_still()
		set_state(S_IDLE)
		return
	var dir := offset.normalized()
	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED
	face_toward(dir, 4.0, delta)
	set_state(S_WALK)


func _begin_windup(target: PlayerController) -> void:
	_target_peer = target.network_id
	_aim = _flat_toward(target)
	set_state(S_WINDUP)


func _windup(delta: float) -> void:
	_stand_still()
	var target := _target()
	if target == null:
		set_state(S_IDLE)
		return
	if state_time < WINDUP_SEC * AIM_FRACTION:
		_aim = _flat_toward(target)
		face_toward(_aim, 10.0, delta)
	if state_time >= WINDUP_SEC:
		set_state(S_CHARGE)


func _charge_after_move(delta: float) -> void:
	for index in get_slide_collision_count():
		var contact := get_slide_collision(index)
		if contact.get_normal().dot(_charge_dir) < -0.6:
			set_state(S_STUNNED)
			return
	for player in system.players():
		var peer := int(player.network_id)
		if _hit.has(peer):
			continue
		var offset := player.global_position - global_position
		if absf(offset.y) > GORE_HEIGHT:
			continue
		offset.y = 0.0
		if offset.length() > GORE_REACH:
			continue
		_hit[peer] = true
		system.hurt_player(player, GORE_DAMAGE, self)
		_recover_len = GORE_RECOVER_SEC
		set_state(S_RECOVER)
		return
	_charge_left -= CHARGE_SPEED * delta
	if _charge_left <= 0.0:
		_recover_len = RECOVER_SEC
		set_state(S_RECOVER)


func _after_fight() -> void:
	var provoker := _provoker()
	if provoker != null:
		_begin_windup(provoker)
		return
	_pause = 1.0
	set_state(S_IDLE)


## Who the hog wants to charge right now, or null if it should calm down.
func _provoker() -> PlayerController:
	if _anger > 0.0:
		var target := _target()
		if target == null:
			target = _nearest(GIVE_UP_DISTANCE)
		if target != null:
			return target
		_anger = 0.0
		return null
	for player in system.players():
		var offset := player.global_position - global_position
		offset.y = 0.0
		if offset.length() <= _trigger_for(player):
			_anger = ANGER_SEC
			return player
	return null


func _trigger_for(player: PlayerController) -> float:
	if player.body_height() < PlayerController.STAND_HEIGHT - 0.3:
		return TRIGGER_CROUCH
	return TRIGGER_STAND


func _target() -> PlayerController:
	if _target_peer <= 1:
		return null
	var player := system.player_for(_target_peer)
	if player == null:
		return null
	var offset := player.global_position - global_position
	offset.y = 0.0
	if offset.length() > GIVE_UP_DISTANCE:
		return null
	return player


func _nearest(max_distance: float) -> PlayerController:
	var best: PlayerController = null
	var best_distance := max_distance
	for player in system.players():
		var offset := player.global_position - global_position
		offset.y = 0.0
		if offset.length() < best_distance:
			best_distance = offset.length()
			best = player
	return best


func _flat_toward(player: PlayerController) -> Vector3:
	var offset := player.global_position - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return forward()
	return offset.normalized()


func _pick_goal() -> Vector3:
	var angle := random_range(-PI, PI)
	var reach := random_range(1.5, WANDER_RADIUS)
	return home + Vector3(cos(angle), 0.0, sin(angle)) * reach


func _stand_still() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
