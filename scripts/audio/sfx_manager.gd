extends Node
class_name SfxManager

## Plays the sounds the Sounds tool wrote to resources/audio/sounds.json.
## A small pool of voices is reused, so a busy fight never allocates nodes.
## An event with no files is silent. Nothing here ever raises for a missing sound.
## Game code does not talk to this node. It calls the static helpers in Sfx.

const MANIFEST_PATH := "res://resources/audio/sounds.json"
const BUS_NAME := &"SFX"
const VOICES_3D := 16
const VOICES_2D := 8
## Attenuation scale of the 3D voices. The camera sits well above the ground,
## so this is large enough that a sound at someone's feet is still clear.
const UNIT_SIZE := 10.0

var manifest_path := MANIFEST_PATH

var _events: Dictionary = {}
var _last_msec: Dictionary = {}
var _last_pick: Dictionary = {}
var _voices_3d: Array[AudioStreamPlayer3D] = []
var _voices_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0
var _rng := RandomNumberGenerator.new()
var _ready_done := false


func _ready() -> void:
	_rng.randomize()
	_ensure_bus()
	for _i in VOICES_3D:
		var voice := AudioStreamPlayer3D.new()
		voice.bus = BUS_NAME
		voice.unit_size = UNIT_SIZE
		add_child(voice)
		_voices_3d.append(voice)
	for _i in VOICES_2D:
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS_NAME
		add_child(voice)
		_voices_2d.append(voice)
	_ready_done = true
	reload()


## Read the manifest again. The Sounds tool writes it, so a running game can pick up changes.
func reload() -> void:
	_events.clear()
	_last_msec.clear()
	_last_pick.clear()
	if not FileAccess.file_exists(manifest_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (parsed is Dictionary):
		push_warning("Sounds: %s is not valid JSON." % manifest_path)
		return
	var rows: Variant = (parsed as Dictionary).get("events", {})
	if not (rows is Dictionary):
		return
	for key in (rows as Dictionary):
		var row: Variant = (rows as Dictionary)[key]
		if not (row is Dictionary):
			continue
		var streams: Array[AudioStream] = []
		var files: Variant = (row as Dictionary).get("files", [])
		if files is Array:
			for path in (files as Array):
				var stream := load_stream(str(path))
				if stream != null:
					streams.append(stream)
		var pitch_min := clampf(float((row as Dictionary).get("pitch_min", 1.0)), 0.25, 4.0)
		var pitch_max := clampf(float((row as Dictionary).get("pitch_max", 1.0)), 0.25, 4.0)
		_events[StringName(str(key))] = {
			"streams": streams,
			"volume_db": float((row as Dictionary).get("volume_db", 0.0)),
			"pitch_min": minf(pitch_min, pitch_max),
			"pitch_max": maxf(pitch_min, pitch_max),
			"cooldown": maxf(float((row as Dictionary).get("cooldown", 0.0)), 0.0),
			"max_distance": maxf(float((row as Dictionary).get("max_distance", 30.0)), 1.0),
		}


## Imported files load as resources. A file the editor has not imported yet is decoded
## from its bytes, so a sound added in the Sounds tool plays on the very next launch.
static func load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var loaded: Variant = load(path)
		if loaded is AudioStream:
			return loaded as AudioStream
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"mp3":
			return AudioStreamMP3.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
	return null


func sound_count(event: StringName) -> int:
	if not _events.has(event):
		return 0
	return (_events[event]["streams"] as Array).size()


func has_event(event: StringName) -> bool:
	return sound_count(event) > 0


## Flat sound, for the player's own actions and for anything with no place in the world.
## pitch is multiplied onto the event's own random pitch, so a run can sound a touch
## quicker than a walk without a second set of files.
func play(event: StringName, gain_db: float = 0.0, pitch: float = 1.0) -> bool:
	if not _ready_done:
		return false
	var spec := _take(event)
	if spec.is_empty():
		return false
	var voice := _voice_2d()
	voice.stream = spec["stream"]
	voice.volume_db = float(spec["volume_db"]) + gain_db
	voice.pitch_scale = clampf(float(spec["pitch"]) * pitch, 0.1, 4.0)
	voice.play()
	return true


## Sound that comes from a place in the world.
func play_at(event: StringName, position: Vector3, gain_db: float = 0.0, pitch: float = 1.0) -> bool:
	if not _ready_done:
		return false
	var spec := _take(event)
	if spec.is_empty():
		return false
	var voice := _voice_3d()
	voice.stream = spec["stream"]
	voice.volume_db = float(spec["volume_db"]) + gain_db
	voice.pitch_scale = clampf(float(spec["pitch"]) * pitch, 0.1, 4.0)
	voice.max_distance = float(spec["max_distance"])
	voice.global_position = position
	voice.play()
	return true


## 0 is silent, 1 is full. Applies to every sound through the SFX bus.
func set_volume(linear: float) -> void:
	var index := AudioServer.get_bus_index(BUS_NAME)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0, 1.0)))


func _take(event: StringName) -> Dictionary:
	if not _events.has(event):
		return {}
	var spec: Dictionary = _events[event]
	var streams: Array = spec["streams"]
	if streams.is_empty():
		return {}
	var now := Time.get_ticks_msec()
	var cooldown_msec := int(float(spec["cooldown"]) * 1000.0)
	if cooldown_msec > 0 and now - int(_last_msec.get(event, -1000000)) < cooldown_msec:
		return {}
	_last_msec[event] = now
	var index := _rng.randi_range(0, streams.size() - 1)
	# Never the same file twice in a row, or footsteps and shots sound like a machine.
	if streams.size() > 1 and index == int(_last_pick.get(event, -1)):
		index = (index + 1 + _rng.randi_range(0, streams.size() - 2)) % streams.size()
	_last_pick[event] = index
	return {
		"stream": streams[index],
		"volume_db": spec["volume_db"],
		"pitch": _rng.randf_range(float(spec["pitch_min"]), float(spec["pitch_max"])),
		"max_distance": spec["max_distance"],
	}


func _voice_3d() -> AudioStreamPlayer3D:
	for voice in _voices_3d:
		if not voice.playing:
			return voice
	_next_3d = (_next_3d + 1) % _voices_3d.size()
	return _voices_3d[_next_3d]


func _voice_2d() -> AudioStreamPlayer:
	for voice in _voices_2d:
		if not voice.playing:
			return voice
	_next_2d = (_next_2d + 1) % _voices_2d.size()
	return _voices_2d[_next_2d]


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, &"Master")
