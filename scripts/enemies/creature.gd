extends CharacterBody3D
class_name Creature

## Server-side base for everything that moves on its own and can be shot.
## It owns health, the damage entry point the hitscan already calls, loot, and
## the state byte that gets replicated. Kinds (Hog now, Swarmer and Brute
## later) override _think() and add their own states from S_KIND_BASE up.
##
## EnemySystem drives advance() from its own physics tick, so a creature never
## simulates by itself. Tests call advance() directly.

signal health_changed(creature: Creature)
signal died(creature: Creature)

const S_IDLE := 0
const S_DEAD := 1
const S_KIND_BASE := 10

const GRAVITY := 22.0
const MAX_FALL := 30.0
const KIND_HOG := 1

var creature_id := 0
var kind := 0
var display_name := "Creature"
var max_health := 50
var health := 50
var state := S_IDLE
var state_time := 0.0
var home := Vector3.ZERO
var system: EnemySystem
var corpse_left := 0.0
## Peer that last hurt this creature, 0 if none. Kinds use it to pick a target.
var last_attacker := 0

var _rng := RandomNumberGenerator.new()


func setup(id: int, kind_id: int, spawn: Vector3, radius: float, height: float) -> void:
	creature_id = id
	kind = kind_id
	home = spawn
	_rng.seed = 7919 * id + 13
	set_physics_process(false)
	collision_layer = PhysicsLayers.DAMAGEABLE
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BUILDING
	floor_snap_length = 0.3
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.0 + 0.05)
	var body := CollisionShape3D.new()
	body.shape = shape
	body.position.y = shape.height * 0.5
	add_child(body)
	add_to_group(&"creature")
	if is_inside_tree():
		global_position = spawn
	else:
		position = spawn


func is_dead() -> bool:
	return state == S_DEAD


func yaw() -> float:
	return rotation.y


func forward() -> Vector3:
	return -Basis(Vector3.UP, rotation.y).z


func set_state(next: int) -> void:
	if next == state:
		return
	state = next
	state_time = 0.0
	_on_state(next)


## The hitscan calls this on whatever it hits. Returns true when it hurt.
func receive_damage(amount: int, _point: Vector3) -> bool:
	if is_dead() or amount <= 0:
		return false
	var next := maxi(health - amount, 0)
	if next >= health:
		return false
	health = next
	health_changed.emit(self)
	if health == 0:
		set_state(S_DEAD)
		velocity = Vector3.ZERO
		died.emit(self)
	else:
		_on_hurt(amount)
	return true


## Called by GameNet just before receive_damage so the creature knows who to
## go after. Harmless if the shot misses the creature.
func note_attacker(peer_id: int) -> void:
	if peer_id > 1:
		last_attacker = peer_id


func advance(delta: float) -> void:
	if is_dead():
		return
	state_time += delta
	_think(delta)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL)
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()
	if not is_dead():
		_after_move(delta)


## What this creature leaves behind: Array of [item_id, quantity].
func roll_loot() -> Array:
	return []


func face_toward(direction: Vector3, rate: float, delta: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return
	var want := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(rate * delta, 0.0, 1.0))


func random_range(low: float, high: float) -> float:
	return _rng.randf_range(low, high)


func random_int(low: int, high: int) -> int:
	return _rng.randi_range(low, high)


func _think(_delta: float) -> void:
	pass


## Runs right after the body moved; slide collisions are valid here.
func _after_move(_delta: float) -> void:
	pass


func _on_state(_next: int) -> void:
	pass


func _on_hurt(_amount: int) -> void:
	pass
