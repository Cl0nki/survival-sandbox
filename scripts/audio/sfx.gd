extends RefCounted
class_name Sfx

## The one call game code makes to make a sound:
##   Sfx.play_at(&"hurt", global_position, is_controlled_locally())
## Events are the ids in tools/ai_asset_pipeline/config/sounds.json:
## footstep, shot, hurt, craft_start, craft_done.
## Safe everywhere. It does nothing on a headless server or bot, and nothing for an event
## the Sounds tool has no file for. It is a plain class and not an autoload because the
## headless tests run without autoloads.

const NODE_NAME := "SfxManager"

static var _manager: SfxManager


## Start the sound node early so the first real sound is not lost.
static func warm() -> void:
	manager()


## A sound at a place in the world. Pass own = true for the local player's own actions:
## those play flat so they do not depend on where the camera is.
static func play_at(event: StringName, position: Vector3, own: bool = false, gain_db: float = 0.0) -> bool:
	var node := manager()
	if node == null:
		return false
	if own:
		return node.play(event, gain_db)
	return node.play_at(event, position, gain_db)


## A flat sound with no place in the world.
static func play(event: StringName, gain_db: float = 0.0) -> bool:
	var node := manager()
	return node != null and node.play(event, gain_db)


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
