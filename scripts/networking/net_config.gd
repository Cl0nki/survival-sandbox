extends RefCounted
class_name NetConfig

## Command-line configuration shared by the dedicated server and clients.
## User arguments are everything after `--` on the Godot command line.

const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_PORT := 7777
const MAX_CLIENTS := 100
const SNAPSHOT_HZ := 20
const INPUT_RATE_PER_SEC := 80
const FIRE_RATE_PER_SEC := 12
const STALE_INPUT_SEC := 0.35
## Remote bodies stay 100 ms behind the newest snapshot so a late packet
## still has a pose to lerp toward. The owning body uses a shorter delay.
const INTERP_DELAY_SEC := 0.10
const OWNER_INTERP_DELAY_SEC := 0.08
## Five percent past the 40 m pistol. A shot can strike the near side of a
## capsule whose center is already past the muzzle's 40 m ray.
const VISIBILITY_DISTANCE := 42.0
## Extra sight around a corner, as a fraction of the distance between eyes.
## A player whose center is about this far past an edge is still visible.
const VISIBILITY_EDGE_MARGIN := 0.05
## Meters outside the hurt capsule that still count as seen. The player
## appears slightly before a bullet can touch them.
const VISIBILITY_LEAD := 0.3
## Zero recomputes sight every physics frame, after movement.
const VISIBILITY_INTERVAL_SEC := 0.0
const INVENTORY_SLOTS := 36
const HOTBAR_SLOTS := 9
const CONTAINER_SLOTS := 27
const INTERACT_RANGE := 2.5
const ITEM_RATE_PER_SEC := 40
const MODE_LOCAL := 0
const MODE_SERVER := 1
const MODE_CLIENT := 2

static func usage() -> String:
	return "\n".join([
		"Survival Sandbox multiplayer",
		"  --server [--port N] [--status-file PATH]",
		"  --client [--address HOST] [--port N] [--window-x N] [--window-y N]",
		"           [--bot] [--expect-peers N] [--status-file PATH]",
		"Local play (no flags) keeps the Milestone 1 prototype.",
	])


static func parse(args: PackedStringArray) -> Dictionary:
	var result := {
		"mode": MODE_LOCAL,
		"address": DEFAULT_ADDRESS,
		"port": DEFAULT_PORT,
		"window_x": -1,
		"window_y": -1,
		"bot": false,
		"expect_peers": 2,
		"status_file": "",
		"help": false,
		"error": "",
	}
	var saw_server := false
	var saw_client := false
	var index := 0
	while index < args.size():
		var arg := str(args[index])
		match arg:
			"--help", "-h":
				result.help = true
			"--server":
				saw_server = true
				result.mode = MODE_SERVER
			"--client":
				saw_client = true
				result.mode = MODE_CLIENT
			"--bot":
				result.bot = true
			"--address", "--port", "--window-x", "--window-y", "--expect-peers", "--status-file":
				if index + 1 >= args.size():
					result.error = "%s needs a value" % arg
					return result
				index += 1
				var value := str(args[index])
				var parsed := _apply_option(result, arg, value)
				if not bool(parsed):
					return result
			_:
				if arg.begins_with("--"):
					result.error = "unknown argument %s" % arg
					return result
		index += 1
	if saw_server and saw_client:
		result.error = "use either --server or --client"
		return result
	if bool(result.bot) and int(result.mode) != MODE_CLIENT:
		result.error = "--bot is only valid with --client"
		return result
	return result


static func _apply_option(result: Dictionary, option: String, value: String) -> bool:
	match option:
		"--address":
			if value.is_empty() or value.contains(" "):
				result.error = "--address is empty"
				return false
			result.address = value
		"--port":
			var port := _integer(value)
			if port < 1 or port > 65535:
				result.error = "--port must be 1-65535"
				return false
			result.port = port
		"--window-x":
			result.window_x = _integer(value)
			if int(result.window_x) < 0:
				result.error = "--window-x must be >= 0"
				return false
		"--window-y":
			result.window_y = _integer(value)
			if int(result.window_y) < 0:
				result.error = "--window-y must be >= 0"
				return false
		"--expect-peers":
			var count := _integer(value)
			if count < 1 or count > MAX_CLIENTS:
				result.error = "--expect-peers must be 1-%d" % MAX_CLIENTS
				return false
			result.expect_peers = count
		"--status-file":
			if value.is_empty():
				result.error = "--status-file is empty"
				return false
			result.status_file = value
	return true


static func _integer(value: String) -> int:
	if not value.is_valid_int():
		return -1
	return int(value)


static func append_line(path: String, line: String) -> void:
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write status file %s" % path)
		return
	file.seek_end()
	file.store_line(line)
	file.close()


static func finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
