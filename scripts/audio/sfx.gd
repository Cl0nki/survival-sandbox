extends RefCounted
class_name Sfx

## The one call game code makes to make a sound:
##   Sfx.play_at(&"hurt", global_position, is_controlled_locally())
## Events are the ids in tools/ai_asset_pipeline/config/sounds.json. Game code plays them
## from: GroundSurface (footsteps), PlayerController (hurt), CreatureView (hog),
## HitscanWeapon and GameNet (shots, impacts), crafters and smelters (crafting).
## Safe everywhere. It does nothing on a headless server or bot, and nothing for an event
## the Sounds tool has no file for. It is a plain class and not an autoload because the
## headless tests run without autoloads.

const NODE_NAME := "SfxManager"

## A gunshot heard from farther than this away uses the distant shot sound.
const FAR_SHOT_METERS := 35.0
## HitscanWeapon.range_meters is 40. A shot that ended this close to the limit hit
## nothing, so it makes no impact sound.
const SHOT_MISS_METERS := 39.5

static var _manager: SfxManager


## Start the sound node early so the first real sound is not lost.
static func warm() -> void:
	manager()


## A sound at a place in the world. Pass own = true for the local player's own actions:
## those play flat so they do not depend on where the camera is.
## pitch scales the event's own random pitch (1.0 leaves it alone).
static func play_at(event: StringName, position: Vector3, own: bool = false, gain_db: float = 0.0, pitch: float = 1.0) -> bool:
	var node := manager()
	if node == null:
		return false
	if own:
		return node.play(event, gain_db, pitch)
	return node.play_at(event, position, gain_db, pitch)


## A flat sound with no place in the world.
static func play(event: StringName, gain_db: float = 0.0, pitch: float = 1.0) -> bool:
	var node := manager()
	return node != null and node.play(event, gain_db, pitch)


## True when the Sounds tool has at least one file for the event.
static func has_sound(event: StringName) -> bool:
	var node := manager()
	return node != null and node.has_event(event)


## The first event in the list that has a sound, so a specific event can fall back to a
## general one. With none available it returns the last, which then plays nothing.
static func first_with_sound(events: Array) -> StringName:
	for event in events:
		if has_sound(StringName(event)):
			return StringName(event)
	return StringName(events[events.size() - 1]) if not events.is_empty() else &""


## A gunshot. The shooter hears it flat. Anyone else hears it from the muzzle, and a shot
## from far away uses the distant sound when there is one.
static func gunshot(origin: Vector3, own: bool) -> bool:
	if own:
		return play_at(&"shot", origin, true)
	var event := &"shot"
	var listener: Variant = listener_position()
	if listener is Vector3 and (listener as Vector3).distance_to(origin) > FAR_SHOT_METERS:
		event = first_with_sound([&"shot_far", &"shot"])
	return play_at(event, origin)


## The bullet arriving. A hit on something that can be hurt sounds different from a miss
## into a wall. A shot that flew its whole range hit nothing and makes no sound here.
static func bullet_lands(origin: Vector3, end_point: Vector3, damaged: bool) -> bool:
	if damaged:
		return play_at(&"bullet_hit", end_point)
	if origin.distance_to(end_point) >= SHOT_MISS_METERS:
		return false
	return play_at(&"bullet_impact", end_point)


## Where the listening camera is, or null when there is none.
static func listener_position() -> Variant:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var camera := tree.root.get_viewport().get_camera_3d()
	if camera == null:
		return null
	return camera.global_position


## Re-read resources/audio/sounds.json.
static func reload() -> void:
	var node := manager()
	if node != null:
		node.reload()


## 0 to 1, for an options menu.
static func set_volume(linear: float) -> void:
	var node := manager()
	if node != null:
		node.set_volume(linear)


static func manager() -> SfxManager:
	if DisplayServer.get_name() == "headless":
		return null
	if _manager != null and is_instance_valid(_manager):
		return _manager
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var created := SfxManager.new()
	created.name = NODE_NAME
	tree.root.add_child.call_deferred(created)
	_manager = created
	return created
